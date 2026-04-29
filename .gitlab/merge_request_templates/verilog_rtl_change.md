## Issue Link

<!-- Branch should be named: {issue_number}-{description} for auto-detection -->

Closes #

## RTL Change Summary

<!-- What RTL changed and why -->

## Modified Areas

- [ ] rtl/control/
- [ ] rtl/MAC/
- [ ] rtl/array/
- [ ] rtl/matrix/
- [ ] rtl/top/
- [ ] rtl/include/

## Behavioral Impact

- [ ] Bug fix
- [ ] Functional enhancement
- [ ] Refactor only (no functional change)

## Interface Impact

- [ ] No interface changes
- [ ] Interface changes included and documented in docs/interface/

## Verification Evidence

- [ ] Target testbench(es) updated in sim/testbenches/
- [ ] Simulation script(s) updated in sim/scripts/ if needed
- [ ] Regression run completed
- [ ] Waveforms/logs attached for key scenarios

### Commands run

```bash
# Example
# make -C sim/scripts <target>
```

## Synthesis/Implementation Checks

- [ ] Synthesizable constructs only
- [ ] No unintended latches/combinational loops
- [ ] Timing/resource impact reviewed (if available)

## Reviewer Checklist

- [ ] Reset behavior is explicit and consistent
- [ ] Control/datapath separation remains readable
- [ ] Cross-module assumptions are documented

## Quick Actions (optional)

/label ~"domain::rtl" ~"workflow::ready-for-review"
/assign_reviewer @reviewer