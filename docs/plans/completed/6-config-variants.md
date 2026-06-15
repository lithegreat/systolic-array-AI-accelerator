# Plan: Accelerator Config Variants

Last reviewed: 2026-06-15
Status: Completed
Owner: Li / Copilot
Tracking: local implementation from SAURIA comparison

## Goal

Create a small, canonical accelerator configuration layer so RTL simulation,
firmware test-vector generation, FPGA defines, and documentation agree on the
same build variants.

## Context

The architecture documents an INT8 baseline in
[ARCHITECTURE.md](../../ARCHITECTURE.md), while some older verification text and
scripts carried fixed 16x16/16-bit assumptions. The relevant contracts are the
top-level interface in [accelerator_top_if.md](../../interface/accelerator_top_if.md)
and the buffer/array contracts under `docs/interface/`. This plan implements the
first, low-risk phase from the SAURIA comparison: configuration consistency, not
runtime-dynamic matrix dimensions.

## Steps

- [x] Add named build variants and expose them to scripts.
- [x] Refactor the firmware vector generator to consume a named variant.
- [x] Let the standalone Verilator runner select variants while preserving
      legacy `--dim` usage.
- [x] Let the FPGA flow select the same named variants while preserving direct
      `ACCEL_DIM` / `ACCEL_DATA_W` overrides.
- [x] Update docs that describe the default datapath and variant commands.
- [x] Run focused checks: generator, 8x8/16x16 standalone Verilator, and docs / ruff checks.

## Progress log

- 2026-06-15 — Started implementation after comparing Group5 against SAURIA.
- 2026-06-15 — Added `accel_config.py`, wired `gen_accel_data.py`,
  `run_verilator.sh`, and the FPGA flow to named build variants, refreshed the
  default generated firmware header, and updated stale INT8/variant docs.
- 2026-06-15 — Verified `int8_8x8`, `int8_16x16`, and `int16_16x16` standalone
  Verilator smoke tests; ruff and docs checks passed.

## Decision log

- 2026-06-15 — Keep the baseline APB accelerator architecture unchanged; this
  plan only centralizes build-time variants. Runtime `M/N/K_DIM` semantics remain
  a separate interface-first task.
- 2026-06-15 — Preserve direct `ACCEL_DIM` / `ACCEL_DATA_W` overrides for FPGA
  experiments, but make `ACCEL_VARIANT=int8_8x8` the documented PYNQ-Z1 path.

## Verification

Completed with:

- `python3 sim/common/c_code/accel_config.py --list`
- `python3 sim/common/c_code/gen_accel_data.py --variant int8_16x16`
- `./sim/scripts/run_verilator.sh --variant int8_8x8` → PASS, 64 C elements == 8.
- `./sim/scripts/run_verilator.sh --variant int8_16x16` → PASS, 256 C elements == 16.
- `./sim/scripts/run_verilator.sh --variant int16_16x16` → PASS, 256 C elements == 16.
- `.venv/bin/ruff format --check sim/common/c_code/accel_config.py sim/common/c_code/gen_accel_data.py`
- `.venv/bin/ruff check sim/common/c_code/accel_config.py sim/common/c_code/gen_accel_data.py`
- `python3 scripts/check_docs.py`
