# Module Interface Specification: Matrix A & B Buffers

## 1. Overview
`matrix_buffer_ab` stores Matrix A and Matrix B through a 32-bit APB subordinate interface and then streams one A column and one B row per accepted beat into the output-stationary systolic array.

The implementation is fixed-geometry per build (`M`, `N`, `K` parameters) and stores matrices in row-major order:

- `A[i,k]` at linear offset `i*K + k`
- `B[k,j]` at linear offset `k*N + j`

## 1.1 Block Diagram

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
      mat_done_o(["mat_done\n(1-cycle pulse)"])
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
   streamer --> mat_done_o
   streamer --> acol_o
   streamer --> brow_o

   style MAB fill:#c8e6c9,stroke:#388e3c
   style APB_IN fill:#f5f5f5,stroke:#999
   style APB_OUT fill:#f5f5f5,stroke:#999
   style STREAM_IN fill:#fff9c4,stroke:#f9a825
   style STREAM_OUT fill:#fff9c4,stroke:#f9a825
```

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
| `PREADY` | Output | `1` | Always asserted (zero-wait) |
| `PSLVERR` | Output | `1` | Asserted on an A/B write when the target bank write pointer is already at capacity (overflow); deasserted otherwise |

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

> **Notes on APB Access:**
> - **Overflow Protection:** Writes beyond the buffer capacity (`M*K` for A, `K*N` for B) are safely ignored by hardware.
> - **W/O Read Behavior:** Reading `0x00` or `0x40` will not cause a slave error but will safely return `0x00000000`.
> - **Transient Reset:** Writing `1` to `MAT_CTRL[0]` triggers a reset in the same cycle. It self-clears, so software does not need to write `0` back.

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