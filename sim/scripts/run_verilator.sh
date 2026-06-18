#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# run_verilator.sh -- Local behavioral simulation of the Group5 accelerator with
#                     Verilator. Self-contained: no SoC, no ibex, no RISC-V hex.
#
# Verilator 5.x (with --timing) is required. Runs the standalone APB testbench
# sim/testbenches/tb_accel.sv against accelerator_top and prints PASS/FAIL.
#
# Usage:
#   ./sim/scripts/run_verilator.sh                         # build + run int8_16x16 default
#   ./sim/scripts/run_verilator.sh --variant int8_8x8      # build + run the PYNQ-Z1 variant
#   ./sim/scripts/run_verilator.sh --dim 8                 # legacy shorthand for int8 8x8
#   ./sim/scripts/run_verilator.sh --trace        # also dump waves to sim/waves/
#   ./sim/scripts/run_verilator.sh --dim 8 --trace
# -----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${ROOT}"

TRACE_ARGS=()
RUN_ARGS=()
DEFINE_ARGS=()
ACCEL_VARIANT="int8_16x16"
ACCEL_DIM_OVERRIDE=""
ACCEL_DATA_W_OVERRIDE=""
while [[ $# -gt 0 ]]; do
    case "${1}" in
        --variant)
            ACCEL_VARIANT="${2:?--variant requires a value, e.g. int8_8x8}"
            shift 2
            ;;
        --variant=*)
            ACCEL_VARIANT="${1#*=}"
            shift
            ;;
        --list-variants)
            python3 sim/common/c_code/accel_config.py --list
            exit 0
            ;;
        --trace)
            mkdir -p sim/waves
            TRACE_ARGS=(--trace)
            RUN_ARGS=(+trace)
            shift
            ;;
        --dim)
            ACCEL_DIM_OVERRIDE="${2:?--dim requires a value, e.g. --dim 8}"
            shift 2
            ;;
        --dim=*)
            ACCEL_DIM_OVERRIDE="${1#*=}"
            shift
            ;;
        --data-w)
            ACCEL_DATA_W_OVERRIDE="${2:?--data-w requires a value, e.g. --data-w 16}"
            shift 2
            ;;
        --data-w=*)
            ACCEL_DATA_W_OVERRIDE="${1#*=}"
            shift
            ;;
        *)
            echo "ERROR: unknown argument '${1}' (expected --variant, --dim, --data-w, --trace)." >&2
            exit 1
            ;;
    esac
done

eval "$(python3 sim/common/c_code/accel_config.py --variant "${ACCEL_VARIANT}" --format shell)"

if ! command -v verilator >/dev/null 2>&1; then
    echo "ERROR: verilator not found on PATH." >&2
    exit 1
fi

if [[ -n "${ACCEL_DIM_OVERRIDE}" ]]; then
    ACCEL_DIM="${ACCEL_DIM_OVERRIDE}"
    ACCEL_M="${ACCEL_DIM_OVERRIDE}"
    ACCEL_N="${ACCEL_DIM_OVERRIDE}"
    ACCEL_K="${ACCEL_DIM_OVERRIDE}"
fi
if [[ -n "${ACCEL_DATA_W_OVERRIDE}" ]]; then
    ACCEL_DATA_W="${ACCEL_DATA_W_OVERRIDE}"
fi

if [[ "${ACCEL_M}" != "${ACCEL_N}" || "${ACCEL_M}" != "${ACCEL_K}" ]]; then
    echo "ERROR: tb_accel currently expects square M=N=K variants." >&2
    exit 1
fi
if ((32 % ACCEL_DATA_W != 0)); then
    echo "ERROR: ACCEL_DATA_W=${ACCEL_DATA_W} must divide the 32-bit APB bus." >&2
    exit 1
fi

DEFINE_ARGS=(-DACCEL_DIM="${ACCEL_M}" -DACCEL_DATA_W="${ACCEL_DATA_W}")

echo "==> Accelerator variant: ${ACCEL_VARIANT} (M=N=K=${ACCEL_M}, DATA_W=${ACCEL_DATA_W}, ACC_W=${ACCEL_ACC_W})"

WARN_SUPPRESS=(
    -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE -Wno-WIDTHEXPAND
    -Wno-WIDTHTRUNC -Wno-TIMESCALEMOD -Wno-UNSIGNED -Wno-CMPCONST
    -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM
)

echo "==> Building with Verilator"
rm -rf sim/veri_work
verilator --binary --timing --timescale 1ns/1ps "${WARN_SUPPRESS[@]}" "${TRACE_ARGS[@]}" "${DEFINE_ARGS[@]}" \
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
