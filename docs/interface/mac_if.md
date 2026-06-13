# MAC Processing Element Interface

> A single output-stationary multiply-accumulate cell: it multiplies two signed
> operands, adds the product into a local accumulator, and pulses the operands on
> to its right and bottom neighbours so the array can stream data through.

- **Module:** `mac_pe`
- **Source:** [`rtl/MAC/mac_pe.sv`](../../rtl/MAC/mac_pe.sv)
- **Owner:** Liu (#2)

## Overview

`mac_pe` is the atomic processing element (PE) of the systolic array. On every
enabled clock edge it computes `a_in × b_in` (signed) and either adds the product
to its accumulator or re-initialises the accumulator with it. At the same time it
registers `a_in`/`b_in` into `a_out`/`b_out` to keep the systolic "pulse" moving.
Each PE owns exactly one `C[i,j]` accumulator.

## Block diagram

```mermaid
flowchart LR
   subgraph INPUTS["Inputs"]
      direction TB
      clk_in(["clk"])
      rst_in(["rst_n"])
      en_in(["en"])
      a_in(["a_in\n[DATA_W-1:0]"])
      b_in(["b_in\n[DATA_W-1:0]"])
      clear_in(["clear_acc"])
   end

   subgraph PE["mac_pe"]
      direction TB
      mul["Signed Multiply\na_in × b_in"]
      acc["Accumulator\nACC_W bits\n(+ or clear)"]
      reg_a["FF\na_out reg"]
      reg_b["FF\nb_out reg"]
      mul --> acc
      a_in_int(( )) --> mul
      b_in_int(( )) --> mul
      a_in_int --> reg_a
      b_in_int --> reg_b
   end

   subgraph OUTPUTS["Outputs"]
      direction TB
      a_out(["a_out\n[DATA_W-1:0]"])
      b_out(["b_out\n[DATA_W-1:0]"])
      pe_out(["pe_out\n[ACC_W-1:0]"])
   end

   a_in -- "systolic\npass-through" --> a_in_int
   b_in -- "systolic\npass-through" --> b_in_int
   clear_in --> acc
   en_in --> PE
   clk_in --> PE
   rst_in --> PE

   reg_a --> a_out
   reg_b --> b_out
   acc --> pe_out

   style PE fill:#bbdefb,stroke:#1976d2
   style INPUTS fill:#f5f5f5,stroke:#999
   style OUTPUTS fill:#f5f5f5,stroke:#999
```

## Parameters

| Parameter | Default | Description |
| --- | --- | --- |
| `DATA_W` | `8` | Bit-width of the signed input operands (INT8 baseline; configurable to `8`/`16`/`32`). |
| `ACC_W` | `32` | Accumulator width (fixed 32). A single `2*DATA_W`-bit product always fits; summing `K` products wraps mod `2^32` in two's-complement (no saturation). |

## Ports

### Clock & reset

| Port | Direction | Width | Description |
| --- | --- | --- | --- |
| `clk` | Input | `1` | System clock. |
| `rst_n` | Input | `1` | Active-low synchronous reset. |

### Control

| Port | Direction | Width | Description |
| --- | --- | --- | --- |
| `en` | Input | `1` | Clock enable. The PE multiplies, accumulates, and shifts only when high. |
| `clear_acc` | Input | `1` | Synchronous accumulator clear. When high, the accumulator is initialised with the current product `a_in × b_in` instead of adding to its previous value. |

### Data

| Port | Direction | Width | Description |
| --- | --- | --- | --- |
| `a_in` | Input | `DATA_W` | Signed operand from the left neighbour / Matrix A stream. |
| `b_in` | Input | `DATA_W` | Signed operand from the top neighbour / Matrix B stream. |
| `a_out` | Output | `DATA_W` | Registered `a_in`, forwarded to the right neighbour next cycle. |
| `b_out` | Output | `DATA_W` | Registered `b_in`, forwarded to the bottom neighbour next cycle. |
| `pe_out` | Output | `ACC_W` | Current signed accumulation result held in this PE. |

## Behavior

- **Signed arithmetic.** Both the multiply and the add use signed logic.
- **Accumulate vs. clear** on an enabled clock edge:
  - `clear_acc = 1` → `acc ← a_in × b_in`
  - `clear_acc = 0` → `acc ← acc + a_in × b_in`
- **Systolic pulse.** `a_out` and `b_out` are flip-flops, so operands advance one PE per cycle.
- **No precision loss.** With `ACC_W = 32`, summing 16-bit products never overflows.

$$\text{acc} \leftarrow (a\_in \times b\_in) + \text{acc}$$

## Notes

- `pe_out` is a combinational tap of the accumulator register (no extra pipeline stage).
