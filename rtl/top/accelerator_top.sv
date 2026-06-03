// -----------------------------------------------------------------------------
// accelerator_top.sv -- top-level wrapper integrating control_unit,
// matrix_buffer_ab, systolic_array, and matrix_buffer_c behind a single
// APB subordinate port.
//
// Address decoding (within the subsystem window):
//   PADDR[9:8] = 2'b00 -> matrix_buffer_ab  (A @ 0x00, B @ 0x40, CTRL @ 0x80)
//   PADDR[9:8] = 2'b01 -> control_unit       (regmap @ 0x100)
//   PADDR[9:8] = 2'b10 -> matrix_buffer_c    (DATA @ 0x200, CTRL @ 0x280)
// -----------------------------------------------------------------------------
`include "accel_pkg.sv"

module accelerator_top
    import accel_pkg::*;
#(
    parameter int unsigned DATA_W = 16,
    parameter int unsigned ACC_W  = 32,
    parameter int unsigned M      = 16,
    parameter int unsigned N      = 16,
    parameter int unsigned K      = 16,
    parameter int unsigned APB_AW = 10,
    parameter int unsigned APB_DW = 32
) (
    input  logic                  clk_in,
    input  logic                  reset_int,    // active-high

    // APB subordinate
    input  logic [APB_AW-1:0]     PADDR,
    input  logic                  PSEL,
    input  logic                  PENABLE,
    input  logic                  PWRITE,
    input  logic [APB_DW-1:0]     PWDATA,
    output logic [APB_DW-1:0]     PRDATA,
    output logic                  PREADY,
    output logic                  PSLVERR,

    // SoC IRQ
    input  logic                  irq_en_4,
    input  logic [7:0]            ss_ctrl_4,
    output logic                  irq_4
);

    logic clk;
    logic rst_n;
    assign clk   = clk_in;
    assign rst_n = ~reset_int;

    // -------------------------------------------------------------------------
    // Address decode
    // -------------------------------------------------------------------------
    logic sel_ab, sel_ctrl, sel_c;
    assign sel_ab   = PSEL && (PADDR[9:8] == 2'b00);
    assign sel_ctrl = PSEL && (PADDR[9:8] == 2'b01);
    assign sel_c    = PSEL && (PADDR[9:8] == 2'b10);

    logic [APB_DW-1:0] prdata_ab, prdata_ctrl, prdata_c;
    logic ready_ab, ready_ctrl, ready_c;
    logic err_ab, err_ctrl, err_c;

    always_comb begin
        if      (sel_ctrl) PRDATA = prdata_ctrl;
        else if (sel_c)    PRDATA = prdata_c;
        else if (sel_ab)   PRDATA = prdata_ab;
        else               PRDATA = '0;
        PREADY  = (sel_ab & ready_ab) | (sel_ctrl & ready_ctrl) | (sel_c & ready_c) | ~PSEL;
        PSLVERR = (sel_ab & err_ab)   | (sel_ctrl & err_ctrl)   | (sel_c & err_c);
    end

    // -------------------------------------------------------------------------
    // Internal interconnect signals
    // -------------------------------------------------------------------------
    logic                array_start;
    logic                array_clear;
    logic                array_done;

    logic                mat_valid;
    logic                sys_ready;
    logic [M*DATA_W-1:0] a_col;
    logic [N*DATA_W-1:0] b_row;

    logic                out_valid;
    logic                out_ready;
    logic [ACC_W-1:0]    c_data;
    logic [$clog2((M>1)?M:2)-1:0] c_row;
    logic [$clog2((N>1)?N:2)-1:0] c_col;

    // -------------------------------------------------------------------------
    // control_unit
    // -------------------------------------------------------------------------
    control_unit #(
        .APB_AW   (APB_AW),
        .APB_DW   (APB_DW)
    ) u_control (
        .clk_in       (clk_in),
        .reset_int    (reset_int),
        .PADDR        (PADDR),
        .PENABLE      (PENABLE),
        .PSEL         (sel_ctrl),
        .PWDATA       (PWDATA),
        .PWRITE       (PWRITE),
        .PRDATA       (prdata_ctrl),
        .PREADY       (ready_ctrl),
        .PSLVERR      (err_ctrl),
        .irq_en_4     (irq_en_4),
        .ss_ctrl_4    (ss_ctrl_4),
        .irq_4        (irq_4),
        .array_start  (array_start),
        .array_clear  (array_clear),
        .array_done   (array_done)
    );

    // -------------------------------------------------------------------------
    // matrix_buffer_ab
    // -------------------------------------------------------------------------
    matrix_buffer_ab #(
        .DATA_W(DATA_W),
        .M     (M),
        .N     (N),
        .K     (K),
        .APB_AW(APB_AW),
        .APB_DW(APB_DW)
    ) u_mat_ab (
        .clk      (clk),
        .rst_n    (rst_n),
        .PADDR    (PADDR),
        .PSEL     (sel_ab),
        .PENABLE  (PENABLE),
        .PWRITE   (PWRITE),
        .PWDATA   (PWDATA),
        .PRDATA   (prdata_ab),
        .PREADY   (ready_ab),
        .PSLVERR  (err_ab),
        .mat_start(array_start),
        .mat_valid(mat_valid),
        .sys_ready(sys_ready),
        .a_col    (a_col),
        .b_row    (b_row)
    );

    // -------------------------------------------------------------------------
    // systolic_array
    // -------------------------------------------------------------------------
    systolic_array #(
        .DATA_W(DATA_W),
        .ACC_W (ACC_W),
        .M     (M),
        .N     (N),
        .K     (K)
    ) u_array (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (array_start),
        .done     (array_done),
        .in_valid (mat_valid),
        .in_ready (sys_ready),
        .a_col    (a_col),
        .b_row    (b_row),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .c_data   (c_data),
        .c_row    (c_row),
        .c_col    (c_col)
    );

    // -------------------------------------------------------------------------
    // matrix_buffer_c
    // -------------------------------------------------------------------------
    assign out_ready = 1'b1;  // capture buffer always ready in v1

    matrix_buffer_c #(
        .ACC_W (ACC_W),
        .M     (M),
        .N     (N),
        .APB_AW(APB_AW),
        .APB_DW(APB_DW)
    ) u_mat_c (
        .clk         (clk),
        .rst_n       (rst_n),
        .PADDR       (PADDR),
        .PSEL        (sel_c),
        .PENABLE     (PENABLE),
        .PWRITE      (PWRITE),
        .PWDATA      (PWDATA),
        .PRDATA      (prdata_c),
        .PREADY      (ready_c),
        .PSLVERR     (err_c),
        .c_in_valid  (out_valid),
        .c_data_in   (c_data),
        .c_row_in    (c_row),
        .c_col_in    (c_col)
    );

endmodule
