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
module matrix_buffer_ab #(
    parameter int unsigned DATA_W = 16,
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

    // Streaming data (one column of A, one row of B per beat)
    output logic [M*DATA_W-1:0]        a_col,
    output logic [N*DATA_W-1:0]        b_row
);

    localparam int unsigned A_DEPTH       = M * K;
    localparam int unsigned B_DEPTH       = K * N;
    localparam int unsigned EPW           = APB_DW / DATA_W;          // elements per APB word
    localparam int unsigned A_PTR_W       = (A_DEPTH > 1) ? $clog2(A_DEPTH + 1) : 1;
    localparam int unsigned B_PTR_W       = (B_DEPTH > 1) ? $clog2(B_DEPTH + 1) : 1;
    localparam int unsigned K_W           = (K > 1) ? $clog2(K + 1) : 1;

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
    assign PSLVERR    = 1'b0;

    // Decode by upper address bits (offset 0x00, 0x40, 0x80)
    logic sel_a, sel_b, sel_ctrl;
    assign sel_a    = (PADDR[7:0] == 8'h00);
    assign sel_b    = (PADDR[7:0] == 8'h40);
    assign sel_ctrl = (PADDR[7:0] == 8'h80);

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
                        if ((a_wptr + e) < A_DEPTH)
                            mem_a[a_wptr + e] <= PWDATA[e*DATA_W +: DATA_W];
                    end
                    a_wptr <= a_wptr + EPW;
                end
                if (apb_access && PWRITE && sel_b) begin
                    for (int e = 0; e < EPW; e++) begin
                        if ((b_wptr + e) < B_DEPTH)
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
            PRDATA[1] = (a_wptr >= A_DEPTH);
            PRDATA[2] = (b_wptr >= B_DEPTH);
        end
    end

    // -------------------------------------------------------------------------
    // Streaming side: produce K beats of (a_col, b_row).
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {S_IDLE, S_RUN, S_DONE} stream_state_e;
    stream_state_e s_q, s_d;
    logic [K_W-1:0] k_q;

    assign mat_valid = (s_q == S_RUN);

    always_comb begin
        s_d = s_q;
        unique case (s_q)
            S_IDLE: if (mat_start) s_d = S_RUN;
            S_RUN:  if (mat_valid && sys_ready && (k_q == K[K_W-1:0] - 1))
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

    // Drive a_col[i] = mem_a[i*K + k_q], b_row[j] = mem_b[k_q*N + j]
    genvar gi, gj;
    generate
        for (gi = 0; gi < M; gi++) begin : g_a_drive
            assign a_col[(gi+1)*DATA_W-1 -: DATA_W] = mem_a[gi*K + k_q];
        end
        for (gj = 0; gj < N; gj++) begin : g_b_drive
            assign b_row[(gj+1)*DATA_W-1 -: DATA_W] = mem_b[k_q*N + gj];
        end
    endgenerate

endmodule
