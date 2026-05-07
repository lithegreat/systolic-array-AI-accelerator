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
      a_data =======>|                           |=======> c_data
      b_data =======>|                           |=======> c_row
                     |                           |=======> c_col
                     +---------------------------+
                           ^       ^
                           |       |
                          clk    rst_n
                          
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
For each cycle where `out_valid && out_ready`, one C element is produced with
its row/col indices.

- `c_data[ACC_W-1:0]`: signed accumulation result.
- `c_row[$clog2(M)-1:0]`: row index of `c_data`.
- `c_col[$clog2(N)-1:0]`: col index of `c_data`.

### Output-Stationary Dataflow
- Each PE owns one `C[i,j]` accumulator.
- One input beat supplies the whole A column `A[:,k]` and the whole B row `B[k,:]`.
- Internal skew shift chains delay row `i` by `i` cycles and column `j` by `j` cycles.
- Each PE accumulates for exactly `K` valid windows, then the array drains results in row-major order.

### Timing Notes (Handshake)
- `start` is sampled in `IDLE` and launches one tile.
- `in_valid` may remain high across cycles; if `in_ready` is low, inputs are
	stalled and must be held stable.
- `out_valid` may remain high across cycles; if `out_ready` is low, outputs are
	stalled and must be held stable.
- `done` asserts for one cycle after the last `(c_row, c_col)` is accepted.
- The compute phase lasts `M + N + K - 2` internal pipeline cycles before drain starts.

### Assumptions
- Matrix A/B modules provide one aligned pair `(a_col, b_row)` per accepted beat.
- One output element is produced per cycle when ready, after pipeline latency.

### Notes
- The current implementation drains `C` in row-major order.
- The current implementation assumes `M` and `N` are powers of two for drain index decoding.
