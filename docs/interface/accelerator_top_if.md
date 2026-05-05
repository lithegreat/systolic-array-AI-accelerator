# Accelerator Top-Level Interface

## 1. Overview

`accelerator_top` is the APB-visible subsystem wrapper that integrates the control unit, Matrix A/B buffer, systolic array, and Matrix C buffer behind a single subordinate port.

It does not implement matrix storage or compute itself. Instead, it routes software access to the correct internal block and wires the compute path as:

`control_unit` -> `matrix_buffer_ab` -> `systolic_array` -> `matrix_buffer_c`

## 2. Block Diagrams

### 2.1 APB Routing and Address Decode

```mermaid
flowchart LR
   external["<b>External APB Ports</b>
PADDR, PSEL, PENABLE
PWRITE, PWDATA"]
   
   decode{{"|PADDR[9:8]|
Decode"}}
   
   ab_apb["<b>matrix_buffer_ab</b>
PADDR[7:0], PSEL, PENABLE
PWRITE, PWDATA, PRDATA
PREADY, PSLVERR"]
   ctrl_apb["<b>control_unit</b>
PADDR[7:0], PSEL, PENABLE
PWRITE, PWDATA, PRDATA
PREADY, PSLVERR"]
   c_apb["<b>matrix_buffer_c</b>
PADDR[7:0], PSEL, PENABLE
PWRITE, PWDATA, PRDATA
PREADY, PSLVERR"]
   
   mux["<b>Mux</b>
PRDATA
PREADY
PSLVERR"]
   
   external --> decode
   
   decode -- "00" --> ab_apb
   decode -- "01" --> ctrl_apb
   decode -- "10" --> c_apb
   
   ab_apb --> mux
   ctrl_apb --> mux
   c_apb --> mux
   
   mux --> external
```

### 2.2 Control and Interrupt Flow

```mermaid
flowchart TB
   soc["<b>SoC</b>"]
   
   irq_en["irq_en_4"]
   ss_ctrl["ss_ctrl_4"]
   
   ctrl["<b>control_unit</b>
array_start, array_clear
array_done
cfg_m/n/k"]
   
   array["<b>systolic_array</b>
start, done"]
   
   ab["<b>matrix_buffer_ab</b>
mat_start"]
   
   irq["irq_4"]
   
   soc --> irq_en
   soc --> ss_ctrl
   
   irq_en --> ctrl
   ss_ctrl --> ctrl
   
   ctrl -- array_start --> ab
   ctrl -- array_start --> array
   
   array -- array_done --> ctrl
   
   ctrl --> irq
   irq --> soc
   
   style ctrl fill:#e1f5ff
   style array fill:#f3e5f5
```

### 2.3 Data Path (A/B Input to C Output)

```mermaid
flowchart LR
   ab["<b>matrix_buffer_ab</b>
a_col, b_row
mat_valid, sys_ready"]
   
   array["<b>systolic_array</b>
in_valid, in_ready
a_col, b_row
out_valid
c_data, c_row, c_col"]
   
   c["<b>matrix_buffer_c</b>
c_in_valid
c_data_in, c_row_in, c_col_in"]
   
   ab -- "mat_valid" --> array
   ab -- "a_col, b_row" --> array
   array -- "in_ready" --> ab
   
   array -- "out_valid" --> c
   array -- "c_data/row/col" --> c
   
   style ab fill:#c8e6c9
   style array fill:#bbdefb
   style c fill:#fff9c4
```

### 2.4 Clock and Reset Distribution

```mermaid
flowchart TB
   clk["<b>clk_in</b>"]
   rst["<b>reset_int</b>"]
   
   ctrl["control_unit"]
   ab["matrix_buffer_ab"]
   array["systolic_array"]
   c["matrix_buffer_c"]
   
   clk --> ctrl
   clk --> ab
   clk --> array
   clk --> c
   
   rst --> ctrl
   rst --> ab
   rst --> array
   rst --> c
   
   style clk fill:#fff59d
   style rst fill:#ffccbc
```

## 3. Parameters

| Parameter | Type | Default | Description |
| --- | --- | --- | --- |
| `DATA_W` | `int unsigned` | `16` | Bit-width for Matrix A and Matrix B data elements. |
| `ACC_W` | `int unsigned` | `32` | Bit-width for Matrix C accumulation results. |
| `M` | `int unsigned` | `4` | Number of rows in the systolic array and buffers. |
| `N` | `int unsigned` | `4` | Number of columns in the systolic array and buffers. |
| `K` | `int unsigned` | `4` | Number of elements in the reduction dimension. |
| `APB_AW` | `int unsigned` | `10` | Address width for the APB subordinate interface. |
| `APB_DW` | `int unsigned` | `32` | Data width for the APB subordinate interface. |

## 4. Port-Level View

### 4.1 External Ports

| Port Name | Direction | Width | Connected block | Detailed behavior |
| --- | --- | --- | --- | --- |
| `clk_in` | Input | `1` | All internal blocks | Shared system clock for the control unit, both matrix buffers, and the systolic array. The top wrapper passes this clock straight through without gating. |
| `reset_int` | Input | `1` | All internal blocks | Active-high top-level reset from the SoC. The wrapper converts it to internal active-low `rst_n` and uses it to reset the submodules. |
| `PADDR` | Input | `APB_AW` | APB decode, all sub-blocks | APB address bus. `accelerator_top` uses `PADDR[9:8]` to choose the target sub-block, and each selected block performs its own local `PADDR[7:0]` decode. |
| `PSEL` | Input | `1` | APB decode, all sub-blocks | APB select for the top wrapper. It must be asserted for the transaction to reach any sub-block. |
| `PENABLE` | Input | `1` | APB sub-blocks | APB enable phase of the transfer. It is forwarded unchanged to the selected sub-block. |
| `PWRITE` | Input | `1` | APB sub-blocks | APB direction qualifier. `1` means write, `0` means read. Forwarded to the selected sub-block. |
| `PWDATA` | Input | `APB_DW` | APB sub-blocks | APB write data bus. Used when software writes control registers or matrix data registers. |
| `PRDATA` | Output | `APB_DW` | APB mux output | Read data returned from the selected sub-block. The top wrapper multiplexes `prdata_ab`, `prdata_ctrl`, and `prdata_c` based on `PADDR[9:8]`. |
| `PREADY` | Output | `1` | APB mux output | APB ready response. It is asserted when the selected sub-block is ready, or when `PSEL` is low. |
| `PSLVERR` | Output | `1` | APB mux output | APB error response. In v1 it is driven by the selected sub-block and is normally deasserted. |
| `irq_en_4` | Input | `1` | `control_unit` | SoC-level interrupt gate. The control unit combines this with its internal interrupt state to generate `irq_4`. |
| `ss_ctrl_4` | Input | `8` | `control_unit` | Reserved subsystem control word from the SoC. It is carried through the top wrapper to the control unit for future compatibility. |
| `irq_4` | Output | `1` | SoC interrupt output | Interrupt request sent back to the SoC. In the current implementation it reflects the control unit's done interrupt condition. |

Port-by-port summary:

- `clk_in` and `reset_int` are the only global structural signals; everything else is either APB control or interrupt plumbing.
- `PADDR`, `PSEL`, `PENABLE`, `PWRITE`, and `PWDATA` are the write/read control path into the chosen sub-block.
- `PRDATA`, `PREADY`, and `PSLVERR` are the return path from the selected sub-block through the top-level APB mux.
- `irq_en_4`, `ss_ctrl_4`, and `irq_4` are the SoC-facing sideband and interrupt signals that only touch the control unit.

### 4.2 Internal Interconnect

| Signal | Source | Sink | Description |
| --- | --- | --- | --- |
| `array_start` | `control_unit` | `matrix_buffer_ab`, `systolic_array` | One-cycle launch pulse for a tile |
| `array_clear` | `control_unit` | internal / compatibility path | Clear pulse aligned with `array_start` |
| `array_done` | `systolic_array` | `control_unit` | Completion pulse from the array |
| `mat_valid` | `matrix_buffer_ab` | `systolic_array` | Valid beat for `a_col` and `b_row` |
| `sys_ready` | `systolic_array` | `matrix_buffer_ab` | Consume-ready handshake for streamed inputs |
| `a_col` | `matrix_buffer_ab` | `systolic_array` | Packed A column vector |
| `b_row` | `matrix_buffer_ab` | `systolic_array` | Packed B row vector |
| `out_valid` | `systolic_array` | `matrix_buffer_c` | Valid C output element |
| `c_data`, `c_row`, `c_col` | `systolic_array` | `matrix_buffer_c` | Captured output element and indices |
| `cfg_m`, `cfg_n`, `cfg_k` | `control_unit` | unused in top | Configuration dimensions exported from `control_unit` (unused to avoid lint warnings) |
| `soft_reset_unused` | `control_unit` | unused in top | Soft reset exported from `control_unit` (unused) |
| `mat_done` | `matrix_buffer_ab` | unused in top | Done pulse from `matrix_buffer_ab` (unused) |
| `cap_full` | `matrix_buffer_c` | unused in top | Capture full flag from `matrix_buffer_c` (unused) |
| `ma_addr`, `mb_addr`, `mc_addr`, `ma_ren`, `mb_ren`, `mc_wen` | `control_unit` | unused in top | Legacy matrix memory interface signals (unused) |

## 5. Address Decode

`accelerator_top` decodes the top two APB address bits:

| PADDR[9:8] | Target block | Function |
| --- | --- | --- |
| `2'b00` | `matrix_buffer_ab` | Software writes Matrix A/B tiles and reads buffer status |
| `2'b01` | `control_unit` | Control registers, status, and interrupt state |
| `2'b10` | `matrix_buffer_c` | Software reads back captured Matrix C results |

Each sub-block keeps its own local `PADDR[7:0]` decode.

## 6. Compute Flow

1. Software programs Matrix A and Matrix B through `matrix_buffer_ab`.
2. Software writes the control register in `control_unit` to request a start.
3. `control_unit` asserts `array_start` and `array_clear`.
4. `matrix_buffer_ab` streams one `a_col` and one `b_row` per accepted beat.
5. `systolic_array` consumes the streamed inputs and produces `c_data` with row/column indices.
6. `matrix_buffer_c` captures the outputs in row-major order.
7. `systolic_array` asserts `array_done`, and `control_unit` raises `done` state and `irq_4` when enabled.

## 7. Notes

- In v1, `PREADY` is effectively driven by the selected sub-block or deasserted when no sub-block is selected.
- `out_ready` is tied high in the top level, so Matrix C capture is always ready in v1.
- The legacy address and enable outputs from `control_unit` are preserved for compatibility but are not used by `accelerator_top`.