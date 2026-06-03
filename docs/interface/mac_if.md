# MAC (Multiply Accumulate) Interface declarations 

### Module name
`mac_pe`
### block diagram


                         +---------------------------+
            b_in =======>|                           |=======> b_out
                         |          mac_pe           |
            a_in =======>|   (Processing Element)    |=======> a_out
                         |                           |
        clear_acc ------>|                           |=======> pe_out
                         +---------------------------+
                                ^       ^       ^
                                |       |       |
                               clk    rst_n     en

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


### Parameters
- `DATA_W` (default 16): Bit-width for signed input data and weights.
- `ACC_W` (default 32): Bit-width for the internal accumulator to prevent overflow ($2 \times DATA\_W$).

### Clock/Reset
- `clk`: System clock.
- `rst_n`: Active-low synchronous reset.

### Control and Handshake
- `en`: Clock enable signal. The PE performs multiplication, accumulation, and data shifting only when `en` is high.
- `clear_acc`: Synchronous clear signal. When asserted, the internal accumulator is reset to zero or initialized with the current product ($A \times B$).

### Data Inputs
- `a_in[DATA_W-1:0]`: Signed data element from the left neighbor or Matrix A stream.
- `b_in[DATA_W-1:0]`: Signed data element from the top neighbor or Matrix B stream.

### Data Outputs
- `a_out[DATA_W-1:0]`: Registered version of `a_in`. It passes the input to the right neighbor on the next `clk` edge.
- `b_out[DATA_W-1:0]`: Registered version of `b_in`. It passes the input to the bottom neighbor on the next `clk` edge.
- `pe_out[ACC_W-1:0]`: The current signed 32-bit accumulation result held within this PE.

### Logic Notes
- **Signed Arithmetic**: All calculations (multiplication and addition) must be performed using signed logic.

- **Formula**:
$$Accumulator = (a\_in \times b\_in) + Accumulator$$

- **Pipelining**: `a_out` and `b_out` must be driven by flip-flops to ensure the systolic "pulse" behavior across the array.

- **Overflow**: The internal accumulator `ACC_W` is sized to 32 bits to ensure no precision is lost during the summation of 16-bit products.

