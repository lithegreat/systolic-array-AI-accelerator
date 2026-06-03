// -----------------------------------------------------------------------------
// skew_shift.sv -- parameterised delay line used to build the systolic skew.
//
// Delays `d_in` by DEPTH cycles when `step` is asserted (gated shift). DEPTH=0
// is a pure combinational pass-through, matching row/column 0 of the array.
// Signed semantics are preserved through the chain.
// -----------------------------------------------------------------------------
module skew_shift #(
    parameter int unsigned W     = 16,
    parameter int unsigned DEPTH = 0
) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  step,
    input  logic signed [W-1:0]   d_in,
    output logic signed [W-1:0]   d_out
);

    generate
        if (DEPTH == 0) begin : g_passthrough
            assign d_out = d_in;
        end else begin : g_chain
            logic signed [W-1:0] sr [DEPTH];
            always_ff @(posedge clk) begin
                if (!rst_n) begin
                    for (int d = 0; d < DEPTH; d++) sr[d] <= '0;
                end else if (step) begin
                    sr[0] <= d_in;
                    for (int d = 1; d < DEPTH; d++) sr[d] <= sr[d-1];
                end
            end
            assign d_out = sr[DEPTH-1];
        end
    endgenerate

endmodule
