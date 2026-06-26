"""Aggregator that runs every per-module cocotb Makefile under sim/testbenches/.

Used by CI; can also be invoked locally with `pytest sim/testbenches`.
After all testbenches run, aggregates Verilator functional coverage and prints
a per-line annotated report via `verilator_coverage`.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
# accel_uvm runs pyuvm tests and has its own dedicated CI job (accel_uvm_sim).
# accel_questa_uvm is a QuestaSim/UVM testbench requiring MTI_HOME (not cocotb).
# Both are excluded here to avoid double-running in the cocotb_sim CI job.
_EXCLUDED = {"accel_uvm", "accel_questa_uvm"}

TESTBENCHES = sorted(
    p
    for p in (REPO_ROOT / "sim" / "testbenches").iterdir()
    if p.is_dir() and (p / "Makefile").is_file() and p.name not in _EXCLUDED
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


@REQUIRES_VERILATOR
def test_coverage_report() -> None:
    """Aggregate Verilator coverage.dat files and print a functional coverage report."""
    if shutil.which("verilator_coverage") is None:
        pytest.skip("verilator_coverage not installed")

    dat_files = sorted(
        tb_dir / "coverage.dat"
        for tb_dir in TESTBENCHES
        if (tb_dir / "coverage.dat").is_file()
    )
    if not dat_files:
        pytest.skip("No coverage.dat files found — run testbenches first")

    annotate_dir = REPO_ROOT / "sim" / "coverage_annotated"
    annotate_dir.mkdir(exist_ok=True)

    lcov_info = REPO_ROOT / "sim" / "coverage.info"
    result = subprocess.run(
        [
            "verilator_coverage",
            "--annotate",
            str(annotate_dir),
            "--annotate-min",
            "1",
            "--write-info",
            str(lcov_info),
        ]
        + [str(f) for f in dat_files],
        check=False,
        capture_output=True,
        text=True,
    )
    # Always print the report regardless of exit code.
    if result.stdout:
        print(result.stdout)
    if result.stderr:
        print(result.stderr)
    print(f"\nAnnotated source written to: {annotate_dir}")
    print(
        f"lcov info written to: {lcov_info}  (open an RTL file and run 'Coverage Gutters: Display Coverage')"
    )
    if result.returncode != 0:
        raise AssertionError(f"verilator_coverage failed (exit={result.returncode})")
