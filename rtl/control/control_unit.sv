`include "accel_pkg.sv"

module control_unit
    import accel_pkg::*;
#(
    parameter int unsigned APB_AW    = 10,
    parameter int unsigned APB_DW    = 32,
    parameter int unsigned MATRIX_AW = 10
) (
    // System clock and reset
    input  logic                     clk_in,
    input  logic                     reset_int,    // active-high from SoC

    // APB subordinate interface
    input  logic [APB_AW-1:0]        PADDR,
    input  logic                     PENABLE,
    input  logic                     PSEL,
    input  logic [APB_DW-1:0]        PWDATA,
    input  logic                     PWRITE,
    output logic [APB_DW-1:0]        PRDATA,
    output logic                     PREADY,
    output logic                     PSLVERR,

    // SoC control & interrupt
    input  logic                     irq_en_4,
    input  logic [7:0]               ss_ctrl_4,
    output logic                     irq_4,

    // Matrix A/B/C external addressing (kept for interface; tied off in v1)
    output logic [MATRIX_AW-1:0]     matrix_a_addr,
    output logic                     matrix_a_ren,
    output logic [MATRIX_AW-1:0]     matrix_b_addr,
    output logic                     matrix_b_ren,
    output logic [MATRIX_AW-1:0]     matrix_c_addr,
    output logic                     matrix_c_wen,

    // Systolic array control
    output logic                     array_start,
    output logic                     array_clear,
    input  logic                     array_done,

    // Exposed register-file values (for top-level wiring)
    output logic [APB_DW-1:0]        cfg_m_dim,
    output logic [APB_DW-1:0]        cfg_n_dim,
    output logic [APB_DW-1:0]        cfg_k_dim,
    output logic                     soft_reset
);

#TODO: Implement control unit logic, including APB register decoding, control signal generation, and interrupt handling.

endmodule;