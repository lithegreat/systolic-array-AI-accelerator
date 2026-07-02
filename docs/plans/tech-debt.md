# Technical Debt Register

Known shortcuts, limitations, and deferred work. Each entry is something we
*chose* not to do now — recorded so it stays visible and schedulable instead of
being forgotten. Promote an entry to an [active plan](README.md) when it gets
picked up; remove it when resolved (the fix should land with the removal).

Last reviewed: 2026-07-02

## How to use

- Add a row when you take a shortcut or discover a limitation.
- Keep the **Impact** honest (what breaks / what's risky if left alone).
- Link to the code, plan, or report that gives context.

## Register

| ID | Area | Description | Impact | Link |
| --- | --- | --- | --- | --- |
| TD-1 | SoC / QuestaSim | Full-SoC QuestaSim run needs `vopt +initreg+0` to clear the Ibex fetch-FIFO 4-state X (unreset `rdata_q` with `ResetAll=0`). Worked around in the sim Makefile, not fixed in SoC RTL. | QuestaSim flow depends on a tool flag; a vendor IP bump could reintroduce the X. | [verification report §5](../verification/accelerator_soc_report.md) |
| TD-2 | Verification | Functional-coverage baseline is below target; stall/back-pressure and buffer over-run paths are thinly covered. **Partially addressed**: new cocotb tests added for control_unit (start-while-busy, IRQ masking, back-to-back compute), matrix_buffer_ab (A/B overflow PSLVERR, streaming backpressure), and matrix_buffer_c (read-past-end PSLVERR, double capture, interleaved capture/read). | Corner-case regressions may slip through. Remaining: raise Verilator line-coverage baseline further. | [ARCHITECTURE scorecard](../ARCHITECTURE.md#maturity-scorecard) |
| TD-3 | ASIC | No gate-level netlist or timing closure yet for the GF 22 nm FDX target. | ASIC deliverable not yet started. | [ARCHITECTURE scorecard](../ARCHITECTURE.md#maturity-scorecard) |
| TD-4 | FPGA / eikon | eikon home-dir disk quota nearly exhausted (9871 MiB used / 8192 MiB soft / 10240 MiB hard, ~369 MiB headroom). Vivado synth+impl+bitstream needs several GiB scratch space, so the FPGA flow (`make fpga` / `all_xilinx`) cannot run there until space is freed or quota is raised. | FPGA flow on eikon is blocked; no bitstream re-validated after the SoC address-map update yet. | [verification report §9.5](../verification/accelerator_soc_report.md) |
| TD-5 | Didactic-SoC submodule | Local fixes to vendored submodule files (e.g. `sim/Makefile`'s `ACCEL_INC_DIR`, `COMMON_CELLS_ASSERTS_OFF`, `RUN_CMD`) are not yet merged upstream, so pulling a new Didactic-SoC revision can silently regress them (happened once after the 2026-07 address-map update). | QuestaSim/other flows can break silently after any submodule sync until these patches land upstream or get committed on our fork. | [verification report §9.4](../verification/accelerator_soc_report.md) |

<!-- Add new rows above. Keep IDs stable; do not renumber on removal. -->
