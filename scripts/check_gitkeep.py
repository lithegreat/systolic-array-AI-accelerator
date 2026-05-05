#!/usr/bin/env python3
"""
Check that any folder containing a .gitkeep file contains ONLY .gitkeep.

If a folder has .gitkeep alongside other files or sub-directories, it means
.gitkeep was not removed after real content was added, which is a mistake.

Exit 0 on success, 1 if violations are found.
"""

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# Directories that are never walked (build artifacts, virtual envs, etc.)
SKIP_DIRS = {".git", ".venv", "__pycache__", "sim_build", "node_modules"}


def check_gitkeep(root: Path) -> list[str]:
    violations: list[str] = []

    for gitkeep in root.rglob(".gitkeep"):
        folder = gitkeep.parent

        # Skip if any ancestor is in SKIP_DIRS
        if any(part in SKIP_DIRS for part in folder.parts):
            continue

        siblings = [p for p in folder.iterdir() if p.name != ".gitkeep"]
        if siblings:
            rel_folder = folder.relative_to(root)
            sibling_names = ", ".join(sorted(p.name for p in siblings))
            violations.append(
                f"  {rel_folder}/ — contains .gitkeep together with: {sibling_names}"
            )

    return violations


def main() -> int:
    violations = check_gitkeep(REPO_ROOT)
    if violations:
        print("ERROR: .gitkeep found in non-empty folder(s):")
        for v in violations:
            print(v)
        print(
            "\nRemove .gitkeep from folders that already contain real content, "
            "or remove the other files if the folder should stay empty."
        )
        return 1

    print("OK: all .gitkeep files are in empty folders.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
