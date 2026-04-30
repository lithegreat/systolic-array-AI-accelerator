# AI Accelerator for Didactic SoC

This project aims to develop a systolic array-based AI accelerator module for the Edu4Chip Didactic SoC platform.

## Current Implementation

The repository now contains a complete v1 output-stationary data path and verification stack:

- RTL modules for `mac_pe`, `systolic_array`, `matrix_buffer_ab`, `matrix_buffer_c`, `control_unit`, and `accelerator_top`
- Python golden models and cocotb testbenches for each major block
- Verilator-based regression driven through `pytest`

Default build-time parameters are:

- `M = 4`
- `N = 4`
- `K = 4`
- `DATA_W = 16`
- `ACC_W = 32`

The implemented dataflow is output-stationary: each PE keeps one output accumulator locally while Matrix A columns and Matrix B rows are streamed into the array.

## 🛠️ Development Environment Setup 
Linux users can follow the instructions below to set up the development environment. 

Windows users are encouraged to use WSL (Windows Subsystem for Linux) for a similar experience.

To set up the development environment, follow these steps:

1. Clone the repository:
   ```bash
   git clone https://gitlab.lrz.de/ai-pro-msmcd-labs/2025/os/group5.git
   cd group5
   ```
2. Create a virtual environment and install dependencies:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   ```

3. Run the verification suite:
   ```bash
   pytest -vv sim/test_runner.py
   ```

4. Run formatting and repository checks:
   ```bash
   black --check .
   python3 scripts/check_conventions.py
   ```

## 👥 Team Responsibilities (RTL Design)

The hardware design is strictly divided into five core RTL modules, tracked via GitLab Issues to prevent merge conflicts and define clear ownership:

- **Issue #1: Control logic and Status / Control** (Li)

- **Issue #2: MAC Unit** (Liu)

- **Issue #3: Systolic array** (Zhong)

- **Issue #4: Matrix A and Matrix B** (Cao)

- **Issue #5: Matrix C** (Shang)

## 📅 Key Milestones

- **May 1**: Block diagram and interface description defined.
- **May 15**: Code and Documentation - Tests fully defined.
- **June 12**: Demonstration - RTL design successfully running on FPGA.
- **July 3**: Code and Documentation - Specifications fulfilled for ASIC (gate-level).
- **July 17**: Final deliverable - All source files, documentation, and presentation.

## Verification Flow

Functional changes in this repository are expected to follow this flow:

1. RTL design under `rtl/`
2. Python golden model for expected behavior
3. cocotb testbench under `sim/testbenches/`
4. Verilator simulation
5. CI regression through `.gitlab-ci.yml`