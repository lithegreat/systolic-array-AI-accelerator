## Bug Summary

<!-- Short description of incorrect RTL behavior -->

## Affected Module(s)

- [ ] rtl/control/
- [ ] rtl/MAC/
- [ ] rtl/array/
- [ ] rtl/matrix/
- [ ] rtl/top/

## Expected vs Actual Behavior

### Expected

<!-- What should happen -->

### Actual

<!-- What happens now -->

## Reproduction

### Simulation setup

- Testbench: sim/testbenches/
- Script/command: sim/scripts/
- Seed (if randomized):

### Minimal stimulus

1.
2.
3.

## Suspected Root Cause

<!-- Optional hypothesis -->

## Interface/Protocol Impact

- [ ] No interface changes expected
- [ ] Handshake/control timing issue
- [ ] Width/packing mismatch
- [ ] Reset behavior mismatch

## Fix Acceptance Criteria

- [ ] Bug reproduced in testbench before fix
- [ ] Failing test now passes
- [ ] No regression in related testbenches
- [ ] docs/interface_definition.md updated if interface behavior changed

## Evidence

- Waveform:
- Log excerpt:
- Commit/MR:

## Quick Actions (optional)

/label ~"type::bug" ~"domain::rtl" ~"status::triage"
/cc @team