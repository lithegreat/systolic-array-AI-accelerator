#!/usr/bin/env python3
"""
Lint the docs/ knowledge base (the project's system of record).

Enforces three properties so the docs stay trustworthy and navigable:

  1. Structure   — the required index / architecture / plans files and the
                   guides|reference|verification|interface areas all exist.
  2. Cross-links — every relative Markdown link inside docs/ (plus AGENTS.md and
                   README.md) resolves, and every doc is reachable (linked from
                   somewhere, directly or via a link to its directory).
  3. Freshness   — living documents carry a parseable `Last reviewed: YYYY-MM-DD`
                   marker so staleness is visible.

Exit 0 on success, 1 if any violation is found. Files whose name starts with
`_` (e.g. `_template.md`) are treated as templates and skipped.
"""

import re
import sys
from datetime import date
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DOCS = REPO_ROOT / "docs"

# 1. Structure: these must exist (files or directories).
REQUIRED_PATHS = [
    "docs/README.md",
    "docs/ARCHITECTURE.md",
    "docs/interface/README.md",
    "docs/plans/README.md",
    "docs/plans/tech-debt.md",
    "docs/plans/active",
    "docs/plans/completed",
    "docs/guides",
    "docs/reference",
    "docs/verification",
]

# 3. Freshness: these living docs (plus every docs/plans/active/*.md) must carry
#    a `Last reviewed: YYYY-MM-DD` marker.
FRESHNESS_FILES = [
    "docs/ARCHITECTURE.md",
    "docs/plans/README.md",
    "docs/plans/tech-debt.md",
]

# The index itself does not need to be linked from elsewhere.
ORPHAN_EXEMPT = {"docs/README.md"}

LINK_RE = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
FRESH_RE = re.compile(r"^Last reviewed:\s*(\d{4}-\d{2}-\d{2})\s*$", re.MULTILINE)


def is_template(path: Path) -> bool:
    return path.name.startswith("_")


def is_external(target: str) -> bool:
    return target.startswith(("http://", "https://", "mailto:", "tel:"))


def rel(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def main() -> int:
    errors: list[str] = []

    if not DOCS.is_dir():
        print("ERROR: docs/ directory is missing.")
        return 1

    # ---- 1. Structure ----------------------------------------------------
    for required in REQUIRED_PATHS:
        if not (REPO_ROOT / required).exists():
            errors.append(f"missing required path: {required}")

    # ---- 2. Cross-links --------------------------------------------------
    # Sources: every docs Markdown file plus the two root entry points.
    sources = sorted(DOCS.rglob("*.md")) + [
        REPO_ROOT / "AGENTS.md",
        REPO_ROOT / "README.md",
    ]
    linked_targets: set[str] = set()

    for md in sources:
        if not md.exists() or is_template(md):
            continue
        text = md.read_text(encoding="utf-8")
        for raw in LINK_RE.findall(text):
            target = raw.strip()
            if is_external(target) or target.startswith("#"):
                continue
            path_part = target.split("#", 1)[0]
            if not path_part:
                continue
            resolved = (md.parent / path_part).resolve()
            try:
                resolved_rel = resolved.relative_to(REPO_ROOT).as_posix()
            except ValueError:
                # Link points outside the repo; ignore.
                continue
            linked_targets.add(resolved_rel)
            if (
                resolved_rel.startswith("Didactic-SoC/")
                and not (REPO_ROOT / "Didactic-SoC" / "Makefile").exists()
            ):
                continue
            if not resolved.exists():
                errors.append(f"dead link in {rel(md)}: '{raw}'")

    # Orphan check: each doc must be linked directly, or via a link to its
    # containing directory (which indexes it).
    for md in sorted(DOCS.rglob("*.md")):
        if is_template(md):
            continue
        md_rel = rel(md)
        if md_rel in ORPHAN_EXEMPT:
            continue
        parent_rel = rel(md.parent)
        if md_rel in linked_targets or parent_rel in linked_targets:
            continue
        errors.append(f"orphaned doc (not linked anywhere): {md_rel}")

    # ---- 3. Freshness ----------------------------------------------------
    freshness_targets = [REPO_ROOT / p for p in FRESHNESS_FILES]
    freshness_targets += sorted((DOCS / "plans" / "active").glob("*.md"))
    for md in freshness_targets:
        if not md.exists() or is_template(md):
            continue
        match = FRESH_RE.search(md.read_text(encoding="utf-8"))
        if not match:
            errors.append(f"missing 'Last reviewed: YYYY-MM-DD' marker in {rel(md)}")
            continue
        try:
            date.fromisoformat(match.group(1))
        except ValueError:
            errors.append(f"invalid review date in {rel(md)}: {match.group(1)}")

    # ---- Report ----------------------------------------------------------
    if errors:
        print("ERROR: docs knowledge-base checks failed:")
        for err in errors:
            print(f"  - {err}")
        print(
            "\nFix dead/orphaned links, restore the required structure, or add the "
            "'Last reviewed:' marker. See docs/README.md for the conventions."
        )
        return 1

    print("OK: docs structure, cross-links, and freshness markers are valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
