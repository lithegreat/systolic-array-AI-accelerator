# Plan: Performance And Status Registers

Last reviewed: 2026-06-15
Status: Completed
Owner: Li / Copilot
Tracking: local implementation from SAURIA comparison

## Goal

Add APB-visible build/status and performance counters, have the firmware read
and sanity-check them, and verify the path in standalone and full-SoC simulation.

## Context

SAURIA exposes version/status, cycle, and stall counters as part of its control
register file. Group5 already has a compact APB control unit in
[control_unit_if.md](../../interface/control_unit_if.md), but it previously only
reported busy/done and interrupt state. This plan added observability without
changing the accelerator dataflow or runtime matrix-dimension semantics.

## Steps

- [x] Extend the control-unit interface contract with build/status and perf registers.
- [x] Add counter event inputs from `accelerator_top` to `control_unit`.
- [x] Update standalone APB testbench checks for the new counters.
- [x] Update `accel.c` to clear/read/sanity-check counters after GEMM.
- [x] Run focused standalone, firmware, and SoC verification.

## Progress log

- 2026-06-15 — Started implementation after SAURIA follow-up analysis.
- 2026-06-15 — Added `BUILD_INFO`, `HW_STATUS`, and `PERF_*` registers; firmware
  now checks build info and performance-counter sanity after GEMM.
- 2026-06-15 — Verified standalone 8x8/16x16, control/top cocotb, firmware
  build, and full-SoC Verilator with the rebuilt firmware image.

## Decision log

- 2026-06-15 — Count global APB read/write transactions in the top-level wrapper,
  and count compute cycles plus input/output stalls in the control unit. This
  keeps datapath RTL unchanged while exposing enough observability for firmware
  and tests.
- 2026-06-15 — Keep `accel_result` as the only firmware global result sink so
  the full-SoC testbench can continue observing DMEM word 0. Performance values
  are read as local firmware variables for sanity checks.

## Verification

Completed with:

- `./sim/scripts/run_verilator.sh --variant int8_8x8` → PASS, perf `cycles=32`.
- `./sim/scripts/run_verilator.sh --variant int8_16x16` → PASS, perf `cycles=64`.
- `cd sim/testbenches/control && PATH=/home/li/repos/group5/.venv/bin:$PATH make` → 5/5 PASS.
- `cd sim/testbenches/top && PATH=/home/li/repos/group5/.venv/bin:$PATH make` → 10/10 PASS.
- `cd Didactic-SoC/sw && make PREFIX=riscv-none-elf TESTCASE=accel TEST=accel test` → firmware rebuilt.
- `cp Didactic-SoC/build/sw/accel.hex Didactic-SoC/verification/verilator/accel.hex`.
- `cd Didactic-SoC && source ../.venv/bin/activate && make verilate_accel` → `accel_result = acce5500`, `[soc_accel] OK`.
- `.venv/bin/ruff format sim/testbenches/control/test_control_unit.py`.
- `.venv/bin/ruff check sim/testbenches/control/test_control_unit.py`.
- `python3 scripts/check_conventions.py`.
- `python3 scripts/check_docs.py`.