# Plan: Fix FPGA 7x Accelerator Replication & Accel-Variant Passthrough

Last reviewed: 2026-07-02
Status: Active
Owner: Li
Tracking: found during Arty A7 FPGA bring-up (no issue filed yet)

## Goal

Root-cause was found for the ~25x resource-utilization blowup that fails
`place_design` on the Arty A7 FPGA flow. This plan tracks fixing the two
compounding causes so a bitstream can actually be produced:

1. Stop the real accelerator from being synthesized 7x (once per student slot).
2. Make `ACCEL_VARIANT` / `ACCEL_DIM` / `ACCEL_DATA_W` actually control the
   parameters of the synthesized `accelerator_top` (currently always
   `M=N=K=16, DATA_W=8` regardless of variant).

## Context

`make all_xilinx` for the new Arty A7 target (`xc7a100tcsg324-1`, 63,400 LUTs)
completed `synth_design` cleanly (0 errors) but `place_design` failed with 13
`[DRC UTLZ-1]` over-utilization errors. Post-synth utilization:
Slice LUTs 1,560,727 / 63,400 = **2461.71%**, Slice Registers 186,180 / 126,800 =
146.83%.

Root cause, confirmed by direct inspection:

- [`Didactic-SoC/src/generated/Didactic.v`](../../../Didactic-SoC/src/generated/Didactic.v)
  instantiates `student_wrapper_0` .. `student_wrapper_6` (7 student slots).
  Every one of them instantiates a module literally named `subsystem`
  (`i_subsystem_0` .. `i_subsystem_6`).
- `Bender.yml` selects between two definitions of `subsystem` via the
  `black_box` tag: `src/generated/subsystem.v` (real accelerator wiring) when
  `not(black_box)`, or `src/tech_generic/subsystem_tieoff.v` (tied-off stub)
  when `black_box`. `Didactic-SoC/fpga/scripts/run_xilinx.tcl` never passes
  `-t black_box`, so `subsystem.v` (real) is the only definition compiled — and
  since Verilog resolves modules by name, it gets bound to **all 7** student
  slots. The whole 16x16x16 systolic array + APB glue is therefore synthesized
  7 times instead of once.
- Separately, [`subsystem.v`](../../../Didactic-SoC/src/generated/subsystem.v)
  instantiates `accelerator_top` with **no parameter overrides**, so even a
  single copy always builds the `M=N=K=16, DATA_W=8` default from
  [`accel_pkg.sv`](../../../rtl/include/accel_pkg.sv), never the
  `ACCEL_VARIANT`-selected size. `run_xilinx.tcl` passes `ACCEL_DIM`/
  `ACCEL_DATA_W` as Verilog `` `define ``s, but nothing in `rtl/` reads them.

The historical Z1 baseline in
[lab_server_examples.md](../../guides/lab_server_examples.md) (58,484 LUTs,
109.93%, single 16x16 instance, 1 DSP48E1) predates the "Migration to new
Didactic-SoC (2026-05-11)" that introduced the 7-slot `student_wrapper`
architecture (see header comment in `subsystem.v`), so this is the first FPGA
run to actually exercise the new 7-slot structure — not a regression from the
recent z1->a7 board-switch or Bender.yml fixes.

`student_wrapper_*.v` / `subsystem.v` are Kactus2/IP-XACT-generated
(header: "EVERYTHING ABOVE THIS LINE MAY BE OVERWRITTEN BY KACTUS2"), so the
fix likely needs to go through the IP-XACT source / SoC-integration owner
rather than hand-editing the generated `.v` files directly.

## Steps

- [ ] Confirm with the SoC-integration owner whether all 7 student slots are
      meant to carry the *real* subsystem for FPGA bring-up, or whether 6 of 7
      should be tied off (`subsystem_tieoff.v`) and only one (ours) real.
- [ ] Implement per-slot module selection so only the intended slot(s)
      instantiate the real `subsystem` (needs a mechanism finer-grained than
      today's single global `black_box` Bender tag, e.g. per-instance IP-XACT
      config, or renaming/parameterizing the generated wrappers).
- [ ] Wire `M`/`N`/`K`/`DATA_W` parameter overrides from `ACCEL_DIM`/
      `ACCEL_DATA_W` through `subsystem.v` into the `accelerator_top`
      instantiation (or a macro-reading mechanism in `accel_pkg.sv`), so
      `ACCEL_VARIANT=int8_8x8` actually changes the synthesized array size.
- [ ] Re-run the Arty A7 (and/or Z1) Vivado flow on eikon; confirm reduced
      utilization and a successful `place_design` / `route_design` /
      `write_bitstream`.
- [ ] Update `docs/guides/lab_server_examples.md` and `docs/ARCHITECTURE.md`
      with corrected utilization numbers once a real bitstream builds.

## Progress log

- 2026-07-02 — Root-caused via a7 `place_design` DRC failure investigation:
  confirmed 7x `subsystem` replication (`Didactic.v` -> `student_wrapper_0..6`
  -> `i_subsystem_0..6`, all resolving to the one real `subsystem.v` because
  `run_xilinx.tcl` never passes `-t black_box`), plus confirmed `subsystem.v`
  passes no parameters to `accelerator_top`. Plan opened; no fix implemented
  yet.

## Decision log

- 2026-07-02 — Decided not to hand-edit the Kactus2-generated
  `student_wrapper_*.v` / `subsystem.v` files unilaterally, since they are
  regenerated from IP-XACT and owned by SoC integration; flagging for a team
  decision on the intended per-slot mechanism first.

## Verification

- `./sim/scripts/run_verilator.sh` and `pytest -vv sim/test_runner.py` must
  still pass after any RTL parameter-passthrough change (no functional
  regression).
- FPGA gate: `make all_xilinx` (a7 or z1) reaches `write_bitstream` with a
  post-place utilization report under 100% for all resource categories.
