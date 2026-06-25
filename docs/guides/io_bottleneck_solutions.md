# I/O Bottleneck Solutions: Comparative Analysis

> Compares architectural approaches to address the APB data-transfer bottleneck
> identified in the GEMM benchmark. The bottleneck accounts for **99.95 %** of
> the accelerator path's wall-clock time: the 16×16 systolic array completes a
> GEMM tile in 32 cycles, yet the end-to-end system speedup is only **1.92×**
> because every matrix element must be pushed or pulled one APB word at a time
> by the CPU.

Last reviewed: 2026-06-25

## Background

### Current data-transfer flow

Each tile execution (`accel_run_tile`) follows these sequential, CPU-blocking steps:

```
1. CPU resets buffer write-pointers     (2 APB writes)
2. CPU writes M×K elements of A        (M×K/EPW APB writes, EPW=4 for INT8)
3. CPU writes K×N elements of B        (K×N/EPW APB writes)
4. CPU writes CTRL=START               (1 APB write)
5. CPU busy-polls REG_STATUS           (N APB reads, CPU fully blocked)
6. CPU reads M×N elements of C         (M×N APB reads, 1 int32 per read, no packing)
7. CPU clears STATUS.done              (1 APB write)
```

For a single 8×8 INT8 tile the approximate cycle cost (APB 2-cycle overhead +
~6-cycle CPU loop body per transaction):

| Phase | Transactions | CPU cycles |
|---|---|---|
| Write A | 16 APB writes | ~128 |
| Write B | 16 APB writes | ~128 |
| Hardware compute | — | 32 |
| Busy-poll | ~50 reads | ~100 |
| Read C | 64 APB reads | ~512 |
| **Total / tile** | | **~900** |

The full 16×16 GEMM uses eight 8×8 tiles, giving roughly **7 200 CPU cycles** in
the data-transfer phases versus **256 cycles** of actual systolic-array compute.

### Root causes

1. **No burst capability on APB** — every transaction is a standalone 2-phase
   handshake; there is no way to amortise the address phase over multiple beats.
2. **CPU executes every transfer in software** — each store/load instruction
   carries ~6 instruction-pipeline cycles of loop overhead on top of the 2-cycle
   APB protocol overhead.
3. **Matrix-C read-back is unpacked** — writes pack 4 INT8 per 32-bit word, but
   C elements are full int32 accumulators, so every read is a single 32-bit word
   with no packing benefit.
4. **Blocking wait** — CPU busy-polls `REG_STATUS` instead of sleeping on an
   interrupt, wasting cycles and preventing any concurrent work.

---

## Solution Comparison

### Solution 1 — IRQ-driven completion (polling → interrupt)

**What changes:** Enable `INT_EN` in the control unit; CPU suspends after writing
`CTRL=START` and resumes on `irq_4`. The APB hardware already supports this
(`INT_EN` / `INT_STAT` registers exist); only the firmware driver changes.

**What it fixes:** Root cause 4 (blocking wait).

**What it does NOT fix:** Transfer cycle count; CPU loop overhead.

**Implementation scope:**
- `accel_driver.c` — replace `wait_done()` polling loop with WFI + ISR.
- No RTL changes.

**Cycle savings (8×8 tile):**
- Removes ~100 idle-poll cycles/tile.
- CPU is freed for other work during the 32-cycle compute window.

**Complexity:** Minimal — a few lines of firmware.

**Verdict:** Easy win; should always be applied, but does not address the
dominant transfer overhead.

---

### Solution 2 — Software double-buffering (tile pipelining)

**What changes:** Maintain two SRAM regions for A/B/C. While the accelerator
processes tile N, the CPU pre-loads tile N+1's data into the second region.
Requires the IRQ (Solution 1) so the CPU is not blocked.

**What it fixes:** Root causes 2 and 4 — hides transfer latency behind compute.

**What it does NOT fix:** Per-transfer APB overhead; total transaction count.

**Implementation scope:**
- Firmware only (`accel_tiled_gemm.c`, double-buffer state machine).
- No RTL changes.

**Cycle savings (full 16×16, 8 tiles):**

```
Without pipelining: 8 × (write_A + write_B + compute + read_C)
                  ≈ 8 × 900 = 7 200 cycles

With pipelining (CPU write overlaps DMA/compute of previous tile):
  Bottleneck = max(CPU_write_time, compute+read_time)
             = max(~256, ~160) = ~256 cycles/tile
  Total      ≈ 8 × 256 = 2 048 cycles   (~3.5× improvement)
```

**Complexity:** Medium — requires careful ping-pong buffer management in firmware.

**Verdict:** Good return for zero hardware cost; effective when matrix is tiled
into many tiles.

---

### Solution 3 — Internal scratchpad SRAM + local DMA (Plan A)

**What changes:** Add a dual-port SRAM block *inside* `tum_ss`. Port A is an APB
slave (CPU writes A/B tiles here at random addresses). Port B is an internal read
port wired to a simple DMA state machine. On `CTRL=START`, the local DMA streams
data from the scratchpad into `matrix_buffer_ab` at one word per clock (no CPU
involvement), and after compute it drains `matrix_buffer_c` back into the
scratchpad. CPU reads C from the scratchpad via APB.

```
tum_ss (no SoC interface change):
┌──────────────────────────────────────────────────┐
│ APB slave (existing)                             │
│   ├─→ control_unit    (registers, FSM, IRQ)      │
│   ├─→ scratchpad_sram (new, random-access A/B/C) │
│   └─→ accelerator_top (unchanged compute path)  │
│                                                  │
│ local_dma (new, ~100 lines RTL):                 │
│   scratchpad port-B ──→ matrix_buffer_ab APB FIFO│
│   matrix_buffer_c   ──→ scratchpad port-B        │
└──────────────────────────────────────────────────┘
```

**What it fixes:** Root causes 2, 3 (partially), and 4.
- The DMA writes to `matrix_buffer_ab` at **1 word / cycle** (internal path, no
  CPU loop overhead). For 32 words: 32 cycles vs. ~128 cycles (CPU).
- The DMA drains `matrix_buffer_c` at 1 word / cycle.
- CPU is fully free during DMA + compute. Combined with Solution 2 (double
  buffering on the scratchpad), CPU SRAM writes can overlap DMA+compute.

**What it does NOT fix:** The CPU→scratchpad write path is still N APB writes
(same transaction count). Only the scratchpad→buffer DMA path is accelerated.

**Implementation scope:**
- New RTL: `rtl/matrix/scratchpad_sram.sv`, `rtl/control/local_dma.sv`
- Modified RTL: `rtl/top/accelerator_top.sv` (instantiate, connect)
- New firmware registers in `accel_regs.h`; updated driver
- No SoC-level changes

**Cycle savings (8×8 tile, with double-buffering):**

| Phase | Current | With local DMA |
|---|---|---|
| CPU write A+B to buffer/scratchpad | ~256 cycles | ~256 cycles (unchanged) |
| DMA → matrix_buffer (internal) | 0 (CPU did it) | **32 cycles** (parallel with CPU) |
| Hardware compute | 32 cycles | 32 cycles |
| DMA drain C (internal) | 0 (CPU read via APB) | **64 cycles** (parallel) |
| CPU read C from scratchpad | ~512 cycles | **~256 cycles** (overlapped) |

With pipelining: bottleneck ≈ **CPU write time (~256 cycles/tile)**.
Theoretical end-to-end for 8 tiles: **~2 000 cycles** (~3.6× over current).

**Complexity:** Medium — new RTL modules required, but entirely within `rtl/`; no
SoC integration risk.

**Verdict:** Best balance of effort and gain for a self-contained improvement.

---

### Solution 4 — SoC-level DMA controller (Plan B)

**What changes:** Add a general-purpose DMA IP connected as both an OBI slave
(CPU configures channels) and an OBI master (DMA reads SoC SRAM). The DMA is
programmed with source address (SoC SRAM where matrix data lives), destination
address (accelerator APB region), and transfer count. CPU issues one DMA
descriptor, then is completely free.

```
CPU ──OBI master──→ OBI xbar ──→ DMA_ctrl (slave, config)
                       ↑
               DMA_ctrl (master) ──→ OBI xbar ──→ SoC SRAM (read A/B)
               DMA_ctrl (master) ──→ APB bridge ──→ tum_ss (write to accel)
```

**What it fixes:** All four root causes.
- Zero CPU loop overhead for data transfer.
- APB burst writes from DMA are still 2 cycles each, but no CPU instruction cost.
- C read-back similarly handled by DMA.
- CPU only writes ~4 DMA descriptor registers.

**What it does NOT fix:** APB still has no burst mode; 2 cycles/word overhead
remains on the DMA→accelerator path. True elimination requires AXI + DMA.

**Implementation scope:**
- New RTL: DMA controller IP
- Modified: `sysctrl_obi_xbar.sv` (new master port), `Didactic.v` (SoC top-level)
- All subsystem teams affected if xbar timing changes

**Cycle savings:** Near-theoretical maximum within APB constraints.
CPU overhead reduced to ~20 cycles (DMA setup). DMA transfer at 2 cycles/word:
128 words × 2 = 256 cycles for A+B write, 64 cycles for C read. Total DMA time
per tile: ~350 cycles. With CPU + DMA pipelining: **~350 cycles/tile**.

**Complexity:** High — SoC-level integration; risk to other student subsystems.

**Verdict:** Optimal performance, but high integration risk. Recommended as a
long-term roadmap item, not a near-term sprint.

---

### Solution 5 — RISC-V custom co-processor instruction (X-Interface)

**What changes:** Attach a custom co-processor to Ibex via the CV-X-IF extension
interface. A single custom instruction (`custom.gemm x1, x2` with base
addresses in `x1`/`x2`) causes the co-processor hardware to self-fetch A and B
from SoC SRAM, drive the accelerator, and write C back — all without further CPU
involvement.

**What it fixes:** All root causes; from the programmer's perspective a GEMM is
a single instruction.

**Implementation scope:**
- Ibex X-IF co-processor module (new RTL)
- OBI master from co-processor into SoC xbar
- Ibex wrapper modifications
- New ISA extension toolchain support

**Complexity:** Very high — requires ISA, toolchain, and SoC-level changes.

**Verdict:** Architecturally elegant; impractical within the current project scope.

---

## Summary and Recommendation

| # | Solution | SoC changes | New RTL | Speedup (estimated) | Effort |
|---|---|---|---|---|---|
| 1 | IRQ-driven completion | None | None | ~1.1× | Very low |
| 2 | SW double-buffering | None | None | ~3.5× | Low |
| 3 | Internal scratchpad + local DMA | **None** | ~200 lines | **~3.6×** | Medium |
| 4 | SoC-level DMA | Yes (xbar) | DMA IP + xbar | ~5–8× | High |
| 5 | Custom RISC-V instruction | Yes (xbar) | Co-proc + xbar | ~10×+ | Very high |

### Recommended roadmap

**Short term (no RTL changes):**
Apply Solutions 1 and 2 together. Zero hardware risk, firmware-only, and already
delivers ~3.5× improvement over the current baseline.

**Medium term (contained RTL work):**
Implement Solution 3. All changes stay inside `rtl/`; the SoC interface is
untouched. Combined with Solutions 1 and 2 this is expected to approach the
theoretical maximum achievable without a SoC-level master port.

**Long term (SoC roadmap):**
Consider Solution 4 as a planned SoC revision once the current tapeout milestone
is met. It removes the remaining APB-loop overhead on the DMA path and unlocks
larger matrix sizes without diminishing returns.

Solution 5 is research-grade and outside the current project scope.

---

## Residual bottleneck after all solutions

Even with Solution 4 (SoC DMA), the APB bus imposes a hard floor of **2
cycles per 32-bit word** on the accelerator data path. For a 16×16 INT8 GEMM:

- Write A+B: (256+256)/4 = 128 words × 2 = **256 cycles**
- Read C: 256 words × 2 = **512 cycles**
- Compute: **32 cycles**
- **Minimum possible with APB: ~800 cycles** (vs. 32 compute cycles)

Eliminating this floor requires replacing the APB data path with AXI4-Stream or
a wider internal bus — a fundamental interface change that is out of scope for
the current accelerator architecture.
