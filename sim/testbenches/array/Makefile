# Cocotb Makefile for systolic_array.
TOPLEVEL := systolic_array
MODULE   := test_systolic_array

REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../..)
VERILOG_SOURCES := \
    $(REPO_ROOT)/rtl/MAC/mac_pe.sv \
    $(REPO_ROOT)/rtl/array/systolic_array.sv

COCOTB_TB_DIR := $(REPO_ROOT)/sim/testbenches/array

include $(REPO_ROOT)/sim/scripts/Makefile.common
