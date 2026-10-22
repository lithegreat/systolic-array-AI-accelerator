#!/usr/bin/env bash
set -euo pipefail

: "${CI_PROJECT_DIR:?CI_PROJECT_DIR is required}"
: "${CI_COMMIT_SHA:?CI_COMMIT_SHA is required}"
: "${CI_PROJECT_ID:?CI_PROJECT_ID is required}"
: "${CI_PIPELINE_ID:?CI_PIPELINE_ID is required}"
: "${CI_JOB_ID:?CI_JOB_ID is required}"
: "${EIKON_HOST:?EIKON_HOST is required}"
: "${EIKON_USER:?EIKON_USER is required}"
: "${EIKON_CI_ROOT:?EIKON_CI_ROOT is required}"
: "${EIKON_GF180_SITE_TCL:?Set the absolute Eikon-local GF180 site path}"
: "${EIKON_SSH_PRIVATE_KEY:?Set a GitLab file variable containing the SSH key}"
: "${EIKON_SSH_KNOWN_HOSTS:?Set a GitLab file variable containing verified host keys}"

fail() {
    printf 'Backend dispatch failed: %s\n' "$*" >&2
    exit 2
}

[[ "$CI_COMMIT_SHA" =~ ^[0-9a-f]{40}$ ]] || fail "invalid commit SHA"
for value in "$CI_PROJECT_ID" "$CI_PIPELINE_ID" "$CI_JOB_ID"; do
    [[ "$value" =~ ^[0-9]+$ ]] || fail "invalid CI identifier"
done
[[ "$EIKON_HOST" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*\.clients\.eikon\.tum\.de$ ]] ||
    fail "host must be an Eikon machine"
[[ "$EIKON_USER" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_-]*$ ]] || fail "invalid SSH user"
for path in "$EIKON_CI_ROOT" "$EIKON_GF180_SITE_TCL"; do
    [[ "$path" =~ ^/[a-zA-Z0-9_./-]+$ && "$path/" != *"/../"* && "$path/" != *"/./"* ]] ||
        fail "Eikon paths must be absolute, without whitespace or traversal"
done
[[ -s "$EIKON_SSH_PRIVATE_KEY" && -s "$EIKON_SSH_KNOWN_HOSTS" ]] ||
    fail "SSH file variables must refer to nonempty files"
[[ "$(git -C "$CI_PROJECT_DIR" rev-parse HEAD)" == "$CI_COMMIT_SHA" ]] ||
    fail "checkout does not match CI_COMMIT_SHA"

umask 077
temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT
install -m 600 -- "$EIKON_SSH_PRIVATE_KEY" "$temporary/key"
install -m 600 -- "$EIKON_SSH_KNOWN_HOSTS" "$temporary/known_hosts"

# A shallow, credential-free snapshot retains the SRAM gitlink/index without
# transferring the runner checkout's credentials, hooks, history or outputs.
git init --quiet --template= "$temporary/source"
git -C "$temporary/source" -c protocol.file.allow=always fetch \
    --quiet --no-tags --depth=1 "$CI_PROJECT_DIR" "$CI_COMMIT_SHA"
git -C "$temporary/source" checkout --quiet --detach FETCH_HEAD

remote_dir="$EIKON_CI_ROOT/$CI_PROJECT_ID/$CI_PIPELINE_ID-$CI_JOB_ID"
printf 'Dispatching commit %s to %s@%s:%s\n' \
    "$CI_COMMIT_SHA" "$EIKON_USER" "$EIKON_HOST" "$remote_dir"
tar -C "$temporary/source" -cf - . | ssh \
    -F /dev/null \
    -o BatchMode=yes -o IdentitiesOnly=yes -o IdentityAgent=none \
    -o StrictHostKeyChecking=yes \
    -o "UserKnownHostsFile=$temporary/known_hosts" \
    -o GlobalKnownHostsFile=/dev/null \
    -o ConnectTimeout=15 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
    -i "$temporary/key" "$EIKON_USER@$EIKON_HOST" \
    "umask 077; mkdir -p '$EIKON_CI_ROOT/$CI_PROJECT_ID' &&
     mkdir '$remote_dir' &&
     tar -xf - -C '$remote_dir' &&
     cd '$remote_dir' &&
     bash ci/run_backend_remote.sh '$EIKON_GF180_SITE_TCL' '$CI_COMMIT_SHA'"
