#!/usr/bin/env bash
# =============================================================================
# run_questa_uvm.sh  --  Run the accel_questa_uvm testbench on the TUM eikon
#                        lab server (lx01.clients.eikon.tum.de).
#
# This script mirrors the pattern of scripts/lab_server_sim.sh:
#   1. Initialises environment modules
#   2. Loads mentor/questasim/2023.4
#   3. Sets the TUM EI license variables
#   4. Executes 'make <target>' inside the alma.sif apptainer container
#      (QuestaSim links against libraries only present inside the container)
#
# Usage (on eikon, from the repo root):
#   bash sim/scripts/run_questa_uvm.sh                        # full regression
#   bash sim/scripts/run_questa_uvm.sh --testname accel_zero_test
#   bash sim/scripts/run_questa_uvm.sh --waves                # GUI + waves
#   bash sim/scripts/run_questa_uvm.sh --target compile       # compile only
#
# Options:
#   --testname <name>   Single test to run (default: full regress)
#   --waves             Open QuestaSim GUI with waveforms
#   --target <target>   Override make target (compile/elaborate/run/regress/waves)
#   --no-rebuild        Skip compile+elaborate; jump straight to run/regress
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TB_DIR="$REPO_ROOT/sim/testbenches/accel_questa_uvm"
SIF="/nas/ei/share/tools/apptainer/MSMCD/alma.sif"
MODULES_INIT="/nas/ei/share/tools/environment_modules/4.5.1/init/bash"

# --- Parse arguments ---------------------------------------------------------
TESTNAME=""
WAVES=0
MAKE_TARGET=""
REBUILD=1

while [[ $# -gt 0 ]]; do
    case "${1}" in
        --testname)
            TESTNAME="${2:?--testname requires a test name}"
            shift 2
            ;;
        --testname=*)
            TESTNAME="${1#*=}"; shift
            ;;
        --waves)
            WAVES=1; shift
            ;;
        --target)
            MAKE_TARGET="${2:?--target requires a make target}"
            shift 2
            ;;
        --target=*)
            MAKE_TARGET="${1#*=}"; shift
            ;;
        --no-rebuild)
            REBUILD=0; shift
            ;;
        -h|--help)
            sed -n '/^# Usage/,/^# =/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo "ERROR: unknown option '${1}'" >&2; exit 1
            ;;
    esac
done

# --- Determine make target ---------------------------------------------------
if [[ -z "$MAKE_TARGET" ]]; then
    if [[ $WAVES -eq 1 ]]; then
        MAKE_TARGET="waves"
    elif [[ -n "$TESTNAME" ]]; then
        MAKE_TARGET="run"
    else
        MAKE_TARGET="regress"
    fi
fi

if [[ $REBUILD -eq 1 && "$MAKE_TARGET" != "compile" && "$MAKE_TARGET" != "clean" ]]; then
    MAKE_TARGETS="compile elaborate $MAKE_TARGET"
else
    MAKE_TARGETS="$MAKE_TARGET"
fi

MAKE_EXTRA=""
[[ -n "$TESTNAME" ]] && MAKE_EXTRA="TESTNAME=$TESTNAME"

# --- Environment checks ------------------------------------------------------
echo "== repo:      $REPO_ROOT"
echo "== tb_dir:    $TB_DIR"
echo "== target:    $MAKE_TARGETS $MAKE_EXTRA"

[[ -f "$TB_DIR/Makefile" ]] || { echo "ERROR: $TB_DIR/Makefile not found"; exit 1; }
[[ -f "$SIF"             ]] || { echo "ERROR: apptainer image not found: $SIF"; exit 1; }

# --- Load environment modules ------------------------------------------------
# shellcheck disable=SC1090
source "$MODULES_INIT"
module load mentor/questasim/2023.4

# MTI_HOME is needed by the Makefile to locate the UVM source tree.
# The module may set it; if not, derive from the vsim binary path.
if [[ -z "${MTI_HOME:-}" ]]; then
    VSIM_BIN="$(command -v vsim 2>/dev/null)"
    if [[ -n "$VSIM_BIN" ]]; then
        MTI_HOME="$(cd "$(dirname "$VSIM_BIN")/.." && pwd)"
        export MTI_HOME
        echo "== MTI_HOME:  $MTI_HOME (derived from vsim path)"
    else
        echo "ERROR: vsim not found on PATH after module load" >&2; exit 1
    fi
fi
echo "== questa:    $(command -v vsim)"

# --- License -----------------------------------------------------------------
# Honor a pre-set LM_LICENSE_FILE; otherwise default to TUM EI lab servers.
: "${LM_LICENSE_FILE:=27000@license.lis.ei.tum.de:1717@license.lis.ei.tum.de}"
: "${MGLS_LICENSE_FILE:=$LM_LICENSE_FILE}"
export LM_LICENSE_FILE MGLS_LICENSE_FILE
echo "== license:   LM_LICENSE_FILE=$LM_LICENSE_FILE"

# --- Run inside apptainer ----------------------------------------------------
# The alma.sif container carries the shared libraries that QuestaSim needs
# (libfreetype, etc.).  /nfs must be bound because vsim lives under /nfs/tools.
apptainer exec \
    --env PATH="$PATH" \
    --env MTI_HOME="$MTI_HOME" \
    --env LM_LICENSE_FILE="$LM_LICENSE_FILE" \
    --env MGLS_LICENSE_FILE="$MGLS_LICENSE_FILE" \
    --bind /nas:/nas --bind /nfs:/nfs \
    --bind /data:/data --bind /tmp:/tmp \
    --bind "$HOME:$HOME" \
    "$SIF" bash -c "
        set -e
        cd '${TB_DIR}'
        make ${MAKE_TARGETS} ${MAKE_EXTRA}
    "

echo "== done."
