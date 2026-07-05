# GEMM Benchmark: CPU vs. CPU+Accelerator

> Measures and compares the cycle cost of a full GEMM computation on the
> bare Ibex core against the same computation offloaded to the systolic-array
> accelerator via APB, running inside the Didactic SoC.

Last reviewed: 2026-06-26

## What is measured

| Path | Description |
|---|---|
| **CPU only** | Naive triple-loop `O(M·N·K)` GEMM on Ibex. `int32_t` accumulation — same wrap semantics as the hardware MAC. |
| **CPU + Accelerator** | Tiled GEMM driver (`accel_run_tiled_gemm`) streams one full tile over APB to the 16×16 systolic array and collects results. Includes APB overhead. |

Timing is derived from the **Ibex instruction trace** emitted by Verilator
(`trace_core_00000000.log`). The runner script (`verilate_soc_benchmark.py`)
annotates the trace with hardware perf-counter values from the UART output.

## UART output

```
benchmark: start
compute: <N> cyc  (REG_PERF_CYCLES, accel)
bus:     <N> cyc  (<wr> wr + <rd> rd) x2
benchmark: PASS
```

The runner script additionally prints a wall-clock breakdown derived from
the Ibex trace:

```
--- Wall-clock breakdown (Ibex trace) ---
  CPU  GEMM:   <N> cyc  (first→last store to cpu_out[])
  Accel path:  <N> cyc  (accel_run_tiled_gemm entry → return to main)
    compute:   <N> cyc  (REG_PERF_CYCLES, systolic array)
    bus:       <N> cyc  (APB transactions x2)
    SW overhead:<N> cyc  (loop control, packing, accumulation)
  Speedup:         X.XXx  (CPU GEMM / Accel wall-clock)
-----------------------------------------
```

## Result code in `bench_result`

| Value | Meaning |
|---|---|
| `0xACCE5500` | PASS (Matches testbench RESULT_PASS) |
| `0xBADD0001` | Accelerator timeout |
| `0xBADD0002` | Build-info mismatch (firmware/RTL parameter mismatch) |
| `0xBADD0003` | Accelerator perf-counter sanity failure |
| `0xBADD0005` | Accelerator result does not match golden |

## Files

| File | Purpose |
|---|---|
| [`Didactic-SoC/sw/benchmark/benchmark.c`](../../Didactic-SoC/sw/benchmark/benchmark.c) | Benchmark firmware |
| [`Didactic-SoC/sw/benchmark/bench_timer.h`](../../Didactic-SoC/sw/benchmark/bench_timer.h) | `mcycle` CSR helpers |
| [`Didactic-SoC/verification/verilator/verilate_soc_benchmark.py`](../../Didactic-SoC/verification/verilator/verilate_soc_benchmark.py) | Verilator simulation runner |

## How to run

All commands run from **`Didactic-SoC/`**. Each `make` target builds the
firmware, copies the hex, and runs the simulation in one step.

```bash
source ../.venv/bin/activate   # colorama required by the runner
export PATH=$HOME/.local/xPacks/@xpack-dev-tools/riscv-none-elf-gcc/15.2.0-1.1/.content/bin:$PATH
```

### 16×16 benchmark (full hardware utilisation)

Matches the hardware dimensions (M=N=K=16, INT8). One tile covers the entire
GEMM — minimum APB traffic, minimum SW overhead.

```bash
make verilate_benchmark        # default — same as verilate_benchmark_16
make verilate_benchmark_16     # explicit
```

### 8×8 benchmark (partial hardware utilisation)

Sends only 8×8×8 sub-matrices to the hardware (`REG_M/N/K_DIM = 8`). Useful
for comparing speedup as a function of problem size. Skips the build-info
check because the firmware dimensions intentionally differ from the hardware
parameters.

```bash
make verilate_benchmark_8
```

### Run both back-to-back

```bash
make verilate_benchmark_16
make verilate_benchmark_8
```

### Speed up on a roomy host

```bash
VERILATOR_JOBS=4 make verilate_benchmark
```

> Override the toolchain prefix if needed:
> `make verilate_benchmark BENCH_CC_PREFIX=riscv32-unknown-elf`

> Override the toolchain prefix if needed:
> `make verilate_benchmark BENCH_CC_PREFIX=riscv32-unknown-elf`

## Interpreting results

* **`compute`** isolates the systolic-array hardware time (`REG_PERF_CYCLES`, START→DONE).
* **`bus`** is `(APB_writes + APB_reads) × 2` — each APB transaction takes exactly
  2 cycles (PREADY=1 on this design).
* **`SW overhead`** is the remainder: Ibex cycles spent in loop control, INT8
  packing, and C read-back — _not_ stalled on APB or waiting for compute.
* **Speedup** scales super-linearly with matrix size: CPU work grows as O(n³)
  while APB traffic and SW overhead grow as O(n²), so larger matrices yield
  higher speedup.

## Benchmark Results (Verilator, 2026-06-26)

### 16×16 INT8 (one tile, full hardware)

```
compute:      64 cyc   (systolic array, single 16×16×16 tile)
bus:         800 cyc   (134 wr + 266 rd) × 2
SW overhead: 7891 cyc  (loop control, packing, C read-back)
Accel path:  8755 cyc
CPU GEMM:   84780 cyc
Speedup:      9.68×
```

### 8×8 INT8 (one tile, partial hardware)

```
compute:      32 cyc   (systolic array, single 8×8×8 tile)
bus:         216 cyc   (38 wr + 70 rd) × 2
SW overhead: 2456 cyc  (loop control, packing, C read-back)
Accel path:  2704 cyc
CPU GEMM:   10878 cyc
Speedup:      4.02×
```

### Scaling analysis

| Metric | 8×8 | 16×16 | Ratio |
|---|---|---|---|
| Speedup | 4.02× | **9.68×** | 2.41× |
| CPU GEMM | 10878 | 84780 | 7.79× ≈ 8× (O(n³)) |
| Accel path | 2704 | 8755 | 3.24× ≈ 4× (O(n²)) |
| bus | 216 | 800 | 3.70× |
| SW overhead | 2456 | 7891 | 3.21× |

CPU work grows O(n³) while the accelerator path grows O(n²) — this is why
the speedup improves from 4× to 9.7× when doubling the matrix dimension.

> **Remaining bottleneck:** SW overhead dominates the accel path (90% at 8×8,
> 90% at 16×16). The hard floor with APB and no DMA is ~800 cycles for
> 16×16 (bus alone). See [io_bottleneck_solutions.md](io_bottleneck_solutions.md)
> for the roadmap to eliminate it.
