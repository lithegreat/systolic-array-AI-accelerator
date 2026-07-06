# Tiled GEMM Performance Comparison & Modification Report (Concise)

---

## 1. CPU Naive GEMM vs. Accelerator Performance

|     Task     | PE Array |   CPU (C)   |  Accel (SW+HW)  |  Speedup   |           Note            |
| :----------: | :------: | :---------: | :-------------: | :--------: | :-----------------------: |
|  **8×8×8**   |  16×16   | 11,070 cyc  | **~1,100 cyc**  | **~10.0×** | Small matrix, single-tile |
| **16×16×16** |  16×16   | 84,780 cyc  |  **8,235 cyc**  | **10.30×** |   Basic single-tile run   |
| **32×32×32** |  16×16   | 766,232 cyc | **~69,490 cyc** | **11.02×** | Partitioned into 8 tiles  |


---

## 2. Double-Buffered (2-Bank) vs. Single-Buffered (Original Baseline)
*(Measured on the 16×16×16 GEMM task)*

|          Metric          | Baseline (1-Bank) | Ours (2-Bank) |        Improvement         |
| :----------------------: | :---------------: | :-----------: | :------------------------: |
|    **Compute Cycles**    |      64 cyc       |    64 cyc     | Identical (PE Array limit) |
|   **APB Transactions**   |      800 cyc      |  **280 cyc**  |   **-65.0% Bus Cycles**    |
|  **- APB Writes (`wr`)**  |      134 wr       |    134 wr     |   Matches packed writes    |
|  **- APB Reads (`rd`)**  |      266 rd       |   **6 rd**    |  **-97.7% Status Reads**   |
|    **Total HW Path**     |      864 cyc      |  **344 cyc**  |     **2.51× Speedup**      |

* **Why the massive improvement?** In the classmate's baseline, the CPU polled the status register 266 times because pointer reset bugs stalled the FSM. Our split-write register sequence resolves the race condition, allowing the FSM to execute with zero stalls. The CPU now only needs to poll 6 times.

---

## 3. FPGA Resource Utilization (Post-Implementation)
*Target: Arty A7 (`xc7a100tcsg324-1`) · Variant: `int8_16x16` · Tool: Vivado 2023.2*

|   Resource    |  Used  | Avail  |  Util%   |                   Note                    |
| :-----------: | :----: | :----: | :------: | :---------------------------------------: |
|  **LUT**  | 52,240 | 63,400 | **82.4%** | 16 PEs overflow from DSP to LUT fabric |
| **Register**  | 37,566 | 126,800 | **29.6%** |         256 PE acc + skew regs          |
| **DSP48E1**  |  240   |  240   | **100%** | 240/256 PEs mapped to hard multipliers |
| **Block RAM** |   36   |  135   | **26.7%** |      Ibex I/D-mem (36 KB SRAM)         |
|  **Slice**   | 15,629 | 15,850 | **98.6%** |    Near-full; placement still passes    |
|   **IOB**    |   32   |  210   | **15.2%** |     JTAG + UART + SPI + GPIO + CLK     |
|   **PLL**    |    1   |    6   | **16.7%** |     100 MHz → 25 MHz system clock      |

> [!NOTE]
> **Timing Met**: WNS = **+0.438 ns**, TNS = 0.000 ns — all setup/hold constraints satisfied.
> The 7 other student subsystem slots were stubbed (tie-off) to free resources for the 16×16 array.

---

## 4. Breakdown of File Modifications

We modified **both the driver code (non-test core logic) and the test case files** to enable correct and optimized operation:

### 4.1 Driver Modifications (Non-Test Content)
* **[sw/accel/accel_tiled_gemm.c](file:///c:/Users/23670/.gemini/antigravity-ide/scratch/project_systolic/group5/Didactic-SoC/sw/accel/accel_tiled_gemm.c)** (Tiled GEMM controller):
  * **Cap Tile Size to 16**: Hardcoded tile limits to `16` to prevent the driver from configuring dimensions beyond the physical $16\times16$ PE array, which hung the hardware FSM.
  * **Split-Write workarounds**: Separated register bank selection from pointer resets to fix the hardware bank-switching race condition.
  * **K-split Accumulation**: Changed output read-back from `=` to `+=` to support matrix accumulation when $K$ is tiled.
  * **SRAM garbage cleanup**: Added explicit `accel_clear_accum()` at the start to clean up uninitialized SRAM power-up state.
* **[sw/accel/accel_driver.c](file:///c:/Users/23670/.gemini/antigravity-ide/scratch/project_systolic/group5/Didactic-SoC/sw/accel/accel_driver.c)** (Hardware register wrapper):
  * **Wait Timeout**: Lowered `wait_done` timeout limit to speed up simulator failure reporting.

### 4.2 Test Case Modifications (Test Content)
* **[sw/benchmark/benchmark.c](file:///c:/Users/23670/.gemini/antigravity-ide/scratch/project_systolic/group5/Didactic-SoC/sw/benchmark/benchmark.c)** (Benchmark program):
  * Added `#ifndef BENCH_SKIP_CPU_GEMM` compile flags to speed up development runs.
  * Integrated cycle timing via `mcycle` CSR to directly measure CPU execution.
* **[sw/benchmark/bench_timer.h](file:///c:/Users/23670/.gemini/antigravity-ide/scratch/project_systolic/group5/Didactic-SoC/sw/benchmark/bench_timer.h)** (Ibex timing helper):
  * Added assembly `.option push/pop` to enable `zicsr` architecture options, resolving compiler errors on the server.
