#!/usr/bin/env bash
# CI helper: run the ASIC flow (asic/scripts/run_flow.sh) on a TUM Eikon lab
# machine over SSH from the GitLab runner container, then pull asic/reports/.
# Usage (repo root): bash scripts/ci_eikon_backend.sh STAGE...   (01..05, check)
#                    bash scripts/ci_eikon_backend.sh cleanup
# The job starting a pipeline (stage 01 / check) probes $EIKON_HOSTS and picks
# the least loaded usable host; it is handed to the later jobs of the pipeline
# through eikon.env (dotenv artifact), because they share a directory in that
# host's /tmp (and thus the Fusion Compiler library).
# The runner mounts the CI key + pinned known_hosts read-only at /eikon-ssh.
set -euo pipefail

EIKON_USER="ge63nag"
EIKON_HOSTS="${EIKON_HOSTS:-linux17 linux16 linux15 linux14 linux13 linux11 linux10 lx01 lx02}"
MIN_FREE_GB=8
SIF=/nas/ei/share/tools/apptainer/MSMCD/alma8.6.sif

cp /eikon-ssh/known_hosts /tmp/known_hosts   # pinned keys; unknown hosts are added on first use
SSH="ssh -i /eikon-ssh/id_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes
     -o UserKnownHostsFile=/tmp/known_hosts -o StrictHostKeyChecking=accept-new
     -o ServerAliveInterval=30"

# Synthesis cache (see docs/guides/asic_backend_guide.md): the stage 01 result
# (design library + reports) is kept on the Eikon host, keyed by a hash of
# everything stage 01 depends on, so an unchanged RTL skips the ~18 min synthesis.
CACHE_DIR="${ASIC_SYNTH_CACHE_DIR:-/tmp/${EIKON_USER}_ci/synth_cache}"
SYNTH_CACHE="${ASIC_SYNTH_CACHE:-$(. asic/common/goals.env && echo "$SYNTH_CACHE")}"
SYNTH_HASH=""
synth_hash() {
    {
        find rtl asic/common -type f ! -name goals.env | sort | xargs sha256sum
        sha256sum asic/flow/scripts/01_synth.tcl asic/flow/scripts/mcmm.tcl asic/scripts/run_flow.sh
        for v in ASIC_M ASIC_N ASIC_K ASIC_DATA_W ASIC_ACC_W; do echo "$v=${!v:-}"; done
        echo "$SIF"
    } | sha256sum | cut -c1-16
}
case " $* " in
    *" 01 "*) if [ "$SYNTH_CACHE" = 1 ]; then SYNTH_HASH=$(synth_hash); fi ;;
esac
[ -z "$SYNTH_HASH" ] || echo ">> Synthesis cache key: $SYNTH_HASH" >&2

# Print "<load per core> <host>" for every reachable, authorized host that has the
# lab tools and enough free memory; the table of all hosts goes to stderr.
probe_hosts() {
    local h
    for h in $EIKON_HOSTS; do
        (
            r=$($SSH -o ConnectTimeout=6 -n "$EIKON_USER@$h.clients.eikon.tum.de" \
                'read l _ < /proc/loadavg; m=$(awk "/MemAvailable/{print int(\$2/1048576)}" /proc/meminfo);
                 t=$(test -f '"$SIF"' && echo 1 || echo 0);
                 c=$(test -n "'"$SYNTH_HASH"'" && test -d '"$CACHE_DIR/$SYNTH_HASH"'/work && echo 1 || echo 0);
                 echo $l $(nproc) $m $t $c' 2>/dev/null) || r=unreachable
            echo "$h $r" > "/tmp/probe_$h"
        ) &
    done
    wait
    for h in $EIKON_HOSTS; do
        read -r _ load cores free tools cached < "/tmp/probe_$h" || true
        echo "   $h: load=${load:-?} cores=${cores:-?} freeGB=${free:-?} tools=${tools:-?} synth_cache=${cached:-?}" >&2
        if [ "${tools:-0}" = 1 ] && [ "${free:-0}" -ge "$MIN_FREE_GB" ]; then
            # a host holding the cached synthesis result wins over any load difference
            echo "$((10#${load/./} / cores - ${cached:-0} * 100000)) $h"   # load per core, in percent
        fi
    done
}

case "$1" in
    01|check)
        echo ">> Probing Eikon hosts: $EIKON_HOSTS" >&2
        EIKON_HOST=$(probe_hosts | sort -n | head -1 | cut -d' ' -f2)
        [ -n "$EIKON_HOST" ] || { echo "ERROR: no usable Eikon host (is the CI key authorized there?)" >&2; exit 1; }
        ;;
    cleanup)
        [ -n "${EIKON_HOST:-}" ] || exit 0   # nothing was started
        ;;
    *)
        : "${EIKON_HOST:?no Eikon host recorded; run the first job of the pipeline}"
        ;;
esac
echo "EIKON_HOST=$EIKON_HOST" > eikon.env
echo ">> Eikon host: $EIKON_HOST"

TARGET="$EIKON_USER@$EIKON_HOST.clients.eikon.tum.de"
REMOTE_DIR="/tmp/${EIKON_USER}_ci/${CI_PROJECT_ID}-${CI_PIPELINE_ID}"

if [ "$1" = cleanup ]; then
    $SSH -n "$TARGET" "rm -rf $REMOTE_DIR"
    exit
fi

# Generated directories are excluded so --delete keeps the earlier stages' results.
$SSH -n "$TARGET" "mkdir -p $REMOTE_DIR"
rsync -az --delete -e "$SSH" \
    --exclude='/asic/flow/work/*' --exclude='/asic/reports/*' --exclude='/asic/results/*' \
    --include='/asic/***' --include='/rtl/***' --exclude='*' \
    ./ "$TARGET:$REMOTE_DIR/"

# Synthesis size exploration: CI/CD (or "Run pipeline") variables ASIC_M, ASIC_N,
# ASIC_K, ASIC_DATA_W, ASIC_ACC_W are forwarded to the flow (see 01_synth.tcl).
PARAM_ENV=""
for v in ASIC_M ASIC_N ASIC_K ASIC_DATA_W ASIC_ACC_W; do
    val="${!v:-}"
    [ -n "$val" ] || continue
    case $val in *[!0-9]*) echo "ERROR: $v must be a positive integer, got '$val'" >&2; exit 1 ;; esac
    PARAM_ENV="$PARAM_ENV export $v=$val &&"
    echo ">> Parameter override: $v=$val"
done

if [ -n "$SYNTH_HASH" ]; then
    PARAM_ENV="$PARAM_ENV export SYNTH_CACHE_HASH=$SYNTH_HASH && export SYNTH_CACHE_DIR=$CACHE_DIR &&"
fi

# Pull the reports even when the flow fails, then fail on the flow's status.
# fc_shell output is far above GitLab's 4 MB job-log limit (the log gets cut
# off); keep only stage markers and errors here, full logs are in the artifacts.
rc=0
# A stage only starts if the previous one left its .done marker (GitLab runs
# `needs` dependents of a failed allow_failure job, e.g. the manual MR job).
$SSH "$TARGET" "cd $REMOTE_DIR && touch .ci_stamp &&$PARAM_ENV bash -s -- $*" 2>&1 <<'REMOTE' |
for s in "$@"; do
    if [ "$s" != check ] && [ "$s" != 01 ]; then
        prev=$(printf %02d $((10#$s - 1)))
        [ -e asic/flow/work/.done_$prev ] || { echo ">> Error: stage $prev has not completed"; exit 1; }
    fi
    cache=""
    if [ "$s" = 01 ] && [ -n "${SYNTH_CACHE_HASH:-}" ]; then
        cache="$SYNTH_CACHE_DIR/$SYNTH_CACHE_HASH"
        if [ -d "$cache/work" ]; then
            # cp -r (no -p): restored reports get fresh mtimes and are uploaded as artifacts
            mkdir -p asic/flow/work asic/reports
            if cp -r "$cache/work/." asic/flow/work/ && cp -r "$cache/reports/." asic/reports/; then
                touch "$cache" asic/flow/work/.done_01
                echo ">> Synthesis cache hit ($SYNTH_CACHE_HASH): stage 01 skipped"
                continue
            fi
            echo ">> Synthesis cache restore failed, running stage 01"
            rm -rf asic/flow/work/* asic/flow/work/.done_* asic/reports/*
        fi
    fi
    bash asic/scripts/run_flow.sh "$s" || exit $?
    touch asic/flow/work/.done_$s
    if [ -n "$cache" ]; then
        if grep -E '^Error:' asic/reports/01_synth.log | grep -qv 'SEL-005'; then
            echo ">> Synthesis not cached (errors in the log)"
        else
            tmp="$cache.tmp$$"
            rm -rf "$tmp"
            mkdir -p "$tmp" && cp -r asic/flow/work "$tmp/work" && cp -r asic/reports "$tmp/reports" \
                && rm -rf "$cache" && mv "$tmp" "$cache" \
                && echo ">> Synthesis cached as $SYNTH_CACHE_HASH" \
                || { echo ">> Synthesis caching failed"; rm -rf "$tmp"; }
            # keep the three most recently used entries
            ls -1dt "$SYNTH_CACHE_DIR"/*/ 2>/dev/null | tail -n +4 | xargs -r rm -rf
        fi
    fi
done
REMOTE
    while IFS= read -r line; do
        case $line in '>>'*|Error:*) echo "$line" ;; esac
    done || rc=${PIPESTATUS[0]}
mkdir -p asic/reports
# Only pull what this job wrote: asic/reports/ on Eikon accumulates over the
# pipeline, and each job uploads its own share as artifacts.
rsync -az -e "$SSH" \
    --files-from=<($SSH -n "$TARGET" "cd $REMOTE_DIR && find asic/reports -type f -newer .ci_stamp") \
    "$TARGET:$REMOTE_DIR/" . || true
[ "$rc" -eq 0 ] || exit "$rc"

# fc_shell can exit 0 after a Tcl error; SEL-005 is documented as harmless.
if grep -sH -E '^Error:' asic/reports/*.log | grep -v 'SEL-005'; then
    echo "ERROR: Fusion Compiler reported errors" >&2
    exit 1
fi
