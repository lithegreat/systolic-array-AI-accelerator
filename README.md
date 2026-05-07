# AI Accelerator for Didactic SoC

This project aims to develop a systolic array-based AI accelerator module for the Edu4Chip Didactic SoC platform.

## 🛠️ Development Environment Setup 
Linux users can follow the instructions below to set up the development environment. 

Windows users are encouraged to use WSL (Windows Subsystem for Linux) for a similar experience.

To set up the development environment, follow these steps:

1. Clone the repository (including submodules):

   You need a token for TUM ShareLaTeX to access the report submodule.
   ```bash
   git clone --recurse-submodules https://gitlab.lrz.de/ai-pro-msmcd-labs/2025/os/group5.git
   cd group5
   ```

   If you encounter issues with submodules, you can also clone them manually:
   ```bash
   git clone https://gitlab.lrz.de/ai-pro-msmcd-labs/2025/os/group5.git
   cd group5
   git submodule init
   git submodule update
   ```

### 📦 Submodules

| Path | Description |
|------|-------------|
| `Didactic-SoC` | Edu4Chip Didactic SoC platform ([GitHub](https://github.com/Edu4Chip/Didactic-SoC)) |
| `report` | Project report (TUM ShareLaTeX), requires a token for access |
2. Create a virtual environment and install dependencies:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
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