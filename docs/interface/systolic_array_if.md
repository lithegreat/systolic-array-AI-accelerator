# Systolic Array Interface

> The compute core: an M×N grid of MAC processing elements that consumes streamed
> A columns and B rows, accumulates each `C[i,j]` in place (output-stationary), and
> drains the result one full row per beat.

- **Module:** `systolic_array`
- **Source:** [`rtl/array/systolic_array.sv`](../../rtl/array/systolic_array.sv)
- **Owner:** Zhong (#3)

## Overview

`systolic_array` instantiates an M×N grid of [`mac_pe`](mac_if.md) cells. Matrix A
and Matrix B are streamed in lockstep, one `(a_col, b_row)` pair per accepted beat.
Internal skew chains delay row `i` by `i` cycles and column `j` by `j` cycles so the
operands meet at the right PE at the right time. Runtime dimensions select the
active sub-tile; inactive physical rows/columns are masked to zero. Each active PE
accumulates over `K_DIM` valid beats, then the array drains one active C row per
beat, top row first.

## Block diagram

```mermaid
flowchart LR
   subgraph INPUTS["Inputs"]
      direction TB
      clk_i(["clk"])
      rst_i(["rst_n"])
      start_i(["start"])
      inv_i(["in_valid"])
      acol_i(["a_col\n[M×DATA_W-1:0]"])
      brow_i(["b_row\n[N×DATA_W-1:0]"])
      ordy_i(["out_ready"])
   end

   subgraph SA["systolic_array  (M × N PEs)"]
      direction TB
      skew["Input Skew\nShift Chains\n(row i delayed i cycles\ncol j delayed j cycles)"]
      grid["PE Grid\nM × N mac_pe\n(output-stationary\naccumulators)"]
      drain["Result Drain\none full C row per beat\nM beats"]
      skew --> grid --> drain
   end

   subgraph OUTPUTS["Outputs"]
      direction TB
      irdy_o(["in_ready"])
      ov_o(["out_valid"])
      done_o(["done"])
      cdata_o(["c_row_data\n[N×ACC_W-1:0]"])
      crow_o(["c_row\n[log2(M)-1:0]"])
   end

   start_i --> SA
   inv_i -- "valid beat" --> skew
   acol_i --> skew
   brow_i --> skew
   ordy_i --> drain
   clk_i --> SA
   rst_i --> SA

   skew -- "in_ready" --> irdy_o
   drain -- "out_valid" --> ov_o
   drain -- "done\n(1-cycle pulse)" --> done_o
   drain --> cdata_o
   drain --> crow_o

   style SA fill:#bbdefb,stroke:#1976d2
   style INPUTS fill:#f5f5f5,stroke:#999
   style OUTPUTS fill:#f5f5f5,stroke:#999
```

## Parameters

| Parameter | Default | Description |
| --- | --- | --- |
| `DATA_W` | `8` | Signed data/weight bit-width (INT8 baseline; configurable to `8`/`16`/`32`). |
| `ACC_W` | `32` | Accumulator / output width. |
| `M` | `16` | Output rows (A rows). |
| `N` | `16` | Output columns (B columns). |
| `K` | `16` | Reduction dimension (number of stream beats per tile). |

## Ports

### Clock & reset

| Port | Direction | Width | Description |
| --- | --- | --- | --- |
| `clk` | Input | `1` | System clock. |
| `rst_n` | Input | `1` | Active-low synchronous reset. |

### Control & handshake

| Port | Direction | Width | Description |
| --- | --- | --- | --- |
| `start` | Input | `1` | Pulse that launches one M×N output tile. Sampled in `IDLE`. |
| `cfg_m_dim` | Input | `32` | Runtime active row count, latched by the control unit on start. |
| `cfg_n_dim` | Input | `32` | Runtime active column count, latched by the control unit on start. |
| `cfg_k_dim` | Input | `32` | Runtime reduction length, latched by the control unit on start. |
| `in_valid` | Input | `1` | Input beat valid this cycle. |
| `in_ready` | Output | `1` | Array can accept an input beat this cycle. |
| `out_valid` | Output | `1` | Output row valid this cycle. |
| `out_ready` | Input | `1` | Downstream can accept the output row this cycle. |
| `done` | Output | `1` | One-cycle pulse after the last C row is accepted. |

### Data

| Port | Direction | Width | Description |
| --- | --- | --- | --- |
| `a_col` | Input | `M*DATA_W` | Packed signed A column for the current `k`. |
| `b_row` | Input | `N*DATA_W` | Packed signed B row for the current `k`. |
| `c_row_data` | Output | `N*ACC_W` | Packed signed C row (column 0 in the low bits, column `N-1` in the high bits). |
| `c_row` | Output | `$clog2(M)` | Row index of `c_row_data`. |

## Behavior

### Output-stationary dataflow

- Each PE owns one `C[i,j]` accumulator.
- One input beat supplies the whole A column `A[:,k]` and the whole B row `B[k,:]`.
- Skew shift chains delay row `i` by `i` cycles and column `j` by `j` cycles.
- Each active PE accumulates over exactly `K_DIM` valid windows, then the array
   drains `M_DIM` result rows, top to bottom. Columns `j >= N_DIM` are zero in the
   packed row output and ignored by `matrix_buffer_c`.
- The compute phase lasts `M_DIM + N_DIM + K_DIM − 2` internal pipeline cycles before drain starts.

### Handshake & timing

- A beat is consumed only when `in_valid && in_ready`; A and B are consumed together.
- `in_valid` / `out_valid` may stay high across cycles; if the matching `*_ready` is low, the data is stalled and must be held stable.
- One active output row is produced per ready cycle after the runtime pipeline latency.
- `done` asserts for one cycle after the last C row is accepted.

## Notes

- C drains in row-major order.
- Drain index decoding works for any positive `M` and `N`; current named build
   variants use square tiles (`M=N=K`) for the standalone runner and FPGA flow.
- Assumes the A/B buffer provides one aligned `(a_col, b_row)` pair per accepted beat.
