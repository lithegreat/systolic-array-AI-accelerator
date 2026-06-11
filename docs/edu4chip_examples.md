# Running the Didactic-SoC software examples

Instructions for building and running the baremetal software examples bundled
with the Didactic SoC, on the TUM lab server (`lx01.clients.eikon.tum.de`).

These are the official Edu4Chip steps, adapted to the way this repository vendors
the SoC as the `Didactic-SoC` submodule. The reference setup script is
`Edu4Chip_setup.sh` (provided by the course); the verified command details below
match what we run for the `accel` testcase.

> The course setup script lays everything out under `~/Edu4Chip`. In this
> repository the SoC lives in the `Didactic-SoC/` submodule instead, so adjust
> paths accordingly (`Didactic-SoC/sim`, `Didactic-SoC/fpga`, ...).

## Environment modules

A non-login shell does not initialise environment modules automatically. Source
the init script once per shell before any `module load`:

```bash
source /nas/ei/share/tools/environment_modules/4.5.1/init/bash
```

Relevant modules:

- `eda_freeware/riscv/64-elf-ubuntu-24.04-gcc/2026.04.05` — RISC-V baremetal gcc
- `mentor/questasim/2023.4` — QuestaSim (`vlog`/`vopt`/`vsim`)
- `xilinx/vivado/2024.1` — Vivado (FPGA bitstream)

## Running the simulation in QuestaSim

> **One-command path.** `scripts/lab_server_sim.sh [TESTCASE]` (default
> `accel`) runs the whole flow below — `repository_init`, the baremetal build,
> and compile + elaborate + run_sim inside the container. `run_sim` needs a
> Mentor license reachable from the environment (see below). The manual steps
> are kept here for reference.

- Load the QuestaSim environment module: `module load mentor/questasim/2023.4`.
- Because of a binary incompatibility with Ubuntu 24.04, the simulation must run
  inside the lab apptainer container. The container image is
  `/nas/ei/share/tools/apptainer/MSMCD/alma.sif`.
- Launch the container, then run `make run_sim` in `Didactic-SoC/sim`.

Non-interactive (headless) invocation with `apptainer exec`. The `/nfs` bind is
**required** — QuestaSim is installed under `/nfs/tools/...`, so without it
`vlib`/`vsim` are not found:

```bash
# Build the accelerator baremetal program first (RISC-V).
module load eda_freeware/riscv/64-elf-ubuntu-24.04-gcc/2026.04.05
cd Didactic-SoC
make build_test XLEN=64 TESTCASE=accel TEST=accel      # -> build/sw/accel.hex

# Compile + elaborate + run inside the container.
module load mentor/questasim/2023.4
SIF=/nas/ei/share/tools/apptainer/MSMCD/alma.sif
apptainer exec --env PATH="$PATH" \
    --bind /nas:/nas --bind /nfs:/nfs --bind /data:/data --bind /tmp:/tmp --bind "$HOME:$HOME" \
    "$SIF" bash -c '
        cd Didactic-SoC/sim
        make compile
        make elaborate TESTCASE=accel
        make run_sim    TESTCASE=accel'   # Ibex boots accel.hex over JTAG
```

Add `GUI=-gui` to `make run_sim` for the QuestaSim GUI (the course setup script
sets the sim Makefile to GUI mode via `sed -i "92s/-c/-gui/"`).

### Licensing for `make run_sim`

`vlog`/`vopt` (compile + elaborate) need no license and already confirm that the
accelerator integrates and elaborates cleanly inside the full SoC. `vsim`
(`make run_sim`) **does** need a Mentor/Siemens license, and fails otherwise with:

```
** Fatal: Failed to initialize licensing environment. License environment not set correctly.
```

Neither the setup script nor the lab `module` files set a license variable
(`module show mentor/questasim/2023.4` only sets `PATH`/`MTI_VCO_MODE`/
`LD_LIBRARY_PATH`), and no license server is configured under `/etc/profile.d`,
`/etc/environment`, the QuestaSim install, or the sibling Mentor modules. This
means the license server address is **provisioned per host / provided by the
course** and is not derivable from these files.

Once you have the lab's Mentor license server (`port@host`, e.g. `1717@host`),
set it before entering the container and pass it through:

```bash
export MGLS_LICENSE_FILE=<port@host>          # or LM_LICENSE_FILE / SALT_LICENSE_SERVER
apptainer exec --env PATH="$PATH" --env MGLS_LICENSE_FILE \
    --bind /nas:/nas --bind /nfs:/nfs --bind /data:/data --bind /tmp:/tmp --bind "$HOME:$HOME" \
    "$SIF" bash -c 'cd Didactic-SoC/sim && make run_sim TESTCASE=accel'
```

If the address is unknown, request it from the course staff / lab admin (it is
not published in the SoC sources). The compile + elaborate steps above are
sufficient to prove RTL integration in the meantime.

## Prototyping on the FPGA (PYNQ-Z1)

- Open a new terminal and load Vivado: `module load xilinx/vivado/2024.1`.
- Open the project `Didactic-SoC/build/fpga/z1/didactic-z1.xpr` (built by
  `make all_xilinx` in `Didactic-SoC/fpga`).
- Write the bitstream to the FPGA.

### Synthesis status (verified) and PYNQ-Z1 capacity

`make all_xilinx` (Vivado 2024.1, target `xc7z020clg400-1`) was run on the lab
server with the accelerator integrated into the SoC. Results:

- **Synthesis passes cleanly**: `synth_design` and `opt_design` complete
  successfully, DRC reports **0 errors**. The accelerator RTL is included in the
  netlist (`accel_pkg`, `control_unit`, `systolic_array`, `accelerator_top`).
- **The default 16x16 accelerator does not fit on the PYNQ-Z1**: the placer
  fails with a capacity overflow, so no bitstream is produced. Post-synthesis
  utilization:

  | Resource        | Used  | Available | Util%   |
  | --------------- | ----- | --------- | ------- |
  | Slice LUTs      | 54822 | 53200     | 103.05% |
  | DSP48E1         | 220   | 220       | 100.00% |
  | Slice Registers | 35399 | 106400    | 33.27%  |

  The 16x16x16 systolic array (256 MAC PEs, `DEF_M/N/K = 16` in
  `rtl/include/accel_pkg.sv`) saturates all 220 DSPs and pushes total LUT usage
  past 100%. To generate a bitstream, reduce the array dimensions (e.g. 8x8) or
  target a larger device.
- **Selecting the array size at synthesis (`ACCEL_DIM`)**: the physical array
  dimension (M=N=K) is set with the `ACCEL_DIM` make/Verilog define, defaulting
  to 16. Build an 8x8 bitstream that fits the PYNQ-Z1 with:

  ```bash
  cd Didactic-SoC/fpga
  make all_xilinx ACCEL_DIM=8
  ```

  Verified result for `ACCEL_DIM=8`: place + route + `write_bitstream` all
  complete (25159/53200 LUTs = 47%, 65/220 DSPs = 30%), producing
  `build/fpga/z1/didactic-z1.runs/impl_1/DidacticZ1.bit` (+`.bin`). Runtime
  matrix dimensions written via the APB regmap must stay <= the chosen
  `ACCEL_DIM`.

> Note: `Didactic-SoC/fpga/scripts/run_xilinx.tcl` hardcodes the synthesis
> include paths (like the sim Makefile). The accelerator's `rtl/include` was
> added there so Vivado can resolve `accel_pkg.sv`.
- Connect the JTAG IO pins on the FPGA board to the FT4232H module.
- Open an OpenOCD connection in a new terminal:
  `openocd -f Didactic-SoC/fpga/utils/openocd-didactic.cfg`.
- Load the RISC-V compiler module:
  `module load eda_freeware/riscv/64-elf-ubuntu-24.04-gcc/2026.04.05`.
- Run `make load_elf` in `Didactic-SoC/fpga`.
- To start execution: type `c` and press Enter.
- To halt execution: press `Ctrl+C`.
- To quit the debugging session: type `quit`.

## Changing the program loaded onto the Ibex core

In `Didactic-SoC/fpga/Makefile` (FPGA) or `Didactic-SoC/sim/Makefile`
(simulation), change the `TEST` or `TESTCASE` variable respectively, e.g.
`TEST ?= blinky` → `TEST ?= hello`. Use `blink`/`blinky` first to sanity-check
the environment before running the `accel` testcase.
