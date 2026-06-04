#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# run_xsim.sh -- Local behavioral simulation of the Group5 accelerator with
#                Vivado xsim. Self-contained: no SoC, no ibex, no RISC-V hex.
#
# Prerequisites:
#   - Vivado installed and on PATH (xvlog/xelab/xsim available).
#     Source the settings script once per shell, e.g.:
#         source /tools/Xilinx/Vivado/2023.2/settings64.sh
#   - Run from anywhere; paths below are resolved relative to the repo root.
#
# Usage:
#   ./sim/scripts/run_xsim.sh          # batch run, prints PASS/FAIL
#   ./sim/scripts/run_xsim.sh -gui     # open the xsim GUI with waveforms
# -----------------------------------------------------------------------------
set -euo pipefail

# Repo root = two levels up from this script (sim/scripts/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

RTL="${ROOT}/rtl"
INC="${RTL}/include"
TB="${ROOT}/sim/testbenches/accel/tb_accel.sv"

WORK="${ROOT}/sim/xsim_work"
mkdir -p "${WORK}"
cd "${WORK}"

GUI=0
if [[ "${1:-}" == "-gui" ]]; then
    GUI=1
fi

if ! command -v xvlog >/dev/null 2>&1; then
    echo "ERROR: xvlog not found. Source Vivado settings64.sh first." >&2
    echo "       e.g. source /tools/Xilinx/Vivado/<ver>/settings64.sh" >&2
    exit 1
fi

echo "==> Compiling (xvlog)"
xvlog -sv \
    -i "${INC}" \
    "${INC}/accel_pkg.sv" \
    "${RTL}/control/control_unit.sv" \
    "${RTL}/MAC/mac_pe.sv" \
    "${RTL}/array/skew_shift.sv" \
    "${RTL}/array/systolic_array.sv" \
    "${RTL}/matrix/matrix_buffer_ab.sv" \
    "${RTL}/matrix/matrix_buffer_c.sv" \
    "${RTL}/top/accelerator_top.sv" \
    "${TB}"

echo "==> Elaborating (xelab)"
xelab tb_accel -s tb_accel_sim -debug typical

if [[ "${GUI}" -eq 1 ]]; then
    echo "==> Launching xsim GUI"
    xsim tb_accel_sim -gui
else
    echo "==> Running xsim (batch)"
    xsim tb_accel_sim -R
fi
