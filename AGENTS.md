# Agent Instructions

Repository-wide instructions for AI coding agents working on this project.
These rules are tool-neutral and apply to Codex, Gemini, Copilot, and other
agents.

## Project Context

This repository implements a systolic-array based AI accelerator for the
Edu4Chip Didactic SoC. Prioritize RTL correctness, interface consistency, and
integration readiness for FPGA first, then ASIC flow.

Important project references:
- `README.md`: setup, team ownership, and milestones.
- `docs/interface/`: source of truth for module interfaces.
- `docs/GITLAB_ISSUE_LINKING.md`: GitLab branch, issue, and MR workflow.
- `docs/SoC Documentation.md`: Didactic SoC platform notes.
- `docs/Slides Kick Off.md`: course timeline, deliverables, and expectations.
- `.gitlab/issue_templates/` and `.gitlab/merge_request_templates/`: issue and
  MR structure.

## Architecture And Ownership

Treat these RTL areas as independent modules with clear ownership boundaries:
- `rtl/control/`: control logic and status/control.
- `rtl/MAC/`: MAC unit.
- `rtl/array/`: systolic array.
- `rtl/matrix/`: Matrix A, Matrix B, and Matrix C buffering.
- `rtl/top/`: top-level integration.

Keep cross-module coupling minimal. Prefer explicit ports and stable handshake
signals instead of hidden assumptions. For cross-owner or cross-module edits,
keep changes small and document the reason in commit or MR text.

## Interface-First Rule

`docs/interface/` defines the module interfaces and should be treated as the
source of truth.

Before adding or changing RTL interfaces:
- Update the matching interface document in `docs/interface/`.
- Align naming, widths, reset behavior, and handshake semantics with the
  interface document.
- Do not silently invent missing protocol details. Add a `TODO` and request
  clarification when details are ambiguous.

Current interface documents:
- `docs/interface/control_unit_if.md`
- `docs/interface/mac_if.md`
- `docs/interface/matrix_buffer_a_b_if.md`
- `docs/interface/systolic_array_if.md`

## RTL Coding Expectations

- Keep RTL synthesizable and deterministic.
- Use parameters for bus widths, data widths, depths, and dimensions where
  practical.
- Avoid unexplained magic numbers.
- Keep reset behavior explicit and consistent within each module.
- Separate control-path and datapath logic where it improves readability and
  verification.
- Use `rtl/include/` for shared constants and macros.
- Preserve signed arithmetic semantics in MAC and array datapaths.
- Prefer valid/ready handshakes for streaming module boundaries.

## Development And Verification Flow

For functional RTL changes, follow this sequence:

1. Update RTL under `rtl/`.
2. Create or update the Python golden/reference model.
3. Add or update cocotb testbenches under `sim/testbenches/`.
4. Run Verilator simulation through scripts under `sim/scripts/`.
5. Confirm CI expectations before merge.

Keep simulation scripts in `sim/scripts/` and waveform-related files in
`sim/waves/` when needed. Keep FPGA constraints/project files under
`fpga/constraints/` and `fpga/vivado_project/`. Keep ASIC scripts/reports under
`asic/scripts/` and `asic/reports/`.

## Documentation Sync

For behavior changes affecting interfaces, registers, module scope, or team
coordination:
- Update `docs/interface/`.
- Update `README.md` when setup, scope, milestones, or ownership expectations
  change.
- Keep documentation concise and factual.

## GitLab Workflow

Use issue-linked branches and MRs.

Branch naming:
- Prefer `{issue_number}-{short-description}`, for example
  `3-systolic-array-stall-logic`.

MR descriptions:
- Use `Closes #N`, `Fixes #N`, or `Resolves #N` when the MR completes an issue.
- Use `Relates to #N`, `Blocks #N`, or `Blocked by #N` when the relationship is
  non-closing.
- Include verification evidence for RTL changes.

Use GitLab templates from `.gitlab/` when creating issues and merge requests.

## GitLab CLI

Use `glab` for GitLab issue, MR, CI, and repository automation when available.

Common commands:
- `glab auth status`
- `glab repo view`
- `glab issue list -A -P 100 -O json`
- `glab issue view <IID>`
- `glab mr create`

For the LRZ GitLab host, use `gitlab.lrz.de`. If remotes use a different SSH
hostname than the API host, pass `-R OWNER/REPO` or configure the host in
`glab`.

## Agent Behavior

- Make minimal, reviewable patches.
- Do not refactor unrelated modules in the same change.
- Do not change source branches when copying selected files from another branch.
- Preserve user or teammate changes already present in the worktree.
- Ask before running destructive commands or long-running build flows.
- When build or test commands are undocumented, inspect the repo first and use
  the narrowest relevant command.
- Keep personal coding style preferences out of repository files unless the
  team agrees.

## Source Guidance Consolidated

This file consolidates agent-facing guidance from:
- `GEMINI.md`
- `.github/copilot-instructions.md`
- `.github/skills/glab-cli/SKILL.md`
- `README.md`
- `docs/GITLAB_ISSUE_LINKING.md`
- `docs/interface/README.md`
- GitLab issue and merge request templates under `.gitlab/`
