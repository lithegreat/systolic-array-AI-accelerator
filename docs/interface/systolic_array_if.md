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
- `M` (default 4): output rows.
- `N` (default 4): output cols.
- `K` (default 4): reduction dimension.

### Clock/Reset
- `clk`: system clock.
- `rst_n`: active-low synchronous reset.

### Control and Handshake
- `start`: pulse to begin one MxN output tile computation.
- `in_valid`: input data valid for the current cycle.
- `in_ready`: systolic array can accept input data this cycle.
- `out_valid`: output data valid for the current cycle.
- `out_ready`: downstream can accept output data this cycle.
- `done`: pulse when the tile is fully produced.

### Data Inputs
Inputs are provided by Matrix A and Matrix B modules in lockstep. For each cycle
where `in_valid && in_ready`, both `a_data` and `b_data` are consumed.

- `a_data[DATA_W-1:0]`: signed element from Matrix A stream.
- `b_data[DATA_W-1:0]`: signed element from Matrix B stream.

### Data Outputs
For each cycle where `out_valid && out_ready`, one C element is produced with
its row/col indices.

- `c_data[2*DATA_W-1:0]`: signed accumulation result.
- `c_row[$clog2(M)-1:0]`: row index of `c_data`.
- `c_col[$clog2(N)-1:0]`: col index of `c_data`.

### Timing Notes (Handshake)
- `start` can be asserted for one cycle when idle. The array latches `start`
	only when idle and `in_ready` is high.
- `in_valid` may remain high across cycles; if `in_ready` is low, inputs are
	stalled and must be held stable.
- `out_valid` may remain high across cycles; if `out_ready` is low, outputs are
	stalled and must be held stable.
- `done` asserts for one cycle after the last `(c_row, c_col)` is accepted.

### Assumptions
- Matrix A/B modules handle scheduling of the correct streaming order for the
	chosen systolic array dataflow.
- One input pair `(a_data, b_data)` is accepted per cycle when ready.
- One output element is produced per cycle when ready, after pipeline latency.

### Open Items
- Confirm streaming order (row-major/col-major) for A/B.
- Confirm whether `done` is based on output acceptance or internal completion.
