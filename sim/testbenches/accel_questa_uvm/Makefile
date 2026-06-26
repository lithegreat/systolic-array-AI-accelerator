# =============================================================================
# Makefile  --  QuestaSim compilation and simulation for accel_questa_uvm
#
# Targets:
#   make compile   – vlib + vlog (UVM library, then DUT + TB)
#   make elaborate – vopt (build optimised simulation binary)
#   make run       – vsim, one test (TESTNAME=accel_random_test by default)
#   make regress   – vsim all five tests; exit non-zero on any failure
#   make waves     – vsim in GUI mode with all waves pre-added
#   make clean     – remove build artefacts
#
# Prerequisites (set by module load on eikon):
#   MTI_HOME    – QuestaSim installation root (set by module load)
#   PATH        – must include $MTI_HOME/bin
#
# The UVM 1.2 library is compiled from source ($MTI_HOME/verilog_src/uvm-1.2).
# All QuestaSim commands are run from $(BUILD_DIR) so the local modelsim.ini
# created there is used instead of any global one.
#
# Usage on eikon (inside apptainer, after module load mentor/questasim/2023.4):
#   make compile elaborate regress
#   make run TESTNAME=accel_zero_test
#   make waves TESTNAME=accel_random_test
# =============================================================================

# ---------------------------------------------------------------------------
# Tool binaries (resolved from PATH after module load)
# ---------------------------------------------------------------------------
VLIB  := vlib
VLOG  := vlog
VMAP  := vmap
VOPT  := vopt
VSIM  := vsim

# ---------------------------------------------------------------------------
# Directory layout
# ---------------------------------------------------------------------------
TB_DIR    := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(TB_DIR)/../../..)
BUILD_DIR := $(TB_DIR)/sim_build

# ---------------------------------------------------------------------------
# UVM source (provided by QuestaSim installation)
# ---------------------------------------------------------------------------
UVM_SRC := $(MTI_HOME)/verilog_src/uvm-1.2/src

# ---------------------------------------------------------------------------
# RTL source files (compilation order: package first)
# ---------------------------------------------------------------------------
RTL_FILES := \
    $(REPO_ROOT)/rtl/include/accel_pkg.sv \
    $(REPO_ROOT)/rtl/MAC/mac_pe.sv \
    $(REPO_ROOT)/rtl/array/skew_shift.sv \
    $(REPO_ROOT)/rtl/array/systolic_array.sv \
    $(REPO_ROOT)/rtl/matrix/matrix_buffer_ab.sv \
    $(REPO_ROOT)/rtl/matrix/matrix_buffer_c.sv \
    $(REPO_ROOT)/rtl/control/control_unit.sv \
    $(REPO_ROOT)/rtl/top/accelerator_top.sv

# ---------------------------------------------------------------------------
# Testbench source files (compilation order matters: pkgs before tb_top)
# ---------------------------------------------------------------------------
TB_FILES := \
    $(TB_DIR)/apb_if.sv \
    $(TB_DIR)/apb_pkg.sv \
    $(TB_DIR)/accel_env_pkg.sv \
    $(TB_DIR)/accel_tests_pkg.sv \
    $(TB_DIR)/tb_top.sv

# ---------------------------------------------------------------------------
# Compiler options (mirrored from Didactic-SoC/sim/Makefile where applicable)
# ---------------------------------------------------------------------------
VLOG_OPTS := \
    -sv \
    -svinputport=compat \
    -suppress 2583 \
    -suppress 2244 \
    -suppress 2388 \
    -suppress 2275

# ---------------------------------------------------------------------------
# Elaboration / simulation options
# ---------------------------------------------------------------------------
VOPT_OPTS  := +acc tb_top -o tb_top_opt
VSIM_OPTS  := -c -suppress 3009 -suppress 8386

# Default test; override on command line: make run TESTNAME=accel_zero_test
TESTNAME ?= accel_random_test

# All five tests run by 'make regress'
TESTS := \
    accel_zero_test \
    accel_identity_test \
    accel_checkerboard_test \
    accel_random_test \
    accel_coverage_test

# ---------------------------------------------------------------------------
# Phony targets
# ---------------------------------------------------------------------------
.PHONY: all compile elaborate run regress waves clean help

all: regress

# ---------------------------------------------------------------------------
# compile  –  build UVM library, then DUT + testbench
# ---------------------------------------------------------------------------
compile:
	@echo "=== [1/3] Compile ==="
	mkdir -p $(BUILD_DIR)/ucdb $(BUILD_DIR)/log
	@# Run every questa command from BUILD_DIR so the local modelsim.ini is used
	cd $(BUILD_DIR) && \
	    $(VLIB) uvm_lib && \
	    $(VLIB) work
	@# Compile UVM 1.2 from source into uvm_lib
	cd $(BUILD_DIR) && $(VLOG) $(VLOG_OPTS) \
	    -work uvm_lib \
	    +incdir+$(UVM_SRC) \
	    +define+QUESTA \
	    $(UVM_SRC)/uvm_pkg.sv
	@# Compile DUT RTL and testbench into work
	cd $(BUILD_DIR) && $(VLOG) $(VLOG_OPTS) \
	    -work work \
	    -L uvm_lib \
	    +incdir+$(UVM_SRC) \
	    +incdir+$(REPO_ROOT)/rtl/include \
	    $(RTL_FILES) $(TB_FILES)
	@echo "=== Compile done ==="

# ---------------------------------------------------------------------------
# elaborate  –  optimise into a simulation binary
# ---------------------------------------------------------------------------
elaborate: compile
	@echo "=== [2/3] Elaborate ==="
	cd $(BUILD_DIR) && $(VOPT) \
	    -work work \
	    -L uvm_lib \
	    $(VOPT_OPTS)
	@echo "=== Elaborate done ==="

# ---------------------------------------------------------------------------
# run  –  simulate a single test (TESTNAME variable)
# ---------------------------------------------------------------------------
run: elaborate
	@echo "=== [3/3] Run: $(TESTNAME) ==="
	mkdir -p $(BUILD_DIR)/ucdb $(BUILD_DIR)/log
	cd $(BUILD_DIR) && $(VSIM) \
	    $(VSIM_OPTS) \
	    -work work \
	    -L uvm_lib \
	    tb_top_opt \
	    -sv_seed random \
	    +UVM_TESTNAME=$(TESTNAME) \
	    +UVM_VERBOSITY=UVM_MEDIUM \
	    +UVM_MAX_QUIT_COUNT=1 \
	    -do "coverage save -onexit ucdb/$(TESTNAME).ucdb; run -all; quit -f" \
	    -l log/$(TESTNAME).log
	@# Check log for any UVM errors that vsim exit code may not reflect
	@if grep -qE "# UVM_FATAL|# UVM_ERROR" $(BUILD_DIR)/log/$(TESTNAME).log; then \
	    echo "FAIL: $(TESTNAME)  (see $(BUILD_DIR)/log/$(TESTNAME).log)"; exit 1; \
	fi
	@echo "PASS: $(TESTNAME)"

# ---------------------------------------------------------------------------
# regress  –  run all five tests; reports pass/fail summary
# ---------------------------------------------------------------------------
regress: elaborate
	@echo "=== Regression: $(words $(TESTS)) tests ==="
	@mkdir -p $(BUILD_DIR)/ucdb $(BUILD_DIR)/log
	@PASS=0; FAIL=0; \
	cd $(BUILD_DIR) && \
	for t in $(TESTS); do \
	    echo "--- $$t ---"; \
	    $(VSIM) $(VSIM_OPTS) \
	        -work work \
	        -L uvm_lib \
	        tb_top_opt \
	        -sv_seed random \
	        +UVM_TESTNAME=$$t \
	        +UVM_VERBOSITY=UVM_MEDIUM \
	        +UVM_MAX_QUIT_COUNT=1 \
	        -do "coverage save -onexit ucdb/$$t.ucdb; run -all; quit -f" \
	        -l log/$$t.log; \
	    if grep -qE "# UVM_FATAL|# UVM_ERROR" log/$$t.log; then \
	        echo "FAIL: $$t"; FAIL=$$((FAIL+1)); \
	    else \
	        echo "PASS: $$t"; PASS=$$((PASS+1)); \
	    fi; \
	done; \
	echo ""; \
	echo "=== Results: $$PASS passed, $$FAIL failed ==="; \
	exit $$FAIL

# ---------------------------------------------------------------------------
# waves  –  GUI mode with all signals pre-loaded
# ---------------------------------------------------------------------------
waves: elaborate
	cd $(BUILD_DIR) && vsim \
	    -gui \
	    -work work \
	    -L uvm_lib \
	    tb_top_opt \
	    -sv_seed random \
	    +UVM_TESTNAME=$(TESTNAME) \
	    +UVM_VERBOSITY=UVM_HIGH \
	    -do "add wave -r /tb_top/*; run -all"

# ---------------------------------------------------------------------------
# clean  –  remove all generated files
# ---------------------------------------------------------------------------
clean:
	rm -rf $(BUILD_DIR) transcript vsim.wlf

# ---------------------------------------------------------------------------
# help
# ---------------------------------------------------------------------------
help:
	@echo "Targets:"
	@echo "  compile              – compile UVM + DUT + TB"
	@echo "  elaborate            – vopt (optimise)"
	@echo "  run [TESTNAME=<t>]   – simulate one test (default: accel_random_test)"
	@echo "  regress              – run all 5 tests"
	@echo "  waves [TESTNAME=<t>] – GUI mode"
	@echo "  clean                – remove build artefacts"
	@echo ""
	@echo "Tests: $(TESTS)"
