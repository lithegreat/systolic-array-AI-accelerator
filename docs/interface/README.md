# Interface Documentation

Module interface contracts — the **source of truth** for every RTL boundary. Update
the matching `_if.md` here *before* changing a module's ports, widths, reset, or
handshake.

## Documents

| Module | Spec | Owner |
| --- | --- | --- |
| Accelerator top (APB subsystem wrapper) | [accelerator_top_if.md](accelerator_top_if.md) | shared |
| Control unit (registers + FSM) | [control_unit_if.md](control_unit_if.md) | Li (#1) |
| MAC processing element | [mac_if.md](mac_if.md) | Liu (#2) |
| Systolic array (M×N PE grid) | [systolic_array_if.md](systolic_array_if.md) | Zhong (#3) |
| Matrix A &amp; B buffer | [matrix_buffer_a_b_if.md](matrix_buffer_a_b_if.md) | Cao (#4) |
| Matrix C buffer | [matrix_buffer_c_if.md](matrix_buffer_c_if.md) | Shang (#5) |

## Conventions

**Filenames** — lowercase `snake_case` with the `_if.md` suffix; underscores only
(no spaces, `&`, or mixed case). Enforced by `scripts/check_conventions.py`.

**Shared template** — every spec follows the same section order so they read the
same way:

1. Title + one-line summary (blockquote)
2. Metadata bullets — **Module**, **Source**, **Owner**
3. `## Overview`
4. `## Block diagram` (Mermaid)
5. `## Parameters` (table)
6. `## Ports` (tables, grouped by interface)
7. `## Register map` (table — only for APB-mapped modules)
8. `## Behavior` (operation, FSM, packing, timing, …)
9. `## Notes` (caveats, assumptions, v1 limitations)

Copy an existing spec (e.g. [mac_if.md](mac_if.md)) as the starting point for a new
module so the format stays consistent.
- [accelerator top](accelerator_top_if.md)