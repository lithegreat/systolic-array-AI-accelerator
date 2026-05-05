module systolic_array #(
    parameter int unsigned DATA_W = 16,
    parameter int unsigned ACC_W  = 32,
    parameter int unsigned M      = 4,
    parameter int unsigned N      = 4,
    parameter int unsigned K      = 4
) (
    input  logic                              clk,
    input  logic                              rst_n,

    input  logic                              start,
    output logic                              done,

    // Streaming input (one column of A and one row of B per beat).
    input  logic                              in_valid,
    output logic                              in_ready,
    input  logic [M*DATA_W-1:0]               a_col,
    input  logic [N*DATA_W-1:0]               b_row,

    // Streaming output (one C element per beat).
    output logic                              out_valid,
    input  logic                              out_ready,
    output logic [ACC_W-1:0]                  c_data,
    output logic [$clog2(M)-1:0]              c_row,
    output logic [$clog2(N)-1:0]              c_col
);

endmodule