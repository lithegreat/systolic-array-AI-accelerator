#!/usr/bin/env bash
# CI helper: cheap fail-fast gates on the synthesis reports, run in asic_synth
# after stage 01 so a design that cannot meet the goals stops before the
# ~30 min placement/routing stages.
#   * area:   total cell area must fit the target core at MAX_UTIL_PCT percent
#   * timing: worst setup slack after synthesis must be >= 0 at the target clock
# The goals come from asic/common/goals.env (override per run with the
# ASIC_MAX_UTIL / ASIC_GATES env vars or CI/CD variables). GATES_MODE=fail makes
# a violation fail the job; warn only reports it, until the design fits.
set -euo pipefail

GOALS_FILE="${ASIC_GOALS_FILE:-asic/common/goals.env}"
# shellcheck disable=SC1090
source "$GOALS_FILE"

REPORTS="${1:-asic/reports}"
CORE_SIDE_UM=$((DIE_SIDE_UM - 2 * CORE_OFFSET_UM))
MAX_UTIL="${ASIC_MAX_UTIL:-$MAX_UTIL_PCT}"
MODE="${ASIC_GATES:-$GATES_MODE}"
rc=0

violation() {
    echo ">> GATE VIOLATION: $*" >&2
    if [ "$MODE" = fail ]; then rc=1; fi
}

area_rpt="$REPORTS/logic_opto_report_area.rpt"
if [ -r "$area_rpt" ]; then
    area=$(sed -n 's/^Total cell area: *\([0-9]*\).*/\1/p' "$area_rpt" | head -1)
    area=${area:-0}
    budget=$((CORE_SIDE_UM * CORE_SIDE_UM * MAX_UTIL / 100))
    echo ">> Area gate: cell area $area um^2, budget $budget um^2 (${MAX_UTIL}% of ${CORE_SIDE_UM}^2)"
    [ "$area" -le "$budget" ] || violation "cell area $area um^2 exceeds budget $budget um^2"
else
    violation "missing $area_rpt"
fi

timing_rpt="$REPORTS/logic_opto_report_timing_setup.rpt"
if [ -r "$timing_rpt" ]; then
    wns=$(sed -n 's/^ *slack ([A-Z]*) *\(-\{0,1\}[0-9.]*\) *$/\1/p' "$timing_rpt" | sort -g | head -1)
    echo ">> Timing gate: worst setup slack ${wns:-n/a} ns at ${CLOCK_MHZ} MHz"
    if [ -z "$wns" ]; then
        violation "no slack found in $timing_rpt"
    elif [ "${wns#-}" != "$wns" ]; then
        violation "setup slack $wns ns < 0 after synthesis"
    fi
else
    violation "missing $timing_rpt"
fi

[ "$rc" -eq 0 ] || echo ">> Gates failed (ASIC_GATES=$MODE)" >&2
exit "$rc"
