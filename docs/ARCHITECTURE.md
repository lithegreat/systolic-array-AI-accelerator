# Architecture

> Top-level map of the accelerator: its domains, the layers each domain passes
> through, and a maturity scorecard that tracks gaps over time. Read this before
> diving into any module; then follow the links into the
> [interface contracts](interface/README.md) or the code.

Last reviewed: 2026-06-15

## Bird's-eye view

A systolic-array GEMM accelerator (`C = A · B`) that lives in the **TUM student
subsystem (SS1)** of the Edu4Chip Didactic SoC. The RISC-V Ibex core configures
and feeds it over an **APB** subordinate port; results are read back over the
same bus.

```
RISC-V Ibex ──OBI──> SoC fabric ──APB──> [ accelerator_top ]
                                          ├── control_unit     (regs, FSM, IRQ)
                                          ├── matrix_buffer_ab  (A, B staging)
                                          ├── systolic_array    (M×N PEs)
                                          │     └── mac_pe      (signed MAC)
                                          └── matrix_buffer_c   (C capture + readback)
```

Dataflow is **output-stationary**: Matrix A streams in row-major, Matrix B
streams in, each PE accumulates one `C[i][j]` over K steps, and Matrix C is read
back element-by-element. Handshakes are valid/ready throughout. The default
simulation/SoC build variant is `int8_16x16`: `M=N=K=16`, `DATA_W=8` signed,
`ACC_W=32` (two's-complement wrap, no saturation). Build variants are cataloged
in [`sim/common/c_code/accel_config.py`](../sim/common/c_code/accel_config.py).

## Domain map (ownership)

Each RTL area is an independently owned module with a stable interface contract.

| Domain | Code | Interface contract | Owner (issue) |
| --- | --- | --- | --- |
| Control & status | [`rtl/control/`](../rtl/control/) | [control_unit_if.md](interface/control_unit_if.md) | Li (#1) |
| MAC unit | [`rtl/MAC/`](../rtl/MAC/) | [mac_if.md](interface/mac_if.md) | Liu (#2) |
| Systolic array | [`rtl/array/`](../rtl/array/) | [systolic_array_if.md](interface/systolic_array_if.md) | Zhong (#3) |
| Matrix A & B buffers | [`rtl/matrix/`](../rtl/matrix/) | [matrix_buffer_a_b_if.md](interface/matrix_buffer_a_b_if.md) | Cao (#4) |
| Matrix C buffer | [`rtl/matrix/`](../rtl/matrix/) | [matrix_buffer_c_if.md](interface/matrix_buffer_c_if.md) | Shang (#5) |
| Top integration | [`rtl/top/`](../rtl/top/) | [accelerator_top_if.md](interface/accelerator_top_if.md) | shared |

Keep cross-module coupling minimal: communicate through the documented ports and
handshakes, never through hidden assumptions.

## Layer map

Each functional change is expected to walk down these layers (see the
development flow in [`AGENTS.md`](../AGENTS.md)):

| Layer | Where | Source of truth |
| --- | --- | --- |
| 1. Interface contract | `docs/interface/` | the `_if.md` file — update *first* |
| 2. RTL design | `rtl/` (+ `rtl/include/accel_pkg.sv`) | synthesizable SystemVerilog |
| 3. Golden / reference model | `sim/common/` (incl. `c_code/`) | Python / C GEMM model |
| 4. Cocotb + Verilator tests | `sim/testbenches/`, `sim/scripts/` | functional regression |
| 5. SoC integration | `Didactic-SoC/` submodule | firmware `sw/accel/`, full-SoC tb |
| 6. Implementation | `fpga/`, `asic/` | PYNQ-Z1 bitstream, GF 22 nm FDX |

## Codemap — where to find things

- **Shared constants / params**: [`rtl/include/accel_pkg.sv`](../rtl/include/accel_pkg.sv).
- **Self-contained RTL**: the accelerator depends only on `accel_pkg.sv` (no
  common_cells/axi/ibex), so it elaborates standalone.
- **Standalone APB testbench**: `sim/testbenches/tb_accel.sv` (no SoC/JTAG/hex).
- **Full-SoC functional test**: `Didactic-SoC/verification/verilator/src/soc_accel/`
  (Ibex runs `sw/accel/accel.c`, drives the accelerator over real OBI/APB).
- **Golden-vector generator**: `sim/common/c_code/gen_accel_data.py`.
- **Verification report**: [verification/accelerator_soc_report.md](verification/accelerator_soc_report.md).

## Cross-cutting invariants

- **Reset**: active-low `rst_n` everywhere, *except* `control_unit`, which takes
  the SoC's active-high `reset_int` (inverted at the `tum_ss` boundary).
- **APB**: 32-bit data, 10-bit address; a 32-bit word packs `32/DATA_W` elements
  LSB-lane first.
- **Signed arithmetic**: preserved end-to-end in MAC and array datapaths.
- **PASS criterion (SoC test)**: data-memory word `accel_result == 0xACCE5500`.

## Maturity scorecard

Rate each area and track the gap that blocks the next level. Update the date and
rows whenever maturity changes, so the scorecard stays a live signal, not a
snapshot.

Legend: **Stable** (verified, contract-locked) · **Working** (functional, gaps
remain) · **WIP** · **Planned**.

| Area / layer | Status | Gap to close next |
| --- | --- | --- |
| Interface contracts | Stable | Keep in lock-step with any RTL port change. |
| RTL — control_unit | Working | Broaden IRQ/status corner-case coverage. |
| RTL — mac_pe | Stable | — |
| RTL — systolic_array | Working | Stall/back-pressure stress tests. |
| RTL — matrix_buffer_ab | Working | Overflow/over-run path coverage. |
| RTL — matrix_buffer_c | Working | Readback-pointer edge cases. |
| Golden / reference model | Stable | — |
| Cocotb + Verilator regression | Working | Raise functional-coverage baseline. |
| SoC integration (Verilator) | Stable | Signed-off: `accel_result == 0xACCE5500`. |
| SoC integration (QuestaSim) | Working | Lab-license-gated; `+initreg+0` fetch-X fix in place. |
| FPGA (PYNQ-Z1) | Working | Full on-board bring-up report. |
| ASIC (GF 22 nm FDX) | Planned | Gate-level netlist + timing. |

> Open gaps that need scheduling go to [plans/tech-debt.md](plans/tech-debt.md);
> work in progress gets an [active plan](plans/README.md).
