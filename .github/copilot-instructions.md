# Project Guidelines

## Layering Model
- This file is the team layer and contains repository-wide, shared rules only.
- Personal preferences should live in a user profile `.instructions.md` file, not in this repository.
- If team and personal instructions conflict, keep repository correctness and interface consistency as the priority for this project.

## Project Context
- This repository implements a systolic array based AI accelerator for the Edu4Chip Didactic SoC.
- Prioritize RTL correctness, interface consistency, and integration readiness for FPGA first, then ASIC flow.
- Follow milestone intent in README: interface clarity first, then implementation, test definition, and demo readiness.

## Architecture And Ownership
- Treat the following top-level RTL areas as independent modules with clear boundaries:
  - `rtl/control/`
  - `rtl/MAC/`
  - `rtl/array/`
  - `rtl/matrix/`
  - `rtl/top/`
- Keep cross-module coupling minimal. Prefer explicit ports and stable handshake signals instead of hidden assumptions.
- Respect module ownership from README issues:
  - Control logic and status/control
  - MAC unit
  - Systolic array
  - Matrix A and Matrix B
  - Matrix C
- For cross-owner edits, keep changes small and document rationale in commit/PR text.

## Interface-First Rule
- `docs/interface_definition.md` is the source of truth for module interfaces.
- Before adding or changing RTL interfaces, update and align the interface definition with the team.
- If interface details are missing or ambiguous, do not invent protocol details silently. Add a TODO note and request clarification.

## RTL Coding Expectations
- Keep RTL synthesizable and deterministic.
- Use parameterized widths where practical; avoid hard-coded magic numbers for bus width/depth.
- Keep reset behavior explicit and consistent within each module.
- Separate control-path and datapath logic when possible to improve readability and verification.
- For shared constants/macros, prefer files in `rtl/include/`.

## Verification And Deliverables
- Add or update matching testbenches under `sim/testbenches/` for functional changes.
- Place simulation scripts in `sim/scripts/` and waveform artifacts/config in `sim/waves/` when needed.
- Keep FPGA constraints and project-specific files under `fpga/constraints/` and `fpga/vivado_project/`.
- Keep ASIC scripts/reports under `asic/scripts/` and `asic/reports/`.

## Documentation Sync
- For behavior changes affecting interfaces, update both:
  - `docs/interface_definition.md`
  - `README.md` if scope, milestone impact, or team coordination expectations change
- Prefer concise, factual updates over long narrative text.

## Agent Behavior
- Propose minimal, reviewable patches.
- Do not refactor unrelated modules in the same change.
- If build/test commands are not documented yet, ask before running destructive or long-running flows.
- Keep personal coding style preferences out of this file unless the whole team agrees.
