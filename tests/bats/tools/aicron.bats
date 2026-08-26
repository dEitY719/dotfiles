#!/usr/bin/env bats
# tests/bats/tools/aicron.bats
# Tests for aicron.sh — the manifest-driven cron job manager (#1472).
#
# aicron owns three pieces of state and the suite is organised around them:
#
#   manifest   the version-controlled job list (jq). Every test points
#              AICRON_MANIFEST at a temp fixture — the shipped
#              shell-common/tools/custom/cron-jobs.json is never read.
#   crontab    the SSOT for "is this job installed" (D-3). A PATH stub stands
#              in for the real `crontab` binary and reads/writes a fixture
#              file, so the developer's live crontab is never touched. The
#              stub logs every invocation to ${_LOG}.
#   state      <state-dir>/<job>.json — paused / last_run / last_exit /
#              last_duration_sec, plus <state-dir>/<job>.lock.
#
# The single most important assertion in this file is that everything OUTSIDE
# an `aicron:` marker block survives `add` and `remove` byte-for-byte: the
# machines running this manage hand-written crontab lines that no tool of ours
# is allowed to eat.

load '../test_helper'

SCRIPT="${DOTFILES_ROOT}/shell-common/tools/custom/aicron.sh"

setup() {
    setup_isolated_home
    _WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aicron-test.XXXXXX")"
    _BIN_DIR="${_WORK_DIR}/bin"
    _JOB_DIR="${_WORK_DIR}/jobs"
    _STATE_DIR="${_WORK_DIR}/state"
    _MANIFEST="${_WORK_DIR}/cron-jobs.json"
    _CRONTAB_FILE="${_WORK_DIR}/crontab.txt"
    _BASELINE="${_WORK_DIR}/crontab.baseline"
    _LOG="${_WORK_DIR}/calls.log"
    _MARK="${_WORK_DIR}/job-ran.log"
    _LOCK_HOLDER_PID=""
    mkdir -p "${_BIN_DIR}" "${_JOB_DIR}" "${_STATE_DIR}"
    : >"${_LOG}"
    : >"${_MARK}"

    _install_crontab_stub
    _seed_crontab
    _make_jobs
    _write_manifest
}

teardown() {
    if [ -n "${_LOCK_HOLDER_PID}" ]; then
        kill "${_LOCK_HOLDER_PID}" 2>/dev/null || true
        wait "${_LOCK_HOLDER_PID}" 2>/dev/null || true
    fi
    # The unwritable-state-dir test chmods the state dir; an assertion that
    # aborts the body before it restores the mode would take `rm -rf` down
    # with it and turn one red test into a broken teardown.
    [ -d "${_STATE_DIR}" ] && chmod 700 "${_STATE_DIR}" 2>/dev/null || true
    rm -rf "${_WORK_DIR}"
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# A `crontab` that reads and writes ${_CRONTAB_FILE} instead of the user's
# real table, and logs what it was asked to do.
_install_crontab_stub() {
    cat >"${_BIN_DIR}/crontab" <<EOF
#!/usr/bin/env bash
printf 'crontab %s\n' "\$*" >>"${_LOG}"
case "\${1:-}" in
    -l)
        if [ -f "${_CRONTAB_FILE}" ]; then
            cat "${_CRONTAB_FILE}"
            exit 0
        fi
        echo "no crontab for test" >&2
        exit 1
        ;;
    -)
        cat >"${_CRONTAB_FILE}"
        exit 0
        ;;
    -r)
        rm -f "${_CRONTAB_FILE}"
        exit 0
        ;;
esac
exit 1
EOF
    chmod +x "${_BIN_DIR}/crontab"
}

# The hand-written lines aicron must never disturb — modelled on the live
# karakeep entry this feature was written next to.
_seed_crontab() {
    cat >"${_CRONTAB_FILE}" <<'EOF'
# hand-written, do not touch
MAILTO=""
*/30 * * * * set -a; . /home/tester/karakeep/.env; set +a; /home/tester/karakeep-sync auto >> /home/tester/logs/cron.log 2>&1

# trailing comment with    odd    spacing
EOF
    cp "${_CRONTAB_FILE}" "${_BASELINE}"
}

_make_jobs() {
    cat >"${_JOB_DIR}/hello.sh" <<EOF
#!/usr/bin/env bash
{
    printf 'ran args=[%s]\n' "\$*"
    printf 'env AICRON_TEST_DEFAULT=%s\n' "\${AICRON_TEST_DEFAULT:-unset}"
    printf 'env AICRON_TEST_JOB=%s\n' "\${AICRON_TEST_JOB:-unset}"
    printf 'env AICRON_TEST_HOMEPATH=%s\n' "\${AICRON_TEST_HOMEPATH:-unset}"
} >>"${_MARK}"
printf 'hello stdout\n'
printf 'hello stderr\n' >&2
exit 0
EOF
    cat >"${_JOB_DIR}/boom.sh" <<EOF
#!/usr/bin/env bash
printf 'boom ran\n' >>"${_MARK}"
exit 7
EOF
    chmod +x "${_JOB_DIR}/hello.sh" "${_JOB_DIR}/boom.sh"
}

# `script` paths are absolute here so the fixture jobs do not have to live
# inside DOTFILES_ROOT. The relative form the shipped manifest uses gets its
# own test below.
_write_manifest() {
    cat >"${_MANIFEST}" <<EOF
{
  "defaults": {
    "env": {
      "AICRON_TEST_DEFAULT": "from-defaults",
      "AICRON_TEST_HOMEPATH": "\$HOME/bin:\${HOME}/sbin"
    }
  },
  "jobs": [
    {
      "name": "hello",
      "script": "${_JOB_DIR}/hello.sh",
      "schedule": "*/5 * * * *",
      "args": ["alpha", "beta gamma"],
      "env": { "AICRON_TEST_JOB": "from-job", "AICRON_TEST_DEFAULT": "overridden" },
      "description": "fixture job that succeeds"
    },
    {
      "name": "boom",
      "script": "${_JOB_DIR}/boom.sh",
      "schedule": "0 * * * *",
      "args": [],
      "env": {},
      "description": "fixture job that fails"
    },
    {
      "name": "ghost",
      "script": "${_JOB_DIR}/never-created.sh",
      "schedule": "0 3 * * *",
      "args": [],
      "env": {},
      "description": "fixture job whose script is missing"
    }
  ]
}
EOF
}

# ---------------------------------------------------------------------------
# Invocation helpers
# ---------------------------------------------------------------------------

_aicron() {
    run env PATH="${_BIN_DIR}:${PATH}" \
        HOME="${HOME}" \
        AICRON_MANIFEST="${_MANIFEST}" \
        AICRON_STATE_DIR="${_STATE_DIR}" \
        bash "${SCRIPT}" "$@"
}

# A PATH carrying only the stub dir plus symlinks to the system binaries
# aicron needs, minus the ones named as arguments. Deleting the stub is not
# enough to make a binary missing — `command -v` keeps walking the inherited
# PATH and would find the real `crontab`.
_path_without() {
    local _d="${_WORK_DIR}/sysbin" _b _p _skip
    rm -rf "${_d}"
    mkdir -p "${_d}"
    for _b in sh bash env jq awk sed grep head tail cat cut tr sort uniq date \
        mkdir rm ln basename dirname sleep mktemp flock tput wc chmod id \
        stty locale crontab; do
        _skip=0
        for _p in "$@"; do
            [ "${_b}" != "${_p}" ] || _skip=1
        done
        [ "${_skip}" -eq 0 ] || continue
        _p=$(command -v "${_b}" 2>/dev/null) || continue
        ln -sf "${_p}" "${_d}/${_b}" 2>/dev/null || true
    done
    # The crontab stub lives in _BIN_DIR; drop it when crontab is excluded.
    if [ "$#" -gt 0 ] && [ "$1" = "crontab" ]; then
        printf '%s' "${_d}"
    else
        printf '%s:%s' "${_BIN_DIR}" "${_d}"
    fi
}

# Everything in the fixture crontab that is NOT inside job <1>'s marker block.
_crontab_outside_block() {
    awk -v tag="$1" '
        $0 == "# BEGIN aicron:" tag { skip = 1; next }
        $0 == "# END aicron:" tag   { skip = 0; next }
        skip != 1                   { print }
    ' "${_CRONTAB_FILE}"
}

# Hold an exclusive flock on job <1>'s lock file until teardown kills the
# holder, so the script under test sees a contended lock. Blocks until the
# lock is genuinely held.
#
# `3>&-` is load-bearing: bats streams TAP on fd 3 and will not finish a test
# until every inheritor closes it. teardown kills `flock`, but the orphaned
# inner `sh -c` would hold fd 3 open for the rest of its sleep.
_hold_job_lock() {
    local _ready="${_WORK_DIR}/lock-held"
    mkdir -p "${_STATE_DIR}"
    flock -x "${_STATE_DIR}/$1.lock" \
        sh -c "printf held >'${_ready}'; sleep 30" >/dev/null 2>&1 3>&- &
    _LOCK_HOLDER_PID=$!

    local _i=0
    while [ ! -s "${_ready}" ] && [ "${_i}" -lt 200 ]; do
        sleep 0.05
        _i=$((_i + 1))
    done
    [ -s "${_ready}" ]
}

_state_field() {
    jq -r "$2" "${_STATE_DIR}/$1.json"
}

# Freeze the last `run`'s stdout into a file. Asserting on `$output` with a
# nested `run jq ...` would clobber `$output` before the second assertion ever
# saw it, so every multi-assertion JSON test parks the payload here first.
_capture_json() {
    _JSON="${_WORK_DIR}/out.json"
    printf '%s' "$output" >"${_JSON}"
}

# ---------------------------------------------------------------------------
# Syntax, help, POSIX (NF-3)
# ---------------------------------------------------------------------------

@test "aicron: bash syntax check on every new file" {
    run bash -n "${SCRIPT}"
    assert_success
    local _f
    for _f in "${DOTFILES_ROOT}"/shell-common/tools/custom/lib/aicron_*.sh; do
        run bash -n "${_f}"
        assert_success
    done
    run bash -n "${DOTFILES_ROOT}/shell-common/functions/aicron.sh"
    assert_success
}

@test "aicron: help exits 0 and lists every subcommand" {
    _aicron help
    assert_success
    local _c
    for _c in list add remove pause resume status run doctor; do
        assert_output --partial "${_c}"
    done
}

@test "aicron: -h and --help behave like help" {
    _aicron -h
    assert_success
    _aicron --help
    assert_success
}

@test "aicron: runs under /bin/sh with no bash-only syntax (NF-3)" {
    run env PATH="${_BIN_DIR}:${PATH}" \
        AICRON_MANIFEST="${_MANIFEST}" \
        AICRON_STATE_DIR="${_STATE_DIR}" \
        sh "${SCRIPT}" help
    assert_success
}

@test "aicron: list runs under /bin/sh too" {
    run env PATH="${_BIN_DIR}:${PATH}" \
        AICRON_MANIFEST="${_MANIFEST}" \
        AICRON_STATE_DIR="${_STATE_DIR}" \
        sh "${SCRIPT}" list
    assert_success
    assert_output --partial "hello"
}

@test "aicron: no subcommand prints usage and fails with 1" {
    _aicron
    assert_failure 1
}

@test "aicron: unknown subcommand exits 1" {
    _aicron frobnicate
    assert_failure 1
}

# ---------------------------------------------------------------------------
# list
# ---------------------------------------------------------------------------

@test "aicron: list prints every manifest job with installed / paused / last run" {
    _aicron list
    assert_success
    assert_output --partial "hello"
    assert_output --partial "boom"
    assert_output --partial "ghost"
    assert_output --partial "installed"
    assert_output --partial "paused"
}

@test "aicron: list reflects crontab as the installed SSOT (D-3)" {
    _aicron list --json
    assert_success
    _capture_json
    run jq -r '.jobs[] | select(.name=="hello") | .installed' "${_JSON}"
    assert_output "false"

    _aicron add hello
    assert_success

    _aicron list --json
    assert_success
    _capture_json
    run jq -r '.jobs[] | select(.name=="hello") | .installed' "${_JSON}"
    assert_output "true"
}

@test "aicron: list --json passes jq -e ." {
    _aicron list --json
    assert_success
    _capture_json
    run jq -e . "${_JSON}"
    assert_success
}

# ---------------------------------------------------------------------------
# add / remove — crontab marker block (D-4)
# ---------------------------------------------------------------------------

@test "aicron: add writes the marker block and the run line" {
    _aicron add hello
    assert_success

    run cat "${_CRONTAB_FILE}"
    assert_output --partial "# BEGIN aicron:hello"
    assert_output --partial "# END aicron:hello"
    assert_output --partial "*/5 * * * * ${SCRIPT} run hello"
}

@test "aicron: add leaves every line outside the marker block byte-identical" {
    _aicron add hello
    assert_success

    _crontab_outside_block hello >"${_WORK_DIR}/outside"
    run cmp "${_WORK_DIR}/outside" "${_BASELINE}"
    assert_success
}

@test "aicron: remove restores the crontab byte-for-byte" {
    _aicron add hello
    assert_success
    _aicron remove hello
    assert_success

    run cmp "${_CRONTAB_FILE}" "${_BASELINE}"
    assert_success
}

@test "aicron: add twice replaces the block instead of duplicating it" {
    _aicron add hello
    assert_success
    _aicron add hello --schedule "17 4 * * *"
    assert_success

    run grep -c "^# BEGIN aicron:hello$" "${_CRONTAB_FILE}"
    assert_output "1"
    run cat "${_CRONTAB_FILE}"
    assert_output --partial "17 4 * * * ${SCRIPT} run hello"
    refute_output --partial "*/5 * * * * ${SCRIPT} run hello"
}

@test "aicron: --schedule overrides the manifest schedule" {
    _aicron add hello --schedule "*/2 * * * *"
    assert_success
    run cat "${_CRONTAB_FILE}"
    assert_output --partial "*/2 * * * * ${SCRIPT} run hello"
}

@test "aicron: remove keeps the state file" {
    _aicron pause hello
    assert_success
    _aicron add hello
    assert_success
    _aicron remove hello
    assert_success

    [ -f "${_STATE_DIR}/hello.json" ]
    run _state_field hello .paused
    assert_output "true"
}

@test "aicron: add on a second job leaves the first job's block intact" {
    _aicron add hello
    assert_success
    _aicron add boom
    assert_success

    run cat "${_CRONTAB_FILE}"
    assert_output --partial "# BEGIN aicron:hello"
    assert_output --partial "# BEGIN aicron:boom"

    _aicron remove boom
    assert_success
    run cat "${_CRONTAB_FILE}"
    assert_output --partial "# BEGIN aicron:hello"
    refute_output --partial "aicron:boom"
}

@test "aicron: add on an unknown job exits 2" {
    _aicron add nope
    assert_failure 2
}

@test "aicron: remove on an unknown job exits 2" {
    _aicron remove nope
    assert_failure 2
}

@test "aicron: add without a job name exits 1" {
    _aicron add
    assert_failure 1
}

# ---------------------------------------------------------------------------
# crontab binary missing (D-8 exit 3)
# ---------------------------------------------------------------------------

@test "aicron: add exits 3 with a clear message when crontab is absent" {
    run env PATH="$(_path_without crontab)" \
        HOME="${HOME}" \
        AICRON_MANIFEST="${_MANIFEST}" \
        AICRON_STATE_DIR="${_STATE_DIR}" \
        bash "${SCRIPT}" add hello
    assert_failure 3
    assert_output --partial "crontab"
}

@test "aicron: remove exits 3 when crontab is absent" {
    run env PATH="$(_path_without crontab)" \
        HOME="${HOME}" \
        AICRON_MANIFEST="${_MANIFEST}" \
        AICRON_STATE_DIR="${_STATE_DIR}" \
        bash "${SCRIPT}" remove hello
    assert_failure 3
    assert_output --partial "crontab"
}

# ---------------------------------------------------------------------------
# pause / resume
# ---------------------------------------------------------------------------

@test "aicron: pause then run skips the job script and exits 0" {
    _aicron pause hello
    assert_success
    run _state_field hello .paused
    assert_output "true"

    _aicron run hello
    assert_success
    run cat "${_MARK}"
    refute_output --partial "ran args="
}

@test "aicron: pause leaves the crontab untouched" {
    _aicron add hello
    assert_success
    cp "${_CRONTAB_FILE}" "${_WORK_DIR}/after-add"
    _aicron pause hello
    assert_success
    run cmp "${_CRONTAB_FILE}" "${_WORK_DIR}/after-add"
    assert_success
}

@test "aicron: resume then run executes the job again" {
    _aicron pause hello
    assert_success
    _aicron resume hello
    assert_success
    run _state_field hello .paused
    assert_output "false"

    _aicron run hello
    assert_success
    run cat "${_MARK}"
    assert_output --partial "ran args="
}

@test "aicron: pause on an unknown job exits 2" {
    _aicron pause nope
    assert_failure 2
}

# ---------------------------------------------------------------------------
# run (D-5)
# ---------------------------------------------------------------------------

@test "aicron: run executes the job and records the result in the state file" {
    _aicron run hello
    assert_success

    [ -f "${_STATE_DIR}/hello.json" ]
    run _state_field hello .last_exit
    assert_output "0"
    run _state_field hello .last_run
    assert_output --regexp '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
    run _state_field hello .last_duration_sec
    assert_output --regexp '^[0-9]+$'
}

@test "aicron: run passes manifest args and the merged env into the job" {
    _aicron run hello
    assert_success

    run cat "${_MARK}"
    assert_output --partial "ran args=[alpha beta gamma]"
    assert_output --partial "env AICRON_TEST_JOB=from-job"
    # job env overrides defaults.env
    assert_output --partial "env AICRON_TEST_DEFAULT=overridden"
    # $HOME and ${HOME} are expanded, nothing else is
    assert_output --partial "env AICRON_TEST_HOMEPATH=${HOME}/bin:${HOME}/sbin"
}

@test "aicron: run appends the job's stdout and stderr to the log" {
    _aicron run hello
    assert_success

    run cat "${_STATE_DIR}/logs/hello.log"
    assert_output --partial "hello stdout"
    assert_output --partial "hello stderr"
}

@test "aicron: run propagates a failing job's exit code" {
    _aicron run boom
    assert_failure 7
    run _state_field boom .last_exit
    assert_output "7"
}

@test "aicron: run on an unknown job exits 2" {
    _aicron run nope
    assert_failure 2
}

@test "aicron: run exits 1 when the job script file is missing" {
    _aicron run ghost
    assert_failure 1
}

@test "aicron: a second concurrent run skips silently with exit 0" {
    _hold_job_lock hello
    _aicron run hello
    assert_success
    run cat "${_MARK}"
    refute_output --partial "ran args="
}

@test "aicron: run works from a bare cron-like environment (NF-2)" {
    run env -i \
        HOME="${HOME}" \
        PATH="/usr/local/bin:/usr/bin:/bin" \
        AICRON_MANIFEST="${_MANIFEST}" \
        AICRON_STATE_DIR="${_STATE_DIR}" \
        "${SCRIPT}" run hello
    assert_success
    run cat "${_MARK}"
    assert_output --partial "ran args=[alpha beta gamma]"
}

# A manifest `script` is relative to DOTFILES_ROOT, and DOTFILES_ROOT is this
# file's own checkout — never whatever the calling shell exported. The fixture
# job is aicron itself (`... run self` -> `aicron help`), because that is a
# relative path guaranteed to exist in every checkout without this test
# writing anything into the repo.
@test "aicron: run resolves a manifest script path relative to its own checkout" {
    cat >"${_MANIFEST}" <<EOF
{ "defaults": { "env": {} },
  "jobs": [ { "name": "self", "script": "shell-common/tools/custom/aicron.sh",
              "schedule": "0 0 * * *", "args": ["help"], "env": {},
              "description": "relative path job" } ] }
EOF

    _aicron run self
    assert_success
    run cat "${_STATE_DIR}/logs/self.log"
    assert_output --partial "Usage: aicron"
}

@test "aicron: DOTFILES_ROOT from the environment does not steer the script lookup" {
    cat >"${_MANIFEST}" <<EOF
{ "defaults": { "env": {} },
  "jobs": [ { "name": "self", "script": "shell-common/tools/custom/aicron.sh",
              "schedule": "0 0 * * *", "args": ["help"], "env": {},
              "description": "relative path job" } ] }
EOF

    run env PATH="${_BIN_DIR}:${PATH}" \
        HOME="${HOME}" \
        DOTFILES_ROOT="${_WORK_DIR}/not-a-checkout" \
        AICRON_MANIFEST="${_MANIFEST}" \
        AICRON_STATE_DIR="${_STATE_DIR}" \
        bash "${SCRIPT}" run self
    assert_success
}

@test "aicron: run survives an unwritable state dir and still executes the job" {
    chmod 500 "${_STATE_DIR}"
    _aicron run hello
    chmod 700 "${_STATE_DIR}"
    assert_success
    run cat "${_MARK}"
    assert_output --partial "ran args="
}

@test "aicron: run treats a corrupt state file as absent and rewrites it" {
    printf 'not json at all\n' >"${_STATE_DIR}/hello.json"
    _aicron run hello
    assert_success
    assert_output --partial "state"
    run jq -e . "${_STATE_DIR}/hello.json"
    assert_success
    run _state_field hello .last_exit
    assert_output "0"
}

# ---------------------------------------------------------------------------
# log rollover (D-7)
# ---------------------------------------------------------------------------

@test "aicron: an oversized log rolls to .1 and a fresh log starts" {
    mkdir -p "${_STATE_DIR}/logs"
    printf 'old log content that is longer than the cap\n' >"${_STATE_DIR}/logs/hello.log"

    run env PATH="${_BIN_DIR}:${PATH}" \
        HOME="${HOME}" \
        AICRON_MANIFEST="${_MANIFEST}" \
        AICRON_STATE_DIR="${_STATE_DIR}" \
        _AICRON_LOG_MAX_BYTES=10 \
        bash "${SCRIPT}" run hello
    assert_success

    run cat "${_STATE_DIR}/logs/hello.log.1"
    assert_output --partial "old log content"
    run cat "${_STATE_DIR}/logs/hello.log"
    refute_output --partial "old log content"
    assert_output --partial "hello stdout"
}

@test "aicron: a log under the cap is not rolled" {
    _aicron run hello
    assert_success
    [ ! -f "${_STATE_DIR}/logs/hello.log.1" ]
}

# ---------------------------------------------------------------------------
# status
# ---------------------------------------------------------------------------

@test "aicron: status reports not-running plus the last run result" {
    _aicron run hello
    assert_success
    _aicron status hello
    assert_success
    assert_output --partial "hello"
    assert_output --partial "*/5 * * * *"
    assert_output --partial "no"
}

@test "aicron: status reports a job whose lock is held as running" {
    _hold_job_lock hello
    _aicron status hello --json
    assert_success
    _capture_json
    run jq -r .running "${_JSON}"
    assert_output "true"
}

@test "aicron: status --json passes jq -e . and carries the last run result" {
    _aicron run boom
    assert_failure 7
    _aicron status boom --json
    assert_success
    _capture_json

    run jq -e . "${_JSON}"
    assert_success
    run jq -r .last_exit "${_JSON}"
    assert_output "7"
    run jq -r .running "${_JSON}"
    assert_output "false"
    run jq -r .installed "${_JSON}"
    assert_output "false"
    run jq -r .paused "${_JSON}"
    assert_output "false"
}

@test "aicron: status on an unknown job exits 2" {
    _aicron status nope
    assert_failure 2
}

# ---------------------------------------------------------------------------
# doctor
# ---------------------------------------------------------------------------

@test "aicron: doctor reports a clean setup" {
    _aicron add hello
    assert_success
    # `ghost` has no script on disk by design — drop it for the clean case.
    jq 'del(.jobs[] | select(.name=="ghost"))' "${_MANIFEST}" >"${_MANIFEST}.tmp"
    mv "${_MANIFEST}.tmp" "${_MANIFEST}"

    _aicron doctor
    assert_success
    refute_output --partial "orphan"
}

@test "aicron: doctor detects a marker block for a job absent from the manifest" {
    cat >>"${_CRONTAB_FILE}" <<EOF
# BEGIN aicron:stale-job
0 0 * * * ${SCRIPT} run stale-job
# END aicron:stale-job
EOF
    _aicron doctor
    assert_success
    assert_output --partial "stale-job"
}

@test "aicron: doctor detects a manifest job whose script file is missing" {
    _aicron doctor
    assert_success
    assert_output --partial "ghost"
    assert_output --partial "never-created.sh"
}

@test "aicron: doctor detects a corrupt state file" {
    printf 'garbage\n' >"${_STATE_DIR}/boom.json"
    _aicron doctor
    assert_success
    assert_output --partial "boom.json"
}

@test "aicron: doctor detects duplicate marker blocks for one job" {
    cat >>"${_CRONTAB_FILE}" <<EOF
# BEGIN aicron:hello
*/5 * * * * ${SCRIPT} run hello
# END aicron:hello
# BEGIN aicron:hello
*/9 * * * * ${SCRIPT} run hello
# END aicron:hello
EOF
    _aicron doctor
    assert_success
    assert_output --partial "duplicate"
}

# ---------------------------------------------------------------------------
# shipped manifest
# ---------------------------------------------------------------------------

@test "aicron: the shipped cron-jobs.json is valid JSON with real script paths" {
    local _shipped="${DOTFILES_ROOT}/shell-common/tools/custom/cron-jobs.json"
    run jq -e . "${_shipped}"
    assert_success

    local _s
    while IFS= read -r _s; do
        [ -f "${DOTFILES_ROOT}/${_s}" ] || fail "manifest script missing: ${_s}"
    done < <(jq -r '.jobs[].script' "${_shipped}")
}
