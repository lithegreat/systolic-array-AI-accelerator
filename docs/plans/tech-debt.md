# Technical Debt Register

Known shortcuts, limitations, and deferred work. Each entry is something we
*chose* not to do now — recorded so it stays visible and schedulable instead of
being forgotten. Promote an entry to an [active plan](README.md) when it gets
picked up; remove it when resolved (the fix should land with the removal).

Last reviewed: 2026-06-13

## How to use

- Add a row when you take a shortcut or discover a limitation.
- Keep the **Impact** honest (what breaks / what's risky if left alone).
- Link to the code, plan, or report that gives context.

## Register

| ID | Area | Description | Impact | Link |
| --- | --- | --- | --- | --- |
| TD-1 | SoC / QuestaSim | Full-SoC QuestaSim run needs `vopt +initreg+0` to clear the Ibex fetch-FIFO 4-state X (unreset `rdata_q` with `ResetAll=0`). Worked around in the sim Makefile, not fixed in SoC RTL. | QuestaSim flow depends on a tool flag; a vendor IP bump could reintroduce the X. | [verification report §5](../verification/accelerator_soc_report.md) |
| TD-2 | Verification | Functional-coverage baseline is below target; stall/back-pressure and buffer over-run paths are thinly covered. | Corner-case regressions may slip through. | [ARCHITECTURE scorecard](../ARCHITECTURE.md#maturity-scorecard) |
| TD-3 | ASIC | No gate-level netlist or timing closure yet for the GF 22 nm FDX target. | ASIC deliverable not yet started. | [ARCHITECTURE scorecard](../ARCHITECTURE.md#maturity-scorecard) |

<!-- Add new rows above. Keep IDs stable; do not renumber on removal. -->
