# Plan: Runtime Matrix Dimensions

Last reviewed: 2026-06-15
Status: Completed
Owner: Li / Copilot
Tracking: local implementation from SAURIA comparison

## Goal

Make `M_DIM`, `N_DIM`, and `K_DIM` real runtime tile dimensions instead of
documentation-only registers. Software can run compact tiles up to the physical
build size without zero-padding A/B/C in software.

## Context

The accelerator has named physical build variants and a `BUILD_INFO` register.
The next step was to let the existing dimension registers select a runtime tile
within that physical shape. This is an interface change spanning
[control_unit_if.md](../../interface/control_unit_if.md),
[matrix_buffer_a_b_if.md](../../interface/matrix_buffer_a_b_if.md),
[systolic_array_if.md](../../interface/systolic_array_if.md), and
[matrix_buffer_c_if.md](../../interface/matrix_buffer_c_if.md).

## Steps

- [x] Update interface contracts with compact runtime tile semantics.
- [x] Latch accepted runtime dimensions in `control_unit` on accepted start.
- [x] Make A/B streamer consume compact `M_DIM*K_DIM` and `K_DIM*N_DIM` layouts.
- [x] Make the array compute/drain only the runtime tile region.
- [x] Make C capture/readback expose compact `M_DIM*N_DIM` results.
- [x] Update top-level and cocotb tests for real partial tiles.
- [x] Run focused standalone/cocotb/docs verification.

## Progress log

- 2026-06-15 — Started implementation after completing test-matrix and corner coverage.
- 2026-06-15 — Wired pending dimensions into A/B preload, latched start-time
  dimensions into array/C readback, added compact runtime-tile cocotb coverage,
  and converted `accel.c` into an 8x8x8 tiled GEMM driver.

## Decision log

- 2026-06-15 — Use compact runtime layout: A is written as `M_DIM*K_DIM`, B as
  `K_DIM*N_DIM`, and C reads back as `M_DIM*N_DIM`. Runtime dimension writes are
  clamped into `1..physical` and accepted only while the control FSM is idle.
- 2026-06-15 — A/B preload uses the pending dimension registers so software can
  write compact data before start. Array execution and C readback use dimensions
  latched on accepted start so the result window remains stable after done.

## Verification

Completed with:

- `./sim/scripts/run_verilator.sh --variant int8_8x8` → PASS.
- `PATH=/home/li/repos/group5/.venv/bin:$PATH pytest -q sim/test_runner.py -k 'control or matrix_ab or matrix_c or array or top'` → 5 selected module regressions PASS.
- `./sim/scripts/run_verilator.sh --variant int8_16x16` → PASS.
- `cd Didactic-SoC/sw && make PREFIX=riscv-none-elf TESTCASE=accel TEST=accel test` → tiled firmware rebuilt.
- `cp Didactic-SoC/build/sw/accel.hex Didactic-SoC/verification/verilator/accel.hex`.
- `cd Didactic-SoC && source ../.venv/bin/activate && make verilate_accel` → `accel_result = acce5500`, `[soc_accel] OK`.
- `.venv/bin/ruff format ...` and `.venv/bin/ruff check ...` on changed Python tests.
- `python3 scripts/check_conventions.py` and `python3 scripts/check_docs.py`.