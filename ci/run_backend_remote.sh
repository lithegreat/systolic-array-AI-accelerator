#!/usr/bin/env bash
set -euo pipefail

if (($# != 2)); then
    printf 'Usage: bash %s /absolute/site.tcl commit-sha\n' "$0" >&2
    exit 2
fi
if [[ "$(hostname -f)" != *.clients.eikon.tum.de ]]; then
    printf 'Backend execution is restricted to Eikon machines.\n' >&2
    exit 1
fi
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd -- "$repo"
[[ "$(git rev-parse HEAD)" == "$2" ]] || {
    printf 'Remote checkout does not match the requested commit.\n' >&2
    exit 1
}
export GF180_SITE_TCL="$1"
umask 077
mkdir -p asic/gf180/output
log="$repo/asic/gf180/output/ci.log"

# Preserve only the exit status and location on the CI connection, not EDA data.
exec 3>&1
report_status() {
    local status=$?
    if ((status == 0)); then
        printf 'GF180 backend PASS; outputs remain on Eikon: %s\n' "$repo/asic/gf180/output" >&3
    else
        printf 'GF180 backend FAILED (exit %s); inspect on Eikon: %s\n' "$status" "$log" >&3
    fi
}
trap report_status EXIT
exec > "$log" 2>&1

# Keep source paths tied to this job, not a teammate's persistent checkout.
tclsh /dev/stdin <<'TCL'
source asic/gf180/scripts/common.tcl
::gf180::load_site
foreach key {rtl_files include_dirs} {
    if {![dict exists $::gf180::site $key] || ![llength [dict get $::gf180::site $key]]} {
        puts stderr "CI site must declare $key from the job checkout"
        exit 1
    }
    foreach path [dict get $::gf180::site $key] {
        if {[string first "$::gf180::repo/" [file normalize $path]] != 0} {
            puts stderr "CI site $key refers outside the job checkout: $path"
            exit 1
        }
    }
}
TCL

# A server-side bound also applies if the SSH client disappears. The common
# lock prevents overlapping jobs even if CI released its resource group.
exec 9>"$(dirname -- "$repo")/.backend.lock"
flock -n 9
timeout --signal=TERM --kill-after=60s 3h bash -c '
    set -euo pipefail
    bash asic/gf180/scripts/fetch_sram.sh init
    bash asic/gf180/scripts/run.sh all
    bash asic/gf180/scripts/run.sh check
'
