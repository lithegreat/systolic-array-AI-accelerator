# Matrix C Buffer Interface

> The output capture buffer. It catches each C row drained by the systolic array,
> stores the result matrix row-major, and hands it back to software over APB.

- **Module:** `matrix_buffer_c`
- **Source:** [`rtl/matrix/matrix_buffer_c.sv`](../../rtl/matrix/matrix_buffer_c.sv)
- **Owner:** Shang (#5)

## Overview

`matrix_buffer_c` captures the drained outputs of the systolic array and stores
them row-major for software read-back over APB. The array drains a full C row per
beat: each accepted beat carries a row index `c_row_in` and a packed row
`c_row_data_in` (N accumulators, column 0 in the low bits). All N columns of that
row are written to linear addresses `c_row_in * N + j` (`j = 0..N-1`) in one cycle.

## Block diagram

```mermaid
flowchart TB
   subgraph CAPTURE_IN["Capture Interface (from systolic_array)"]
      direction LR
      cv_i(["c_in_valid"])
      cd_i(["c_row_data_in\n[N*ACC_W-1:0]"])
      cr_i(["c_row_in\n[log2(M)-1:0]"])
   end

   subgraph MC["matrix_buffer_c"]
      direction TB
      addr_calc["Address Calc\nc_row_in × N + j"]
      mem_c["Matrix C Storage\nM × N elements\nACC_W bits each\n(row-major)"]
      cap_cnt["Row Counter\n(0 → M = full)"]
      rd_ptr["Read Pointer\nauto-increment on APB read"]
      decode_apb{{"APB Decode\n0x00 → read MAT_C_DATA\n0x80 → MAT_CTRL"}}

      addr_calc --> mem_c
      mem_c --> rd_ptr
      cap_cnt --> decode_apb
      rd_ptr --> decode_apb
   end

   subgraph APB_IN["APB Interface"]
      pa_i(["PADDR[7:0]"])
      ps_i(["PSEL / PENABLE / PWRITE"])
      pw_i(["PWDATA"])
   end

   subgraph APB_OUT["APB Read Back"]
      pr_o(["PRDATA\nPREADY / PSLVERR\ncapture_full via MAT_CTRL[1]"])
   end

   cv_i --> addr_calc
   cd_i --> mem_c
   cr_i --> addr_calc

   pa_i --> decode_apb
   ps_i --> decode_apb
   pw_i --> decode_apb
   decode_apb --> pr_o

   style MC fill:#fff9c4,stroke:#f9a825
   style CAPTURE_IN fill:#bbdefb,stroke:#1976d2
   style APB_IN fill:#f5f5f5,stroke:#999
   style APB_OUT fill:#f5f5f5,stroke:#999
```

## Parameters

| Parameter | Default | Description |
| --- | --- | --- |
| `ACC_W` | `32` | Captured accumulator width. |
| `M` | `16` | Output rows. |
| `N` | `16` | Output columns. |
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
| `PSLVERR` | Output | `1` | Asserted on a data read once the read pointer has passed the captured C window (over-read); deasserted otherwise. |

### Capture

| Port | Direction | Width | Description |
| --- | --- | --- | --- |
| `c_in_valid` | Input | `1` | Incoming C row valid. The row is captured when valid and the buffer is not yet full (fewer than `M` rows captured). |
| `c_row_data_in` | Input | `N*ACC_W` | Packed C row (N accumulators, column 0 in the low bits). |
| `c_row_in` | Input | `$clog2(max(M,2))` | Row index of `c_row_data_in`. |

> The capture path has no `ready`/back-pressure output port: the buffer simply
> accepts the first `M` rows after reset and ignores any further `c_in_valid`
> beats. "Full" is observable to software through `MAT_CTRL` bit `1` (see the
> register map). Internally these are the `c_in_ready = (rows_captured < M)` and
> `capture_full = (rows_captured >= M)` conditions.

## Register map

| Offset | Register | Access | Description |
| --- | --- | --- | --- |
| `0x00` | `MAT_C_DATA` | R/O | Read the next stored C element; read pointer auto-increments. |
| `0x80` | `MAT_CTRL` | R/W | Bit `0`: reset capture count and read pointer. Read bit `1`: `capture_full`. |

## Behavior

- Storage is row-major: `C[i,j]` reads back in the order `(0,0)`, `(0,1)`, …, `(M-1,N-1)`.
- The buffer captures incoming rows while fewer than `M` rows have been stored since the last reset; once full it ignores further `c_in_valid` beats.
- Reading `MAT_C_DATA` returns the low `APB_DW` bits of the stored `ACC_W` value.
- A full C row is written in a single cycle (all N columns at once).

## Notes

- `c_in_ready` and `capture_full` are internal status conditions, not module ports; software observes "full" via `MAT_CTRL` bit `1`.
- In the top-level integration the array's `out_ready` is tied high, so the buffer must be reset (via `MAT_CTRL[0]`) before each new tile to accept all `M` rows.
