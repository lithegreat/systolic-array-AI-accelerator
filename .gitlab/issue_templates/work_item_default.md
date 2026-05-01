<!--
Use this template for general issues, tasks, improvements, documentation,
tooling, CI, and service desk tickets.
For epics, copy this template to the group-level templates location.
-->

## Summary

<!-- One-sentence description of the work item -->

## Work Type

- [ ] Bug
- [ ] Feature
- [ ] Improvement
- [ ] Refactor
- [ ] Documentation
- [ ] Tooling/CI
- [ ] Verification/simulation
- [ ] Maintenance/chore

## Area

- [ ] RTL
- [ ] Verification/simulation
- [ ] Documentation
- [ ] Tooling/CI
- [ ] Project/process
- [ ] Other:

## Branch Naming

**Recommended:** `git checkout -b {issue_number}-description`

GitLab auto-links branches that start with the issue number.

## Problem Statement

<!-- What problem are we solving and why now? -->

## Scope

### In scope

-

### Out of scope

-

## Acceptance Criteria

- [ ]
- [ ]
- [ ]

## Implementation Notes

<!-- Relevant context, design notes, scripts, docs, or architecture/interface details -->

## Verification Plan

- [ ] Not needed; reason:
- [ ] Add or update tests in `sim/testbenches/`
- [ ] Verify interface behavior against `docs/interface/`
- [ ] Run relevant tooling/CI command:
- [ ] Include wave/script/log references if applicable

## Risks And Dependencies

-

## Quick Actions (optional)

/label ~"type::feature" ~"status::triage"
/cc @team

<!-- Examples:
/assign @username
/milestone %"Milestone Name"
/due in 2 weeks
/weight 3
/estimate 2d
-->
