#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# run_verilator.sh -- Local behavioral simulation of the Group5 accelerator with
#                     Verilator. Self-contained: no SoC, no ibex, no RISC-V hex.
#
# Verilator 5.x (with --timing) is required. Runs the standalone APB testbench
# sim/testbenches/tb_accel.sv against accelerator_top and prints PASS/FAIL.
#
# Usage:
#   ./sim/scripts/run_verilator.sh                # build + run (16x16 default)
#   ./sim/scripts/run_verilator.sh --dim 8        # build + run an 8x8 array
#   ./sim/scripts/run_verilator.sh --trace        # also dump waves to sim/waves/
#   ./sim/scripts/run_verilator.sh --dim 8 --trace
# -----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${ROOT}"

if ! command -v verilator >/dev/null 2>&1; then
    echo "ERROR: verilator not found on PATH." >&2
    exit 1
fi

TRACE_ARGS=()
RUN_ARGS=()
DIM_ARGS=()
ACCEL_DIM=""
while [[ $# -gt 0 ]]; do
    case "${1}" in
        --trace)
            mkdir -p sim/waves
            TRACE_ARGS=(--trace)
            RUN_ARGS=(+trace)
            shift
            ;;
        --dim)
            ACCEL_DIM="${2:?--dim requires a value, e.g. --dim 8}"
            DIM_ARGS=(-DACCEL_DIM="${ACCEL_DIM}")
            shift 2
            ;;
        --dim=*)
            ACCEL_DIM="${1#*=}"
            DIM_ARGS=(-DACCEL_DIM="${ACCEL_DIM}")
            shift
            ;;
        *)
            echo "ERROR: unknown argument '${1}' (expected --dim <N> and/or --trace)." >&2
            exit 1
            ;;
    esac
done
echo "==> Accelerator array size: ${ACCEL_DIM:-16 (default)}"

WARN_SUPPRESS=(
    -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE -Wno-WIDTHEXPAND
    -Wno-WIDTHTRUNC -Wno-TIMESCALEMOD -Wno-UNSIGNED -Wno-CMPCONST
    -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM
)

echo "==> Building with Verilator"
rm -rf sim/veri_work
verilator --binary --timing --timescale 1ns/1ps "${WARN_SUPPRESS[@]}" "${TRACE_ARGS[@]}" "${DIM_ARGS[@]}" \
    --top-module tb_accel \
    -Irtl/include \
    -Mdir sim/veri_work \
    rtl/include/accel_pkg.sv \
    rtl/control/control_unit.sv \
    rtl/MAC/mac_pe.sv \
    rtl/array/skew_shift.sv \
    rtl/array/systolic_array.sv \
    rtl/matrix/matrix_buffer_ab.sv \
    rtl/matrix/matrix_buffer_c.sv \
    rtl/top/accelerator_top.sv \
    sim/testbenches/accel/tb_accel.sv

echo "==> Running simulation"
./sim/veri_work/Vtb_accel "${RUN_ARGS[@]}"
