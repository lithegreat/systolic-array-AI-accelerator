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
