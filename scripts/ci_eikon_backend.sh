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

# Print "<load per core> <host>" for every reachable, authorized host that has the
# lab tools and enough free memory; the table of all hosts goes to stderr.
probe_hosts() {
    local h
    for h in $EIKON_HOSTS; do
        (
            r=$($SSH -o ConnectTimeout=6 -n "$EIKON_USER@$h.clients.eikon.tum.de" \
                'read l _ < /proc/loadavg; m=$(awk "/MemAvailable/{print int(\$2/1048576)}" /proc/meminfo);
                 echo $l $(nproc) $m $(test -f '"$SIF"' && echo 1 || echo 0)' 2>/dev/null) || r=unreachable
            echo "$h $r" > "/tmp/probe_$h"
        ) &
    done
    wait
    for h in $EIKON_HOSTS; do
        read -r _ load cores free tools < "/tmp/probe_$h" || true
        echo "   $h: load=${load:-?} cores=${cores:-?} freeGB=${free:-?} tools=${tools:-?}" >&2
        if [ "${tools:-0}" = 1 ] && [ "${free:-0}" -ge "$MIN_FREE_GB" ]; then
            echo "$((10#${load/./} / cores)) $h"   # load per core, in percent
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

# Pull the reports even when the flow fails, then fail on the flow's status.
# fc_shell output is far above GitLab's 4 MB job-log limit (the log gets cut
# off); keep only stage markers and errors here, full logs are in the artifacts.
rc=0
# A stage only starts if the previous one left its .done marker (GitLab runs
# `needs` dependents of a failed allow_failure job, e.g. the manual MR job).
$SSH "$TARGET" "cd $REMOTE_DIR && bash -s -- $*" 2>&1 <<'REMOTE' |
for s in "$@"; do
    if [ "$s" != check ] && [ "$s" != 01 ]; then
        prev=$(printf %02d $((10#$s - 1)))
        [ -e asic/flow/work/.done_$prev ] || { echo ">> Error: stage $prev has not completed"; exit 1; }
    fi
    bash asic/scripts/run_flow.sh "$s" || exit $?
    touch asic/flow/work/.done_$s
done
REMOTE
    while IFS= read -r line; do
        case $line in '>>'*|Error:*) echo "$line" ;; esac
    done || rc=${PIPESTATUS[0]}
mkdir -p asic/reports
rsync -az -e "$SSH" "$TARGET:$REMOTE_DIR/asic/reports/" asic/reports/ || true
[ "$rc" -eq 0 ] || exit "$rc"

# fc_shell can exit 0 after a Tcl error; SEL-005 is documented as harmless.
if grep -sH -E '^Error:' asic/reports/*.log | grep -v 'SEL-005'; then
    echo "ERROR: Fusion Compiler reported errors" >&2
    exit 1
fi
