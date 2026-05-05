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
    localparam int unsigned DEF_M       = 4;   // C/A row count
    localparam int unsigned DEF_N       = 4;   // C/B col count
    localparam int unsigned DEF_K       = 4;   // reduction depth
    localparam int unsigned DEF_DATA_W  = 16;  // signed input width
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

    // CTRL bit positions
    localparam int CTRL_START_BIT      = 0;
    localparam int CTRL_SOFTRST_BIT    = 1;
    // STATUS bit positions
    localparam int STATUS_BUSY_BIT     = 0;
    localparam int STATUS_DONE_BIT     = 1;
    // INT bit positions
    localparam int INT_DONE_BIT        = 0;

endpackage : accel_pkg

`endif
