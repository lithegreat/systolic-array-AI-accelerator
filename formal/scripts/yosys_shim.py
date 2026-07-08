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
     instantiated checker module). Only the text between the
     __FORMAL_PROPS_BEGIN__/__FORMAL_PROPS_END__ marker comments in the
     properties fragment is spliced -- the fragment wraps that text in its
     own throwaway module shell so it is also valid, self-contained
     SystemVerilog when opened directly in an editor/linter; that shell is
     discarded here and never reaches Yosys.

Never touches anything under rtl/ -- it only produces a throwaway copy
inside the SymbiYosys work directory.

Usage: yosys_shim.py <src.sv> <dst.sv> [properties_fragment.svh]
"""

import re
import sys

IMPORT_RE = re.compile(r"^[ \t]*import\s+\w+::\*\s*;[ \t]*\r?\n", re.M)
MODULE_RE = re.compile(r"^module\b", re.M)
ENDMODULE_RE = re.compile(r"^endmodule\b.*$", re.M)
PROPS_BEGIN_RE = re.compile(r"^[ \t]*//[ \t]*__FORMAL_PROPS_BEGIN__", re.M)
PROPS_END_RE = re.compile(r"^[ \t]*//[ \t]*__FORMAL_PROPS_END__", re.M)


def extract_props(props_text: str) -> str:
    """Return only the text between the BEGIN/END marker comments.

    control_unit_formal.svh (and similar fragments) wrap their real
    property content in a throwaway module shell so the file is valid,
    self-contained SystemVerilog for editors/linters. That shell must not
    leak into the real splice, so pull out just the marked region. Only
    matches markers that start a `//` comment line (not mere mentions of
    the marker names in prose elsewhere in the file). Falls back to the
    whole text if no markers are present, for fragments that don't need a
    lint shell.
    """
    begin_m = PROPS_BEGIN_RE.search(props_text)
    end_m = PROPS_END_RE.search(props_text)
    if begin_m is None or end_m is None:
        return props_text
    start = props_text.find("\n", begin_m.end()) + 1
    end = end_m.start()
    return props_text[start:end]


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
            props = extract_props(f.read())
        matches = list(ENDMODULE_RE.finditer(text))
        if not matches:
            print(f"error: no 'endmodule' found in {src}", file=sys.stderr)
            return 1
        last = matches[-1]
        text = text[: last.start()] + props + "\n" + text[last.start() :]

    with open(dst, "w", encoding="utf-8") as f:
        f.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
