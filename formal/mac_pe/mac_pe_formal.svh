// -----------------------------------------------------------------------------
// mac_pe_formal.svh -- SVA property body for mac_pe.
//
// This is NOT a standalone module in the formal (yosys) flow: yosys_shim.py
// splices only the text between the __FORMAL_PROPS_BEGIN__/__FORMAL_PROPS_END__
// markers below into a throwaway copy of mac_pe.sv, right before its
// `endmodule`, so the properties reference mac_pe's internal signals directly
// (clk, rst_n, en, clear_acc, a_in, b_in, acc_q, product, ...). The original
// rtl/MAC/mac_pe.sv is never modified -- see mac_pe.sby.
//
// The mac_pe_formal_lint_shim module below is NOT part of the splice --
// it exists purely so this file is valid, self-contained SystemVerilog when
// opened directly by an editor/linter. Keep its placeholder declarations in
// sync with mac_pe.sv's internal signals if that file changes.
//
// Properties encoded here (from docs/interface/mac_if.md):
//   P1. Reset clears acc_q, a_out, b_out to zero.
//   P2. When en=0, acc_q, a_out, b_out are stable (no-change).
//   P3. clear_acc=1 (with en=1): acc_q latches a_in*b_in (not adds).
//   P4. clear_acc=0 (with en=1): acc_q accumulates acc_q + a_in*b_in.
//   P5. Systolic passthrough: a_out/b_out register a_in/b_in when en=1.
//   P6. pe_out is always a combinational tap of acc_q.
//
// Run: sby -f mac_pe.sby        (prove)  -- all properties hold by k-induction
//      sby -f mac_pe_cover.sby  (cover)  -- clear and accumulate paths reachable
// -----------------------------------------------------------------------------

`pragma diagnostic push
`pragma diagnostic ignore="-Wunknown-sys-name" // $initstate is Yosys/SBY-only

module mac_pe_formal_lint_shim #(
    parameter int unsigned DATA_W = 8,
    parameter int unsigned ACC_W  = 32
) (
    // Declared as inputs only so standalone lint/editor compilation doesn't
    // flag them as undriven -- the real splice resolves these against mac_pe's
    // own internal signals.
    input logic                          clk,
    input logic                          rst_n,
    input logic                          en,
    input logic                          clear_acc,
    input logic signed [DATA_W-1:0]      a_in,
    input logic signed [DATA_W-1:0]      b_in,
    input logic signed [DATA_W-1:0]      a_out,
    input logic signed [DATA_W-1:0]      b_out,
    input logic signed [ACC_W-1:0]       pe_out,
    input logic signed [ACC_W-1:0]       acc_q,
    input logic signed [2*DATA_W-1:0]    product
);

    // __FORMAL_PROPS_BEGIN__ -- yosys_shim.py splices only the lines between
    // this marker and __FORMAL_PROPS_END__ into mac_pe's real module body;
    // the lint-shim wrapper above/below is never seen by the formal flow.

logic f_past_valid;
initial f_past_valid = 1'b0;
always @(posedge clk) f_past_valid <= 1'b1;

// Force a real synchronous reset at the start of every BMC/induction trace.
// ($initstate is true only for the initial state of the design.)
always @* begin
    if ($initstate) assume (!rst_n);
end

// -------------------------------------------------------------------------
// P1. Reset clears all state registers to zero (synchronous reset: registers
//     clear on the clock edge while rst_n is low, so check CURRENT values
//     when $past(rst_n)==0, i.e. reset was held the previous cycle).
// -------------------------------------------------------------------------
always @(posedge clk) begin
    if (f_past_valid && !$past(rst_n)) begin
        assert (acc_q == '0);
        assert (a_out == '0);
        assert (b_out == '0);
    end
end

// -------------------------------------------------------------------------
// P2. When en=0, acc_q, a_out, b_out do not change.
// -------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && f_past_valid && $past(rst_n) && !$past(en)) begin
        assert (acc_q == $past(acc_q));
        assert (a_out == $past(a_out));
        assert (b_out == $past(b_out));
    end
end

// -------------------------------------------------------------------------
// P3. clear_acc=1 with en=1: accumulator initialises to a_in*b_in.
//     (sign-extended product, not added to old acc.)
// -------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && f_past_valid && $past(rst_n) && $past(en) && $past(clear_acc))
        assert (acc_q == ACC_W'(signed'($past(product))));
end

// -------------------------------------------------------------------------
// P4. clear_acc=0 with en=1: accumulator adds sign-extended product.
// -------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && f_past_valid && $past(rst_n) && $past(en) && !$past(clear_acc))
        assert (acc_q == $past(acc_q) + ACC_W'(signed'($past(product))));
end

// -------------------------------------------------------------------------
// P5. Systolic passthrough: a_out/b_out register a_in/b_in when en=1.
// -------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n && f_past_valid && $past(rst_n) && $past(en)) begin
        assert (a_out == $past(a_in));
        assert (b_out == $past(b_in));
    end
end

// -------------------------------------------------------------------------
// P6. pe_out is always a combinational tap of acc_q (no extra pipeline stage).
// -------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n)
        assert (pe_out == acc_q);
end

// -------------------------------------------------------------------------
// Reachability sanity: clear and accumulate paths must both be reachable,
// and a_out must be able to carry a non-zero value.
// -------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst_n) begin
        cover (en && !clear_acc && acc_q != '0);   // accumulate with non-zero acc
        cover (en && clear_acc);                    // clear path
        cover (a_out != '0);                        // systolic passthrough live
    end
end

    // __FORMAL_PROPS_END__
endmodule

`pragma diagnostic pop
