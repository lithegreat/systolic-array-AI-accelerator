#!/usr/bin/env bash
# CI helper: run the ASIC flow (asic/scripts/run_flow.sh) on a TUM Eikon lab
# machine over SSH from the GitLab runner container, then pull asic/reports/.
# Usage (repo root): bash scripts/ci_eikon_backend.sh STAGE...   (01..05, check)
#                    bash scripts/ci_eikon_backend.sh cleanup
# All jobs of one pipeline share the remote directory (and thus the Fusion
# Compiler library), so the stages can be split over several CI jobs.
# The runner mounts the CI key + pinned known_hosts read-only at /eikon-ssh.
set -euo pipefail

TARGET="ge63nag@linux17.clients.eikon.tum.de"
REMOTE_DIR="/tmp/ge63nag_ci/${CI_PROJECT_ID}-${CI_PIPELINE_ID}"
SSH="ssh -i /eikon-ssh/id_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes
     -o UserKnownHostsFile=/eikon-ssh/known_hosts -o ServerAliveInterval=30"

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
$SSH -n "$TARGET" "cd $REMOTE_DIR && for s in $*; do bash asic/scripts/run_flow.sh \$s || exit \$?; done" 2>&1 |
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
