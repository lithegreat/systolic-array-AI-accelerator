#!/usr/bin/env python3
"""yosys_shim.py -- formal-verification-only preprocessing shim.

Yosys's built-in Verilog/SystemVerilog frontend (`read_verilog -sv`) does not
parse the `module foo import pkg::*; #(...) (...);` header-import syntax used
throughout this project's RTL (rtl/control/control_unit.sv,
rtl/matrix/matrix_buffer_*.sv, rtl/top/accelerator_top.sv). Verilator and
commercial tools accept it fine; only Yosys's parser rejects it.

This script:
  1. rewrites `import pkg::*;` out of the module header and hoists it to
     compilation-unit scope (before the `module` keyword), which Yosys does
     accept. This is a syntactic no-op for our single-file formal harnesses.
  2. optionally splices an SVA property-body fragment in just before the
     module's final `endmodule`, so properties can reference the module's
     internal signals directly (Yosys's frontend doesn't wire up
     hierarchical `dut.<signal>` references into a sibling instance's
     internals -- only real module ports resolve correctly that way, so
     splicing into the same module body is used instead of a bound/
     instantiated checker module).

Never touches anything under rtl/ -- it only produces a throwaway copy
inside the SymbiYosys work directory.

Usage: yosys_shim.py <src.sv> <dst.sv> [properties_fragment.svh]
"""
import re
import sys

IMPORT_RE = re.compile(r'^[ \t]*import\s+\w+::\*\s*;[ \t]*\r?\n', re.M)
MODULE_RE = re.compile(r'^module\b', re.M)
ENDMODULE_RE = re.compile(r'^endmodule\b.*$', re.M)


def main() -> int:
    if len(sys.argv) not in (3, 4):
        print(__doc__, file=sys.stderr)
        return 1

    src, dst = sys.argv[1], sys.argv[2]
    with open(src, encoding="utf-8") as f:
        text = f.read()

    imports = IMPORT_RE.findall(text)
    if imports:
        text = IMPORT_RE.sub("", text)
        text = MODULE_RE.sub("".join(imports) + "module", text, count=1)

    if len(sys.argv) == 4:
        with open(sys.argv[3], encoding="utf-8") as f:
            props = f.read()
        matches = list(ENDMODULE_RE.finditer(text))
        if not matches:
            print(f"error: no 'endmodule' found in {src}", file=sys.stderr)
            return 1
        last = matches[-1]
        text = text[: last.start()] + props + "\n" + text[last.start():]

    with open(dst, "w", encoding="utf-8") as f:
        f.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

