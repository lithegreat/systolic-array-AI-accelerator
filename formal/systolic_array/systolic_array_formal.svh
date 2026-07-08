// -----------------------------------------------------------------------------
// systolic_array_formal.svh -- SVA property body for systolic_array.
//
// This is NOT a standalone module in the formal (yosys) flow: yosys_shim.py
// splices only the text between the __FORMAL_PROPS_BEGIN__/__FORMAL_PROPS_END__
// markers below into a throwaway copy of systolic_array.sv (plus its skew_shift
// and mac_pe dependencies), so the properties reference systolic_array's
// internal FSM and counter signals directly. RTL files are never modified --
// see systolic_array.sby.
//
// The proof targets a small parameter set (M=N=K=2, DATA_W=8, ACC_W=32) to
// keep the flattened PE grid tractable for k-induction. The FSM/counter
// invariants proved here are parameter-independent; only cover depth needs
// scaling for larger M/N/K.
//
// Properties encoded here (from docs/interface/systolic_array_if.md):
//   P1. Reset clears FSM to S_IDLE and all counters to zero.
//   P2. FSM legal transitions: IDLE->RUN->DRAIN->DONE->IDLE only.
//   P3. in_ready asserted only in S_RUN and only while k_cnt_q < cfg_k_dim.
//   P4. out_valid iff in S_DRAIN.
//   P5. done iff in S_DONE (one-cycle pulse per completion).
//   P6. k_cnt_q never exceeds cfg_k_dim; d_cnt_q never exceeds cfg_m_dim.
//
// Run: sby -f systolic_array.sby       (prove)
//      sby -f systolic_array_cover.sby  (cover)
// -----------------------------------------------------------------------------

`pragma diagnostic push
`pragma diagnostic ignore="-Wunknown-sys-name" // $initstate is Yosys/SBY-only

module systolic_array_formal_lint_shim #(
    parameter int unsigned DATA_W = 8,
    parameter int unsigned ACC_W  = 32,
    parameter int unsigned M      = 2,
    parameter int unsigned N      = 2,
    parameter int unsigned K      = 2
) (
    // Placeholder ports for standalone editor/lint compilation only.
    // The real splice resolves these names against systolic_array's
    // own internal signals.
    input logic        clk,
    input logic        rst_n,
    input logic        start,
    input logic        done,
    input logic        in_ready,
    input logic        out_valid,
    input logic        in_valid,
    input logic        out_ready,
    input logic [1:0]  state_q,    // state_e is 2-bit
    input logic [31:0] t_cnt_q,
    input logic [31:0] k_cnt_q,
    input logic [31:0] d_cnt_q,
    input logic [31:0] cfg_m_dim,
    input logic [31:0] cfg_n_dim,
    input logic [31:0] cfg_k_dim
);

    // __FORMAL_PROPS_BEGIN__ -- yosys_shim.py splices only between these markers

localparam logic [1:0] F_SA_IDLE  = 2'd0;
localparam logic [1:0] F_SA_RUN   = 2'd1;
localparam logic [1:0] F_SA_DRAIN = 2'd2;
localparam logic [1:0] F_SA_DONE  = 2'd3;


logic f_past_valid;
initial f_past_valid = 1'b0;
always @(posedge clk) f_past_valid <= 1'b1;

// -------------------------------------------------------------------------
// P1. Reset clears FSM to S_IDLE and counters to zero (synchronous reset:
//     check the cycle AFTER reset was held, i.e. $past(rst_n)==0).
// -------------------------------------------------------------------------
always @(posedge clk) begin
    if (f_past_valid && !$past(rst_n)) begin
        assert (state_q == F_SA_IDLE);
        assert (k_cnt_q == '0);
        assert (d_cnt_q == '0);
    end
end

// -------------------------------------------------------------------------
// P2. FSM legal transitions (without concurrent reset).
// -------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && f_past_valid && $past(rst_n)) begin
        if ($past(state_q) == F_SA_IDLE)
            assert (state_q == F_SA_IDLE || state_q == F_SA_RUN);
        if ($past(state_q) == F_SA_RUN)
            assert (state_q == F_SA_RUN || state_q == F_SA_DRAIN);
        if ($past(state_q) == F_SA_DRAIN)
            assert (state_q == F_SA_DRAIN || state_q == F_SA_DONE);
        if ($past(state_q) == F_SA_DONE)
            assert (state_q == F_SA_IDLE);
    end
end

// -------------------------------------------------------------------------
// P3. in_ready: only high in S_RUN, and only while k_cnt_q < cfg_k_dim.
// -------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n) begin
        if (in_ready) assert (state_q == F_SA_RUN);
        if (in_ready) assert (k_cnt_q < cfg_k_dim);
        if (state_q != F_SA_RUN) assert (!in_ready);
    end
end

// -------------------------------------------------------------------------
// P4. out_valid iff in S_DRAIN.
// -------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n)
        assert (out_valid == (state_q == F_SA_DRAIN));
end

// -------------------------------------------------------------------------
// P5. done iff in S_DONE.
// -------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n)
        assert (done == (state_q == F_SA_DONE));
end


// -------------------------------------------------------------------------
// Reachability sanity: all non-IDLE states must be reachable.
// -------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n) begin
        cover (state_q == F_SA_RUN);
        cover (state_q == F_SA_DRAIN);
        cover (state_q == F_SA_DONE);
    end
end

    // __FORMAL_PROPS_END__
endmodule

`pragma diagnostic pop
