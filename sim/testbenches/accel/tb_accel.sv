// -----------------------------------------------------------------------------
// tb_accel.sv -- Standalone APB testbench for accelerator_top.
//
// This testbench is self-contained: it depends only on the accelerator RTL
// (rtl/) and accel_pkg, so it can run in any simulator (Vivado xsim, Verilator,
// Questa) WITHOUT the SoC, the ibex core, JTAG, or a RISC-V program hex.
//
// It mirrors the software smoke test (sw/accel/accel.c):
//   1. Fill Matrix A and Matrix B with all ones.
//   2. Issue a start pulse via the control_unit CTRL register.
//   3. Wait for STATUS.done.
//   4. Read back Matrix C and check every element equals K.
//
// With A and B all ones, C[i][j] = sum over K of (1*1) = K.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_accel;

    // Physical array size (M=N=K). Override at compile time with
    // +define+ACCEL_DIM=8 (Verilator: -DACCEL_DIM=8) to test the 8x8 build;
    // defaults to 16 to match accelerator_top / the golden model.
`ifndef ACCEL_DIM
  `define ACCEL_DIM 16
`endif

    // Match accelerator_top default parameters.
    localparam int unsigned DATA_W = 16;
    localparam int unsigned ACC_W  = 32;
    localparam int unsigned M      = `ACCEL_DIM;
    localparam int unsigned N      = `ACCEL_DIM;
    localparam int unsigned K      = `ACCEL_DIM;
    localparam int unsigned APB_AW = 10;
    localparam int unsigned APB_DW = 32;

    localparam int unsigned EPW = APB_DW / DATA_W; // elements per APB word = 2

    // Address map inside the subsystem window (PADDR[9:8] decode).
    localparam logic [APB_AW-1:0] ADDR_A      = 10'h000; // matrix_buffer_ab : A
    localparam logic [APB_AW-1:0] ADDR_B      = 10'h040; // matrix_buffer_ab : B
    localparam logic [APB_AW-1:0] ADDR_AB_CTL = 10'h080; // matrix_buffer_ab : CTRL
    localparam logic [APB_AW-1:0] ADDR_CTRL   = 10'h100; // control_unit : CTRL
    localparam logic [APB_AW-1:0] ADDR_STATUS = 10'h104; // control_unit : STATUS
    localparam logic [APB_AW-1:0] ADDR_M_DIM  = 10'h108;
    localparam logic [APB_AW-1:0] ADDR_N_DIM  = 10'h10C;
    localparam logic [APB_AW-1:0] ADDR_K_DIM  = 10'h118;
    localparam logic [APB_AW-1:0] ADDR_C_DATA = 10'h200; // matrix_buffer_c : DATA
    localparam logic [APB_AW-1:0] ADDR_C_CTL  = 10'h280; // matrix_buffer_c : CTRL

    // DUT signals.
    logic                  clk;
    logic                  reset_int; // active-high (accelerator_top inverts)
    logic [APB_AW-1:0]     PADDR;
    logic                  PSEL;
    logic                  PENABLE;
    logic                  PWRITE;
    logic [APB_DW-1:0]     PWDATA;
    logic [APB_DW-1:0]     PRDATA;
    logic                  PREADY;
    logic                  PSLVERR;
    logic                  irq_en_4;
    logic [7:0]            ss_ctrl_4;
    logic                  irq_4;

    // -------------------------------------------------------------------------
    // Clock: 100 MHz.
    // -------------------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT.
    // -------------------------------------------------------------------------
    accelerator_top #(
        .DATA_W (DATA_W),
        .ACC_W  (ACC_W),
        .M      (M),
        .N      (N),
        .K      (K),
        .APB_AW (APB_AW),
        .APB_DW (APB_DW)
    ) dut (
        .clk_in    (clk),
        .reset_int (reset_int),
        .PADDR     (PADDR),
        .PSEL      (PSEL),
        .PENABLE   (PENABLE),
        .PWRITE    (PWRITE),
        .PWDATA    (PWDATA),
        .PRDATA    (PRDATA),
        .PREADY    (PREADY),
        .PSLVERR   (PSLVERR),
        .irq_en_4  (irq_en_4),
        .ss_ctrl_4 (ss_ctrl_4),
        .irq_4     (irq_4)
    );

    // -------------------------------------------------------------------------
    // APB driver tasks (drive on negedge, standard 2-phase APB, PREADY=1).
    // -------------------------------------------------------------------------
    task automatic apb_write(input logic [APB_AW-1:0] addr, input logic [APB_DW-1:0] data);
        @(negedge clk);
        PSEL    = 1'b1;
        PENABLE = 1'b0;
        PWRITE  = 1'b1;
        PADDR   = addr;
        PWDATA  = data;
        @(negedge clk);
        PENABLE = 1'b1; // access phase; write commits on the next posedge
        @(negedge clk);
        PSEL    = 1'b0;
        PENABLE = 1'b0;
        PWRITE  = 1'b0;
    endtask

    task automatic apb_read(input logic [APB_AW-1:0] addr, output logic [APB_DW-1:0] data);
        @(negedge clk);
        PSEL    = 1'b1;
        PENABLE = 1'b0;
        PWRITE  = 1'b0;
        PADDR   = addr;
        @(negedge clk);
        PENABLE = 1'b1;   // access phase
        #1 data = PRDATA; // combinational read, sampled before the committing posedge
        @(negedge clk);
        PSEL    = 1'b0;
        PENABLE = 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Test sequence.
    // -------------------------------------------------------------------------
    integer i;
    integer errors;
    logic [APB_DW-1:0] rdata;
    integer timeout;

    initial begin
        // Init.
        reset_int = 1'b1; // active-high reset asserted
        PSEL      = 1'b0;
        PENABLE   = 1'b0;
        PWRITE    = 1'b0;
        PADDR     = '0;
        PWDATA    = '0;
        irq_en_4  = 1'b0;
        ss_ctrl_4 = 8'h00;
        errors    = 0;

        // Hold reset for a few cycles, then release.
        repeat (5) @(negedge clk);
        reset_int = 1'b0;
        repeat (2) @(negedge clk);

        // 1. Reset A/B write pointers.
        apb_write(ADDR_AB_CTL, 32'h0000_0001);

        // 2. Stream Matrix A = all ones (two 16-bit lanes per word -> 0x0001_0001).
        for (i = 0; i < (M*K)/EPW; i = i + 1) begin
            apb_write(ADDR_A, 32'h0001_0001);
        end

        // 3. Stream Matrix B = all ones.
        for (i = 0; i < (K*N)/EPW; i = i + 1) begin
            apb_write(ADDR_B, 32'h0001_0001);
        end

        // 4. Reset C capture/read pointer.
        apb_write(ADDR_C_CTL, 32'h0000_0001);

        // 5. Program dimension registers (documentation/visibility).
        apb_write(ADDR_M_DIM, M);
        apb_write(ADDR_N_DIM, N);
        apb_write(ADDR_K_DIM, K);

        // 6. Issue start pulse (CTRL bit 0).
        apb_write(ADDR_CTRL, 32'h0000_0001);

        // 7. Poll STATUS.done (bit 1) with a timeout.
        timeout = 10000;
        rdata   = '0;
        while (((rdata[1] == 1'b0)) && (timeout > 0)) begin
            apb_read(ADDR_STATUS, rdata);
            timeout = timeout - 1;
        end

        if (timeout == 0) begin
            $display("[tb_accel] ERROR: timeout waiting for STATUS.done");
            $display("[tb_accel] RESULT: FAIL");
            $fatal(1, "timeout");
        end

        // 8. Read back all C elements and check == K.
        for (i = 0; i < M*N; i = i + 1) begin
            apb_read(ADDR_C_DATA, rdata);
            if (rdata !== K) begin
                if (errors < 10)
                    $display("[tb_accel] C[%0d] = %0d (expected %0d)", i, rdata, K);
                errors = errors + 1;
            end
        end

        // 9. Report.
        if (errors == 0) begin
            $display("[tb_accel] All %0d C elements == %0d", M*N, K);
            $display("[tb_accel] RESULT: PASS");
        end else begin
            $display("[tb_accel] %0d / %0d C elements mismatched", errors, M*N);
            $display("[tb_accel] RESULT: FAIL");
        end

        repeat (5) @(negedge clk);
        $finish;
    end

    // Global watchdog.
    initial begin
        #2_000_000; // 2 ms
        $display("[tb_accel] ERROR: global watchdog timeout");
        $display("[tb_accel] RESULT: FAIL");
        $fatal(1, "watchdog");
    end

endmodule
