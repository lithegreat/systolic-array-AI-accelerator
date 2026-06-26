# Documentation — System of Record

This `docs/` tree is the project's **system of record**: the durable, deep source
of truth. [`AGENTS.md`](../AGENTS.md) at the repo root is only a ~100-line *map*;
everything authoritative lives here and is reached by **progressive disclosure** —
start at this index, then follow the link into the area you need.

If a fact about the design, a protocol, a workflow, or a decision matters, it
belongs in one of these files (not buried in a commit message or chat log).

## Map

| Area | Path | What it holds |
| --- | --- | --- |
| Architecture | [ARCHITECTURE.md](ARCHITECTURE.md) | Top-level domain/layer map, per-area maturity scorecard, and tracked gaps. **Start here** to understand the system. |
| Interfaces | [interface/README.md](interface/README.md) | Module interface contracts (ports, widths, reset, handshakes). **The source of truth** for every RTL boundary. |
| Plans | [plans/README.md](plans/README.md) | First-class planning artifacts: active execution plans, completed plans with decision logs, and the tech-debt register. |
| Guides | [guides/](guides/) | How-to workflow docs (GitLab/MR workflow, lab-server examples). |
| Reference | [reference/](reference/) | Platform and course reference material (Didactic SoC platform, course kick-off). |
| Verification | [verification/](verification/) | Verification and bring-up reports; UVM testbench guide. |

## Directory layout

```
docs/
├── README.md                 # this index (system-of-record map)
├── ARCHITECTURE.md           # domain/layer map + maturity scorecard + gaps
├── interface/                # module interface contracts (source of truth)
│   ├── README.md
│   └── *_if.md
├── plans/                    # plans as first-class, version-controlled artifacts
│   ├── README.md             # plan lifecycle + conventions
│   ├── active/               # in-progress execution plans (one file per plan)
│   ├── completed/            # archived plans (kept for the decision log)
│   └── tech-debt.md          # known technical debt register
├── guides/                   # how-to / workflow docs
│   ├── benchmark.md          # GEMM benchmark guide & analysis
│   ├── io_bottleneck_solutions.md  # comparative analysis of I/O bottleneck fixes
│   ├── gitlab_workflow.md
│   └── lab_server_examples.md
├── reference/                # platform & course reference material
│   ├── soc_platform.md       # Didactic SoC platform notes
│   └── course_kickoff.md     # course timeline, deliverables, expectations
└── verification/             # verification & bring-up reports
    └── accelerator_soc_report.md
```

## Conventions

- **Filenames**: lowercase `snake_case`. Interface specs use the `_if.md` suffix
  (enforced by `scripts/check_conventions.py`).
- **Cross-linking**: every doc is reachable from this index or from
  [ARCHITECTURE.md](ARCHITECTURE.md). Use relative links; the docs linter
  (`scripts/check_docs.py`) fails the build on dead links or orphaned files.
- **Freshness**: living documents (`ARCHITECTURE.md`, `plans/tech-debt.md`, each
  active plan) carry a `Last reviewed: YYYY-MM-DD` line near the top. Update it
  whenever you touch the file; the linter requires the marker.
- **Keep it factual and concise.** Prefer updating an existing doc over adding a
  near-duplicate.

## Where do I put …?

| If you are documenting… | Put it in… |
| --- | --- |
| A new/changed RTL interface | `interface/<module>_if.md` (update first) |
| How the system is structured or a maturity gap | `ARCHITECTURE.md` |
| A multi-step piece of work you are starting | `plans/active/<n>-<slug>.md` |
| A piece of work you finished | move its plan to `plans/completed/` |
| A shortcut/hack/known limitation | `plans/tech-debt.md` |
| A repeatable procedure (build/run/lab) | `guides/` |
| Vendor/course material for context | `reference/` |
| Test results / sign-off evidence | `verification/` |
