// -----------------------------------------------------------------------------
// matrix_buffer_c.sv -- Matrix-C output buffer.
//
// Captures one full C row (N accumulators in c_row_data_in) per cycle when
// c_in_valid is high (always-ready). Provides APB read-back at offset 0x00 with
// auto-incrementing read pointer; control bits at offset 0x80.
//
// APB map (offsets):
//   0x00 MAT_C_DATA (R/O) : read packed elements from C, auto-increment.
//   0x80 MAT_CTRL   (R/W) : [0]=reset read pointer (W1S), [1]=full flag (RO).
//
// Storage layout: row-major C[i,j] -> offset i*N + j.
// Each ACC_W-wide accumulator value is exposed truncated/zero-extended to APB_DW.
// -----------------------------------------------------------------------------
`include "accel_pkg.sv"

module matrix_buffer_c
    import accel_pkg::*;
#(
    parameter int unsigned ACC_W  = 32,
    parameter int unsigned M      = 16,
    parameter int unsigned N      = 16,
    parameter int unsigned APB_AW = 10,
    parameter int unsigned APB_DW = 32
) (
    input  logic                       clk,
    input  logic                       rst_n,

    // APB subordinate
    input  logic [APB_AW-1:0]          PADDR,
    input  logic                       PSEL,
    input  logic                       PENABLE,
    input  logic                       PWRITE,
    input  logic [APB_DW-1:0]          PWDATA,
    output logic [APB_DW-1:0]          PRDATA,
    output logic                       PREADY,
    output logic                       PSLVERR,

    // Capture from systolic array (one full C row per beat)
    input  logic                       c_in_valid,
    input  logic [N*ACC_W-1:0]         c_row_data_in,
    input  logic [$clog2((M>1)?M:2)-1:0] c_row_in
);

    localparam int unsigned C_DEPTH = M * N;
    localparam int unsigned PTR_W   = (C_DEPTH > 1) ? $clog2(C_DEPTH + 1) : 1;
    localparam int unsigned ROW_W   = (M > 1) ? $clog2(M + 1) : 1;

    logic [ACC_W-1:0] mem_c [C_DEPTH];
    logic [PTR_W-1:0] r_ptr;
    logic [ROW_W-1:0] rows_captured;   // number of C rows captured

    logic c_in_ready;
    logic capture_full;
    assign c_in_ready   = (rows_captured < M);
    assign capture_full = (rows_captured >= M);

    logic apb_access;
    assign apb_access = PSEL && PENABLE;
    assign PREADY     = 1'b1;
    // Flag reads past the captured C window as an error.
    assign PSLVERR    = apb_access && !PWRITE && sel_data && (r_ptr >= C_DEPTH[PTR_W-1:0]);

    logic sel_data, sel_ctrl;
    assign sel_data = (PADDR[7:0] == MAT_C_DATA_OFF);
    assign sel_ctrl = (PADDR[7:0] == MAT_C_CTRL_OFF);

    // -------------------------------------------------------------------------
    // Capture path: write all N columns of the incoming row in one cycle.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rows_captured <= '0;
        end else if (apb_access && PWRITE && sel_ctrl && PWDATA[0]) begin
            rows_captured <= '0;
        end else if (c_in_valid && c_in_ready) begin
            for (int j = 0; j < N; j++) begin
                mem_c[c_row_in * N + j] <= c_row_data_in[j*ACC_W +: ACC_W];
            end
            rows_captured <= rows_captured + 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // APB read pointer
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            r_ptr <= '0;
        end else if (apb_access && PWRITE && sel_ctrl && PWDATA[0]) begin
            r_ptr <= '0;
        end else if (apb_access && !PWRITE && sel_data) begin
            if (r_ptr < C_DEPTH)
                r_ptr <= r_ptr + 1'b1;
        end
    end

    always_comb begin
        PRDATA = '0;
        if (apb_access && !PWRITE) begin
            if (sel_data) begin
                PRDATA = (r_ptr < C_DEPTH) ? mem_c[r_ptr][APB_DW-1:0] : '0;
            end else if (sel_ctrl) begin
                PRDATA[1] = capture_full;
            end
        end
    end

endmodule
