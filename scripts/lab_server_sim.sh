#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Run the full-SoC QuestaSim simulation for the group5 accelerator on the TUM
# lab server (lx01.clients.eikon.tum.de), using THIS repository's Didactic-SoC
# submodule (already integrated with the accelerator).
#
# Usage (on the lab server, from anywhere in the repo):
#   bash scripts/lab_server_sim.sh [TESTCASE]
#   TESTCASE defaults to "accel". run_sim always runs; the script defaults
#   LM_LICENSE_FILE to the TUM EI lab license servers and forwards it into the
#   container (override by exporting LM_LICENSE_FILE before running).
#
# How this differs from the official Edu4Chip_setup.sh:
#   * Official builds a fresh tree in ~/Edu4Chip: downloads bender into
#     benderDir/ and `git clone`s Edu4Chip/Didactic-SoC at a fixed upstream
#     commit. THIS script uses the Didactic-SoC submodule already vendored in
#     this repo (the accel-integrated fork) — no clone, no ~/Edu4Chip.
#   * Official patches the SoC Makefiles in place with `sed` (32->64 bit,
#     TEST->TESTCASE, FPGA/openocd/xdc fixes). We instead pass XLEN=64 /
#     TESTCASE / TEST on the make command line and keep the submodule clean.
#     (The only committed SoC change is the accel rtl/include incdir in
#     sim/Makefile, needed because `bender script flist` emits no +incdir.)
#   * Official assumes environment modules are already initialised (login
#     shell). We `source` the modules init explicitly (works in any shell).
#   * Official runs `make compile`/`make elaborate` OUTSIDE the container and
#     only enters it for run_sim. We run the whole QuestaSim phase inside the
#     alma.sif container via `apptainer exec` (verified path) and add the
#     REQUIRED `--bind /nfs` (QuestaSim lives under /nfs/tools — without it
#     vlib/vsim are not found).
#   * Official switches the sim Makefile to GUI (`sed 92s/-c/-gui`); we keep CLI
#     (headless) so it runs over SSH. Pass GUI=-gui yourself if you want the GUI.
#   * run_sim needs a Mentor license, which neither the lab modules nor the
#     official script set. This script defaults LM_LICENSE_FILE (and
#     MGLS_LICENSE_FILE) to the TUM EI lab servers and forwards them into the
#     container; export your own before running to override.
# -----------------------------------------------------------------------------
set -euo pipefail

TESTCASE="${1:-accel}"

# Resolve repo root from this script's location (scripts/ -> repo root).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOC_DIR="$REPO_ROOT/Didactic-SoC"
SIF="/nas/ei/share/tools/apptainer/MSMCD/alma.sif"
MODULES_INIT="/nas/ei/share/tools/environment_modules/4.5.1/init/bash"

echo "== repo:     $REPO_ROOT"
echo "== soc:      $SOC_DIR"
echo "== testcase: $TESTCASE"

[ -f "$SOC_DIR/Makefile" ] || { echo "ERROR: submodule missing; run 'git submodule update --init --recursive'"; exit 1; }
[ -f "$SIF" ] || { echo "ERROR: container image not found: $SIF"; exit 1; }

# --- environment modules (explicit init; official assumes a login shell) ------
# shellcheck disable=SC1090
source "$MODULES_INIT"

# --- bender on PATH (prefer the binary vendored in bin/, else download) --------
if [ -x "$REPO_ROOT/bin/bender" ]; then
    export PATH="$REPO_ROOT/bin:$PATH"
elif ! command -v bender >/dev/null 2>&1; then
    echo "ERROR: bender not found. Put it in $REPO_ROOT/bin or on PATH."; exit 1
fi
echo "== bender:   $(command -v bender) ($(bender --version 2>/dev/null))"

# --- fetch SoC RTL dependencies (idempotent) ----------------------------------
( cd "$SOC_DIR" && make repository_init )

# --- build the baremetal program (RISC-V; rv32imc/ilp32 via XLEN=64 multilib) -
module load eda_freeware/riscv/64-elf-ubuntu-24.04-gcc/2026.04.05
( cd "$SOC_DIR" && make build_test XLEN=64 TESTCASE="$TESTCASE" TEST="$TESTCASE" )
module unload eda_freeware/riscv/64-elf-ubuntu-24.04-gcc/2026.04.05

# --- QuestaSim phase, inside the alma.sif container ---------------------------
module load mentor/questasim/2023.4

# QuestaSim/Mentor license. Honor a pre-set LM_LICENSE_FILE/MGLS_LICENSE_FILE;
# otherwise default to the TUM EI lab license servers. The host shell that
# launches this script may not have it set (e.g. lx01), and the alma.sif env is
# otherwise clean, so default it here and forward it INTO the container.
: "${LM_LICENSE_FILE:=27000@license.lis.ei.tum.de:1717@license.lis.ei.tum.de}"
: "${MGLS_LICENSE_FILE:=$LM_LICENSE_FILE}"
export LM_LICENSE_FILE MGLS_LICENSE_FILE
echo "== license:  LM_LICENSE_FILE=$LM_LICENSE_FILE"

# Headless run: drive the sim to completion and quit (the SoC sim Makefile
# otherwise defaults to a GUI-friendly "run 0ms;"). Override with RUN_CMD=...
RUN_CMD="${RUN_CMD:-run -all; quit -f}"
echo "== run_cmd:  $RUN_CMD"

apptainer exec \
    --env PATH="$PATH" \
    --env LM_LICENSE_FILE="$LM_LICENSE_FILE" \
    --env MGLS_LICENSE_FILE="$MGLS_LICENSE_FILE" \
    --bind /nas:/nas --bind /nfs:/nfs --bind /data:/data --bind /tmp:/tmp --bind "$HOME:$HOME" \
    "$SIF" bash -c "
        set -e
        cd '$SOC_DIR/sim'
        make compile
        make elaborate TESTCASE='$TESTCASE'
        make run_sim TESTCASE='$TESTCASE' ${GUI:+GUI=$GUI} RUN_CMD='$RUN_CMD'
    "

echo "== done."
