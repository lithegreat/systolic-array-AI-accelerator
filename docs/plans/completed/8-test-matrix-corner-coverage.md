# Plan: Test Matrix And Corner Coverage

Last reviewed: 2026-06-15
Status: Completed
Owner: Li / Copilot
Tracking: local implementation from SAURIA comparison

## Goal

Expand regression beyond one random GEMM by adding named edge-case vector
generation, multi-seed/edge-case top-level tests, and focused buffer/control
corner coverage.

## Context

SAURIA uses Python to generate many constrained convolution cases and debug bus
tests. Group5 now has named build variants and performance/status registers, so
the next low-risk improvement is broader verification coverage without changing
RTL behavior.

## Steps

- [x] Add edge-case modes and alternate output path to the firmware vector generator.
- [x] Add multi-seed and edge-case matrix tests at `accelerator_top` level.
- [x] Add A/B buffer overrun and back-pressure corner tests.
- [x] Add C buffer over-read, reset-full, and ignore-after-full tests.
- [x] Add control-unit start-while-busy and status W1C coverage.
- [x] Run focused cocotb, generator, standalone, and docs checks.

## Progress log

- 2026-06-15 — Started implementation after performance/status register work.
- 2026-06-15 — Added `gen_accel_data.py --case/--out`, top-level multi-seed and
  edge-case GEMM tests, and focused matrix/control corner tests.

## Decision log

- 2026-06-15 — Keep edge-case generation opt-in through `gen_accel_data.py --case`
  and add `--out` for temporary generated headers so verification can exercise
  cases without modifying the checked-in firmware vector header.

## Verification

Completed with:

- `python3 sim/common/c_code/gen_accel_data.py --list-cases`.
- `python3 sim/common/c_code/gen_accel_data.py --variant int8_16x16 --case checkerboard --out /tmp/accel_checker.h`.
- `python3 sim/common/c_code/gen_accel_data.py --variant int8_8x8 --case minmax --seed 0x123 --out /tmp/accel_minmax_8.h`.
- `PATH=/home/li/repos/group5/.venv/bin:$PATH pytest -q sim/test_runner.py -k 'control or matrix_ab or matrix_c or top'` → 4 selected module regressions PASS.
- `./sim/scripts/run_verilator.sh --variant int8_16x16` → PASS.
- `.venv/bin/ruff format ...` and `.venv/bin/ruff check ...` on changed Python files.
