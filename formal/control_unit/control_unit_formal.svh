// -----------------------------------------------------------------------------
// control_unit_formal.svh -- SVA property body for control_unit.
//
// This is NOT a standalone module in the formal (yosys) flow: yosys_shim.py
// splices only the text between the __FORMAL_PROPS_BEGIN__/__FORMAL_PROPS_END__
// markers below into a throwaway copy of control_unit.sv, right before its
// `endmodule`, so the properties can reference control_unit's internal
// signals directly (clk, rst_n, cstate_q, reg_ctrl, ...). rtl/control/
// control_unit.sv itself is never modified -- see control_unit.sby.
//
// (Two other approaches were tried and rejected because Yosys's built-in
// read_verilog frontend doesn't support them: `bind` is parsed but silently
// never instantiates the bound module (assertions never run, false PASS);
// and a checker instantiated alongside control_unit with ports wired via
// hierarchical `dut.<signal>` references produces dangling, disconnected
// wires for internal (non-port) signals -- only real module ports resolve
// correctly that way.)
//
// The control_unit_formal_lint_shim module below is NOT part of what gets
// spliced into the real proof -- it exists purely so this file is valid,
// self-contained SystemVerilog when opened directly by an editor/linter
// (e.g. slang-server's single-file "shallow compilation"). Without it every
// statement here is flagged "member not allowed at compilation unit scope",
// since bare always-blocks aren't legal outside a module. Keep the
// placeholder declarations' names/types in sync with control_unit.sv's
// internal signals if that file's signals change.
//
// See docs/interface/control_unit_if.md for the compute-FSM diagram these
// properties encode. Run with SymbiYosys: sby -f control_unit.sby
// -----------------------------------------------------------------------------
`include "accel_pkg.sv"

`pragma diagnostic push
`pragma diagnostic ignore="-Wunknown-sys-name" // $initstate is a Yosys/SBY-only builtin, see below

module control_unit_formal_lint_shim
    import accel_pkg::*;
#(
    parameter int unsigned APB_DW = 32,
    parameter int unsigned M      = DEF_M,
    parameter int unsigned N      = DEF_N,
    parameter int unsigned K      = DEF_K
) (
    // Declared as inputs (rather than free-floating `logic`) purely so
    // standalone lint/editor compilation doesn't flag them as "never
    // assigned" -- the real splice never sees this port list, since only
    // the properties themselves reference these names, resolved there
    // against control_unit's actual internal signals.
    input logic              clk,
    input logic              rst_n,
    input logic              reset_int,
    input logic [APB_DW-1:0] reg_ctrl,
    input logic [APB_DW-1:0] reg_status,
    input logic [APB_DW-1:0] reg_int_stat,
    input logic [APB_DW-1:0] reg_m_dim,
    input logic [APB_DW-1:0] reg_n_dim,
    input logic [APB_DW-1:0] reg_k_dim,
    input logic [1:0]        cstate_q,
    input logic              start_pulse,
    input logic              done_event,
    input logic              array_start,
    input logic              array_clear
);

    // __FORMAL_PROPS_BEGIN__ -- yosys_shim.py splices only the lines between
    // this marker and __FORMAL_PROPS_END__ into control_unit's real module
    // body; the wrapper above/below exists for standalone editor parsing
    // only and is never seen by the formal flow.

localparam logic [1:0] F_CU_IDLE  = 2'd0;
localparam logic [1:0] F_CU_ISSUE = 2'd1;
localparam logic [1:0] F_CU_BUSY  = 2'd2;
localparam logic [1:0] F_CU_DONE  = 2'd3;

// Force a real power-on reset at the start of every BMC/induction trace.
// ($initstate is true only for the design's initial state.) Without this,
// solvers are free to pick an initial register state that never passed
// through reset, which trivially "violates" reset-established invariants
// (e.g. clamp_dim()'s range guarantee) for reasons that have nothing to do
// with the RTL's actual behaviour.
always @* begin
    if ($initstate) assume (reset_int);
end

logic f_past_valid;
initial f_past_valid = 1'b0;
always @(posedge clk) f_past_valid <= 1'b1;

// -------------------------------------------------------------------------
// Compute FSM: legal transition graph (IDLE -> ISSUE -> BUSY -> DONE -> IDLE)
//
// All transitions are qualified with "no concurrent soft-reset", because
// CTRL.softrst can legitimately interrupt any state and force IDLE (that's
// its job). See the KNOWN ISSUE note below the same-cycle invariants block:
// formal verification found that the soft-reset override interacts badly
// with STATUS.busy for exactly one cycle.
// -------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && f_past_valid && $past(rst_n) && !$past(reg_ctrl[CTRL_SOFTRST_BIT])) begin
        if ($past(cstate_q) == F_CU_IDLE && !$past(start_pulse))
            assert (cstate_q == F_CU_IDLE);
        if ($past(cstate_q) == F_CU_IDLE && $past(start_pulse))
            assert (cstate_q == F_CU_ISSUE);
        if ($past(cstate_q) == F_CU_ISSUE)
            assert (cstate_q == F_CU_BUSY);
        if ($past(cstate_q) == F_CU_BUSY && !$past(done_event))
            assert (cstate_q == F_CU_BUSY);
        if ($past(cstate_q) == F_CU_BUSY && $past(done_event))
            assert (cstate_q == F_CU_DONE);
        if ($past(cstate_q) == F_CU_DONE)
            assert (cstate_q == F_CU_IDLE);

        // One-cycle latency from an accepted start write to array_start.
        if ($past(start_pulse))
            assert (array_start);

        // Runtime dimension registers only change from IDLE (clamp_dim is
        // only called while cstate_q == C_IDLE in the RTL).
        if ($past(cstate_q) != F_CU_IDLE) begin
            assert (reg_m_dim == $past(reg_m_dim));
            assert (reg_n_dim == $past(reg_n_dim));
            assert (reg_k_dim == $past(reg_k_dim));
        end
    end

    // Soft reset (CTRL bit 1) forces the FSM back to IDLE next cycle --
    // this one always holds, softrst-concurrency-or-not.
    if (rst_n && f_past_valid && $past(rst_n) && $past(reg_ctrl[CTRL_SOFTRST_BIT]))
        assert (cstate_q == F_CU_IDLE);

    // INT_STAT.done is set unconditionally the cycle after DONE (only
    // meaningful without a concurrent soft-reset, which itself clears
    // INT_STAT).
    if (rst_n && f_past_valid && $past(rst_n) && !$past(reg_ctrl[CTRL_SOFTRST_BIT])
        && $past(cstate_q) == F_CU_DONE)
        assert (reg_int_stat[INT_DONE_BIT]);

    // Invariant: STATUS.busy is 1 if and only if the FSM is not in IDLE.
    // (This holds in all cycles, including immediately after a soft-reset).
    if (rst_n)
        assert (reg_status[STATUS_BUSY_BIT] == (cstate_q != F_CU_IDLE));
end

// -------------------------------------------------------------------------
// Same-cycle invariants
// -------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n) begin
        // array_start/array_clear are defined identically today; guard
        // against future edits accidentally decoupling them.
        assert (array_start == array_clear);
        assert (!array_start || (cstate_q == F_CU_ISSUE));

        // clamp_dim() must always return a value in [1, build max].
        assert (reg_m_dim >= 1 && reg_m_dim <= M);
        assert (reg_n_dim >= 1 && reg_n_dim <= N);
        assert (reg_k_dim >= 1 && reg_k_dim <= K);
    end
end

// -------------------------------------------------------------------------
// Reachability sanity (each FSM state must actually be reachable -- pairs
// with the assertions above so a "PASS" isn't just a vacuous proof)
// -------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n) begin
        cover (cstate_q == F_CU_ISSUE);
        cover (cstate_q == F_CU_BUSY);
        cover (cstate_q == F_CU_DONE);
    end
end

    // __FORMAL_PROPS_END__
endmodule

`pragma diagnostic pop
