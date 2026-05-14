"""Aggregator that runs every per-module cocotb Makefile under sim/testbenches/.

Used by CI; can also be invoked locally with `pytest sim/testbenches`.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
TESTBENCHES = sorted(
    p
    for p in (REPO_ROOT / "sim" / "testbenches").iterdir()
    if p.is_dir() and (p / "Makefile").is_file()
)

REQUIRES_VERILATOR = pytest.mark.skipif(
    shutil.which("verilator") is None,
    reason="verilator not installed",
)


@REQUIRES_VERILATOR
@pytest.mark.parametrize("tb_dir", TESTBENCHES, ids=lambda p: p.name)
def test_cocotb_module(tb_dir: Path) -> None:
    # Clean the per-module sim_build to avoid stale artefacts.
    build = tb_dir / "sim_build"
    if build.is_dir():
        shutil.rmtree(build)
    result = subprocess.run(
        ["make"],
        cwd=tb_dir,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        # Surface tail of log so CI shows useful context.
        print(result.stdout[-4000:])
        print(result.stderr[-2000:])
        raise AssertionError(f"{tb_dir.name} failed (exit={result.returncode})")
