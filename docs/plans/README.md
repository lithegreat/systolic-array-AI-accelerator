# Plans

Plans are **first-class, version-controlled artifacts**. They let an agent (or a
teammate) pick up complex work without external context: the intent, the steps,
the progress, and the decisions all live in the repo.

Last reviewed: 2026-06-13

## When to write a plan

- **Small / lightweight change** — no plan file. Use a short inline checklist in
  the MR description and just do the work.
- **Complex or multi-session work** (cross-module, risky, or spanning several
  steps) — create an **execution plan** under `active/`, keep it updated as you
  go, and move it to `completed/` when done.

If you are unsure, err toward writing a plan: a stale plan is cheaper than lost
context.

## Lifecycle

```
active/<n>-<slug>.md   ──(work proceeds, log kept)──>   completed/<n>-<slug>.md
        │
        └── spawns/【records known shortcuts】──> tech-debt.md
```

1. **Open**: copy [`_template.md`](_template.md) to
   `active/<issue-or-seq>-<short-slug>.md` (e.g. `3-array-stall-logic.md`).
2. **Work**: keep the *Progress log* and *Decision log* current — append, don't
   rewrite history. Update `Last reviewed:` each session.
3. **Close**: set status to `Completed`, then `git mv` it to `completed/`.
4. **Spill-over**: anything deferred goes to [tech-debt.md](tech-debt.md) with a
   back-link to the plan.

## Conventions

- One concern per plan. Filenames: `snake`/`kebab` lowercase, prefixed with the
  issue number or a sequence number.
- Every plan carries a `Last reviewed: YYYY-MM-DD` line (the docs linter checks
  active plans for it).
- Link the plan from its MR, and link the MR/issue from the plan.

## Index

- **Active**: see [`active/`](active/) (empty = nothing in flight).
- **Completed**: see [`completed/`](completed/) (the decision-log archive).
- **Tech debt**: [tech-debt.md](tech-debt.md).
