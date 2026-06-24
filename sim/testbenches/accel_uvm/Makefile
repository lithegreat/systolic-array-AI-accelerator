# -----------------------------------------------------------------------------
# Makefile for the accelerator pyuvm testbench
#
# Runs all @pyuvm.test()-decorated tests in tests/directed_test.py and
# tests/random_test.py through Verilator + cocotb.
#
# Usage:
#   make               – run all UVM tests
#   make SIM=icarus    – use Icarus instead (requires iverilog 11+)
# -----------------------------------------------------------------------------
TOPLEVEL := accelerator_top
MODULE   := tests.directed_test,tests.random_test

REPO_ROOT     := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../..)
COCOTB_TB_DIR := $(REPO_ROOT)/sim/testbenches/accel_uvm

VERILOG_SOURCES := \
    $(REPO_ROOT)/rtl/MAC/mac_pe.sv \
    $(REPO_ROOT)/rtl/array/skew_shift.sv \
    $(REPO_ROOT)/rtl/array/systolic_array.sv \
    $(REPO_ROOT)/rtl/matrix/matrix_buffer_ab.sv \
    $(REPO_ROOT)/rtl/matrix/matrix_buffer_c.sv \
    $(REPO_ROOT)/rtl/control/control_unit.sv \
    $(REPO_ROOT)/rtl/top/accelerator_top.sv

include $(REPO_ROOT)/sim/scripts/Makefile.common
