# Module Interface Specification: Matrix C Buffer

## 1. Overview

`matrix_buffer_c` captures the drained outputs of the systolic array and stores them in row-major order for software read-back over APB.

Each accepted element is identified by `(c_row_in, c_col_in)` and written to linear address `c_row_in * N + c_col_in`.

## 2. Parameters

| Parameter Name | Default Value | Description |
| :--- | :--- | :--- |
| `ACC_W` | `32` | Captured accumulator width |
| `M` | `4` | Number of output rows |
| `N` | `4` | Number of output columns |
| `APB_AW` | `10` | APB address width |
| `APB_DW` | `32` | APB data width |

## 3. Port List

### 3.1 APB Interface

| Port | Direction | Width | Description |
| :--- | :--- | :--- | :--- |
| `clk` | Input | `1` | System clock |
| `rst_n` | Input | `1` | Active-low synchronous reset |
| `PADDR` | Input | `APB_AW` | APB address; local decode uses `PADDR[7:0]` |
| `PSEL` | Input | `1` | APB select |
| `PENABLE` | Input | `1` | APB enable |
| `PWRITE` | Input | `1` | APB write enable |
| `PWDATA` | Input | `APB_DW` | APB write data |
| `PRDATA` | Output | `APB_DW` | APB read data |
| `PREADY` | Output | `1` | Always asserted in v1 |
| `PSLVERR` | Output | `1` | Always deasserted in v1 |

### 3.2 Capture Interface

| Port | Direction | Width | Description |
| :--- | :--- | :--- | :--- |
| `c_in_valid` | Input | `1` | Incoming C element valid |
| `c_in_ready` | Output | `1` | Capture ready; deasserts once the buffer is full |
| `c_data_in` | Input | `ACC_W` | Captured C element value |
| `c_row_in` | Input | `$clog2(max(M,2))` | Row index of `c_data_in` |
| `c_col_in` | Input | `$clog2(max(N,2))` | Column index of `c_data_in` |
| `capture_full` | Output | `1` | High when `M*N` elements have been accepted since last reset |

## 4. Register Map

| Offset | Name | Access | Description |
| :--- | :--- | :--- | :--- |
| `0x00` | `MAT_C_DATA` | R/O | Read the next stored C element; read pointer auto-increments |
| `0x80` | `MAT_CTRL` | R/W | Bit `0`: reset capture count and read pointer. Read bit `1`: `capture_full` |

## 5. Behavior

- Storage order is row-major: `C[i,j]` is read back in the order `(0,0)`, `(0,1)`, ..., `(M-1,N-1)`.
- `c_in_ready` is high until `M*N` elements have been accepted.
- Reading `MAT_C_DATA` returns the low `APB_DW` bits of the stored `ACC_W` value.
- Writing `1` to `MAT_CTRL[0]` resets both the read pointer and the full/capture count state.