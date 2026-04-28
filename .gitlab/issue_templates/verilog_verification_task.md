## Verification Task Summary

<!-- What behavior or module must be verified -->

## Branch Naming

**Create branch as:** `git checkout -b 101-verification-description`

→ GitLab auto-links branch to this issue

## Verification Target

- DUT module/path:
- Spec/interface reference:
- Priority: low | medium | high

## Test Strategy

- [ ] Directed tests
- [ ] Randomized tests
- [ ] Corner cases (reset/overflow/stall/backpressure)
- [ ] Assertions

## Testbench Details

- Testbench file: sim/testbenches/
- Stimulus source:
- Scoreboard/checks:
- Coverage goal (if used):

## Pass/Fail Criteria

- [ ] Deterministic pass criteria defined
- [ ] Expected latency/timing windows defined
- [ ] Error reporting added for debug

## Deliverables

- [ ] Testbench committed
- [ ] Script updates in sim/scripts/
- [ ] Wave setup in sim/waves/ (if needed)
- [ ] Results attached in issue/MR

## Quick Actions (optional)

/label ~"type::task" ~"domain::verification" ~"status::ready"
/cc @team