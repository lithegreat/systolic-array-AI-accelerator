TOPLEVEL := accelerator_top
MODULE   := test_accelerator_top

REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../..)
VERILOG_SOURCES := \
    $(REPO_ROOT)/rtl/MAC/mac_pe.sv \
    $(REPO_ROOT)/rtl/array/skew_shift.sv \
    $(REPO_ROOT)/rtl/array/systolic_array.sv \
    $(REPO_ROOT)/rtl/matrix/matrix_buffer_ab.sv \
    $(REPO_ROOT)/rtl/matrix/matrix_buffer_c.sv \
    $(REPO_ROOT)/rtl/control/control_unit.sv \
    $(REPO_ROOT)/rtl/top/accelerator_top.sv

COCOTB_TB_DIR := $(REPO_ROOT)/sim/testbenches/top

include $(REPO_ROOT)/sim/scripts/Makefile.common
