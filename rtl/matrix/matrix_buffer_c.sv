// -----------------------------------------------------------------------------
// matrix_buffer_c.sv -- Matrix-C output buffer.
//
// Captures one (c_data, c_row, c_col) per cycle when c_in_valid is high
// (always-ready). Provides APB read-back at offset 0x00 with auto-incrementing
// read pointer; control bits at offset 0x80.
//
// APB map (offsets):
//   0x00 MAT_C_DATA (R/O) : read packed elements from C, auto-increment.
//   0x80 MAT_CTRL   (R/W) : [0]=reset read pointer (W1S), [1]=full flag (RO).
//
// Storage layout: row-major C[i,j] -> offset i*N + j.
// Each ACC_W-wide accumulator value is exposed truncated/zero-extended to APB_DW.
// -----------------------------------------------------------------------------
module matrix_buffer_c #(
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

    // Capture from systolic array
    input  logic                       c_in_valid,
    input  logic [ACC_W-1:0]           c_data_in,
    input  logic [$clog2((M>1)?M:2)-1:0] c_row_in,
    input  logic [$clog2((N>1)?N:2)-1:0] c_col_in
);

    localparam int unsigned C_DEPTH = M * N;
    localparam int unsigned PTR_W   = (C_DEPTH > 1) ? $clog2(C_DEPTH + 1) : 1;

    logic [ACC_W-1:0] mem_c [C_DEPTH];
    logic [PTR_W-1:0] r_ptr;
    logic [PTR_W-1:0] capture_count;

    logic c_in_ready;
    logic capture_full;
    assign c_in_ready   = (capture_count < C_DEPTH);
    assign capture_full = (capture_count >= C_DEPTH);

    logic apb_access;
    assign apb_access = PSEL && PENABLE;
    assign PREADY     = 1'b1;
    assign PSLVERR    = 1'b0;

    logic sel_data, sel_ctrl;
    assign sel_data = (PADDR[7:0] == 8'h00);
    assign sel_ctrl = (PADDR[7:0] == 8'h80);

    // -------------------------------------------------------------------------
    // Capture path
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            capture_count <= '0;
            for (int i = 0; i < C_DEPTH; i++) mem_c[i] <= '0;
        end else if (apb_access && PWRITE && sel_ctrl && PWDATA[0]) begin
            capture_count <= '0;
        end else if (c_in_valid && c_in_ready) begin
            mem_c[c_row_in * N + c_col_in] <= c_data_in;
            capture_count <= capture_count + 1'b1;
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
