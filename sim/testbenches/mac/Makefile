# Cocotb Makefile for mac_pe.
TOPLEVEL := mac_pe
MODULE   := test_mac_pe

REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../..)
VERILOG_SOURCES := $(REPO_ROOT)/rtl/MAC/mac_pe.sv

COCOTB_TB_DIR := $(REPO_ROOT)/sim/testbenches/mac

include $(REPO_ROOT)/sim/scripts/Makefile.common
