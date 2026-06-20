// -----------------------------------------------------------------------------
// matrix_buffer_ab.sv -- Matrix-A and Matrix-B input buffers with APB write
// port and a streaming read port for the systolic array.
//
// Optimized version: Uses 2D partitioned register arrays and sequential write
// counters to eliminate dynamic multipliers/dividers and reduce multiplexer scale.
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

    localparam int unsigned EPW           = APB_DW / DATA_W;          // elements per APB word
    localparam int unsigned M_W           = (M > 1) ? $clog2(M + 1) : 1;
    localparam int unsigned N_W           = (N > 1) ? $clog2(N + 1) : 1;
    localparam int unsigned K_W           = (K > 1) ? $clog2(K + 1) : 1;
    localparam int unsigned A_COL_IDX_W   = (K > 1) ? $clog2(K) : 1;
    localparam int unsigned B_ROW_IDX_W   = (K > 1) ? $clog2(K) : 1;

    // Storage banks - 2D Partitioned Array
    logic [DATA_W-1:0] mem_a [M][K];
    logic [DATA_W-1:0] mem_b [K][N];

    // Write pointers (2D counters)
    logic [M_W-1:0] a_wrow_q;
    logic [K_W-1:0] a_wcol_q;
    logic [K_W-1:0] b_wrow_q;
    logic [N_W-1:0] b_wcol_q;

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

    // Flag writes that would push past a bank's capacity
    assign PSLVERR    = apb_access && PWRITE &&
                        ((sel_a && (APB_DW'(a_wrow_q) >= cfg_m_dim)) ||
                         (sel_b && (APB_DW'(b_wrow_q) >= cfg_k_dim)));

    // -------------------------------------------------------------------------
    // Sequential 2D Write Pointer Incrementers (No multiplication/division)
    // -------------------------------------------------------------------------
    logic [M_W-1:0] a_wrow_d [EPW];
    logic [K_W-1:0] a_wcol_d [EPW];
    logic [M_W-1:0] next_a_wrow;
    logic [K_W-1:0] next_a_wcol;

    always_comb begin
        a_wrow_d = '{default: '0};
        a_wcol_d = '{default: '0};
        a_wrow_d[0] = a_wrow_q;
        a_wcol_d[0] = a_wcol_q;
        for (int e = 1; e < EPW; e++) begin
            if (a_wcol_d[e-1] == cfg_k_dim[K_W-1:0] - 1'b1) begin
                a_wcol_d[e] = '0;
                a_wrow_d[e] = a_wrow_d[e-1] + 1'b1;
            end else begin
                a_wcol_d[e] = a_wcol_d[e-1] + 1'b1;
                a_wrow_d[e] = a_wrow_d[e-1];
            end
        end

        if (a_wcol_d[EPW-1] == cfg_k_dim[K_W-1:0] - 1'b1) begin
            next_a_wcol = '0;
            next_a_wrow = a_wrow_d[EPW-1] + 1'b1;
        end else begin
            next_a_wcol = a_wcol_d[EPW-1] + 1'b1;
            next_a_wrow = a_wrow_d[EPW-1];
        end
    end

    logic [K_W-1:0] b_wrow_d [EPW];
    logic [N_W-1:0] b_wcol_d [EPW];
    logic [K_W-1:0] next_b_wrow;
    logic [N_W-1:0] next_b_wcol;

    always_comb begin
        b_wrow_d = '{default: '0};
        b_wcol_d = '{default: '0};
        b_wrow_d[0] = b_wrow_q;
        b_wcol_d[0] = b_wcol_q;
        for (int e = 1; e < EPW; e++) begin
            if (b_wcol_d[e-1] == cfg_n_dim[N_W-1:0] - 1'b1) begin
                b_wcol_d[e] = '0;
                b_wrow_d[e] = b_wrow_d[e-1] + 1'b1;
            end else begin
                b_wcol_d[e] = b_wcol_d[e-1] + 1'b1;
                b_wrow_d[e] = b_wrow_d[e-1];
            end
        end

        if (b_wcol_d[EPW-1] == cfg_n_dim[N_W-1:0] - 1'b1) begin
            next_b_wcol = '0;
            next_b_wrow = b_wrow_d[EPW-1] + 1'b1;
        end else begin
            next_b_wcol = b_wcol_d[EPW-1] + 1'b1;
            next_b_wrow = b_wrow_d[EPW-1];
        end
    end

    // -------------------------------------------------------------------------
    // APB write logic (zero-wait)
    // -------------------------------------------------------------------------
    logic ctrl_reset_ptrs;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            a_wrow_q <= '0;
            a_wcol_q <= '0;
            b_wrow_q <= '0;
            b_wcol_q <= '0;
        end else begin
            if (ctrl_reset_ptrs) begin
                a_wrow_q <= '0;
                a_wcol_q <= '0;
                b_wrow_q <= '0;
                b_wcol_q <= '0;
            end else begin
                if (apb_access && PWRITE && sel_a) begin
                    if (APB_DW'(a_wrow_q) < cfg_m_dim) begin
                        for (int e = 0; e < EPW; e++) begin
                            if (APB_DW'(a_wrow_d[e]) < cfg_m_dim)
                                mem_a[a_wrow_d[e]][a_wcol_d[e]] <= PWDATA[e*DATA_W +: DATA_W];
                        end
                        a_wrow_q <= next_a_wrow;
                        a_wcol_q <= next_a_wcol;
                    end
                end
                if (apb_access && PWRITE && sel_b) begin
                    if (APB_DW'(b_wrow_q) < cfg_k_dim) begin
                        for (int e = 0; e < EPW; e++) begin
                            if (APB_DW'(b_wrow_d[e]) < cfg_k_dim)
                                mem_b[b_wrow_d[e]][b_wcol_d[e]] <= PWDATA[e*DATA_W +: DATA_W];
                        end
                        b_wrow_q <= next_b_wrow;
                        b_wcol_q <= next_b_wcol;
                    end
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
            PRDATA[1] = (APB_DW'(a_wrow_q) >= cfg_m_dim);
            PRDATA[2] = (APB_DW'(b_wrow_q) >= cfg_k_dim);
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

    // Inactive physical rows/columns are streamed as zero.
    genvar gi, gj;
    generate
        for (gi = 0; gi < M; gi++) begin : g_a_drive
            assign a_col[(gi+1)*DATA_W-1 -: DATA_W] =
                (APB_DW'(gi) < cfg_m_dim) ? mem_a[gi][k_q[A_COL_IDX_W-1:0]] : '0;
        end
        for (gj = 0; gj < N; gj++) begin : g_b_drive
            assign b_row[(gj+1)*DATA_W-1 -: DATA_W] =
                (APB_DW'(gj) < cfg_n_dim) ? mem_b[k_q[B_ROW_IDX_W-1:0]][gj] : '0;
        end
    endgenerate

endmodule
