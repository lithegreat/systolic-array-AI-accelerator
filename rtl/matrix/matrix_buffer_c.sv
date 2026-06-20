// -----------------------------------------------------------------------------
// matrix_buffer_c.sv -- Matrix-C output buffer.
//
// Optimized version: Uses 2D partitioned register arrays and sequential read/capture
// counters to eliminate dynamic multipliers/dividers and reduce multiplexer scale.
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
    input  logic [$clog2((M>1)?M:2)-1:0] c_row_in,

    // Runtime compact-tile dimensions (1..physical M/N).
    input  logic [APB_DW-1:0]          cfg_m_dim,
    input  logic [APB_DW-1:0]          cfg_n_dim
);

    localparam int unsigned M_W     = (M > 1) ? $clog2(M + 1) : 1;
    localparam int unsigned N_W     = (N > 1) ? $clog2(N + 1) : 1;
    localparam int unsigned ROW_W   = (M > 1) ? $clog2(M + 1) : 1;

    // Storage banks - 2D Partitioned Array
    logic [ACC_W-1:0] mem_c [M][N];

    // Read pointers (2D counters)
    logic [M_W-1:0] r_row_q;
    logic [N_W-1:0] r_col_q;

    logic [ROW_W-1:0] rows_captured;   // number of C rows captured

    logic c_in_ready;
    logic capture_full;
    assign c_in_ready   = (APB_DW'(rows_captured) < cfg_m_dim);
    assign capture_full = (APB_DW'(rows_captured) >= cfg_m_dim);

    logic apb_access;
    assign apb_access = PSEL && PENABLE;
    assign PREADY     = 1'b1;

    logic sel_data, sel_ctrl;
    assign sel_data = (PADDR[7:0] == MAT_C_DATA_OFF);
    assign sel_ctrl = (PADDR[7:0] == MAT_C_CTRL_OFF);

    // Flag reads past the captured C window as an error.
    assign PSLVERR    = apb_access && !PWRITE && sel_data && (APB_DW'(r_row_q) >= cfg_m_dim);

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
                if (APB_DW'(j) < cfg_n_dim) begin
                    mem_c[c_row_in][j] <= c_row_data_in[j*ACC_W +: ACC_W];
                end
            end
            rows_captured <= rows_captured + 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // APB read pointer
    // -------------------------------------------------------------------------
    logic [M_W-1:0] next_r_row;
    logic [N_W-1:0] next_r_col;

    always_comb begin
        if (r_col_q == cfg_n_dim[N_W-1:0] - 1'b1) begin
            next_r_col = '0;
            next_r_row = r_row_q + 1'b1;
        end else begin
            next_r_col = r_col_q + 1'b1;
            next_r_row = r_row_q;
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            r_row_q <= '0;
            r_col_q <= '0;
        end else if (apb_access && PWRITE && sel_ctrl && PWDATA[0]) begin
            r_row_q <= '0;
            r_col_q <= '0;
        end else if (apb_access && !PWRITE && sel_data) begin
            if (APB_DW'(r_row_q) < cfg_m_dim) begin
                r_row_q <= next_r_row;
                r_col_q <= next_r_col;
            end
        end
    end

    always_comb begin
        PRDATA = '0;
        if (apb_access && !PWRITE) begin
            if (sel_data) begin
                PRDATA = (APB_DW'(r_row_q) < cfg_m_dim) ? mem_c[r_row_q][r_col_q][APB_DW-1:0] : '0;
            end else if (sel_ctrl) begin
                PRDATA[1] = capture_full;
            end
        end
    end

endmodule
