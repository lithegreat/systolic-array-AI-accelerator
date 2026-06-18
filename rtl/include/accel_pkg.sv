// -----------------------------------------------------------------------------
// accel_pkg.sv
// Shared parameters and APB register-map offsets for the systolic-array
// accelerator. Modules may override the size parameters via their own
// `parameter` ports; the values here serve as defaults and as the single
// source of truth for the SoC integration view.
// -----------------------------------------------------------------------------
`ifndef ACCEL_PKG_SV
`define ACCEL_PKG_SV

package accel_pkg;

    // -------------------------------------------------------------------------
    // Sizing
    // -------------------------------------------------------------------------
    localparam int unsigned DEF_M       = 16;  // C/A row count
    localparam int unsigned DEF_N       = 16;  // C/B col count
    localparam int unsigned DEF_K       = 16;  // reduction depth
    localparam int unsigned DEF_DATA_W  = 8;   // signed input width (INT8 baseline)
    localparam int unsigned DEF_ACC_W   = 32;  // accumulator width

    // -------------------------------------------------------------------------
    // APB regmap (control_unit) -- offsets relative to control base
    // -------------------------------------------------------------------------
    localparam logic [9:0] REG_CTRL     = 10'h00; // [0]=start, [1]=soft_reset
    localparam logic [9:0] REG_STATUS   = 10'h04; // [0]=busy,  [1]=done
    localparam logic [9:0] REG_M_DIM    = 10'h08; // matrix A rows / C rows
    localparam logic [9:0] REG_N_DIM    = 10'h0C; // matrix B cols / C cols
    localparam logic [9:0] REG_INT_EN   = 10'h10; // [0]=done irq enable
    localparam logic [9:0] REG_INT_STAT = 10'h14; // [0]=done irq pending (W1C)
    localparam logic [9:0] REG_K_DIM    = 10'h18; // reduction dimension K
    localparam logic [9:0] REG_BUILD_INFO      = 10'h1C; // [7:0]=M,[15:8]=N,[23:16]=K,[31:24]=DATA_W
    localparam logic [9:0] REG_HW_STATUS       = 10'h20; // perf/status sticky bits + FSM state
    localparam logic [9:0] REG_PERF_CTRL       = 10'h24; // [0]=clear performance counters/status
    localparam logic [9:0] REG_PERF_CYCLES     = 10'h28; // compute cycles between start and done
    localparam logic [9:0] REG_PERF_APB_WRITES = 10'h2C; // completed top-level APB writes
    localparam logic [9:0] REG_PERF_APB_READS  = 10'h30; // completed top-level APB reads
    localparam logic [9:0] REG_PERF_IN_STALLS  = 10'h34; // input-ready but no input-valid cycles
    localparam logic [9:0] REG_PERF_OUT_STALLS = 10'h38; // output-valid but no output-ready cycles

    // -------------------------------------------------------------------------
    // Matrix buffer local offsets (decoded on PADDR[7:0]) -- single source of
    // truth for the input/output buffer address maps.
    // -------------------------------------------------------------------------
    // matrix_buffer_ab
    localparam logic [7:0] MAT_A_DATA_OFF  = 8'h00; // write A elements (auto-inc)
    localparam logic [7:0] MAT_B_DATA_OFF  = 8'h40; // write B elements (auto-inc)
    localparam logic [7:0] MAT_AB_CTRL_OFF = 8'h80; // [0]=reset ptrs, [1/2]=full RO
    // matrix_buffer_c
    localparam logic [7:0] MAT_C_DATA_OFF  = 8'h00; // read C elements (auto-inc)
    localparam logic [7:0] MAT_C_CTRL_OFF  = 8'h80; // [0]=reset ptr, [1]=full RO

    // CTRL bit positions
    localparam int CTRL_START_BIT      = 0;
    localparam int CTRL_SOFTRST_BIT    = 1;
    // STATUS bit positions
    localparam int STATUS_BUSY_BIT     = 0;
    localparam int STATUS_DONE_BIT     = 1;
    // INT bit positions
    localparam int INT_DONE_BIT        = 0;
    // PERF_CTRL bit positions
    localparam int PERF_CLEAR_BIT      = 0;
    // HW_STATUS bit positions
    localparam int HW_STATUS_PERF_ACTIVE_BIT      = 0;
    localparam int HW_STATUS_IN_STALL_SEEN_BIT    = 1;
    localparam int HW_STATUS_OUT_STALL_SEEN_BIT   = 2;
    localparam int HW_STATUS_COUNTER_OVERFLOW_BIT = 3;
    localparam int HW_STATUS_FSM_STATE_LSB        = 8;

endpackage : accel_pkg

`endif
