# Matrix A &amp; B Buffer Interface

> The input staging buffers. Software writes Matrix A and Matrix B over APB; on a
> start pulse the buffer streams one A column and one B row per beat into the
> systolic array.

- **Module:** `matrix_buffer_ab`
- **Source:** [`rtl/matrix/matrix_buffer_ab.sv`](../../rtl/matrix/matrix_buffer_ab.sv)
- **Owner:** Cao (#4)

## Overview

`matrix_buffer_ab` stores Matrix A and Matrix B behind a 32-bit APB subordinate
port, then streams one A column and one B row per accepted beat into the
output-stationary systolic array. Physical storage is fixed per build (`M`, `N`,
`K`), while runtime dimensions select a compact tile inside that physical shape.
For runtime dimensions `(m, n, k)`, matrices are written row-major:

- `A[i,k]` at linear offset `i*k + k` for `i < m`
- `B[k,j]` at linear offset `k*n + j` for `j < n`

## Block diagram

```mermaid
flowchart TB
   subgraph APB_IN["APB Interface (Write Path)"]
      direction LR
      paddr(["PADDR[7:0]"])
      psel(["PSEL / PENABLE"])
      pwrite(["PWRITE / PWDATA"])
   end

   subgraph MAB["matrix_buffer_ab"]
      direction TB
      decode_apb{{"APB Decode\n0x00 → A\n0x40 → B\n0x80 → CTRL"}}
      mem_a["Matrix A Storage\nM × K elements\nrow-major\nA[i,k] @ i*K+k"]
      mem_b["Matrix B Storage\nK × N elements\nrow-major\nB[k,j] @ k*N+j"]
      wp_a["Write Ptr A\nauto-increment"]
      wp_b["Write Ptr B\nauto-increment"]
      streamer["K-beat Streamer\nbeat k:\na_col[i] = A[i,k]\nb_row[j] = B[k,j]"]

      decode_apb --> wp_a --> mem_a --> streamer
      decode_apb --> wp_b --> mem_b --> streamer
   end

   subgraph APB_OUT["APB Read Back"]
      prdata_o(["PRDATA\nPREADY / PSLVERR"])
   end

   subgraph STREAM_IN["Streaming Control"]
      mat_start_i(["mat_start\n(1-cycle pulse)"])
      sys_ready_i(["sys_ready"])
   end

   subgraph STREAM_OUT["Streaming Output"]
      mat_valid_o(["mat_valid"])
      acol_o(["a_col\n[M×DATA_W-1:0]"])
      brow_o(["b_row\n[N×DATA_W-1:0]"])
   end

   paddr --> decode_apb
   psel --> decode_apb
   pwrite --> decode_apb
   decode_apb --> prdata_o

   mat_start_i --> streamer
   sys_ready_i --> streamer

   streamer --> mat_valid_o
   streamer --> acol_o
   streamer --> brow_o

   style MAB fill:#c8e6c9,stroke:#388e3c
   style APB_IN fill:#f5f5f5,stroke:#999
   style APB_OUT fill:#f5f5f5,stroke:#999
   style STREAM_IN fill:#fff9c4,stroke:#f9a825
   style STREAM_OUT fill:#fff9c4,stroke:#f9a825
```

## Parameters

| Parameter | Default | Description |
| --- | --- | --- |
| `DATA_W` | `8` | Element bit-width (INT8 baseline). The unpacking logic supports any width that divides 32 evenly (`8`/`16`/`32`). |
| `M` | `16` | Output rows / A rows. |
| `N` | `16` | Output columns / B columns. |
| `K` | `16` | Reduction dimension (stream beats per tile). |
| `APB_AW` | `10` | APB address width. |
| `APB_DW` | `32` | APB data width. |

## Ports

### APB

| Port | Direction | Width | Description |
| --- | --- | --- | --- |
| `clk` | Input | `1` | System clock. |
| `rst_n` | Input | `1` | Active-low synchronous reset. |
| `PADDR` | Input | `APB_AW` | APB address; local decode uses `PADDR[7:0]`. |
| `PSEL` | Input | `1` | APB select. |
| `PENABLE` | Input | `1` | APB enable. |
| `PWRITE` | Input | `1` | APB write enable. |
| `PWDATA` | Input | `APB_DW` | APB write data. |
| `PRDATA` | Output | `APB_DW` | APB read data. |
| `PREADY` | Output | `1` | Always asserted (zero-wait). |
| `PSLVERR` | Output | `1` | Asserted on an A/B write when the target bank write pointer is already at capacity (overflow); deasserted otherwise. |

### Streaming

| Port | Direction | Width | Description |
| --- | --- | --- | --- |
| `mat_start` | Input | `1` | One-cycle pulse that starts a K-beat stream. |
| `mat_valid` | Output | `1` | Stream beat valid. |
| `sys_ready` | Input | `1` | Systolic array ready to consume a beat. |
| `cfg_m_dim` | Input | `APB_DW` | Pending runtime M dimension used to size compact A writes and zero-mask inactive rows. |
| `cfg_n_dim` | Input | `APB_DW` | Pending runtime N dimension used to size compact B writes and zero-mask inactive columns. |
| `cfg_k_dim` | Input | `APB_DW` | Pending runtime K dimension used as the stream length and compact A/B row stride. |
| `a_col` | Output | `M*DATA_W` | Packed A column for the current `k`. |
| `b_row` | Output | `N*DATA_W` | Packed B row for the current `k`. |

## Register map

| Offset | Register | Access | Description |
| --- | --- | --- | --- |
| `0x00` | `MAT_A_DATA` | W/O | Write packed Matrix A elements; write pointer auto-increments. |
| `0x40` | `MAT_B_DATA` | W/O | Write packed Matrix B elements; write pointer auto-increments. |
| `0x80` | `MAT_CTRL` | R/W | Bit `0`: reset write pointers of the currently APB-selected bank (write bit `3`). Read bit `1`: A full (selected bank). Read bit `2`: B full (selected bank). Bit `3` (R/W): APB write bank select (`0`/`1`). Bit `4` (R/W): streaming-read bank select fed to the systolic array. Bit `5` (R/W): reuse-B flag for the selected write bank (when set, `MAT_CTRL[0]` does not clear that bank's B write pointer, allowing B to be reused across ticks while A is refreshed). |

APB access rules:

- **Overflow protection.** Writes beyond the active compact tile (`M_DIM*K_DIM`
   for A, `K_DIM*N_DIM` for B) are safely ignored and assert `PSLVERR` on the
   overrun access.
- **Write-only reads.** Reading `0x00` or `0x40` does not raise a slave error; it returns `0x00000000`.
- **Transient reset.** Writing `1` to `MAT_CTRL[0]` resets the pointers in the same cycle and self-clears, so software need not write `0` back.

## Behavior

### Data packing

The APB bus is 32 bits wide; elements are packed least-significant-lane first.

| `DATA_W` | Elements per write |
| --- | --- |
| `8` | 4 |
| `16` | 2 |
| `32` | 1 |

Example for `DATA_W = 8`: `PWDATA = (el_3 << 24) | (el_2 << 16) | (el_1 << 8) | el_0`.

### Streaming

- Software writes compact A and B tiles in row-major order using the pending
   runtime dimensions from `cfg_*_dim`.
- On `mat_start`, the buffer begins a `K_DIM`-beat stream.
- Beat `k` drives `a_col[i] = A[i,k]` for `i < M_DIM`, otherwise zero, and
   `b_row[j] = B[k,j]` for `j < N_DIM`, otherwise zero.
- A beat is consumed only when `mat_valid && sys_ready`.

### Double buffering (2-bank)

- Storage is physically duplicated into two banks (`mem_a[2][M][K]`,
   `mem_b[2][K][N]`) with independent write-pointer pairs per bank.
- `MAT_CTRL[3]` selects which bank subsequent `MAT_A_DATA`/`MAT_B_DATA` writes
   (and `MAT_CTRL[0]` resets) target; `MAT_CTRL[4]` selects which bank is
   streamed to the systolic array on `mat_start`. Software can therefore stage
   the next tile into the idle bank while the current bank streams/computes.
- `MAT_CTRL[5]` (reuse-B), when set for a bank, makes `MAT_CTRL[0]` skip
   clearing that bank's B write pointer/content, so a B matrix already loaded
   there is reused across multiple A tiles without re-writing it.
- Address indexing into `mem_a`/`mem_b` uses the row/column registers directly
   (no runtime multiply/divide), replacing the earlier linear
   `row*width + col` addressing scheme.

## Notes

- Storage geometry is fixed at build time by `M`, `N`, and `K`; compact runtime
   tiles reuse the same storage from offset zero after `MAT_CTRL[0]` resets the
   write pointers.
