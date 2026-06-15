// -----------------------------------------------------------------------------
// matrix_buffer_ab.sv -- Matrix-A and Matrix-B input buffers with APB write
// port and a streaming read port for the systolic array.
//
// APB write map (offsets):
//   0x00 MAT_A_DATA  (W/O) : write packed elements into A, auto-increment.
//   0x40 MAT_B_DATA  (W/O) : write packed elements into B, auto-increment.
//   0x80 MAT_CTRL    (R/W) : [0]=reset write pointers (write-1-self-clear),
//                            [1]=A bank full, [2]=B bank full (RO bits).
//
// Each APB write unpacks `APB_DW/DATA_W` elements (LSB-first) into the bank.
// Storage holds the matrices in row-major order:
//   A[i,k] -> offset i*K + k
//   B[k,j] -> offset k*N + j
//
// Streaming read port (to systolic_array):
//   * On `mat_start`, present beat-0 immediately with mat_valid=1.
//   * On every (mat_valid && sys_ready) edge, advance to next k.
//   * After K beats, mat_valid drops; mat_done pulses one cycle.
// -----------------------------------------------------------------------------
`include "accel_pkg.sv"

module matrix_buffer_ab
    import accel_pkg::*;
#(
    parameter int unsigned DATA_W = 8,
    parameter int unsigned M      = 16,
    parameter int unsigned N      = 16,
    parameter int unsigned K      = 16,
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

    // Streaming control
    input  logic                       mat_start,
    output logic                       mat_valid,
    input  logic                       sys_ready,

    // Runtime compact-tile dimensions (1..physical M/N/K).
    input  logic [APB_DW-1:0]          cfg_m_dim,
    input  logic [APB_DW-1:0]          cfg_n_dim,
    input  logic [APB_DW-1:0]          cfg_k_dim,

    // Streaming data (one column of A, one row of B per beat)
    output logic [M*DATA_W-1:0]        a_col,
    output logic [N*DATA_W-1:0]        b_row
);

    localparam int unsigned A_DEPTH       = M * K;
    localparam int unsigned B_DEPTH       = K * N;
    localparam int unsigned EPW           = APB_DW / DATA_W;          // elements per APB word
    localparam int unsigned A_ADDR_W      = (A_DEPTH > 1) ? $clog2(A_DEPTH) : 1;
    localparam int unsigned B_ADDR_W      = (B_DEPTH > 1) ? $clog2(B_DEPTH) : 1;
    localparam int unsigned A_PTR_W       = (A_DEPTH > 1) ? $clog2(A_DEPTH + 1) : 1;
    localparam int unsigned B_PTR_W       = (B_DEPTH > 1) ? $clog2(B_DEPTH + 1) : 1;
    localparam int unsigned K_W           = (K > 1) ? $clog2(K + 1) : 1;

    logic [APB_DW-1:0] active_a_depth;
    logic [APB_DW-1:0] active_b_depth;
    assign active_a_depth = cfg_m_dim * cfg_k_dim;
    assign active_b_depth = cfg_k_dim * cfg_n_dim;

    // Storage banks
    logic [DATA_W-1:0] mem_a [A_DEPTH];
    logic [DATA_W-1:0] mem_b [B_DEPTH];

    // Write pointers
    logic [A_PTR_W-1:0] a_wptr;
    logic [B_PTR_W-1:0] b_wptr;

    // -------------------------------------------------------------------------
    // APB transaction qualifier
    // -------------------------------------------------------------------------
    logic apb_access;
    assign apb_access = PSEL && PENABLE;
    assign PREADY     = 1'b1;

    // Decode by local offset (from accel_pkg)
    logic sel_a, sel_b, sel_ctrl;
    assign sel_a    = (PADDR[7:0] == MAT_A_DATA_OFF);
    assign sel_b    = (PADDR[7:0] == MAT_B_DATA_OFF);
    assign sel_ctrl = (PADDR[7:0] == MAT_AB_CTRL_OFF);

    // Flag writes that would push past a bank's capacity so software
    // over-runs surface instead of being silently dropped.
    assign PSLVERR    = apb_access && PWRITE &&
                        ((sel_a && (APB_DW'(a_wptr) >= active_a_depth)) ||
                         (sel_b && (APB_DW'(b_wptr) >= active_b_depth)));

    // -------------------------------------------------------------------------
    // APB write logic (zero-wait)
    // -------------------------------------------------------------------------
    logic ctrl_reset_ptrs;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            a_wptr <= '0;
            b_wptr <= '0;
        end else begin
            if (ctrl_reset_ptrs) begin
                a_wptr <= '0;
                b_wptr <= '0;
            end else begin
                if (apb_access && PWRITE && sel_a) begin
                    for (int e = 0; e < EPW; e++) begin
                        if (APB_DW'(a_wptr + e) < active_a_depth)
                            mem_a[a_wptr + e] <= PWDATA[e*DATA_W +: DATA_W];
                    end
                    a_wptr <= a_wptr + EPW;
                end
                if (apb_access && PWRITE && sel_b) begin
                    for (int e = 0; e < EPW; e++) begin
                        if (APB_DW'(b_wptr + e) < active_b_depth)
                            mem_b[b_wptr + e] <= PWDATA[e*DATA_W +: DATA_W];
                    end
                    b_wptr <= b_wptr + EPW;
                end
            end
        end
    end

    assign ctrl_reset_ptrs = apb_access && PWRITE && sel_ctrl && PWDATA[0];

    // -------------------------------------------------------------------------
    // APB read
    // -------------------------------------------------------------------------
    always_comb begin
        PRDATA = '0;
        if (apb_access && !PWRITE && sel_ctrl) begin
            PRDATA[1] = (APB_DW'(a_wptr) >= active_a_depth);
            PRDATA[2] = (APB_DW'(b_wptr) >= active_b_depth);
        end
    end

    // -------------------------------------------------------------------------
    // Streaming side: produce K beats of (a_col, b_row).
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {S_IDLE, S_RUN, S_DONE} stream_state_e;
    stream_state_e s_q, s_d;
    logic [K_W-1:0] k_q;
    logic [K_W-1:0] cfg_k_last;
    assign cfg_k_last = cfg_k_dim[K_W-1:0] - 1'b1;

    assign mat_valid = (s_q == S_RUN);

    always_comb begin
        s_d = s_q;
        unique case (s_q)
            S_IDLE: if (mat_start) s_d = S_RUN;
            S_RUN:  if (mat_valid && sys_ready && (k_q == cfg_k_last))
                        s_d = S_DONE;
            S_DONE: s_d = S_IDLE;
            default: s_d = S_IDLE;
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            s_q <= S_IDLE;
            k_q <= '0;
        end else begin
            s_q <= s_d;
            if (s_q == S_IDLE && mat_start) begin
                k_q <= '0;
            end else if (mat_valid && sys_ready) begin
                k_q <= k_q + 1'b1;
            end
            if (s_q == S_DONE) k_q <= '0;
        end
    end

    // Compact runtime tile layout:
    //   A[i,k] -> i*cfg_k_dim + k for i < cfg_m_dim, k < cfg_k_dim
    //   B[k,j] -> k*cfg_n_dim + j for k < cfg_k_dim, j < cfg_n_dim
    // Inactive physical rows/columns are streamed as zero.
    genvar gi, gj;
    generate
        for (gi = 0; gi < M; gi++) begin : g_a_drive
            logic [APB_DW-1:0] a_idx;
            assign a_idx = (APB_DW'(gi) * cfg_k_dim) + APB_DW'(k_q);
            assign a_col[(gi+1)*DATA_W-1 -: DATA_W] =
                (APB_DW'(gi) < cfg_m_dim) ? mem_a[a_idx[A_ADDR_W-1:0]] : '0;
        end
        for (gj = 0; gj < N; gj++) begin : g_b_drive
            logic [APB_DW-1:0] b_idx;
            assign b_idx = (APB_DW'(k_q) * cfg_n_dim) + APB_DW'(gj);
            assign b_row[(gj+1)*DATA_W-1 -: DATA_W] =
                (APB_DW'(gj) < cfg_n_dim) ? mem_b[b_idx[B_ADDR_W-1:0]] : '0;
        end
    endgenerate

endmodule
