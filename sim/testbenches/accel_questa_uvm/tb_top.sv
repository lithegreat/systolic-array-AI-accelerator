// =============================================================================
// tb_top.sv  --  UVM testbench top module for accelerator_top
//
// Responsibilities:
//   – Generate 100 MHz clock and active-high reset sequence
//   – Instantiate APB interface and DUT (accelerator_top)
//   – Register the virtual interface in uvm_config_db so every test can
//     find it with get(this, "", "vif", vif)
//   – Call run_test() to launch the test named by +UVM_TESTNAME
//   – Provide a simulation timeout watchdog (default 10 ms)
//
// Usage:
//   vsim tb_top +UVM_TESTNAME=accel_random_test +UVM_VERBOSITY=UVM_MEDIUM
// =============================================================================

`include "accel_pkg.sv"
`include "uvm_macros.svh"

module tb_top;

    import uvm_pkg::*;
    import apb_pkg::*;
    import accel_env_pkg::*;
    import accel_tests_pkg::*;

    // -------------------------------------------------------------------------
    // Tile dimensions – must match the DUT's compile-time parameters below
    // -------------------------------------------------------------------------
    localparam int unsigned TB_M      = 4;
    localparam int unsigned TB_N      = 4;
    localparam int unsigned TB_K      = 4;
    localparam int unsigned TB_DATA_W = 16;
    localparam int unsigned TB_ACC_W  = 32;

    // -------------------------------------------------------------------------
    // Clock and reset
    // -------------------------------------------------------------------------
    logic clk       = 1'b0;
    logic reset_int = 1'b1;   // active-high reset; DUT released after 20 cycles

    always #5 clk = ~clk;    // 100 MHz  (period = 10 ns)

    // -------------------------------------------------------------------------
    // APB interface instance
    // -------------------------------------------------------------------------
    apb_if apb(.clk(clk));

    // reset_int is driven by the initial block and forwarded into the interface
    // so UVM driver/monitor can see it.
    assign apb.reset_int = reset_int;

    // -------------------------------------------------------------------------
    // DUT: accelerator_top
    // -------------------------------------------------------------------------
    accelerator_top #(
        .DATA_W (TB_DATA_W),
        .ACC_W  (TB_ACC_W),
        .M      (TB_M),
        .N      (TB_N),
        .K      (TB_K)
    ) dut (
        .clk_in   (clk),
        .reset_int(reset_int),
        // APB subordinate
        .PADDR    (apb.PADDR),
        .PSEL     (apb.PSEL),
        .PENABLE  (apb.PENABLE),
        .PWRITE   (apb.PWRITE),
        .PWDATA   (apb.PWDATA),
        .PRDATA   (apb.PRDATA),
        .PREADY   (apb.PREADY),
        .PSLVERR  (apb.PSLVERR),
        // SoC sideband (not used by testbench)
        .irq_en_4 (1'b0),
        .ss_ctrl_4(8'h00),
        .irq_4    ()     // intentionally left unconnected
    );

    // -------------------------------------------------------------------------
    // UVM startup: register VIF, apply reset, call run_test()
    // -------------------------------------------------------------------------
    initial begin
        // Make the virtual interface accessible to all UVM components
        uvm_config_db #(virtual apb_if)::set(
            null,                  // from root
            "uvm_test_top*",       // wildcard matches every sub-component
            "vif",
            apb);

        // Assert reset for 20 clock cycles (200 ns), then release
        reset_int = 1'b1;
        repeat (20) @(posedge clk);
        reset_int = 1'b0;
        @(posedge clk);

        // Dispatch the test selected via +UVM_TESTNAME (default: no default –
        // +UVM_TESTNAME must be supplied on the vsim command line).
        run_test();
    end

    // -------------------------------------------------------------------------
    // Watchdog: prevent infinite loops from hanging the regression
    // -------------------------------------------------------------------------
    initial begin
        #10_000_000;   // 10 ms
        `uvm_fatal("WATCHDOG", "Simulation watchdog fired after 10 ms")
    end

endmodule : tb_top
