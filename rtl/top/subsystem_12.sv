// -----------------------------------------------------------------------------
// subsystem_12.sv -- Top-level wrapper for AI group 5 in Didactic SoC.
//
// Wraps accelerator_top behind the standard Didactic SoC student subsystem interface:
//   - APB subordinate port (PADDR[15:0], PSEL, PENABLE, PWRITE, PWDATA, PRDATA, PREADY, PSLVERR)
//   - Clock and active-low reset (clk, reset_n)
//   - Subsystem IRQ (irq, irq_en)
//   - PMOD GPIO stubs (pmod_gpi, pmod_gpio_oe, pmod_gpo)
// -----------------------------------------------------------------------------
`include "accel_pkg.sv"

module subsystem_12 #(
    parameter int unsigned NUM_GPIO = 16,
    parameter int unsigned APB_AW   = 16,
    parameter int unsigned APB_DW   = 32,
    parameter int unsigned DATA_W   = 8,
    parameter int unsigned ACC_W    = 32,
    parameter int unsigned M        = 16,
    parameter int unsigned N        = 16,
    parameter int unsigned K        = 16
) (
    // APB Subordinate Interface
    input  logic [APB_AW-1:0]   PADDR,
    input  logic                PENABLE,
    input  logic                PSEL,
    input  logic [APB_DW-1:0]   PWDATA,
    input  logic                PWRITE,
    output logic [APB_DW-1:0]   PRDATA,
    output logic                PREADY,
    output logic                PSLVERR,

    // Clock and Reset
    input  logic                clk,
    input  logic                reset_n,    // active-low from SoC

    // Interrupt
    output logic                irq,
    input  logic                irq_en,

    // PMOD GPIO (unused by accelerator, tied off)
    input  logic [NUM_GPIO-1:0] pmod_gpi,
    output logic [NUM_GPIO-1:0] pmod_gpio_oe,
    output logic [NUM_GPIO-1:0] pmod_gpo
);

    // Accelerator core instantiation
    accelerator_top #(
        .DATA_W (DATA_W),
        .ACC_W  (ACC_W),
        .M      (M),
        .N      (N),
        .K      (K),
        .APB_AW (10),
        .APB_DW (APB_DW)
    ) i_accelerator_top (
        .clk_in    (clk),
        .reset_int (~reset_n),       // accelerator_top expects active-high reset
        .PADDR     (PADDR[9:0]),     // accelerator uses lower 10 address bits
        .PSEL      (PSEL),
        .PENABLE   (PENABLE),
        .PWRITE    (PWRITE),
        .PWDATA    (PWDATA),
        .PRDATA    (PRDATA),
        .PREADY    (PREADY),
        .PSLVERR   (PSLVERR),
        .irq_en_4  (irq_en),
        .ss_ctrl_4 (8'b0),
        .irq_4     (irq)
    );

    // Unused GPIO signals safely tied off
    assign pmod_gpio_oe = '0;
    assign pmod_gpo     = '0;

endmodule
