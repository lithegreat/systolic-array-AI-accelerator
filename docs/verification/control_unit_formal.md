# Formal Verification of `control_unit` (SymbiYosys)

> **Status**: implemented and passing — k-induction proof (`mode prove`) and a
> reachability sanity check (`mode cover`) both green.
> **Tooling**: [Yosys](https://github.com/YosysHQ/yosys) 0.63 + Z3 4.15.8 via
> [SymbiYosys](https://github.com/YosysHQ/sby) (`sby`).
> **Scope**: `rtl/control/control_unit.sv` — the compute FSM
> (`IDLE → ISSUE → BUSY → DONE → IDLE`), APB register-file invariants, and
> interrupt / soft-reset behaviour.

---

## 1. Why formal, and why now

The cocotb suite (`sim/testbenches/control/`) exercises `control_unit` with
directed and constrained-random scenarios, but simulation can only ever check
the traces it happens to generate. A control FSM with a handful of registers
(`CTRL`, `STATUS`, `M/N/K_DIM`, `INT_EN/STAT`) and an asynchronous-looking
soft-reset bit is exactly the kind of small, state-heavy design where an
exhaustive/inductive proof is cheap to run and can catch corner cases (e.g. a
soft-reset landing on the same cycle as a state transition) that are easy to
miss with directed tests and unlikely to be hit by constrained-random
sequences without deliberately biasing toward them.

This effort answers the "can/should we do formal here" question from
[docs/plans/tech-debt.md](../plans/tech-debt.md) (TD-2, IRQ/status corner-case
coverage) with a working, reusable harness — and, in the process, found a real
one-cycle race condition (§4).

## 2. Toolchain

Not yet part of the CI images (`ci/check.Dockerfile`, `ci/sim.Dockerfile`);
install locally:

```bash
sudo dnf install -y yosys z3          # or: apt install yosys z3 (Debian/Ubuntu)

# SymbiYosys isn't packaged for Fedora; build from source
git clone --depth 1 https://github.com/YosysHQ/sby.git /tmp/sby
cd /tmp/sby && sudo make install PREFIX=/usr/local
```

This installs `sby` to `/usr/local/sbin/sby`. Other SMT backends (`cvc5`,
`yices`) are available via `dnf` if a second opinion is ever needed; Boolector
is not packaged and would need a source build.

## 3. Harness design

```
formal/
├── scripts/
│   └── yosys_shim.py                    # preprocessing shim (see below)
└── control_unit/
    ├── control_unit_formal.svh          # SVA property body (the actual spec)
    ├── control_unit.sby                 # mode prove: k-induction, depth 15
    └── control_unit_cover.sby           # mode cover: reachability sanity check
```

Run it:

```bash
cd formal/control_unit
sby -f control_unit.sby          # PASS/FAIL: all properties hold (or a counterexample)
sby -f control_unit_cover.sby    # PASS: ISSUE/BUSY/DONE states are all reachable
```

Both must be read together: `mode prove` alone can pass *vacuously* if a
property's guard can never be true, so `control_unit_cover.sby` explicitly
covers reaching `ISSUE`, `BUSY`, and `DONE` to confirm the proof is exercising
real behaviour, not an unreachable corner of the state space.

### 3.1 Properties are spliced into a throwaway copy of the RTL, not bound

`control_unit_formal.svh` is **not** a standalone module — it's a fragment of
`always @(posedge clk)` blocks with `assert`/`cover` statements. The `[script]`
section of each `.sby` file runs `formal/scripts/yosys_shim.py`, which copies
`control_unit.sv` and splices the fragment's text in just before its
`endmodule`, so the properties see the module's real internal signals
(`cstate_q`, `reg_ctrl`, `reg_status`, …) directly, with no port wiring at all.
`rtl/control/control_unit.sv` itself is **never modified** — the spliced copy
is a build artifact.

This design was not the first thing tried. Two more "conventional" approaches
were attempted and abandoned because of limitations in Yosys's built-in
`read_verilog -sv` frontend (§4 covers the actual bug found; this is about the
harness plumbing):

1. **`bind`-based checker module.** `bind control_unit control_unit_formal chk (.*);`
   parses without error, but Yosys silently never instantiates the bound
   module (confirmed via `design.log`: `Removing unused module`) — so none of
   the assertions ever ran, and a deliberately-false test assertion still
   reported PASS.
2. **Explicit instantiation with hierarchical port wiring**
   (`.reg_m_dim(dut.reg_m_dim)`, referencing an internal, non-port signal of
   the `dut` instance). This produces a dangling, disconnected wire ("used
   but has no driver") for every internal signal — confirmed by comparing VCD
   values: `dut.reg_m_dim` correctly showed `16`, while the checker's
   supposedly-wired copy stayed stuck at `0`.

Both failure modes are dangerous specifically because they still print PASS —
which is why every property in this harness was sanity-checked by temporarily
injecting a deliberately-false assertion and confirming SymbiYosys actually
reports FAIL before trusting a real PASS.

### 3.2 `yosys_shim.py`: working around two frontend gaps

Two more Yosys `read_verilog -sv` limitations required a preprocessing step
(`formal/scripts/yosys_shim.py <src.sv> <dst.sv> [properties.svh]`), applied
only to the throwaway copy, never to `rtl/`:

- **Header-import syntax.** `module foo import pkg::*; #(...) (...);` (used
  throughout this project's RTL, and accepted by Verilator and commercial
  tools) is rejected by Yosys's frontend (`TOK_IMPORT` syntax error). The
  shim hoists the `import` line to compilation-unit scope, before the
  `module` keyword, via regex — semantically equivalent for a single-file
  formal build.
- **No `assert property (@(posedge clk) ...)` / `default clocking`.**
  Clocked concurrent assertions and default-clocking/disable blocks aren't
  supported by this frontend either (syntax errors on `@` and `default`).
  All properties are written instead as plain immediate `assert`/`cover`
  statements inside explicit `always @(posedge clk) if (guard) ...` blocks,
  which Yosys does support.

### 3.3 Reset assumption

Without an explicit reset assumption, a BMC/k-induction solver is free to
pick an initial register state that never passed through reset, which
trivially "violates" reset-established invariants (e.g. the `clamp_dim()`
range guarantee) for reasons that have nothing to do with the RTL's actual
behaviour. `control_unit_formal.svh` forces a real reset at the start of
every trace with:

```systemverilog
always @* if ($initstate) assume (reset_int);
```

## 4. A real bug found this way

**Soft-reset vs. `STATUS.busy` race**, found by
[control_unit_formal.svh](../../formal/control_unit/control_unit_formal.svh)
and confirmed with a concrete counterexample trace
(`formal/control_unit/control_unit/engine_0/trace.vcd`):

> When `CTRL.softrst` is set during the same cycle that `start_pulse` (or an
> in-flight compute) would otherwise drive `cstate_d` to a non-`IDLE` value,
> `control_unit.sv`'s soft-reset branch correctly forces `cstate_q` back to
> `IDLE` on the next clock edge — but `reg_status[STATUS_BUSY_BIT]` is still
> assigned unconditionally from that same (pre-override) `cstate_d`
> immediately afterward. The result: `STATUS.busy` reads `1` for exactly one
> cycle while `cstate_q == IDLE`.

The property that would assert `STATUS.busy == (cstate_q != IDLE)`
unconditionally is currently qualified to exclude the concurrent-soft-reset
cycle (see the `KNOWN ISSUE` comment in `control_unit_formal.svh`), so the
proof passes while documenting the gap rather than hiding it.

This is tracked as **TD-7** in
[docs/plans/tech-debt.md](../plans/tech-debt.md) pending a decision to fix the
RTL (make the `STATUS.busy` assignment respect the soft-reset override, same
as `cstate_q`) or accept it as a documented one-cycle read glitch.

## 5. Lessons learned / reusable notes

- **Never trust a formal PASS without also confirming cover/reachability is
  non-vacuous** — pair every `mode prove` `.sby` file with a `mode cover`
  sibling that reaches the interesting states.
- **Always sanity-check a harness** by injecting a deliberately-false
  assertion and confirming SymbiYosys reports FAIL before trusting real
  results — both the `bind` no-op and the dangling hierarchical-wire bug
  above were only caught this way.
- **Yosys's built-in `read_verilog -sv` frontend is a meaningful SV subset**,
  not full SystemVerilog: no header-import syntax, no clocked
  `assert property (@(posedge clk) ...)`, no `default clocking`/`default
  disable iff`, and `bind` is a parse-only no-op. Splice properties directly
  into a throwaway copy of the module body instead of binding or
  instantiating a separate checker.
- **Formal verification can find genuine, subtle RTL bugs that dynamic
  simulation misses** — the soft-reset/`STATUS.busy` race (§4) is a concrete
  example from a design that was already passing its cocotb regression.

## 6. Possible next steps

- Extend the same harness pattern to `rtl/array/systolic_array.sv` and/or
  `rtl/MAC/mac_pe.sv` (arithmetic/overflow invariants are good formal
  targets).
- Add a CI job once `yosys`/`sby` are baked into `ci/check.Dockerfile` or
  `ci/sim.Dockerfile`.
- Resolve TD-7 (fix the RTL race or formally accept it).
