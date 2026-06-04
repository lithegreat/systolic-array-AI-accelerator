#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# run_verilator.sh -- Local behavioral simulation of the Group5 accelerator with
#                     Verilator. Self-contained: no SoC, no ibex, no RISC-V hex.
#
# Verilator 5.x (with --timing) is required. Runs the standalone APB testbench
# sim/testbenches/tb_accel.sv against accelerator_top and prints PASS/FAIL.
#
# Usage:
#   ./sim/scripts/run_verilator.sh           # build + run
#   ./sim/scripts/run_verilator.sh --trace   # also dump waves to sim/waves/
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
if [[ "${1:-}" == "--trace" ]]; then
    mkdir -p sim/waves
    TRACE_ARGS=(--trace)
    RUN_ARGS=(+trace)
fi

WARN_SUPPRESS=(
    -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE -Wno-WIDTHEXPAND
    -Wno-WIDTHTRUNC -Wno-TIMESCALEMOD -Wno-UNSIGNED -Wno-CMPCONST
    -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM
)

echo "==> Building with Verilator"
rm -rf sim/veri_work
verilator --binary --timing --timescale 1ns/1ps "${WARN_SUPPRESS[@]}" "${TRACE_ARGS[@]}" \
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
