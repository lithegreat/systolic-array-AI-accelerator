module control_unit #(
    parameter APB_AW    = 10,
    parameter APB_DW    = 32,
    parameter MATRIX_AW = 10  // Temporary parameter for Matrix address width
) (
    // System Clock and Reset
    input  logic                 clk_in,
    input  logic                 reset_int,

    // APB Subordinate Interface
    input  logic [APB_AW-1:0]    PADDR,
    input  logic                 PENABLE,
    input  logic                 PSEL,
    input  logic [APB_DW-1:0]    PWDATA,
    input  logic                 PWRITE,
    output logic [APB_DW-1:0]    PRDATA,
    output logic                 PREADY,
    output logic                 PSLVERR,

    // SoC Control & Interrupt
    input  logic                 irq_en_4,
    input  logic [7:0]           ss_ctrl_4,
    output logic                 irq_4,

    // AI Accelerator Internal Interface - Matrix A
    output logic [MATRIX_AW-1:0] matrix_a_addr,
    output logic                 matrix_a_ren,

    // AI Accelerator Internal Interface - Matrix B
    output logic [MATRIX_AW-1:0] matrix_b_addr,
    output logic                 matrix_b_ren,

    // AI Accelerator Internal Interface - Matrix C
    output logic [MATRIX_AW-1:0] matrix_c_addr,
    output logic                 matrix_c_wen,

    // AI Accelerator Internal Interface - Systolic Array
    output logic                 array_start,
    output logic                 array_clear,
    input  logic                 array_done
);

    // TODO: Implement APB decoding, registers MAP and Accelerator control FSM

endmodule
