#!/usr/bin/env bash
# CI helper: run the ASIC flow (asic/scripts/run_flow.sh) on a TUM Eikon lab
# machine over SSH from the GitLab runner container, then pull asic/reports/.
# Usage (repo root): bash scripts/ci_eikon_backend.sh [all|01|02|03|04|05|check]
# The runner mounts the CI key + pinned known_hosts read-only at /eikon-ssh.
set -euo pipefail

STAGE="${1:-all}"
TARGET="ge63nag@linux17.clients.eikon.tum.de"
REMOTE_DIR="/tmp/ge63nag_ci/${CI_PROJECT_ID}-${CI_JOB_ID}"
SSH="ssh -i /eikon-ssh/id_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes
     -o UserKnownHostsFile=/eikon-ssh/known_hosts -o ServerAliveInterval=30"

trap '$SSH -n $TARGET "rm -rf $REMOTE_DIR"' EXIT

$SSH -n "$TARGET" "mkdir -p $REMOTE_DIR"
rsync -az --delete -e "$SSH" --include='/asic/***' --include='/rtl/***' --exclude='*' \
    ./ "$TARGET:$REMOTE_DIR/"

# Pull the reports even when the flow fails, then fail on the flow's status.
rc=0
$SSH -n "$TARGET" "cd $REMOTE_DIR && bash asic/scripts/run_flow.sh $STAGE" || rc=$?
mkdir -p asic/reports
rsync -az -e "$SSH" "$TARGET:$REMOTE_DIR/asic/reports/" asic/reports/ || true
[ "$rc" -eq 0 ] || exit "$rc"

# fc_shell can exit 0 after a Tcl error; SEL-005 is documented as harmless.
if grep -sH -E '^Error:' asic/reports/*.log | grep -v 'SEL-005'; then
    echo "ERROR: Fusion Compiler reported errors" >&2
    exit 1
fi
