# Formal Verification of `control_unit` (SymbiYosys)

> **Status**: implemented and passing — k-induction proof (`mode prove`) and a
> reachability sanity check (`mode cover`) both green.
> **Tooling**: [Yosys](https://github.com/YosysHQ/yosys) 0.63 + Z3 (4.16.x, via
> the `z3-solver` PyPI wheel — see §7) via [SymbiYosys](https://github.com/YosysHQ/sby) (`sby`).
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

Preinstalled in the CI simulation image (`ci/sim.Dockerfile`) and run automatically as a GitLab CI pipeline job. As of §7, CI gets its `z3` binary from the `z3-solver` PyPI wheel (`requirements/sim.txt`), not the distro apt package — see §7 for why.

To install/run locally:

```bash
sudo dnf install -y yosys          # or: apt install yosys (Debian/Ubuntu)
pip install z3-solver              # modern prebuilt z3 CLI, see §7

# SymbiYosys isn't packaged for Fedora; build from source
git clone --depth 1 https://github.com/YosysHQ/sby.git /tmp/sby
cd /tmp/sby && sudo make install PREFIX=/usr/local
```

This installs `sby` to `/usr/local/bin/sby`. A distro `z3` package (`apt`/`dnf`
install) also works for local, non-resource-constrained use, but prefer
`z3-solver` since it's the version validated against this harness (see §7).
Other SMT backends (`cvc5`, `yices`) are available via `dnf` if a second
opinion is ever needed; Boolector is not packaged and would need a source
build.

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

## 4. A real bug found and resolved

**Soft-reset vs. `STATUS.busy` race**, found by
[control_unit_formal.svh](../../formal/control_unit/control_unit_formal.svh)
and confirmed with a concrete counterexample trace:

> When `CTRL.softrst` was set during the same cycle that `start_pulse` (or an
> in-flight compute) would otherwise drive `cstate_d` to a non-`IDLE` value,
> `control_unit.sv`'s soft-reset branch correctly forced `cstate_q` back to
> `IDLE` on the next clock edge — but `reg_status[STATUS_BUSY_BIT]` was still
> assigned unconditionally from that same (pre-override) `cstate_d`
> immediately afterward. The result: `STATUS.busy` read `1` for exactly one
> cycle while `cstate_q == IDLE`.

This has been fixed in the RTL by wrapping the normal assignments of `reg_status`
and `reg_int_stat` inside the `else` branch of the soft reset check.
The formal property now asserts `STATUS.busy == (cstate_q != IDLE)`
unconditionally and passes in all cycles. This resolved **TD-7**.

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

## 7. CI incident: solver OOM traced to an ancient apt `z3`, not proof complexity (2026-07-08)

`control_unit_formal` started reliably timing out in CI (`job_execution_timeout`
after 5 minutes), while `mac_pe_formal`/`systolic_array_formal` kept passing on
the same runner. `glab ci trace <job_id>` showed the solver hanging on
`Checking assumptions in step 0` for 5+ minutes before dying
(`Unexpected EOF response from solver`) — i.e. z3 itself was crashing/thrashing,
not the harness looping through many BMC steps.

**Root cause**: `ci/sim.Dockerfile` installed z3 via plain `apt-get install z3`,
which resolves to **z3 4.8.12** (released 2021) in the `verilator/verilator:latest`
base image — a version with materially worse bit-vector solver performance for
this kind of design. The identical `control_unit.sby` model solves in well
under a second with a modern z3 (verified both locally and by SSHing directly
into the runner and running `sby` inside a rebuilt image).

**Fix**: `ci/sim.Dockerfile` no longer installs z3 via apt; `requirements/sim.txt`
adds `z3-solver` instead, whose PyPI wheel ships a modern prebuilt `z3` binary
(lands at `/usr/local/bin/z3`, ahead of apt's `/usr/bin` on `PATH`, currently
resolving to 4.16.x). A `RUN z3 --version` line in the Dockerfile sanity-checks
this at image build time.

**A dead end worth recording**: before the real cause was found, four commits
tried to work around the symptom by shrinking the proof itself — `mode prove`
(k-induction) → `mode bmc` (bounded, depth 10), depth 15 → 10, the real 32-bit
APB register width → an 8-bit `` `ifdef FORMAL `` abstraction, and
`chparam -set M 2 -set N 2 -set K 2`. **None of these fixed the CI failure**
(the job still timed out after all four landed) because they were treating the
wrong problem — and they silently weakened what was actually being proved
(a bounded check instead of an unbounded inductive one; an 8-bit register
abstraction instead of the real 32-bit hardware). All four were reverted once
the z3 upgrade landed; the harness now runs at its original strength (`mode
prove`, depth 15, real `APB_DW=32`, no dimension shrinking) and still completes
in ~1-3s / <45MB. **Lesson**: for a formal-verification CI timeout/OOM, check
the solver/toolchain version in the actual CI image before concluding the
proof itself is too expensive — `sby`/z3 version differences can dwarf any
plausible state-space reduction.
