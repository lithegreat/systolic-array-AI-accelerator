#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT
mkdir -p "$temporary/source/ci" "$temporary/source/asic/gf180/scripts" "$temporary/bin"
cp -- "$root/ci/run_backend_remote.sh" "$temporary/source/ci/"
cp -- "$root/asic/gf180/scripts/common.tcl" "$temporary/source/asic/gf180/scripts/"
mkdir -p "$temporary/source/rtl"
printf 'module fixture; endmodule\n' > "$temporary/source/rtl/fixture.sv"
cat > "$temporary/source/asic/gf180/scripts/fetch_sram.sh" <<'SH'
set -euo pipefail
[[ "$1" == init ]]
printf 'PRIVATE_EDA_SOURCE_OUTPUT\n'
exit "${FAKE_SRAM_STATUS:-0}"
SH
cat > "$temporary/source/asic/gf180/scripts/run.sh" <<'SH'
set -euo pipefail
printf 'PRIVATE_EDA_TOOL_OUTPUT %s\n' "$1"
printf '%s\n' "$1" >> asic/gf180/output/steps
if [[ "$1" == all ]]; then exit "${FAKE_FLOW_STATUS:-0}"; fi
[[ "$1" == check ]]
exit "${FAKE_CHECK_STATUS:-0}"
SH
git init -q "$temporary/source"
git -C "$temporary/source" add .
git -C "$temporary/source" -c user.name=CI -c user.email=ci@example.invalid \
    commit -qm fixture
git -C "$temporary/source" -c user.name=CI -c user.email=ci@example.invalid \
    commit --allow-empty -qm fixture-tip
export CI_PROJECT_DIR="$temporary/source"
export CI_COMMIT_SHA
CI_COMMIT_SHA=$(git -C "$CI_PROJECT_DIR" rev-parse HEAD)
export CI_PROJECT_ID=5 CI_PIPELINE_ID=10 CI_JOB_ID=1
export EIKON_HOST=linux17.clients.eikon.tum.de EIKON_USER=ge63nag
export EIKON_CI_ROOT="$temporary/eikon"
export EIKON_GF180_SITE_TCL="$temporary/site.tcl"
export EIKON_SSH_PRIVATE_KEY="$temporary/key"
export EIKON_SSH_KNOWN_HOSTS="$temporary/known_hosts"
printf 'fixture key, never printed\n' > "$EIKON_SSH_PRIVATE_KEY"
printf 'fixture known host\n' > "$EIKON_SSH_KNOWN_HOSTS"
cat > "$EIKON_GF180_SITE_TCL" <<'TCL'
set site [dict create \
    rtl_files [list [file join $::gf180::repo rtl fixture.sv]] \
    include_dirs [list [file join $::gf180::repo rtl]]]
TCL
cat > "$temporary/bin/hostname" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${FAKE_HOSTNAME:-linux17.clients.eikon.tum.de}"
SH
cat > "$temporary/bin/ssh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$SSH_ARGS"
if [[ "${FAKE_SSH_STATUS:-0}" != 0 ]]; then exit "$FAKE_SSH_STATUS"; fi
exec bash -c "${@: -1}"
SH
cat > "$temporary/bin/timeout" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == --signal=TERM && "$2" == --kill-after=60s && "$3" == 3h ]]
shift 3
if [[ "${FAKE_TIMEOUT_STATUS:-0}" != 0 ]]; then exit "$FAKE_TIMEOUT_STATUS"; fi
exec "$@"
SH
chmod +x "$temporary/bin/ssh" "$temporary/bin/hostname" "$temporary/bin/timeout"
export PATH="$temporary/bin:$PATH" SSH_ARGS="$temporary/ssh.args"

assert_failure() {
    local expected="$1" status=0
    shift
    "$@" > "$temporary/client.log" 2>&1 || status=$?
    if ((status != expected)); then
        cat "$temporary/client.log" >&2
        printf 'Expected exit %s, received %s\n' "$expected" "$status" >&2
        exit 1
    fi
}
assert_private() {
    if grep -q 'PRIVATE_EDA_' "$temporary/client.log"; then
        printf 'EDA output escaped into CI output\n' >&2
        exit 1
    fi
}
dispatch=(bash "$root/ci/run_backend.sh")
"${dispatch[@]}" > "$temporary/client.log" 2>&1
run="$EIKON_CI_ROOT/5/10-1"
grep -q 'backend PASS' "$temporary/client.log"
test "$(cat "$run/asic/gf180/output/steps")" = $'all\ncheck'
grep -q PRIVATE_EDA_TOOL_OUTPUT "$run/asic/gf180/output/ci.log"
test "$(git -C "$run" rev-parse HEAD)" = "$CI_COMMIT_SHA"
test "$(git -C "$run" rev-list --count HEAD)" = 1
grep -Fxq StrictHostKeyChecking=yes "$SSH_ARGS"
grep -Fxq BatchMode=yes "$SSH_ARGS"
grep -Fxq IdentitiesOnly=yes "$SSH_ARGS"
test ! -e "$(sed -n 's/^UserKnownHostsFile=//p' "$SSH_ARGS")"
assert_private

# Neither untracked files nor credentials/config from the runner are copied.
printf 'untracked fixture\n' > "$CI_PROJECT_DIR/private.data"
printf 'uncommitted source modification\n' > "$CI_PROJECT_DIR/rtl/fixture.sv"
git -C "$CI_PROJECT_DIR" config http.extraheader 'PRIVATE_CREDENTIAL_FIXTURE'
export CI_JOB_ID=2
"${dispatch[@]}" > "$temporary/client.log" 2>&1
test ! -e "$EIKON_CI_ROOT/5/10-2/private.data"
grep -Fxq 'module fixture; endmodule' "$EIKON_CI_ROOT/5/10-2/rtl/fixture.sv"
test -z "$(git -C "$EIKON_CI_ROOT/5/10-2" config --get http.extraheader)"
assert_private
assert_failure 1 "${dispatch[@]}"

git clone --quiet --depth=1 "file://$CI_PROJECT_DIR" "$temporary/shallow"
test "$(git -C "$temporary/shallow" rev-parse --is-shallow-repository)" = true
export CI_JOB_ID=13
env CI_PROJECT_DIR="$temporary/shallow" "${dispatch[@]}" > "$temporary/client.log" 2>&1
grep -q 'backend PASS' "$temporary/client.log"
assert_private

export CI_JOB_ID=3
assert_failure 7 env FAKE_FLOW_STATUS=7 "${dispatch[@]}"
grep -q 'backend FAILED (exit 7)' "$temporary/client.log"
test "$(cat "$EIKON_CI_ROOT/5/10-3/asic/gf180/output/steps")" = all
assert_private
export CI_JOB_ID=4
assert_failure 9 env FAKE_CHECK_STATUS=9 "${dispatch[@]}"
assert_private
export CI_JOB_ID=5
assert_failure 8 env FAKE_SRAM_STATUS=8 "${dispatch[@]}"
test ! -e "$EIKON_CI_ROOT/5/10-5/asic/gf180/output/steps"
assert_private
export CI_JOB_ID=6
assert_failure 255 env FAKE_SSH_STATUS=255 "${dispatch[@]}"
export CI_JOB_ID=7
assert_failure 1 env FAKE_HOSTNAME=azure-runner "${dispatch[@]}"
export CI_JOB_ID=9
assert_failure 124 env FAKE_TIMEOUT_STATUS=124 "${dispatch[@]}"
grep -q 'backend FAILED (exit 124)' "$temporary/client.log"
assert_private

exec 8>"$EIKON_CI_ROOT/5/.backend.lock"
flock -n 8
export CI_JOB_ID=10
assert_failure 1 "${dispatch[@]}"
test ! -e "$EIKON_CI_ROOT/5/10-10/asic/gf180/output/steps"
flock -u 8
exec 8>&-
assert_private

cat > "$EIKON_GF180_SITE_TCL" <<'TCL'
set site [dict create rtl_files {/another/checkout/fixture.sv} include_dirs {/another/checkout}]
TCL
export CI_JOB_ID=8
assert_failure 1 "${dispatch[@]}"
grep -q 'outside the job checkout' "$EIKON_CI_ROOT/5/10-8/asic/gf180/output/ci.log"
assert_private
export CI_JOB_ID=11
assert_failure 1 env EIKON_GF180_SITE_TCL="$temporary/missing-site.tcl" "${dispatch[@]}"
test ! -e "$EIKON_CI_ROOT/5/10-11/asic/gf180/output/steps"
assert_private
printf 'error "PRIVATE_EDA_INVALID_SITE"\n' > "$EIKON_GF180_SITE_TCL"
export CI_JOB_ID=12
assert_failure 1 "${dispatch[@]}"
test ! -e "$EIKON_CI_ROOT/5/10-12/asic/gf180/output/steps"
assert_private
assert_failure 2 env EIKON_HOST=untrusted.example.invalid "${dispatch[@]}"
assert_failure 2 env EIKON_CI_ROOT='/tmp/../unsafe' "${dispatch[@]}"
assert_failure 2 env EIKON_GF180_SITE_TCL='/tmp/site;echo-unsafe' "${dispatch[@]}"
assert_failure 2 env EIKON_SSH_PRIVATE_KEY=/nonexistent "${dispatch[@]}"
assert_failure 2 env EIKON_SSH_KNOWN_HOSTS=/nonexistent "${dispatch[@]}"
assert_failure 2 env CI_COMMIT_SHA=0000000000000000000000000000000000000000 "${dispatch[@]}"
printf 'PASS: exact-commit SSH dispatch, output isolation, timeout/lock/site failures and input guards.\n'
