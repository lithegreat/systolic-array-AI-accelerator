# Module Interface Specification: Matrix A & B Buffers

## 1. Overview
`matrix_buffer_ab` stores Matrix A and Matrix B through a 32-bit APB subordinate interface and then streams one A column and one B row per accepted beat into the output-stationary systolic array.

The implementation is fixed-geometry per build (`M`, `N`, `K` parameters) and stores matrices in row-major order:

- `A[i,k]` at linear offset `i*K + k`
- `B[k,j]` at linear offset `k*N + j`

## 2. Parameters

| Parameter Name | Default Value | Description |
| :--- | :--- | :--- |
| `DATA_W` | `16` | Element bit width. The implemented unpacking logic supports widths that divide 32 evenly. Current verification uses `16`. |
| `M` | `4` | Number of output rows / A rows. |
| `N` | `4` | Number of output columns / B columns. |
| `K` | `4` | Reduction dimension; number of stream beats per tile. |
| `APB_AW` | `10` | APB address width. |
| `APB_DW` | `32` | APB data width. |

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

### 3.2 Streaming Interface

| Port | Direction | Width | Description |
| :--- | :--- | :--- | :--- |
| `mat_start` | Input | `1` | One-cycle pulse that starts a K-beat stream |
| `mat_done` | Output | `1` | One-cycle pulse after the last beat is accepted |
| `mat_valid` | Output | `1` | Stream beat valid |
| `sys_ready` | Input | `1` | Systolic array ready |
| `a_col` | Output | `M*DATA_W` | Packed A column vector for current `k` |
| `b_row` | Output | `N*DATA_W` | Packed B row vector for current `k` |

## 4. Register Map

| Offset | Name | Access | Description |
| :--- | :--- | :--- | :--- |
| `0x00` | `MAT_A_DATA` | W/O | Write packed Matrix A elements; write pointer auto-increments |
| `0x40` | `MAT_B_DATA` | W/O | Write packed Matrix B elements; write pointer auto-increments |
| `0x80` | `MAT_CTRL` | R/W | Bit `0`: reset both write pointers. Read bit `1`: A full. Read bit `2`: B full |

## 5. Data Packing Rules

The APB bus is 32 bits wide. Elements are packed least-significant-lane first.

- If `DATA_W = 8`: 4 elements per write.
- If `DATA_W = 16`: 2 elements per write.
- If `DATA_W = 32`: 1 element per write.

Example for `DATA_W = 16`:

`PWDATA = (el_1 << 16) | el_0`

## 6. Streaming Behavior

- Software writes A and B in row-major order.
- On `mat_start`, the buffer begins a `K`-beat stream.
- Beat `k` drives:
  - `a_col[i] = A[i,k]` for `i = 0 .. M-1`
  - `b_row[j] = B[k,j]` for `j = 0 .. N-1`
- A beat is consumed only when `mat_valid && sys_ready`.
- After beat `K-1` is accepted, `mat_done` pulses for one cycle.