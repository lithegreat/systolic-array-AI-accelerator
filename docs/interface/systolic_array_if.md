# Module Interface Specification

Issue #3.

## Systolic Array Top-Level Interface 

### Module name
`systolic_array`

### block diagram
                     +---------------------------+
       start ------->|                           |
    in_valid ------->|                           |-----> out_valid
    in_ready <-------|      systolic_array       |<----- out_ready
                     |       (M=4, N=4, K=4)     |-----> done
                     |                           |
      a_data =======>|                           |=======> c_row_data
      b_data =======>|                           |=======> c_row
                     |                           |
                     +---------------------------+
                           ^       ^
                           |       |
                          clk    rst_n

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
                          
### Parameters
- `DATA_W` (default 16): data/weight bit-width, signed integer.
- `ACC_W` (default 32): accumulator/output width.
- `M` (default 4): output rows.
- `N` (default 4): output cols.
- `K` (default 4): reduction dimension.

### Clock/Reset
- `clk`: system clock.
- `rst_n`: active-low synchronous reset.

### Control and Handshake
- `start`: pulse to begin one MxN output tile computation.
- `in_valid`: input vector beat valid for the current cycle.
- `in_ready`: systolic array can accept an input vector beat this cycle.
- `out_valid`: output data valid for the current cycle.
- `out_ready`: downstream can accept output data this cycle.
- `done`: pulse when the tile is fully produced.

### Data Inputs
Inputs are provided by Matrix A and Matrix B modules in lockstep. For each cycle
where `in_valid && in_ready`, both `a_col` and `b_row` are consumed.

- `a_col[M*DATA_W-1:0]`: packed signed column vector from Matrix A for the current `k`.
- `b_row[N*DATA_W-1:0]`: packed signed row vector from Matrix B for the current `k`.

### Data Outputs
For each cycle where `out_valid && out_ready`, one full C row is produced with
its row index. The array drains `M` beats total (top row first).

- `c_row_data[N*ACC_W-1:0]`: packed signed accumulation results for the row
  (column 0 in the low bits, column `N-1` in the high bits).
- `c_row[$clog2(M)-1:0]`: row index of `c_row_data`.

### Output-Stationary Dataflow
- Each PE owns one `C[i,j]` accumulator.
- One input beat supplies the whole A column `A[:,k]` and the whole B row `B[k,:]`.
- Internal skew shift chains delay row `i` by `i` cycles and column `j` by `j` cycles.
- Each PE accumulates for exactly `K` valid windows, then the array drains results one row per beat in top-to-bottom order.

### Timing Notes (Handshake)
- `start` is sampled in `IDLE` and launches one tile.
- `in_valid` may remain high across cycles; if `in_ready` is low, inputs are
	stalled and must be held stable.
- `out_valid` may remain high across cycles; if `out_ready` is low, outputs are
	stalled and must be held stable.
- `done` asserts for one cycle after the last C row is accepted.
- The compute phase lasts `M + N + K - 2` internal pipeline cycles before drain starts.

### Assumptions
- Matrix A/B modules provide one aligned pair `(a_col, b_row)` per accepted beat.
- One output row (N elements) is produced per cycle when ready, after pipeline latency.

### Notes
- The current implementation drains `C` in row-major order.
- The current implementation assumes `M` and `N` are powers of two for drain index decoding.
