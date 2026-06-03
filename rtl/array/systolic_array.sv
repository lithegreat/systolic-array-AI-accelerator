// -----------------------------------------------------------------------------
// systolic_array.sv -- output-stationary M x N systolic array.
//
// Dataflow:
//   * Output-stationary: each PE owns one C[i,j] and accumulates K products.
//   * Per cycle the buffer presents a column slice of A (a_col, M elements)
//     and a row slice of B (b_row, N elements), both indexed by the same k.
//   * Internal skew shift chains delay row i's west feed by i cycles and
//     col j's north feed by j cycles, producing the classic OS schedule.
//   * Each PE samples its inputs during a K-wide window starting at cycle
//     t = i + j (relative to the start of computation). The first cycle
//     in that window asserts clear_acc to initialise the accumulator.
//
// Streaming protocol:
//   * `start` (1-cycle pulse) launches a tile compute. While compute is
//     running, the array asserts `in_ready` for the first K cycles and
//     consumes (a_col, b_row) on every (in_valid && in_ready) cycle.
//   * After M + N + K - 2 cycles of computation, the array switches to
//     drain mode: one full C row (N accumulators packed into c_row_data) is
//     emitted per accepted cycle (out_valid && out_ready), top row first.
//   * `done` pulses for one cycle after the last C row is accepted.
// -----------------------------------------------------------------------------
module systolic_array #(
    parameter int unsigned DATA_W = 16,
    parameter int unsigned ACC_W  = 32,
    parameter int unsigned M      = 16,
    parameter int unsigned N      = 16,
    parameter int unsigned K      = 16
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

    // Streaming output (one full C row, N accumulators, per beat).
    output logic                              out_valid,
    input  logic                              out_ready,
    output logic [N*ACC_W-1:0]                c_row_data,
    output logic [((M>1)?$clog2(M):1)-1:0]    c_row
);

    // -------------------------------------------------------------------------
    // Sizing constants
    // -------------------------------------------------------------------------
    localparam int unsigned COMPUTE_CYCLES = M + N + K - 2; // last cycle index = COMPUTE_CYCLES-1
    localparam int unsigned DRAIN_COUNT    = M;             // one row emitted per beat
    localparam int unsigned T_W            = $clog2(COMPUTE_CYCLES + 1);
    localparam int unsigned K_W            = $clog2(K + 1);
    localparam int unsigned D_W            = $clog2(DRAIN_COUNT + 1);
    localparam int unsigned ROW_W          = (M > 1) ? $clog2(M) : 1;

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {S_IDLE, S_RUN, S_DRAIN, S_DONE} state_e;
    state_e state_q, state_d;

    logic [T_W-1:0] t_cnt_q;   // computation cycle counter
    logic [K_W-1:0] k_cnt_q;   // accepted input beats
    logic [D_W-1:0] d_cnt_q;   // drained output beats

    logic step;        // advance compute pipeline this cycle
    logic accept_in;   // (in_valid && in_ready)
    logic accept_out;  // (out_valid && out_ready)

    assign in_ready  = (state_q == S_RUN) && (k_cnt_q < K[K_W-1:0]);
    assign accept_in = in_ready && in_valid;
    // While loading we wait for input; after load the pipeline ticks every cycle.
    assign step      = (state_q == S_RUN) && ((k_cnt_q >= K[K_W-1:0]) || in_valid);

    assign out_valid  = (state_q == S_DRAIN);
    assign accept_out = out_valid && out_ready;
    assign done       = (state_q == S_DONE);

    always_comb begin
        state_d = state_q;
        unique case (state_q)
            S_IDLE: if (start) state_d = S_RUN;
            S_RUN:  if (step && (t_cnt_q == COMPUTE_CYCLES[T_W-1:0] - 1))
                        state_d = S_DRAIN;
            S_DRAIN: if (accept_out && (d_cnt_q == DRAIN_COUNT[D_W-1:0] - 1))
                        state_d = S_DONE;
            S_DONE: state_d = S_IDLE;
            default: state_d = S_IDLE;
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_q <= S_IDLE;
            t_cnt_q <= '0;
            k_cnt_q <= '0;
            d_cnt_q <= '0;
        end else begin
            state_q <= state_d;

            if (state_q == S_IDLE && start) begin
                t_cnt_q <= '0;
                k_cnt_q <= '0;
                d_cnt_q <= '0;
            end else begin
                if (step)      t_cnt_q <= t_cnt_q + 1'b1;
                if (accept_in) k_cnt_q <= k_cnt_q + 1'b1;
                if (accept_out) d_cnt_q <= d_cnt_q + 1'b1;
                if (state_q == S_DONE) begin
                    t_cnt_q <= '0;
                    k_cnt_q <= '0;
                    d_cnt_q <= '0;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Unpack input vectors
    // -------------------------------------------------------------------------
    logic signed [DATA_W-1:0] a_col_arr [M];
    logic signed [DATA_W-1:0] b_row_arr [N];
    genvar gi, gj;
    generate
        for (gi = 0; gi < M; gi++) begin : g_unpack_a
            assign a_col_arr[gi] = a_col[(gi+1)*DATA_W-1 -: DATA_W];
        end
        for (gj = 0; gj < N; gj++) begin : g_unpack_b
            assign b_row_arr[gj] = b_row[(gj+1)*DATA_W-1 -: DATA_W];
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Skew shift chains (row i feed delayed by i cycles, col j by j cycles)
    // -------------------------------------------------------------------------
    logic signed [DATA_W-1:0] a_west [M];   // westmost input to row i
    logic signed [DATA_W-1:0] b_north [N];  // northmost input to col j

    // Provide zeros once load window has elapsed.
    logic signed [DATA_W-1:0] a_feed [M];
    logic signed [DATA_W-1:0] b_feed [N];
    generate
        for (gi = 0; gi < M; gi++) begin : g_a_feed
            assign a_feed[gi] = (k_cnt_q < K[K_W-1:0]) ? a_col_arr[gi] : '0;
        end
        for (gj = 0; gj < N; gj++) begin : g_b_feed
            assign b_feed[gj] = (k_cnt_q < K[K_W-1:0]) ? b_row_arr[gj] : '0;
        end
    endgenerate

    // Row i feed delayed by i cycles; col j feed delayed by j cycles.
    generate
        for (gi = 0; gi < M; gi++) begin : g_a_skew
            skew_shift #(.W(DATA_W), .DEPTH(gi)) u_a_skew (
                .clk(clk), .rst_n(rst_n), .step(step),
                .d_in(a_feed[gi]), .d_out(a_west[gi])
            );
        end
        for (gj = 0; gj < N; gj++) begin : g_b_skew
            skew_shift #(.W(DATA_W), .DEPTH(gj)) u_b_skew (
                .clk(clk), .rst_n(rst_n), .step(step),
                .d_in(b_feed[gj]), .d_out(b_north[gj])
            );
        end
    endgenerate

    // -------------------------------------------------------------------------
    // PE grid
    // -------------------------------------------------------------------------
    logic signed [DATA_W-1:0] pe_a [M][N+1]; // [*][0] = west input, [*][N] = east overflow
    logic signed [DATA_W-1:0] pe_b [M+1][N]; // [0][*] = north input, [M][*] = south overflow
    logic signed [ACC_W-1:0]  pe_out [M][N];

    generate
        for (gi = 0; gi < M; gi++) begin : g_pe_west_in
            assign pe_a[gi][0] = a_west[gi];
        end
        for (gj = 0; gj < N; gj++) begin : g_pe_north_in
            assign pe_b[0][gj] = b_north[gj];
        end
    endgenerate

    generate
        for (gi = 0; gi < M; gi++) begin : g_pe_row
            for (gj = 0; gj < N; gj++) begin : g_pe_col
                logic en_pe;
                logic clr_pe;
                // Window: t in [i+j, i+j+K-1]
                assign en_pe  = step
                                && (t_cnt_q >= (gi + gj))
                                && (t_cnt_q <  (gi + gj + K));
                assign clr_pe = en_pe && (t_cnt_q == (gi + gj));

                mac_pe #(
                    .DATA_W(DATA_W),
                    .ACC_W (ACC_W)
                ) u_pe (
                    .clk      (clk),
                    .rst_n    (rst_n),
                    .en       (en_pe),
                    .clear_acc(clr_pe),
                    .a_in     (pe_a[gi][gj]),
                    .b_in     (pe_b[gi][gj]),
                    .a_out    (pe_a[gi][gj+1]),
                    .b_out    (pe_b[gi+1][gj]),
                    .pe_out   (pe_out[gi][gj])
                );
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Drain logic: emit one full C row (N accumulators) per beat, top row
    // first. Works for any M, N (no power-of-two restriction).
    // -------------------------------------------------------------------------
    logic [ROW_W-1:0] drain_row_q;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            drain_row_q <= '0;
        end else if (state_q == S_IDLE && start) begin
            drain_row_q <= '0;
        end else if (state_q == S_DONE) begin
            drain_row_q <= '0;
        end else if (accept_out) begin
            drain_row_q <= drain_row_q + 1'b1;
        end
    end

    // Pack the selected row's N accumulators LSB-first (column 0 in low bits).
    generate
        for (gj = 0; gj < N; gj++) begin : g_drain_pack
            assign c_row_data[(gj+1)*ACC_W-1 -: ACC_W] = pe_out[drain_row_q][gj];
        end
    endgenerate

    assign c_row = drain_row_q;

endmodule
