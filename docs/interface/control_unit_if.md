# Control Unit Interface Declarations

### Module Name
`control_unit`

### Block Diagram

```text
                           +---------------------------+
        SoC clock/reset -->|                           |===> Matrix A Control (addr, ren, start)
                           |                           |===> Matrix B Control (addr, ren, start)
          SoC APB Bus ====>|                           |===> Matrix C Control (addr, wen, start)
                           |       control_unit        |===> Systolic Array Control (start, clear)
       SoC interrupts <----|                           |<=== Array/Buffer Status (done, busy)
                           +---------------------------+
```

### Description
The Control Unit is responsible for interfacing with the Didactic SoC via the APB subordinate interface, exposing configuration and status registers. It decodes instructions from the CPU and generates the appropriate control signals to orchestrate the Multiply-Accumulate (MAC) systolic array, as well as managing the addressing and loading of Matrix A, Matrix B, and Matrix C buffers.

### Parameters

| Parameter Name | Default Value | Description |
| --- | --- | --- |
| `APB_AW` | `10` | APB Address Width (in bits) |
| `APB_DW` | `32` | APB Data Width (in bits) |

### Ports

#### System & APB Interface (from Didactic SoC Platform)

| Port Name | Direction | Width | Description |
| --- | --- | --- | --- |
| `clk_in` | Input | `1` | System clock |
| `reset_int` | Input | `1` | Active-high internal reset from SoC |
| `PADDR` | Input | `APB_AW` | APB address |
| `PENABLE` | Input | `1` | APB enable |
| `PSEL` | Input | `1` | APB select |
| `PWDATA` | Input | `APB_DW` | APB write data |
| `PWRITE` | Input | `1` | APB write enable |
| `PRDATA` | Output | `APB_DW` | APB read data |
| `PREADY` | Output | `1` | APB ready |
| `PSLVERR` | Output | `1` | APB subordinate error |
| `irq_en_4` | Input | `1` | IRQ enable from SoC |
| `ss_ctrl_4` | Input | `8` | Subsystem control word from SoC |
| `irq_4` | Output | `1` | Interrupt to CPU |

#### Internal Control & Status Interface (Preliminary)

| Port Name | Direction | Width | Description |
| --- | --- | --- | --- |
| `matrix_a_addr` | Output | `TBD` | Read address for Matrix A buffer |
| `matrix_a_ren` | Output | `1`   | Read enable for Matrix A buffer |
| `matrix_b_addr` | Output | `TBD` | Read address for Matrix B buffer |
| `matrix_b_ren` | Output | `1`   | Read enable for Matrix B buffer |
| `matrix_c_addr` | Output | `TBD` | Write address for Matrix C buffer |
| `matrix_c_wen` | Output | `1`   | Write enable for Matrix C buffer |
| `array_start` | Output | `1`   | Start signal for systolic array computation |
| `array_clear` | Output | `1`   | Clear/reset signal for MAC accumulators |
| `array_done`  | Input  | `1`   | Done signal from systolic array computation |

### Preliminary Register Map

| Offset | Register Name | R/W | Description |
| --- | --- | --- | --- |
| `0x00` | `CTRL` | R/W | Control register (e.g., bit 0: start, bit 1: soft reset) |
| `0x04` | `STATUS` | R | Status register (e.g., bit 0: busy, bit 1: done) |
| `0x08` | `M_A_DIM` | R/W | Matrix A dimensions (rows, cols) |
| `0x0C` | `M_B_DIM` | R/W | Matrix B dimensions (rows, cols) |
| `0x10` | `INT_EN` | R/W | Interrupt enable mask |
| `0x14` | `INT_STAT` | R/W1C | Interrupt status (cleared on write 1) |
