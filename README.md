# AI Accelerator for Didactic SoC

This project implements a systolic-array based AI accelerator for the [Edu4Chip didactic SoC](https://github.com/Edu4Chip/Didactic-SoC) and includes RTL sources, Python golden models, cocotb testbenches, and Verilator-based simulation.

If you want the interface reference, see [docs/interface/README.md](docs/interface/README.md).

## Architecture Overview
The ML accelerator architecture is divided into the following loosely-coupled functional blocks:
- **Control Logic**: Orchestrates data movement and computation (in `rtl/control/`).
- **MAC Unit**: The core Multiply-Accumulate processing element (in `rtl/MAC/`).
- **Systolic Array**: Grid of MAC units for matrix multiplication (in `rtl/array/`).
- **Matrix A & B**: Input distribution structures (in `rtl/matrix/`).
- **Matrix C**: Output accumulation and readback logic (in `rtl/matrix/`).

The integration target is the Edu4Chip SoC platform. Both ASIC (GF 22 nm FDX) and FPGA prototyping targets are maintained.

## What lives where
- `rtl/` contains the SystemVerilog design components (`MAC/`, `array/`, `matrix/`, `control/`, `top/`).
- `sim/testbenches/` contains the cocotb and Verilator test scripts categorized per module.
- `sim/common/` contains shared Python helpers and golden models.
- `docs/` contains documentation on the Didactic SoC, GitLab coordination, and interfaces.
- `fpga/` contains FPGA constraints and the Vivado project setup.
- `asic/` contains reports and scripts targeting the GF 22 nm FDX technology node.
- `sw/` contains C-based software drivers and tests for the RISC-V Ibex core interactions.

## Development and Verification Flow
Functionality changes require the following pipeline to be considered complete:
1. **RTL Design**: Implement the SystemVerilog design under `rtl/`. Sub-modules must adhere to the interface contracts defined in `docs/interface/`.
2. **Python Golden Model**: Author a software reference model matching the expected behavioral outputs under `sim/testbenches/` or `sim/common/`.
3. **Cocotb Testbench**: Develop Python-based testbenches utilizing cocotb to check DUT outputs against the golden model.
4. **Verilator Simulation**: Confirm that tests pass properly through Verilator in a Linux environment.
5. **CI Automation**: Assure every merge request natively passes in the automated CI jobs.

## Before you start
- Use Linux for development. If you are on Windows, use WSL or another Linux environment.
- Use Python 3.13 or an older supported Python 3 release. Python 3.14 is not supported yet because cocotb does not support it at the moment.
- Install Git, Python, and Verilator before running the simulations.

## Quick start
1. Clone the repository.
2. Create and activate a Python virtual environment.
3. Install the Python requirements.
4. Run the checks or the test suite.

### Clone the repository

```bash
git clone https://gitlab.lrz.de/ai-pro-msmcd-labs/2025/os/group5.git
cd group5
```

### Create the Python environment

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

If `python3` is not found, install Python from your Linux distribution first.

## Run locally
If Verilator is missing, install it with your package manager. On Debian or Ubuntu, for example:

```bash
sudo apt install verilator
```

On Fedora:

```bash
sudo dnf install verilator
```

## GitLab workflow
This project should not be pushed directly to the `main` branch. Create a branch for your work and open a merge request.

Recommended flow:
1. Create or pick a GitLab issue first.
2. Create a branch for that issue.
3. Open a merge request from that branch.
4. Ask at least one other user to approve the MR before merging.

Use the issue and MR linking guide in [docs/GITLAB_ISSUE_LINKING.md](docs/GITLAB_ISSUE_LINKING.md).

Recommended branch naming:

```bash
git checkout -b 2-mac-unit-pipeline-fix
```

This makes it easier for GitLab to link the branch to the related issue.

In the MR description, link the issue explicitly. A common pattern is:

```markdown
Closes #2
```

It is better to create the issue before the MR so the branch, discussion, and review all stay connected to one work item.

## Running simulations and viewing coverage

All cocotb testbenches are driven by a single pytest entry point:

```bash
source .venv/bin/activate
pytest sim/test_runner.py -v
```

This runs every per-module Makefile under `sim/testbenches/` (array, control, mac, matrix\_ab, matrix\_c, top) and then produces a functional coverage report.

### Functional RTL coverage

Verilator is invoked with `--coverage` (configured in `sim/scripts/Makefile.common`).
After all testbenches complete, `test_coverage_report` in `sim/test_runner.py` runs
`verilator_coverage` to:

- Print a summary line (`Total coverage (N/334)`) to the terminal.
- Write annotated RTL sources to `sim/coverage_annotated/` — lines prefixed with
  `%00` were never executed.
- Write `sim/coverage.info` in lcov format for the
  [Coverage Gutters](https://marketplace.visualstudio.com/items?itemName=ryanluker.vscode-coverage-gutters)
  VS Code extension.

To view coverage highlights in the editor:
1. Open any RTL file (e.g. `rtl/top/accelerator_top.sv`).
2. Open the Command Palette (`Ctrl+Shift+P`) → **Coverage Gutters: Display Coverage**.

Green gutter marks indicate executed lines; red marks indicate unexecuted lines.

Run only the coverage report (against existing `coverage.dat` files) without re-running simulations:

```bash
pytest sim/test_runner.py::test_coverage_report -v -s
```

### Current coverage baseline

As of June 2026 the aggregate line coverage across all RTL modules is **80 %** (269 / 334 lines).

| Module | Uncovered lines | Notes |
|---|---|---|
| `accelerator_top.sv` | 1 | `PSLVERR` (tied-zero, never asserted) |
| `control_unit.sv` | 2 | `unique case` FSM default branch (unreachable by design) |
| `matrix_buffer_ab.sv` | 2 | `unique case` FSM default + `PSLVERR` |
| `matrix_buffer_c.sv` | 1 | `PSLVERR` (tied-zero) |
| `systolic_array.sv` | 1 | `unique case` FSM default (unreachable by design) |

Remaining gaps are either ports tied to constant zero (`PSLVERR`) or `unique case` default
branches that require an illegal FSM state to fire. Both are intentional design constraints.

## CI and pre-commit
This repository uses GitLab CI to check the code automatically. The CI pipeline currently runs:
- convention checks
- `black --check .`
- `.gitkeep` validation
- cocotb simulation through Verilator

Pre-commit hooks are also configured for local use. They run:
- `black`
- `python scripts/check_conventions.py`
- `python scripts/check_gitkeep.py`

Install and enable pre-commit if you want the same checks before every commit:

```bash
pip install pre-commit
pre-commit install
```

Run it manually when needed:

```bash
pre-commit run --all-files
```

## Troubleshooting
- If `python3` or `pip` is missing, install Python from your Linux distribution.
- If the virtual environment does not activate, check that you are using a Linux shell.
- If Verilator is missing, install it before running the simulation tests.
- If a check fails, read the first error message first; it usually points to the real problem.
