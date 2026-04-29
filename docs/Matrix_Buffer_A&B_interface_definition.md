# Module Interface Specification: Matrix A & B Buffers

## 1. Overview 
This module acts as the data buffer for Matrix A and Matrix B in the Systolic Array accelerator. It receives data from the RISC-V CPU via a 32-bit APB interface, unpacks the data based on the configured bit-width, stores it in internal registers/SRAM, and streams it to the Systolic Array using a synchronous Valid/Ready handshake protocol.

## 2. Parameters 
| Parameter Name | Default Value | Description |
| :--- | :--- | :--- |
| `DATA_W` | 16 | Data bit-width of a single element (Supported: 8, 16, 32). |
| `M` | 4 | Number of rows in the Systolic Array. |
| `N` | 4 | Number of columns in the Systolic Array. |
| `APB_DW` | 32 | APB data bus width (Fixed by SoC architecture). |

## 3. Port List 

### 3.1 APB Interface
* `input logic clk`: System clock.
* `input logic rst_n`: Active-low synchronous reset.
* `input logic [31:0] PWDATA`: APB write data bus.
* `input logic PWRITE`: APB write enable.
* `input logic PSEL`: APB slave select.
* `input logic PENABLE`: APB enable.
* `input logic [7:0] PADDR`: APB address bus (Lower 8 bits for register offset).

### 3.2 Array Interface
* `output logic mat_valid`: High when both Matrix A and B buffers are full and ready to stream.
* `input logic sys_ready`: High when Systolic Array is ready to accept inputs.
* `output logic [M*DATA_W-1:0] a_data`: A full column vector from Matrix A.
* `output logic [N*DATA_W-1:0] b_data`: A full row vector from Matrix B.

## 4. Register Map
*(Note: Base Address for Subsystem 0 is `0x01050000`)*

| Offset | Name | Access | Description |
| :--- | :--- | :--- | :--- |
| `0x00` | `MAT_A_DATA` | W/O | Write port for Matrix A. Address auto-increments internally. |
| `0x40` | `MAT_B_DATA` | W/O | Write port for Matrix B. Address auto-increments internally. |
| `0x80` | `MAT_CTRL` | R/W | Control/Status register (e.g., bit 0: Clear Buffer, bit 1: Force Start). |

## 5. HW/SW Co-design & Data Packing Rules
The APB bus width is strictly 32-bit. To maximize bus bandwidth, the software (C code) **MUST pack** multiple matrix elements into a single 32-bit word before writing to the APB interface. The hardware will unpack them automatically based on the `DATA_W` parameter.

### 5.1 Packing Rule (C Code Perspective):
* **If `DATA_W = 8`**: Pack 4 elements per write.
  `PWDATA = (el_3 << 24) | (el_2 << 16) | (el_1 << 8) | el_0;`
* **If `DATA_W = 16`**: Pack 2 elements per write.
  `PWDATA = (el_1 << 16) | el_0;`
* **If `DATA_W = 32`**: 1 element per write. No packing required.

### 5.2 Unpacking Rule (Hardware Perspective):
The SystemVerilog module dynamically unpacks `PWDATA[31:0]` using the `DATA_W` parameter at compile time and stores the elements sequentially into the internal 2D register arrays.

## 6. Timing and Handshake Protocol 
* **Streaming Order:** Row-major . Data is written to the buffer row by row, matching the APB transaction format.
* **Handshake:** Standard `Valid/Ready`. Data is successfully passed to the Systolic Array **only** on the rising clock edge where `mat_valid == 1` and `sys_ready == 1`.
* **Vector Transfer:** Once the handshake is successful, a full vector `a_data` and a full vector `b_data` are transmitted to the MAC array concurrently in the same clock cycle.