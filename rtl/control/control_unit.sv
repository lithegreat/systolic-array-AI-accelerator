// -----------------------------------------------------------------------------
// control_unit.sv -- APB-attached control unit for the systolic accelerator.
//
// External ports follow docs/interface/control_unit_if.md (active-high
// reset_int from the SoC; converted internally to active-low rst_n). This
// file implements:
//   * APB subordinate FSM (SETUP / ACCESS, zero-wait).
//   * Register file (CTRL / STATUS / M_DIM / N_DIM / K_DIM / INT_EN / INT_STAT).
//   * Build/status registers and lightweight performance counters.
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
    parameter int unsigned DATA_W    = DEF_DATA_W,
    parameter int unsigned M         = DEF_M,
    parameter int unsigned N         = DEF_N,
    parameter int unsigned K         = DEF_K,
    parameter int unsigned APB_AW    = 10,
    parameter int unsigned APB_DW    = 32
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

    // Systolic array control
    output logic                     array_start,
    output logic                     array_clear,
    input  logic                     array_done,

    // Runtime tile dimensions (clamped to the physical build dimensions).
    output logic [APB_DW-1:0]        cfg_m_dim,
    output logic [APB_DW-1:0]        cfg_n_dim,
    output logic [APB_DW-1:0]        cfg_k_dim,
    output logic [APB_DW-1:0]        run_m_dim,
    output logic [APB_DW-1:0]        run_n_dim,
    output logic [APB_DW-1:0]        run_k_dim,

    // Performance event inputs from accelerator_top
    input  logic                     perf_apb_write,
    input  logic                     perf_apb_read,
    input  logic                     perf_input_stall,
    input  logic                     perf_output_stall
);

    // -------------------------------------------------------------------------
    // Reset conversion: active-high reset_int -> active-low rst_n
    // -------------------------------------------------------------------------
    logic clk;
    logic rst_n;
    assign clk   = clk_in;
    assign rst_n = ~reset_int;

    // -------------------------------------------------------------------------
    // Register file
    // -------------------------------------------------------------------------
`ifdef FORMAL
    localparam int unsigned REG_W = 8;
`else
    localparam int unsigned REG_W = APB_DW;
`endif
    logic [REG_W-1:0]  reg_ctrl;
    logic [REG_W-1:0]  reg_status;
    logic [REG_W-1:0]  reg_m_dim;
    logic [REG_W-1:0]  reg_n_dim;
    logic [REG_W-1:0]  reg_k_dim;
    logic [REG_W-1:0]  latched_m_dim;
    logic [REG_W-1:0]  latched_n_dim;
    logic [REG_W-1:0]  latched_k_dim;
    logic [REG_W-1:0]  reg_int_en;
    logic [REG_W-1:0]  reg_int_stat;
    logic [REG_W-1:0]  perf_cycles;
    logic [REG_W-1:0]  perf_apb_writes;
    logic [REG_W-1:0]  perf_apb_reads;
    logic [REG_W-1:0]  perf_in_stalls;
    logic [REG_W-1:0]  perf_out_stalls;
    logic              perf_active;
    logic              perf_in_stall_seen;
    logic              perf_out_stall_seen;
    logic              perf_counter_overflow;

    // -------------------------------------------------------------------------
    // APB transaction qualification
    // -------------------------------------------------------------------------
    logic apb_access;
    assign apb_access = PSEL && PENABLE;
    assign PREADY     = 1'b1;
    assign PSLVERR    = 1'b0;

    logic apb_write_strobe;
    assign apb_write_strobe = apb_access && PWRITE;

    function automatic logic [REG_W-1:0] clamp_dim(
        input logic [REG_W-1:0] value,
        input int unsigned max_value
    );
        logic [REG_W-1:0] max_word;
        begin
            max_word = REG_W'(max_value);
            if (value == '0) begin
                clamp_dim = REG_W'(1);
            end else if (value > max_word) begin
                clamp_dim = max_word;
            end else begin
                clamp_dim = value;
            end
        end
    endfunction

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
    assign cfg_m_dim  = {{(APB_DW-REG_W){1'b0}}, reg_m_dim};
    assign cfg_n_dim  = {{(APB_DW-REG_W){1'b0}}, reg_n_dim};
    assign cfg_k_dim  = {{(APB_DW-REG_W){1'b0}}, reg_k_dim};
    assign run_m_dim  = {{(APB_DW-REG_W){1'b0}}, latched_m_dim};
    assign run_n_dim  = {{(APB_DW-REG_W){1'b0}}, latched_n_dim};
    assign run_k_dim  = {{(APB_DW-REG_W){1'b0}}, latched_k_dim};

    logic perf_clear_w;
    assign perf_clear_w = apb_write_strobe && (reg_off == REG_PERF_CTRL[7:0]) && PWDATA[PERF_CLEAR_BIT];

    logic [APB_DW-1:0] build_info;
    logic [APB_DW-1:0] hw_status;

    always_comb begin
        build_info = '0;
        build_info[7:0]   = 8'(M);
        build_info[15:8]  = 8'(N);
        build_info[23:16] = 8'(K);
        build_info[31:24] = 8'(DATA_W);

        hw_status = '0;
        hw_status[HW_STATUS_PERF_ACTIVE_BIT]      = perf_active;
        hw_status[HW_STATUS_IN_STALL_SEEN_BIT]    = perf_in_stall_seen;
        hw_status[HW_STATUS_OUT_STALL_SEEN_BIT]   = perf_out_stall_seen;
        hw_status[HW_STATUS_COUNTER_OVERFLOW_BIT] = perf_counter_overflow;
        hw_status[HW_STATUS_FSM_STATE_LSB +: 2]   = cstate_q;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            reg_ctrl     <= '0;
            reg_status   <= '0;
            reg_m_dim    <= REG_W'(M);
            reg_n_dim    <= REG_W'(N);
            reg_k_dim    <= REG_W'(K);
            latched_m_dim <= REG_W'(M);
            latched_n_dim <= REG_W'(N);
            latched_k_dim <= REG_W'(K);
            reg_int_en   <= '0;
            reg_int_stat <= '0;
            perf_cycles           <= '0;
            perf_apb_writes       <= '0;
            perf_apb_reads        <= '0;
            perf_in_stalls        <= '0;
            perf_out_stalls       <= '0;
            perf_active           <= 1'b0;
            perf_in_stall_seen    <= 1'b0;
            perf_out_stall_seen   <= 1'b0;
            perf_counter_overflow <= 1'b0;
            cstate_q     <= C_IDLE;
        end else begin
            cstate_q <= cstate_d;

            // CTRL register: SW writes, but start bit auto-clears next cycle.
            if (apb_write_strobe && reg_off == REG_CTRL[7:0]) begin
                reg_ctrl <= REG_W'(PWDATA);
            end else begin
                reg_ctrl[CTRL_START_BIT] <= 1'b0;
            end

            // Soft reset clears the compute FSM and status (but not regfile).
            if (reg_ctrl[CTRL_SOFTRST_BIT]) begin
                cstate_q                   <= C_IDLE;
                reg_status                 <= '0;
                reg_int_stat               <= '0;
                reg_ctrl[CTRL_SOFTRST_BIT] <= 1'b0;
                perf_active                 <= 1'b0;
            end else begin
                // STATUS register.
                reg_status[STATUS_BUSY_BIT] <= (cstate_d != C_IDLE);
                if (cstate_q == C_DONE)
                    reg_status[STATUS_DONE_BIT] <= 1'b1;
                else if (apb_write_strobe && reg_off == REG_STATUS[7:0] && PWDATA[STATUS_DONE_BIT])
                    reg_status[STATUS_DONE_BIT] <= 1'b0;

                // INT_STAT: set on done event; W1C from SW.
                if (cstate_q == C_DONE) reg_int_stat[INT_DONE_BIT] <= 1'b1;
                else if (apb_write_strobe && reg_off == REG_INT_STAT[7:0] && PWDATA[INT_DONE_BIT])
                    reg_int_stat[INT_DONE_BIT] <= 1'b0;
            end

            // Runtime dimension registers. Writes are accepted only while idle;
            // this keeps an in-flight tile's compact layout stable.
            if (cstate_q == C_IDLE) begin
                if (apb_write_strobe && reg_off == REG_M_DIM[7:0]) begin
                    reg_m_dim <= clamp_dim(REG_W'(PWDATA), M);
                end
                if (apb_write_strobe && reg_off == REG_N_DIM[7:0]) begin
                    reg_n_dim <= clamp_dim(REG_W'(PWDATA), N);
                end
                if (apb_write_strobe && reg_off == REG_K_DIM[7:0]) begin
                    reg_k_dim <= clamp_dim(REG_W'(PWDATA), K);
                end
            end

            // INT_EN: simple R/W.
            if (apb_write_strobe && reg_off == REG_INT_EN[7:0]) reg_int_en <= REG_W'(PWDATA);

            if (perf_clear_w) begin
                perf_cycles           <= '0;
                perf_apb_writes       <= '0;
                perf_apb_reads        <= '0;
                perf_in_stalls        <= '0;
                perf_out_stalls       <= '0;
                perf_active           <= 1'b0;
                perf_in_stall_seen    <= 1'b0;
                perf_out_stall_seen   <= 1'b0;
                perf_counter_overflow <= 1'b0;
            end else begin
                if (start_pulse) begin
                    perf_cycles         <= '0;
                    perf_in_stalls      <= '0;
                    perf_out_stalls     <= '0;
                    perf_active         <= 1'b1;
                    perf_in_stall_seen  <= 1'b0;
                    perf_out_stall_seen <= 1'b0;
                    latched_m_dim       <= reg_m_dim;
                    latched_n_dim       <= reg_n_dim;
                    latched_k_dim       <= reg_k_dim;
                end else if (done_event) begin
                    perf_active <= 1'b0;
                end

                if (perf_apb_write) begin
                    if (&perf_apb_writes) begin
                        perf_counter_overflow <= 1'b1;
                    end else begin
                        perf_apb_writes <= perf_apb_writes + 1'b1;
                    end
                end
                if (perf_apb_read) begin
                    if (&perf_apb_reads) begin
                        perf_counter_overflow <= 1'b1;
                    end else begin
                        perf_apb_reads <= perf_apb_reads + 1'b1;
                    end
                end

                if (perf_active) begin
                    if (&perf_cycles) begin
                        perf_counter_overflow <= 1'b1;
                    end else begin
                        perf_cycles <= perf_cycles + 1'b1;
                    end

                    if (perf_input_stall) begin
                        perf_in_stall_seen <= 1'b1;
                        if (&perf_in_stalls) begin
                            perf_counter_overflow <= 1'b1;
                        end else begin
                            perf_in_stalls <= perf_in_stalls + 1'b1;
                        end
                    end

                    if (perf_output_stall) begin
                        perf_out_stall_seen <= 1'b1;
                        if (&perf_out_stalls) begin
                            perf_counter_overflow <= 1'b1;
                        end else begin
                            perf_out_stalls <= perf_out_stalls + 1'b1;
                        end
                    end
                end
            end
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
                REG_BUILD_INFO[7:0]:      PRDATA = build_info;
                REG_HW_STATUS[7:0]:       PRDATA = hw_status;
                REG_PERF_CTRL[7:0]:       PRDATA = '0;
                REG_PERF_CYCLES[7:0]:     PRDATA = perf_cycles;
                REG_PERF_APB_WRITES[7:0]: PRDATA = perf_apb_writes;
                REG_PERF_APB_READS[7:0]:  PRDATA = perf_apb_reads;
                REG_PERF_IN_STALLS[7:0]:  PRDATA = perf_in_stalls;
                REG_PERF_OUT_STALLS[7:0]: PRDATA = perf_out_stalls;
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
