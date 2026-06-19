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

The verified accelerator path for PYNQ-Z1 is the `int8_8x8` build. Keep the
firmware vectors and the bitstream variant in lockstep: the firmware reads the
accelerator `BUILD_INFO` register at boot and reports `accel: BUILD INFO
MISMATCH` if the software's `ACC_M/N/K/DATA_W` values do not match the physical
array compiled into the bitstream.

### End-to-end accelerator flow

Run these commands from the repository root on the lab server unless noted
otherwise.

1. Generate firmware vectors for the same accelerator variant that will be built
  into the FPGA bitstream:

  ```bash
  VARIANT=int8_8x8
  python3 sim/common/c_code/gen_accel_data.py \
     --variant "$VARIANT" \
     --out Didactic-SoC/fpga/sw/accel/accel_gemm_data.h
  ```

2. Build the FPGA software image. The lab module provides
  `riscv64-unknown-elf-gcc`; the Makefile still emits 32-bit Ibex code through
  `-march=rv32imc -mabi=ilp32`:

  ```bash
  module load eda_freeware/riscv/64-elf-ubuntu-24.04-gcc/2026.04.05
  cd Didactic-SoC/fpga/sw
  make -B test TESTCASE=accel
  cd ../../..
  ```

  The output ELF is `Didactic-SoC/build/fpga/sw/accel.elf`.

3. Build the matching PYNQ-Z1 bitstream:

  ```bash
  module load xilinx/vivado/2024.1
  cd Didactic-SoC/fpga
  make all_xilinx ACCEL_VARIANT="$VARIANT"
  cd ../..
  ```

  The bitstream is written under
  `Didactic-SoC/build/fpga/z1/didactic-z1.runs/impl_1/DidacticZ1.bit`.

4. Program the PYNQ-Z1 from Vivado Hardware Manager. Open the generated project
  `Didactic-SoC/build/fpga/z1/didactic-z1.xpr`, connect to the board, and write
  `DidacticZ1.bit` to the FPGA.

5. Configure OpenOCD for the FT4232H JTAG adapter on the machine where the
  adapter is physically attached. The PID should be `0x6011`, and the serial
  must match the attached adapter:

  ```bash
  cd Didactic-SoC/fpga/utils
  serial=$(lsusb -v -d 0403:6011 | grep iSerial | sed -n 's/.* //p')
  sed -i "s/^adapter serial .*/adapter serial ${serial}; # either comment out or modify to match adapter/" openocd-didactic.cfg
  sed -i "s/ftdi vid_pid 0x0403 0x6010/ftdi vid_pid 0x0403 0x6011/" openocd-didactic.cfg
  cd ../../..
  ```

  Do not run the serial replacement on a remote server that cannot see the USB
  device; an empty `serial` value will make the OpenOCD config harder to use.

6. Start OpenOCD in one terminal:

  ```bash
  openocd -f Didactic-SoC/fpga/utils/openocd-didactic.cfg
  ```

7. Load and run the ELF from a second terminal:

  ```bash
  module load eda_freeware/riscv/64-elf-ubuntu-24.04-gcc/2026.04.05
  cd Didactic-SoC/fpga
  make load_elf TEST=accel
  ```

  In GDB, type `c` to continue. The UART should print `accel: start` followed
  by `accel: PASS` when the run succeeds. Use `Ctrl+C` to halt and `quit` to
  leave GDB.

### FPGA debug notes

`accel.elf` prints the hardware and software build geometry if the `BUILD_INFO`
check fails. Interpret the 32-bit value as `[31:24]=DATA_W`, `[23:16]=K`,
`[15:8]=N`, `[7:0]=M`:

- `hw build=0x08080808`, `sw build=0x08101010`: the board has an 8x8 bitstream,
  but the loaded ELF was built with 16x16 vectors. Regenerate
  `Didactic-SoC/fpga/sw/accel/accel_gemm_data.h` with `--variant int8_8x8` and
  reload `accel.elf`.
- `hw build=0x08101010`, `sw build=0x08080808`: the ELF is for 8x8, but the FPGA
  is running a 16x16 bitstream. Rebuild and reprogram the PYNQ-Z1 bitstream with
  `ACCEL_VARIANT=int8_8x8`.
- `hw build=0x00000000`: the CPU is not reading the accelerator register window.
  Check that the accelerator bitstream is programmed, `ss_init(ACCEL_SS)` ran,
  the TUM subsystem clock/reset are enabled, and the APB base address is still
  `0x0105_1000`.

Useful GDB reads while halted:

```gdb
x/wx 0x0105111c   # REG_BUILD_INFO
p/x accel_result  # PASS=0xACCE5500, mismatch=0xBADD0002
```

### Synthesis status (verified) and PYNQ-Z1 capacity

`make all_xilinx` (Vivado 2024.1, target `xc7z020clg400-1`) was run on the lab
server with the accelerator integrated into the SoC. Results:

- **Synthesis passes cleanly**: `synth_design` and `opt_design` complete
  successfully, DRC reports **0 errors**. The accelerator RTL is included in the
  netlist (`accel_pkg`, `control_unit`, `systolic_array`, `accelerator_top`).
- **The default 16x16 accelerator does not fit on the PYNQ-Z1**: the placer
  fails with a capacity overflow, so no bitstream is produced. Synthesis itself
  completes cleanly (0 errors); placement fails (`[Place 30-487]`: 7310 slices
  required vs 5618 available of 13300). Post-synthesis utilization (INT8
  baseline, `DEF_DATA_W = 8`):

  | Resource        | Used  | Available | Util%   |
  | --------------- | ----- | --------- | ------- |
  | Slice LUTs      | 58484 | 53200     | 109.93% |
  | Slice Registers | 33844 | 106400    |  31.81% |
  | DSP48E1         |     1 | 220       |   0.45% |
  | Block RAM       |     0 | 140       |   0.00% |

  The 16x16x16 systolic array (256 MAC PEs, `DEF_M/N/K = 16` in
  `rtl/include/accel_pkg.sv`) is **LUT-bound** at the INT8 baseline: the 8-bit
  multiplies map into LUT fabric instead of DSP48 blocks, so the DSPs sit almost
  entirely unused (1/220) while LUTs exceed 100%. (At the former 16-bit datapath
  the same array was instead **DSP-bound** — 220/220 DSPs at 100% alongside LUTs
  ~103%.) To generate a bitstream, reduce the array dimensions (e.g. 8x8), force
  the multiplies onto the idle DSPs (a `use_dsp` attribute on the MAC product),
  or target a larger device.
- **Selecting the accelerator variant at synthesis (`ACCEL_VARIANT`)**: the
  physical array dimension and datapath width are selected from the named
  variants in `sim/common/c_code/accel_config.py`, defaulting to `int8_16x16`.
  Build an 8x8 bitstream that fits the PYNQ-Z1 with:

  ```bash
  cd Didactic-SoC/fpga
  make all_xilinx ACCEL_VARIANT=int8_8x8
  ```

  Direct overrides remain available for experiments, e.g.
  `make all_xilinx ACCEL_DIM=8 ACCEL_DATA_W=8`.

  Verified result for the `int8_8x8` build (`ACCEL_DIM=8`, `ACCEL_DATA_W=8`):
  synthesis, place + route, and `write_bitstream` all complete, producing
  `build/fpga/z1/didactic-z1.runs/impl_1/DidacticZ1.bit` (+`.bin`).
  Post-implementation utilization ≈ 28.9k/53200 LUTs (54%), 14.9k FFs (14%),
  1/220 DSPs, 0 BRAM; DRC 0 errors. Timing shows a small `-0.014 ns` violation
  on the JTAG clock path (`td_o_reg → jtag_tdo`) — a board I/O path independent of
  the accelerator datapath and the chosen variant. Runtime matrix dimensions
  written via the APB regmap must stay <= the chosen physical array dimension.

> Note: `Didactic-SoC/fpga/scripts/run_xilinx.tcl` hardcodes the synthesis
> include paths (like the sim Makefile). The accelerator's `rtl/include` was
> added there so Vivado can resolve `accel_pkg.sv`.

## Changing the program loaded onto the Ibex core

In `Didactic-SoC/fpga/Makefile` (FPGA) or `Didactic-SoC/sim/Makefile`
(simulation), change the `TEST` or `TESTCASE` variable respectively, e.g.
`TEST ?= blinky` → `TEST ?= hello`. Use `blink`/`blinky` first to sanity-check
the environment before running the `accel` testcase.
