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

    // Element bit-width. INT8 baseline; override with +define+ACCEL_DATA_W=16
    // (Verilator: -DACCEL_DATA_W=16) to exercise a wider datapath.
`ifndef ACCEL_DATA_W
  `define ACCEL_DATA_W 8
`endif

    // Match accelerator_top default parameters.
    localparam int unsigned DATA_W = `ACCEL_DATA_W;
    localparam int unsigned ACC_W  = 32;
    localparam int unsigned M      = `ACCEL_DIM;
    localparam int unsigned N      = `ACCEL_DIM;
    localparam int unsigned K      = `ACCEL_DIM;
    localparam int unsigned APB_AW = 10;
    localparam int unsigned APB_DW = 32;

    localparam int unsigned EPW = APB_DW / DATA_W; // elements per APB word (DATA_W=8 -> 4)

    // A/B fill word: value 1 in every DATA_W-bit lane, so each streamed element
    // is 1 regardless of width (=> C[i][j] = K). Width-generic replacement for
    // the old 16-bit-specific 0x0001_0001 literal.
    localparam logic [APB_DW-1:0] ONES_WORD = {EPW{DATA_W'(1)}};

    // Address map inside the subsystem window (PADDR[9:8] decode).
    localparam logic [APB_AW-1:0] ADDR_A      = 10'h000; // matrix_buffer_ab : A
    localparam logic [APB_AW-1:0] ADDR_B      = 10'h040; // matrix_buffer_ab : B
    localparam logic [APB_AW-1:0] ADDR_AB_CTL = 10'h080; // matrix_buffer_ab : CTRL
    localparam logic [APB_AW-1:0] ADDR_CTRL   = 10'h100; // control_unit : CTRL
    localparam logic [APB_AW-1:0] ADDR_STATUS = 10'h104; // control_unit : STATUS
    localparam logic [APB_AW-1:0] ADDR_M_DIM  = 10'h108;
    localparam logic [APB_AW-1:0] ADDR_N_DIM  = 10'h10C;
    localparam logic [APB_AW-1:0] ADDR_K_DIM  = 10'h118;
    localparam logic [APB_AW-1:0] ADDR_BUILD_INFO      = 10'h11C;
    localparam logic [APB_AW-1:0] ADDR_HW_STATUS       = 10'h120;
    localparam logic [APB_AW-1:0] ADDR_PERF_CTRL       = 10'h124;
    localparam logic [APB_AW-1:0] ADDR_PERF_CYCLES     = 10'h128;
    localparam logic [APB_AW-1:0] ADDR_PERF_APB_WRITES = 10'h12C;
    localparam logic [APB_AW-1:0] ADDR_PERF_APB_READS  = 10'h130;
    localparam logic [APB_AW-1:0] ADDR_PERF_IN_STALLS  = 10'h134;
    localparam logic [APB_AW-1:0] ADDR_PERF_OUT_STALLS = 10'h138;
    localparam logic [APB_AW-1:0] ADDR_C_DATA = 10'h200; // matrix_buffer_c : DATA
    localparam logic [APB_AW-1:0] ADDR_C_CTL  = 10'h280; // matrix_buffer_c : CTRL

    localparam logic [APB_DW-1:0] EXPECT_BUILD_INFO = {
        8'(DATA_W), 8'(K), 8'(N), 8'(M)
    };

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
    logic [APB_DW-1:0] perf_apb_reads;
    logic [APB_DW-1:0] perf_apb_writes;
    logic [APB_DW-1:0] perf_cycles;
    logic [APB_DW-1:0] perf_in_stalls;
    logic [APB_DW-1:0] perf_out_stalls;
    logic [APB_DW-1:0] hw_status;
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

        // 2. Stream Matrix A = all ones (1 in every DATA_W-bit lane).
        for (i = 0; i < (M*K)/EPW; i = i + 1) begin
            apb_write(ADDR_A, ONES_WORD);
        end

        // 3. Stream Matrix B = all ones.
        for (i = 0; i < (K*N)/EPW; i = i + 1) begin
            apb_write(ADDR_B, ONES_WORD);
        end

        // 4. Reset C capture/read pointer.
        apb_write(ADDR_C_CTL, 32'h0000_0001);

        // 5. Program dimension registers (documentation/visibility).
        apb_write(ADDR_M_DIM, M);
        apb_write(ADDR_N_DIM, N);
        apb_write(ADDR_K_DIM, K);

        apb_read(ADDR_BUILD_INFO, rdata);
        if (rdata !== EXPECT_BUILD_INFO) begin
            $display("[tb_accel] BUILD_INFO = 0x%08x (expected 0x%08x)", rdata, EXPECT_BUILD_INFO);
            errors = errors + 1;
        end

        // Clear performance counters after preload/config writes so the counts
        // describe the compute/readback window.
        apb_write(ADDR_PERF_CTRL, 32'h0000_0001);

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

        apb_read(ADDR_PERF_APB_READS, perf_apb_reads);
        apb_read(ADDR_PERF_APB_WRITES, perf_apb_writes);
        apb_read(ADDR_PERF_CYCLES, perf_cycles);
        apb_read(ADDR_PERF_IN_STALLS, perf_in_stalls);
        apb_read(ADDR_PERF_OUT_STALLS, perf_out_stalls);
        apb_read(ADDR_HW_STATUS, hw_status);

        if (perf_apb_writes < 1) begin
            $display("[tb_accel] PERF_APB_WRITES = %0d (expected >= 1)", perf_apb_writes);
            errors = errors + 1;
        end
        if (perf_apb_reads < M*N) begin
            $display("[tb_accel] PERF_APB_READS = %0d (expected >= %0d)", perf_apb_reads, M*N);
            errors = errors + 1;
        end
        if (perf_cycles == 0) begin
            $display("[tb_accel] PERF_CYCLES should be nonzero");
            errors = errors + 1;
        end
        if (perf_out_stalls != 0 || hw_status[2]) begin
            $display("[tb_accel] unexpected output stall count/status: count=%0d status=0x%08x",
                     perf_out_stalls, hw_status);
            errors = errors + 1;
        end
        if (hw_status[3]) begin
            $display("[tb_accel] unexpected performance counter overflow: status=0x%08x", hw_status);
            errors = errors + 1;
        end

        $display("[tb_accel] perf cycles=%0d apb_writes=%0d apb_reads=%0d in_stalls=%0d out_stalls=%0d status=0x%08x",
                 perf_cycles, perf_apb_writes, perf_apb_reads, perf_in_stalls, perf_out_stalls,
                 hw_status);

        // 9. Report.
        if (errors == 0) begin
            $display("[tb_accel] All %0d C elements == %0d", M*N, K);
            $display("[tb_accel] RESULT: PASS");
        end else begin
            $display("[tb_accel] %0d / %0d C elements mismatched", errors, M*N);
            $display("[tb_accel] RESULT: FAIL");
            $fatal(1, "mismatch or performance/status check failure");
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
