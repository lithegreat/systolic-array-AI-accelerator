// =============================================================================
// apb_if.sv  --  APB interface for accelerator_top UVM testbench
//
// Matches accelerator_top port widths: APB_AW=10, APB_DW=32.
// reset_int is exposed as a plain logic signal (driven by tb_top) so that
// UVM components can monitor it to detect end-of-reset.
// =============================================================================

interface apb_if (input logic clk);

    logic        reset_int;   // active-high; driven by tb_top
    logic [9:0]  PADDR;
    logic        PSEL;
    logic        PENABLE;
    logic        PWRITE;
    logic [31:0] PWDATA;
    logic [31:0] PRDATA;
    logic        PREADY;
    logic        PSLVERR;

    // -------------------------------------------------------------------------
    // Driver clocking block – TB drives APB outputs one clock after posedge
    // (output skew #1; sampling point = #1step before posedge)
    // -------------------------------------------------------------------------
    clocking driver_cb @(posedge clk);
        default input #1step output #1;
        output PADDR;
        output PSEL;
        output PENABLE;
        output PWRITE;
        output PWDATA;
        input  PRDATA;
        input  PREADY;
        input  PSLVERR;
    endclocking

    // -------------------------------------------------------------------------
    // Monitor clocking block – samples all signals just before posedge
    // -------------------------------------------------------------------------
    clocking monitor_cb @(posedge clk);
        default input #1step;
        input reset_int;
        input PADDR;
        input PSEL;
        input PENABLE;
        input PWRITE;
        input PWDATA;
        input PRDATA;
        input PREADY;
        input PSLVERR;
    endclocking

    modport driver_mp  (clocking driver_cb,  input clk);
    modport monitor_mp (clocking monitor_cb, input clk);

endinterface : apb_if
