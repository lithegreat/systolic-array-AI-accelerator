---
name: glab-ci
user-invocable: true
description: "Use glab to inspect failed GitLab CI pipelines, fetch failed job logs, fix the cause, push, and verify the rerun."
---

# glab CI Repair Workflow

Use this skill when a GitLab CI pipeline fails and the task is to diagnose and
fix it from the command line.

## Preconditions

- Work from the branch with the failing pipeline.
- Confirm the worktree state first:

```bash
git status --short --branch
```

- Confirm GitLab API access:

```bash
glab auth status
```

If `glab` cannot resolve or reach `gitlab.lrz.de`, retry with normal network
access rather than guessing from local state.

## Find The Failed Pipeline

List recent pipelines for the current branch:

```bash
glab ci list --ref "$(git branch --show-current)" --output json --per-page 5
```

For failed pipelines only:

```bash
glab ci list --ref "$(git branch --show-current)" --status failed --output json
```

Record the failing pipeline `id`, `sha`, and `web_url`.

## Inspect Failed Jobs

List jobs for the pipeline. If the project id is not known, get it from
`glab repo view` or from the pipeline JSON.

```bash
glab api projects/<project_id>/pipelines/<pipeline_id>/jobs
```

Find jobs where `"status":"failed"`. Record each failed job `id`, `name`, and
`failure_reason`.

Fetch the failed job trace:

```bash
glab ci trace <job_id>
```

Read the last meaningful error lines first, then scan upward for the command
that produced the failure.

## Fix Locally

- Reproduce the failing command locally when practical.
- Patch the smallest relevant file.
- Run the same command locally after the fix.
- If another CI job checks formatting, run the matching local check too.

For this repository, common CI commands are:

```bash
python3 scripts/check_conventions.py
ruff format --check .
```

If `ruff` is not installed locally, either install project requirements in the
active environment or format changes manually to match Ruff format output.

## Commit And Push

Commit only the CI fix and directly related files:

```bash
git status --short
git diff --stat
git add <fixed-files>
git commit -m "fix: <short ci failure cause>"
git push
```

Do not mix unrelated cleanup into the CI fix commit.

## Verify The Rerun

After pushing, check the newest pipeline for the branch:

```bash
glab ci list --ref "$(git branch --show-current)" --output json --per-page 1
```

If it is still running, poll until it reaches `success` or `failed`.

If it fails again:

1. Fetch the new failed job list.
2. Fetch the new failed job trace.
3. Fix the next root cause.
4. Push another focused commit.

Stop only when the newest pipeline for the branch is `success`, or when the
failure is blocked by missing credentials, unavailable infrastructure, or a
decision that needs a maintainer.
