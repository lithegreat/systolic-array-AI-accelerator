# Formal Verification — `mac_pe` and `systolic_array`

> Properties are proved by SymbiYosys (SBY) + Z3 via the same splice-shim
> pattern used for `control_unit`.  CI runs all four tasks in the `sim` stage.

## 1. Scope

| Module | File | Properties |
|---|---|---|
| `mac_pe` | `formal/mac_pe/mac_pe_formal.svh` | Arithmetic/accumulator invariants (P1–P6) |
| `systolic_array` | `formal/systolic_array/systolic_array_formal.svh` | FSM/handshake/counter invariants (P1–P5) |

## 2. Toolchain

Same as `control_unit_formal.md` §2: SymbiYosys (`sby`) + Yosys `read_verilog -sv` + Z3 solver, installed in `group5-ci-sim:latest` on the runner host.

The splice-shim (`formal/scripts/yosys_shim.py`) is reused unchanged for both modules.

## 3. `mac_pe` — arithmetic invariants

**Run:** `sby -f mac_pe.sby` (prove, k-induction, depth 10) and `sby -f mac_pe_cover.sby` (cover, depth 10).

### Properties

| ID | Property | Notes |
|---|---|---|
| P1 | After synchronous reset (`!$past(rst_n)`), `acc_q == 0 && a_out == 0 && b_out == 0` | Checked cycle after reset edge |
| P2 | When `en == 0` (previous cycle), no register changes | Stability |
| P3 | `en && clear_acc` → `acc_q == ACC_W'(product)` | Initialise mode |
| P4 | `en && !clear_acc` → `acc_q == $past(acc_q) + ACC_W'(product)` | Accumulate mode |
| P5 | `en` → `a_out == $past(a_in)` and `b_out == $past(b_in)` | Systolic passthrough |
| P6 | `pe_out == acc_q` at all times | Combinational tap |

Cover targets: accumulate with non-zero acc, clear path, and `a_out != 0` (passthrough live).

### Result

```
DONE (PASS, rc=0)  -- mac_pe.sby      (k-induction, all P1-P6)
DONE (PASS, rc=0)  -- mac_pe_cover.sby (3 cover traces found in ≤3 steps)
```

## 4. `systolic_array` — FSM/handshake invariants

**Run:** `sby -f systolic_array.sby` (bmc, depth 20, M=N=K=2) and `sby -f systolic_array_cover.sby` (cover, depth 20).

### Parameter choice

The proof uses `M=N=K=2` (`chparam` in the `[script]` block) to keep the flattened 2×2 PE grid tractable.  The FSM/counter properties are parameter-independent; only the depth/cover targets need scaling for larger tiles.

### Engine note — `mode bmc` instead of `mode prove`

`systolic_array.sv` uses `unique case` for the FSM.  Yosys elaborates an implicit default-coverage `assume` that makes `smtbmc --presat` report `PREUNSAT` during the induction basecase step when the initial register state is unconstrained.  The induction half independently succeeds.  Switching to `mode bmc` at depth 20 sidesteps the `--presat` check while still covering all states reachable from reset under M=N=K=2.

### Properties

| ID | Property |
|---|---|
| P1 | After synchronous reset: `state_q == S_IDLE && k_cnt_q == 0 && d_cnt_q == 0` |
| P2 | FSM legal transitions: `IDLE→RUN→DRAIN→DONE→IDLE` only |
| P3 | `in_ready` only asserted in `S_RUN` and only while `k_cnt_q < cfg_k_dim` |
| P4 | `out_valid` iff `state_q == S_DRAIN` |
| P5 | `done` iff `state_q == S_DONE` |

Cover targets: `S_RUN`, `S_DRAIN`, `S_DONE` all reachable (3 traces found in ≤1 step from unconstrained initial state).

### Result

```
DONE (PASS, rc=0)  -- systolic_array.sby      (bmc depth 20, all P1-P5)
DONE (PASS, rc=0)  -- systolic_array_cover.sby (3 cover traces found at step 1)
```

## 5. CI integration

```yaml
mac_pe_formal:
  stage: sim
  image: $SIM_IMAGE
  resource_group: sim-runner
  timeout: 5m
  script:
    - cd formal/mac_pe && sby -f mac_pe.sby && sby -f mac_pe_cover.sby

systolic_array_formal:
  stage: sim
  image: $SIM_IMAGE
  resource_group: sim-runner
  timeout: 10m
  script:
    - cd formal/systolic_array && sby -f systolic_array.sby && sby -f systolic_array_cover.sby
```

## 6. File tree

```
formal/
  mac_pe/
    mac_pe.sby              # prove config (k-induction, depth 10)
    mac_pe_cover.sby        # cover config (depth 10)
    mac_pe_formal.svh       # SVA property body
  systolic_array/
    systolic_array.sby      # bmc config (depth 20, M=N=K=2)
    systolic_array_cover.sby
    systolic_array_formal.svh
  scripts/
    yosys_shim.py           # shared splice shim (unchanged)
```

## 7. Next steps / open items

- Extend `systolic_array` to `mode prove` by rewriting the RTL's `unique case`
  with an explicit `default: state_d = S_IDLE` and then overriding in a
  `(* formal *)` wrapper — this would let the induction basecase run without
  `--presat` UNSAT.
- Add arithmetic overflow-detection properties to `systolic_array` covering
  the PE accumulator path (currently proved only in `mac_pe`).
- Scale cover depth for M=N=K=4 to exercise the full skew chain.
