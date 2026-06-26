# Agent Instructions

This file is a **map, not an encyclopedia**. It is the small, stable entry point
injected into every agent's context; the durable source of truth lives in
[`docs/`](docs/README.md) and is reached by **progressive disclosure** — start
here, then follow the links. Keep this file ~100 lines: when something needs more
than a couple of lines, put it in `docs/` and link it.

Applies to all AI agents (Codex, Gemini, Copilot, Claude, …). It is the **only**
agent-instruction file in this repo (see *How agents load this file* below).

## Mission

A systolic-array AI accelerator for the Edu4Chip Didactic SoC. Optimize, in
priority order, for **RTL correctness → interface consistency → integration
readiness** (FPGA first, then ASIC). Deliver minimal, reviewable, well-scoped
patches.

## Start here (progressive disclosure)

| Need | Go to |
| --- | --- |
| How the system is built, what's mature, where the gaps are | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| The full documentation index (system of record) | [docs/README.md](docs/README.md) |
| A module's ports / protocol (**source of truth**) | [docs/interface/](docs/interface/README.md) |
| Plans, decision logs, tech debt | [docs/plans/](docs/plans/README.md) |
| Build / run / lab procedures | [docs/guides/](docs/guides/) |
| UVM testbench for `accelerator_top` | [docs/verification/accel_uvm_tb.md](docs/verification/accel_uvm_tb.md) |
| Setup, milestones, team ownership | [README.md](README.md) |

## Operating loop

Run every task through this loop; do not skip verification.

1. **Orient** — read the relevant interface doc and code first. `docs/interface/`
   is the source of truth; never guess a protocol.
2. **Plan** — small change: a short inline checklist. Complex/multi-session work:
   open an execution plan in [docs/plans/active/](docs/plans/README.md) and keep
   its progress + decision logs current.
3. **Implement** — interface-first; keep the change scoped to one concern.
4. **Verify** — run the narrowest matching gate (below) and fix until green.
   Never hand back RTL or sim changes you have not run.
5. **Close** — sync the affected `docs/`, then commit / open an MR with
   verification evidence.

When details are ambiguous, do not invent them: add a `TODO` and ask.

## Golden rules

- **Interface-first**: update the matching `docs/interface/<module>_if.md`
  *before* changing an RTL boundary (naming, widths, reset, handshake).
- **Docs are the system of record**: if a design fact, protocol, or decision
  matters, write it in `docs/` — not only in a commit message or chat.
- **Plans are first-class**: complex work is tracked in `docs/plans/`, committed.
- **Minimal patches**: don't refactor unrelated modules in the same change; don't
  discard teammates' in-progress work.
- **RTL**: synthesizable, deterministic, explicit reset, signed-arithmetic safe,
  parameters over magic numbers, valid/ready at streaming boundaries.

## Verification gates

Activate the venv first so the `ruff` pre-commit hook runs:
`source .venv/bin/activate`. CI (`.gitlab-ci.yml`) runs them all; locally run the
narrowest gate covering your change.

- **Setup (once)**: `python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements/check.txt -r requirements/sim.txt && pre-commit install`
- **Format / lint**: `ruff format --check .` and `ruff check .`
- **Repo + docs conventions**: `python3 scripts/check_conventions.py`,
  `python3 scripts/check_docs.py`, `python3 scripts/check_gitkeep.py`
- **Standalone accel sim (Verilator)**: `./sim/scripts/run_verilator.sh`
- **cocotb regression**: `pytest -vv sim/test_runner.py`
- **Full-SoC functional sim**: `cd Didactic-SoC && make verilate_accel`
  (PASS = `accel_result == 0xACCE5500`)
- **Regenerate golden vectors**: `python3 sim/common/c_code/gen_accel_data.py`
- **Full-SoC QuestaSim** (lab server, Mentor license): `bash scripts/lab_server_sim.sh accel`

## GitLab workflow

Issue-linked branches (`{issue}-{slug}`) and MRs; use `glab` for automation
(host `gitlab.lrz.de`). MRs close issues with `Closes #N` and carry verification
evidence. Full workflow and CI-failure triage:
[docs/guides/gitlab_workflow.md](docs/guides/gitlab_workflow.md) and the `glab-ci`
skill at `.agents/skills/glab-ci/SKILL.md`.

## Guardrails

- Take local, reversible actions (edit, sim, lint) freely.
- **Confirm before** destructive or shared-infra actions: deleting files/
  branches, `git push --force`, history rewrites, dropping data. Never bypass
  safety checks (e.g. `--no-verify`).
- Keep personal style preferences out of repo files unless the team agrees.

## How agents load this file

`AGENTS.md` is the **only** agent-instruction file here. Do **not** add per-tool
files (`.github/copilot-instructions.md`, `CLAUDE.md`, `GEMINI.md`) — they
duplicate this and drift. Update `AGENTS.md` (and `docs/`) instead.

- **GitHub Copilot / VS Code**: enable `chat.useAgentsMdFile: true` to load this
  file directly as always-on instructions.
- **Codex, Gemini, Claude, other AGENTS.md-aware tools**: read automatically from
  the repo root.
