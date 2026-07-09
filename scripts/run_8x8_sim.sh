#!/usr/bin/env bash
set -euo pipefail
python3 sim/common/c_code/gen_accel_data.py --variant int8_8x8
export ACCEL_VARIANT=int8_8x8
export DUT_DEFINES="+define+RVFI +define+INC_ASSERT +define+COMMON_CELLS_ASSERTS_OFF +define+ACCEL_DIM=8"
bash scripts/lab_full_flow.sh sim
