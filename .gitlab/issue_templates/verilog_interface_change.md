## Interface Change Request

<!-- Describe the interface behavior or signal changes -->

## Scope

- [ ] Control/status interface
- [ ] MAC unit interface
- [ ] Systolic array interface
- [ ] Matrix A/B/C interface
- [ ] Top-level integration interface

## Current Interface

<!-- Reference current ports/protocol from docs/interface_definition.md -->

## Proposed Interface

<!-- Add/remove/rename signals, width changes, timing/handshake behavior -->

## Compatibility Plan

- [ ] Backward compatible
- [ ] Requires coordinated updates across modules
- [ ] Requires firmware/software driver changes

## Verification Plan

- [ ] Interface assertions/checkers updated
- [ ] Integration testbench updated in sim/testbenches/
- [ ] Top-level simulation demonstrates compatibility

## Documentation Plan

- [ ] Update docs/interface_definition.md before/with implementation
- [ ] Update README.md if milestone/scope is affected

## Approval Checklist

- [ ] Module owners aligned
- [ ] Cross-module assumptions documented

## Quick Actions (optional)

/label ~"type::change" ~"domain::interface" ~"status::needs-discussion"
/cc @team