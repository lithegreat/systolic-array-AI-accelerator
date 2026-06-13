// -----------------------------------------------------------------------------
// mac_pe.sv -- single processing element for the output-stationary array.
//
// Behaviour (per docs/interface/mac_if.md):
//   * Synchronous active-low reset clears all flops.
//   * When `en` is high on a clock edge:
//       - a_out, b_out latch a_in, b_in (systolic pulse).
//       - If clear_acc: acc <= a_in * b_in   (initialise accumulator with the
//         current product, output-stationary friendly).
//         else        : acc <= acc + a_in * b_in.
//   * pe_out is a combinational tap of acc (no extra flop).
// Signed arithmetic is used throughout.
// -----------------------------------------------------------------------------
module mac_pe #(
    parameter int unsigned DATA_W = 8,
    parameter int unsigned ACC_W  = 32
) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  en,
    input  logic                  clear_acc,
    input  logic signed [DATA_W-1:0] a_in,
    input  logic signed [DATA_W-1:0] b_in,
    output logic signed [DATA_W-1:0] a_out,
    output logic signed [DATA_W-1:0] b_out,
    output logic signed [ACC_W-1:0]  pe_out
);

    logic signed [ACC_W-1:0] acc_q;
    logic signed [2*DATA_W-1:0] product;

    assign product = a_in * b_in;
    assign pe_out  = acc_q;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            acc_q <= '0;
            a_out <= '0;
            b_out <= '0;
        end else if (en) begin
            a_out <= a_in;
            b_out <= b_in;
            if (clear_acc)
                acc_q <= ACC_W'(product);
            else
                acc_q <= acc_q + ACC_W'(product);
        end
    end

endmodule
