#!/usr/bin/env bash
# =============================================================================
# lab_full_flow.sh — QuestaSim 仿真 + Vivado FPGA 综合 一体化脚本
#
# 在 TUM 实验室服务器 (lx01.clients.eikon.tum.de) 上运行。
#
# Usage:
#   bash scripts/lab_full_flow.sh              # 运行全部（仿真 + 综合）
#   bash scripts/lab_full_flow.sh sim          # 只运行 QuestaSim 仿真
#   bash scripts/lab_full_flow.sh synth        # 只运行 Vivado 综合
#   bash scripts/lab_full_flow.sh compile-only # 只运行 compile+elaborate（不需要 license）
#
# Environment overrides:
#   ACCEL_VARIANT=int8_8x8    (default; 16x16 does NOT fit PYNQ-Z1)
#   LM_LICENSE_FILE=port@host (Mentor license for vsim)
#   TESTCASE=accel            (baremetal test program)
# =============================================================================
set -euo pipefail

FLOW="${1:-all}"   # all | sim | synth | compile-only
TESTCASE="${2:-accel}"
ACCEL_VARIANT="${ACCEL_VARIANT:-int8_8x8}"

# Resolve repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOC_DIR="$REPO_ROOT/Didactic-SoC"
SIF="/nas/ei/share/tools/apptainer/MSMCD/alma.sif"
MODULES_INIT="/nas/ei/share/tools/environment_modules/4.5.1/init/bash"

echo "======================================================================="
echo "  lab_full_flow.sh"
echo "======================================================================="
echo "  Flow:          $FLOW"
echo "  Repo root:     $REPO_ROOT"
echo "  SoC dir:       $SOC_DIR"
echo "  Testcase:      $TESTCASE"
echo "  ACCEL_VARIANT: $ACCEL_VARIANT"
echo "======================================================================="

# --- Validate prerequisites ---
[ -f "$SOC_DIR/Makefile" ] || { echo "ERROR: SoC submodule missing. Run: git submodule update --init --recursive"; exit 1; }

# --- Init environment modules ---
# shellcheck disable=SC1090
source "$MODULES_INIT"

# --- Ensure bender on PATH ---
if [ -x "$REPO_ROOT/bin/bender" ]; then
    export PATH="$REPO_ROOT/bin:$PATH"
elif ! command -v bender >/dev/null 2>&1; then
    echo "==> bender not found. Downloading..."
    mkdir -p "$REPO_ROOT/bin"
    (cd "$REPO_ROOT/bin" && \
     wget -q https://github.com/pulp-platform/bender/releases/download/v0.31.0/bender-0.31.0-x86_64-linux-gnu-ubuntu24.04.tar.gz && \
     tar -xzf bender-0.31.0-*.tar.gz && rm -f bender-0.31.0-*.tar.gz)
    export PATH="$REPO_ROOT/bin:$PATH"
fi
echo "==> bender: $(command -v bender) ($(bender --version 2>/dev/null || echo 'unknown'))"

# --- Fetch SoC RTL dependencies (idempotent) ---
echo ""
echo "==> [STEP 0] Fetching SoC dependencies (bender update)..."
( cd "$SOC_DIR" && make repository_init )

# =========================================================================
# PHASE 1: QuestaSim Full-SoC Simulation
# =========================================================================
run_questasim() {
    local compile_only="${1:-false}"

    echo ""
    echo "======================================================================="
    echo "  PHASE 1: QuestaSim Full-SoC Simulation"
    if [ "$compile_only" = "true" ]; then
        echo "  Mode: compile + elaborate only (no license required)"
    fi
    echo "======================================================================="

    # -- Build baremetal firmware --
    echo "==> [STEP 1] Building RISC-V baremetal firmware (TESTCASE=$TESTCASE)..."
    module load eda_freeware/riscv/64-elf-ubuntu-24.04-gcc/2026.04.05
    ( cd "$SOC_DIR" && make build_test XLEN=64 TESTCASE="$TESTCASE" TEST="$TESTCASE" )
    module unload eda_freeware/riscv/64-elf-ubuntu-24.04-gcc/2026.04.05

    # -- QuestaSim phase --
    echo "==> [STEP 2] Loading QuestaSim module..."
    module load mentor/questasim/2023.4

    # License setup
    : "${LM_LICENSE_FILE:=27000@license.lis.ei.tum.de:1717@license.lis.ei.tum.de}"
    : "${MGLS_LICENSE_FILE:=$LM_LICENSE_FILE}"
    export LM_LICENSE_FILE MGLS_LICENSE_FILE
    echo "    LM_LICENSE_FILE=$LM_LICENSE_FILE"

    # Pre-resolve bender paths on host (avoid glibc mismatch in container)
    echo "==> [STEP 3] Pre-resolving bender dependencies on host..."
    COMMON_CELLS_DIR="$(cd "$SOC_DIR" && bender path common_cells)"
    AXI_DIR="$(cd "$SOC_DIR" && bender path axi)"
    APB_DIR="$(cd "$SOC_DIR" && bender path apb)"
    REGIF_DIR="$(cd "$SOC_DIR" && bender path register_interface)"
    OBI_DIR="$(cd "$SOC_DIR" && bender path obi)"
    SIM_FLIST="$(cd "$SOC_DIR" && bender script flist -t rtl -t vendor -t simulation -t tracer -t didactic_obi | tr '\n' ' ')"

    MAKE_OVERRIDES="COMMON_CELLS_DIR='$COMMON_CELLS_DIR' AXI_DIR='$AXI_DIR' APB_DIR='$APB_DIR' REGIF_DIR='$REGIF_DIR' OBI_DIR='$OBI_DIR' SIM_FLIST='$SIM_FLIST'"

    [ -f "$SIF" ] || { echo "ERROR: Container image not found: $SIF"; exit 1; }

    if [ "$compile_only" = "true" ]; then
        # Compile + elaborate only (no license needed)
        echo "==> [STEP 4] Running compile + elaborate in container (no license needed)..."
        apptainer exec \
            --env PATH="$PATH" \
            --bind /nas:/nas --bind /nfs:/nfs --bind /data:/data --bind /tmp:/tmp --bind "$HOME:$HOME" \
            "$SIF" bash -c "
                set -e
                cd '$SOC_DIR/sim'
                echo '--- make compile ---'
                make compile $MAKE_OVERRIDES
                echo '--- make elaborate ---'
                make elaborate TESTCASE='$TESTCASE' $MAKE_OVERRIDES
                echo ''
                echo '=========================================='
                echo '  compile + elaborate: SUCCESS'
                echo '  RTL integrates cleanly in the full SoC.'
                echo '=========================================='
            "
    else
        # Full flow: compile + elaborate + run_sim
        RUN_CMD="${RUN_CMD:-run -all; quit -f}"
        echo "==> [STEP 4] Running compile + elaborate + run_sim in container..."
        apptainer exec \
            --env PATH="$PATH" \
            --env LM_LICENSE_FILE="$LM_LICENSE_FILE" \
            --env MGLS_LICENSE_FILE="$MGLS_LICENSE_FILE" \
            --bind /nas:/nas --bind /nfs:/nfs --bind /data:/data --bind /tmp:/tmp --bind "$HOME:$HOME" \
            "$SIF" bash -c "
                set -e
                cd '$SOC_DIR/sim'
                echo '--- make compile ---'
                make compile $MAKE_OVERRIDES
                echo '--- make elaborate ---'
                make elaborate TESTCASE='$TESTCASE' $MAKE_OVERRIDES
                echo '--- make run_sim ---'
                make run_sim TESTCASE='$TESTCASE' RUN_CMD='$RUN_CMD' $MAKE_OVERRIDES
            "
    fi

    echo ""
    echo "==> QuestaSim phase complete."
}

# =========================================================================
# PHASE 2: Vivado FPGA Synthesis
# =========================================================================
run_vivado() {
    echo ""
    echo "======================================================================="
    echo "  PHASE 2: Vivado FPGA Synthesis (ACCEL_VARIANT=$ACCEL_VARIANT)"
    echo "======================================================================="

    # -- Generate firmware vectors matching the FPGA variant --
    echo "==> [STEP 5] Generating firmware vectors for variant $ACCEL_VARIANT..."
    if [ -f "$REPO_ROOT/.venv/bin/activate" ]; then
        source "$REPO_ROOT/.venv/bin/activate"
    fi
    python3 "$REPO_ROOT/sim/common/c_code/gen_accel_data.py" \
        --variant "$ACCEL_VARIANT" \
        --out "$SOC_DIR/fpga/sw/accel/accel_gemm_data.h"

    # -- Build FPGA software image --
    echo "==> [STEP 6] Building FPGA firmware (accel.elf)..."
    module load eda_freeware/riscv/64-elf-ubuntu-24.04-gcc/2026.04.05
    ( cd "$SOC_DIR/fpga/sw" && make -B test TESTCASE=accel )
    module unload eda_freeware/riscv/64-elf-ubuntu-24.04-gcc/2026.04.05

    # -- Run Vivado synthesis + implementation + bitstream --
    echo "==> [STEP 7] Running Vivado synthesis (target: PYNQ-Z1, xc7z020)..."
    module load xilinx/vivado/2024.1
    ( cd "$SOC_DIR/fpga" && make all_xilinx ACCEL_VARIANT="$ACCEL_VARIANT" )

    # -- Print results --
    BIT_FILE="$SOC_DIR/build/fpga/z1/didactic-z1.runs/impl_1/DidacticZ1.bit"
    UTIL_RPT="$SOC_DIR/build/fpga/logs/z1.utilization.rpt"
    TIMING_RPT="$SOC_DIR/build/fpga/logs/z1.timing.rpt"

    echo ""
    echo "======================================================================="
    echo "  Vivado Synthesis Results"
    echo "======================================================================="
    if [ -f "$BIT_FILE" ]; then
        echo "  ✅ Bitstream: $BIT_FILE"
        ls -lh "$BIT_FILE"
    else
        echo "  ❌ Bitstream NOT found (synthesis/implementation may have failed)"
    fi

    if [ -f "$UTIL_RPT" ]; then
        echo ""
        echo "  --- Utilization Summary (top lines) ---"
        head -60 "$UTIL_RPT"
    fi

    if [ -f "$TIMING_RPT" ]; then
        echo ""
        echo "  --- Timing Summary (top lines) ---"
        head -30 "$TIMING_RPT"
    fi

    echo ""
    echo "==> Vivado phase complete."
}

# =========================================================================
# Main dispatch
# =========================================================================
case "$FLOW" in
    all)
        run_questasim false
        run_vivado
        ;;
    sim)
        run_questasim false
        ;;
    compile-only)
        run_questasim true
        ;;
    synth)
        run_vivado
        ;;
    *)
        echo "Usage: $0 [all|sim|synth|compile-only] [TESTCASE]"
        echo "  all          - QuestaSim sim + Vivado synth (default)"
        echo "  sim          - QuestaSim sim only"
        echo "  synth        - Vivado FPGA synthesis only"
        echo "  compile-only - QuestaSim compile+elaborate only (no license)"
        exit 1
        ;;
esac

echo ""
echo "======================================================================="
echo "  All requested phases complete."
echo "======================================================================="
