// -----------------------------------------------------------------------------
// control_unit.sv -- APB-attached control unit for the systolic accelerator.
//
// External ports follow docs/interface/control_unit_if.md (active-high
// reset_int from the SoC; converted internally to active-low rst_n). This
// file implements:
//   * APB subordinate FSM (SETUP / ACCESS, zero-wait).
//   * Register file (CTRL / STATUS / M_DIM / N_DIM / K_DIM / INT_EN / INT_STAT).
//   * Compute FSM: IDLE -> ISSUE -> BUSY -> DONE.
//   * Soft-reset bit and done-interrupt.
//
// The matrix_*_addr / *_ren / *_wen ports are kept for interface compatibility
// with the v0 spec but are not driven by streaming v1 (the matrix buffers
// stream autonomously). They are tied to '0 here.
// -----------------------------------------------------------------------------
`include "accel_pkg.sv"

module control_unit
    import accel_pkg::*;
#(
    parameter int unsigned APB_AW    = 10,
    parameter int unsigned APB_DW    = 32,
    parameter int unsigned MATRIX_AW = 10
) (
    // System clock and reset
    input  logic                     clk_in,
    input  logic                     reset_int,    // active-high from SoC

    // APB subordinate interface
    input  logic [APB_AW-1:0]        PADDR,
    input  logic                     PENABLE,
    input  logic                     PSEL,
    input  logic [APB_DW-1:0]        PWDATA,
    input  logic                     PWRITE,
    output logic [APB_DW-1:0]        PRDATA,
    output logic                     PREADY,
    output logic                     PSLVERR,

    // SoC control & interrupt
    input  logic                     irq_en_4,
    input  logic [7:0]               ss_ctrl_4,
    output logic                     irq_4,

    // Matrix A/B/C external addressing (kept for interface; tied off in v1)
    output logic [MATRIX_AW-1:0]     matrix_a_addr,
    output logic                     matrix_a_ren,
    output logic [MATRIX_AW-1:0]     matrix_b_addr,
    output logic                     matrix_b_ren,
    output logic [MATRIX_AW-1:0]     matrix_c_addr,
    output logic                     matrix_c_wen,

    // Systolic array control
    output logic                     array_start,
    output logic                     array_clear,
    input  logic                     array_done,

    // Exposed register-file values (for top-level wiring)
    output logic [APB_DW-1:0]        cfg_m_dim,
    output logic [APB_DW-1:0]        cfg_n_dim,
    output logic [APB_DW-1:0]        cfg_k_dim,
    output logic                     soft_reset
);

    // -------------------------------------------------------------------------
    // Reset conversion: active-high reset_int -> active-low rst_n
    // -------------------------------------------------------------------------
    logic clk;
    logic rst_n;
    assign clk   = clk_in;
    assign rst_n = ~reset_int;

    // -------------------------------------------------------------------------
    // Tie unused legacy address ports
    // -------------------------------------------------------------------------
    assign matrix_a_addr = '0;
    assign matrix_a_ren  = 1'b0;
    assign matrix_b_addr = '0;
    assign matrix_b_ren  = 1'b0;
    assign matrix_c_addr = '0;
    assign matrix_c_wen  = 1'b0;

    // -------------------------------------------------------------------------
    // Register file
    // -------------------------------------------------------------------------
    logic [APB_DW-1:0] reg_ctrl;
    logic [APB_DW-1:0] reg_status;
    logic [APB_DW-1:0] reg_m_dim;
    logic [APB_DW-1:0] reg_n_dim;
    logic [APB_DW-1:0] reg_k_dim;
    logic [APB_DW-1:0] reg_int_en;
    logic [APB_DW-1:0] reg_int_stat;

    assign cfg_m_dim  = reg_m_dim;
    assign cfg_n_dim  = reg_n_dim;
    assign cfg_k_dim  = reg_k_dim;
    assign soft_reset = reg_ctrl[CTRL_SOFTRST_BIT];

    // -------------------------------------------------------------------------
    // APB transaction qualification
    // -------------------------------------------------------------------------
    logic apb_access;
    assign apb_access = PSEL && PENABLE;
    assign PREADY     = 1'b1;
    assign PSLVERR    = 1'b0;

    logic apb_write_strobe;
    assign apb_write_strobe = apb_access && PWRITE;

    // -------------------------------------------------------------------------
    // Compute FSM
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {C_IDLE, C_ISSUE, C_BUSY, C_DONE} cstate_e;
    cstate_e cstate_q, cstate_d;

    logic start_pulse;     // 1-cycle CTRL.start write
    logic done_event;      // detected array_done

    assign array_start = (cstate_q == C_ISSUE);
    assign array_clear = (cstate_q == C_ISSUE);

    always_comb begin
        cstate_d = cstate_q;
        unique case (cstate_q)
            C_IDLE:  if (start_pulse) cstate_d = C_ISSUE;
            C_ISSUE: cstate_d = C_BUSY;
            C_BUSY:  if (done_event)  cstate_d = C_DONE;
            C_DONE:  cstate_d = C_IDLE;
            default: cstate_d = C_IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // Sequential register updates
    // -------------------------------------------------------------------------
    // Decode within the local 256-byte register window so the unit works
    // behind any address mux (top-level decoder owns PADDR[9:8]).
    logic [7:0] reg_off;
    assign reg_off = PADDR[7:0];

    logic ctrl_start_w;
    assign ctrl_start_w = apb_write_strobe && (reg_off == REG_CTRL[7:0]) && PWDATA[CTRL_START_BIT];
    assign start_pulse  = ctrl_start_w && (cstate_q == C_IDLE);

    assign done_event = array_done;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            reg_ctrl     <= '0;
            reg_status   <= '0;
            reg_m_dim    <= APB_DW'(DEF_M);
            reg_n_dim    <= APB_DW'(DEF_N);
            reg_k_dim    <= APB_DW'(DEF_K);
            reg_int_en   <= '0;
            reg_int_stat <= '0;
            cstate_q     <= C_IDLE;
        end else begin
            cstate_q <= cstate_d;

            // CTRL register: SW writes, but start bit auto-clears next cycle.
            if (apb_write_strobe && reg_off == REG_CTRL[7:0]) begin
                reg_ctrl <= PWDATA;
            end else begin
                reg_ctrl[CTRL_START_BIT] <= 1'b0;
            end

            // Soft reset clears the compute FSM and status (but not regfile).
            if (reg_ctrl[CTRL_SOFTRST_BIT]) begin
                cstate_q                   <= C_IDLE;
                reg_status                 <= '0;
                reg_int_stat               <= '0;
                reg_ctrl[CTRL_SOFTRST_BIT] <= 1'b0;
            end

            // STATUS register.
            reg_status[STATUS_BUSY_BIT] <= (cstate_d != C_IDLE);
            if (cstate_q == C_DONE)
                reg_status[STATUS_DONE_BIT] <= 1'b1;
            else if (apb_write_strobe && reg_off == REG_STATUS[7:0] && PWDATA[STATUS_DONE_BIT])
                reg_status[STATUS_DONE_BIT] <= 1'b0;

            // Dim regs.
            if (apb_write_strobe && reg_off == REG_M_DIM[7:0]) reg_m_dim <= PWDATA;
            if (apb_write_strobe && reg_off == REG_N_DIM[7:0]) reg_n_dim <= PWDATA;
            if (apb_write_strobe && reg_off == REG_K_DIM[7:0]) reg_k_dim <= PWDATA;

            // INT_EN: simple R/W.
            if (apb_write_strobe && reg_off == REG_INT_EN[7:0]) reg_int_en <= PWDATA;

            // INT_STAT: set on done event; W1C from SW.
            if (cstate_q == C_DONE) reg_int_stat[INT_DONE_BIT] <= 1'b1;
            else if (apb_write_strobe && reg_off == REG_INT_STAT[7:0] && PWDATA[INT_DONE_BIT])
                reg_int_stat[INT_DONE_BIT] <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // APB read mux (combinational)
    // -------------------------------------------------------------------------
    always_comb begin
        PRDATA = '0;
        if (apb_access && !PWRITE) begin
            unique case (reg_off)
                REG_CTRL[7:0]:     PRDATA = reg_ctrl;
                REG_STATUS[7:0]:   PRDATA = reg_status;
                REG_M_DIM[7:0]:    PRDATA = reg_m_dim;
                REG_N_DIM[7:0]:    PRDATA = reg_n_dim;
                REG_K_DIM[7:0]:    PRDATA = reg_k_dim;
                REG_INT_EN[7:0]:   PRDATA = reg_int_en;
                REG_INT_STAT[7:0]: PRDATA = reg_int_stat;
                default:           PRDATA = '0;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Interrupt output (level)
    // -------------------------------------------------------------------------
    assign irq_4 = irq_en_4 && reg_int_en[INT_DONE_BIT] && reg_int_stat[INT_DONE_BIT];

    // ss_ctrl_4 reserved for future SoC routing (e.g., debug taps).
    logic _unused_ss;
    assign _unused_ss = |ss_ctrl_4;

endmodule
