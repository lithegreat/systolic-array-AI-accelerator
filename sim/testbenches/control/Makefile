TOPLEVEL := control_unit
MODULE   := test_control_unit

REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../..)
VERILOG_SOURCES := $(REPO_ROOT)/rtl/control/control_unit.sv

COCOTB_TB_DIR := $(REPO_ROOT)/sim/testbenches/control

include $(REPO_ROOT)/sim/scripts/Makefile.common
