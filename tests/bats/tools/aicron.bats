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

# A `crontab` whose `-l` fails for a REAL reason (EACCES, a broken install) —
# not the benign "no crontab for <user>" the default stub reports for an empty
# table. Telling those two apart is the whole of B1.
_break_crontab_dump() {
    cat >"${_BIN_DIR}/crontab" <<EOF
#!/usr/bin/env bash
printf 'crontab %s\n' "\$*" >>"${_LOG}"
case "\${1:-}" in
    -l)
        echo "crontab: cannot read /var/spool/cron/crontabs/tester: Permission denied" >&2
        exit 1
        ;;
    -)
        cat >"${_CRONTAB_FILE}"
        exit 0
        ;;
esac
exit 1
EOF
    chmod +x "${_BIN_DIR}/crontab"
}

# A `crontab` that, while aicron is mid-dump, plants a symlink at every temp
# path the old fixed-name scheme (`${TMPDIR}/aicron-crontab.$$`) could have
# picked, pointing at ${_WORK_DIR}/victim.
#
# The pid is not guessed: this stub is forked BY aicron, so $PPID is either
# aicron's own shell or the subshell it ran the dump in, and /proc gives the
# parent of that. Under the old code the very next write followed one of those
# symlinks and created the victim file; under mktemp names nothing can.
_install_planting_crontab_stub() {
    cat >"${_BIN_DIR}/crontab" <<EOF
#!/usr/bin/env bash
printf 'crontab %s\n' "\$*" >>"${_LOG}"
if [ "\${1:-}" = "-l" ]; then
    _p="\$PPID"
    _i=0
    while [ -n "\$_p" ] && [ "\$_p" != "1" ] && [ "\$_i" -lt 6 ]; do
        ln -sfn "${_WORK_DIR}/victim" "\${TMPDIR}/aicron-crontab.\$_p" 2>/dev/null || true
        _p=\$(awk '{print \$4}' "/proc/\$_p/stat" 2>/dev/null)
        _i=\$((_i + 1))
    done
fi
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
esac
exit 1
EOF
    chmod +x "${_BIN_DIR}/crontab"
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

# _aicron with the process's stderr dropped before bats can merge it into
# $output. The three-valued views warn on stderr precisely so that `--json`
# stays machine-readable, and `run` merging the two streams would hide the
# difference this suite has to assert.
_aicron_json() {
    run env PATH="${_BIN_DIR}:${PATH}" \
        HOME="${HOME}" \
        AICRON_MANIFEST="${_MANIFEST}" \
        AICRON_STATE_DIR="${_STATE_DIR}" \
        bash -c 'exec bash "$0" "$@" 2>/dev/null' "${SCRIPT}" "$@"
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

@test "aicron: doctor detects a manifest job installed under a stale schedule (#1496)" {
    _aicron add hello
    assert_success
    # The manifest changed after `add` ran — mirrors #1496: the crontab was
    # never reinstalled, so the two schedules disagree.
    jq '(.jobs[] | select(.name=="hello") | .schedule) = "*/9 * * * *"' \
        "${_MANIFEST}" >"${_MANIFEST}.tmp"
    mv "${_MANIFEST}.tmp" "${_MANIFEST}"

    _aicron doctor
    assert_success
    assert_output --partial "schedule drift for job hello"
    assert_output --partial '"*/9 * * * *"'
    assert_output --partial '"*/5 * * * *"'
}

@test "aicron: doctor stays quiet when the installed schedule matches the manifest" {
    _aicron add hello
    assert_success
    _aicron doctor
    assert_success
    refute_output --partial "schedule drift"
}

@test "aicron: doctor does not false-positive on manifest whitespace padding (#1496 review, agy)" {
    _aicron add hello
    assert_success
    # Column-aligned padding in a hand-edited manifest is valid cron syntax
    # but not byte-identical to the crontab's normalized single-space form —
    # the comparison must collapse it, not treat it as drift.
    jq '(.jobs[] | select(.name=="hello") | .schedule) = "*/5   *   *   *   *"' \
        "${_MANIFEST}" >"${_MANIFEST}.tmp"
    mv "${_MANIFEST}.tmp" "${_MANIFEST}"

    _aicron doctor
    assert_success
    refute_output --partial "schedule drift"
}

@test "aicron: doctor compares @-macro schedules too, not just 5-field ones (#1496 review, codex)" {
    jq '(.jobs[] | select(.name=="hello") | .schedule) = "@daily"' \
        "${_MANIFEST}" >"${_MANIFEST}.tmp"
    mv "${_MANIFEST}.tmp" "${_MANIFEST}"
    _aicron add hello
    assert_success

    jq '(.jobs[] | select(.name=="hello") | .schedule) = "@weekly"' \
        "${_MANIFEST}" >"${_MANIFEST}.tmp"
    mv "${_MANIFEST}.tmp" "${_MANIFEST}"

    _aicron doctor
    assert_success
    assert_output --partial "schedule drift for job hello"
    assert_output --partial '"@weekly"'
    assert_output --partial '"@daily"'
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

# ---------------------------------------------------------------------------
# crontab dump failures (B1) — a table we could not read is never an empty one
# ---------------------------------------------------------------------------

@test "aicron: add aborts with exit 3 and writes nothing when the crontab cannot be read" {
    _break_crontab_dump
    _aicron add hello
    assert_failure 3
    assert_output --partial "Permission denied"

    # The table is untouched, and `crontab -` was never even invoked: a dump
    # failure read as "the table is empty" is what would have replaced every
    # hand-written line with our one marker block.
    run cmp "${_CRONTAB_FILE}" "${_BASELINE}"
    assert_success
    run grep -c '^crontab -$' "${_LOG}"
    assert_output "0"
}

@test "aicron: remove aborts with exit 3 when the crontab cannot be read" {
    _aicron add hello
    assert_success
    cp "${_CRONTAB_FILE}" "${_WORK_DIR}/after-add"

    _break_crontab_dump
    _aicron remove hello
    assert_failure 3
    assert_output --partial "Permission denied"
    run cmp "${_CRONTAB_FILE}" "${_WORK_DIR}/after-add"
    assert_success
}

@test "aicron: list reports installed as unknown, not no, when the crontab cannot be read" {
    _break_crontab_dump
    _aicron list
    assert_success
    assert_output --partial "installed=unknown"
    assert_output --partial "could not read the crontab"

    # The warning goes to stderr so --json stays parseable, and the unknown
    # answer is null rather than the false that would read as "not installed".
    _aicron_json list --json
    assert_success
    _capture_json
    run jq -e . "${_JSON}"
    assert_success
    run jq -r '.jobs[] | select(.name=="hello") | .installed' "${_JSON}"
    assert_output "null"
}

@test "aicron: status reports installed as unknown when the crontab cannot be read" {
    _break_crontab_dump
    _aicron_json status hello --json
    assert_success
    _capture_json
    run jq -e . "${_JSON}"
    assert_success
    run jq -r .installed "${_JSON}"
    assert_output "null"
}

@test "aicron: doctor says the crontab could not be read instead of listing every job as drifted" {
    _break_crontab_dump
    _aicron doctor
    assert_success
    assert_output --partial "the crontab could not be read"
    refute_output --partial "orphan crontab block"
}

@test "aicron: a user with no crontab yet is an empty table, not a failure" {
    rm -f "${_CRONTAB_FILE}"
    _aicron add hello
    assert_success

    run cat "${_CRONTAB_FILE}"
    assert_output --partial "# BEGIN aicron:hello"
    run grep -c . "${_CRONTAB_FILE}"
    assert_output "3"
}

# ---------------------------------------------------------------------------
# temp files (B2) — unguessable names, no fixed-path fallback
# ---------------------------------------------------------------------------

@test "aicron: no temp path is derived from the pid" {
    # grep answers 1 for "nothing matched" and 2 for "I could not read that
    # file", and assert_failure took both — so this guard went green when the
    # very sources it scans were missing or moved, which is the one scenario a
    # B2 regression is most likely to arrive with (#1479).
    local -a _sources=(
        "${SCRIPT}"
        "${DOTFILES_ROOT}"/shell-common/tools/custom/lib/aicron_*.sh
    )

    # An unmatched glob leaves the literal pattern in the array, so the -f
    # check below covers both "the file is gone" and "the glob matched
    # nothing" with one test.
    local _f
    for _f in "${_sources[@]}"; do
        [ -f "${_f}" ] || fail "guard target is missing, so this test proves nothing: ${_f}"
    done

    run grep -En '[$][$]' "${_sources[@]}"
    assert_failure 1

    # Positive control over the SAME operand list plus one planted file: a
    # fixture-only control would prove the pattern still matches something,
    # not that this invocation — this source list, this glob expansion —
    # still reports a match when one of its own files goes bad.
    printf '_tmp="${TMPDIR}/aicron.$$"\n' >"${_WORK_DIR}/pid_derived.sh"
    run grep -En '[$][$]' "${_sources[@]}" "${_WORK_DIR}/pid_derived.sh"
    assert_success
}

@test "aicron: a symlink planted at the old fixed crontab temp path is not followed" {
    export TMPDIR="${_WORK_DIR}/tmp"
    mkdir -p "${TMPDIR}"
    _install_planting_crontab_stub

    _aicron add hello
    assert_success

    [ ! -e "${_WORK_DIR}/victim" ]
    run cat "${_CRONTAB_FILE}"
    assert_output --partial "# BEGIN aicron:hello"
}

@test "aicron: a symlink planted at the old fixed rc temp path is not followed" {
    export TMPDIR="${_WORK_DIR}/tmp"
    mkdir -p "${TMPDIR}"

    # The job itself does the planting: by the time it runs, the flock
    # subshell that would write the rc file exists, and walking /proc up from
    # $PPID covers both it and aicron's own shell without guessing a pid.
    cat >"${_JOB_DIR}/planter.sh" <<'PLANT'
#!/usr/bin/env bash
_p="$PPID"
_i=0
while [ -n "$_p" ] && [ "$_p" != "1" ] && [ "$_i" -lt 6 ]; do
    ln -sfn "${VICTIM}" "${TMPDIR}/aicron-rc.${_p}" 2>/dev/null || true
    _p=$(awk '{print $4}' "/proc/${_p}/stat" 2>/dev/null)
    _i=$((_i + 1))
done
exit 0
PLANT
    chmod +x "${_JOB_DIR}/planter.sh"
    jq --arg s "${_JOB_DIR}/planter.sh" --arg v "${_WORK_DIR}/victim" \
        '.jobs += [{name:"planter",script:$s,schedule:"0 0 * * *",args:[],
                    env:{VICTIM:$v},description:"plants symlinks"}]' \
        "${_MANIFEST}" >"${_MANIFEST}.tmp"
    mv "${_MANIFEST}.tmp" "${_MANIFEST}"

    _aicron run planter
    assert_success
    [ ! -e "${_WORK_DIR}/victim" ]
    run _state_field planter .last_exit
    assert_output "0"
}

@test "aicron: add fails cleanly when mktemp is unavailable instead of using a fixed path" {
    run env PATH="$(_path_without mktemp)" \
        HOME="${HOME}" \
        AICRON_MANIFEST="${_MANIFEST}" \
        AICRON_STATE_DIR="${_STATE_DIR}" \
        bash "${SCRIPT}" add hello
    assert_failure 3
    run cmp "${_CRONTAB_FILE}" "${_BASELINE}"
    assert_success
}

# ---------------------------------------------------------------------------
# a run that is killed mid-flight (B3)
# ---------------------------------------------------------------------------

@test "aicron: a run killed after taking the lock is a failure, not a silent success" {
    # Killing the subshell that holds the lock is exactly what an OOM kill
    # does: the lock was taken, the job never reported a code. The empty rc
    # file that leaves behind used to be indistinguishable from "the lock was
    # busy", so cron was told 0.
    cat >"${_JOB_DIR}/killer.sh" <<'KILLER'
#!/usr/bin/env bash
kill -9 "$PPID" 2>/dev/null
exit 0
KILLER
    chmod +x "${_JOB_DIR}/killer.sh"
    jq --arg s "${_JOB_DIR}/killer.sh" \
        '.jobs += [{name:"killer",script:$s,schedule:"0 0 * * *",args:[],env:{},
                    description:"dies mid-run"}]' \
        "${_MANIFEST}" >"${_MANIFEST}.tmp"
    mv "${_MANIFEST}.tmp" "${_MANIFEST}"

    _aicron run killer
    assert_failure 4
    assert_output --partial "without reporting an exit code"
}

# ---------------------------------------------------------------------------
# remove and doctor drift (B4)
# ---------------------------------------------------------------------------

@test "aicron: remove cleans the orphan crontab block doctor reports" {
    _aicron add hello
    assert_success
    jq 'del(.jobs[] | select(.name=="hello"))' "${_MANIFEST}" >"${_MANIFEST}.tmp"
    mv "${_MANIFEST}.tmp" "${_MANIFEST}"

    _aicron doctor
    assert_success
    assert_output --partial "orphan crontab block"

    _aicron remove hello
    assert_success
    run cmp "${_CRONTAB_FILE}" "${_BASELINE}"
    assert_success

    _aicron doctor
    assert_success
    refute_output --partial "orphan crontab block"
}

@test "aicron: remove exits 2 when neither the manifest nor the crontab knows the job" {
    _aicron remove nope
    assert_failure 2
    run cmp "${_CRONTAB_FILE}" "${_BASELINE}"
    assert_success
}

@test "aicron: add still requires manifest membership" {
    cat >>"${_CRONTAB_FILE}" <<EOF
# BEGIN aicron:stale-job
0 0 * * * ${SCRIPT} run stale-job
# END aicron:stale-job
EOF
    _aicron add stale-job
    assert_failure 2
    _aicron run stale-job
    assert_failure 2
    _aicron pause stale-job
    assert_failure 2
}

# ---------------------------------------------------------------------------
# argument validation (F3)
# ---------------------------------------------------------------------------

@test "aicron: run rejects an extra argument instead of silently dropping it" {
    _aicron run hello --dry-run
    assert_failure 1
    assert_output --partial "unexpected argument"
    run cat "${_MARK}"
    refute_output --partial "ran args="
}

@test "aicron: remove, pause, resume and status reject an extra argument" {
    _aicron remove hello extra
    assert_failure 1
    _aicron pause hello extra
    assert_failure 1
    _aicron resume hello extra
    assert_failure 1
    _aicron status hello extra
    assert_failure 1

    run cmp "${_CRONTAB_FILE}" "${_BASELINE}"
    assert_success
    [ ! -f "${_STATE_DIR}/hello.json" ]
}

@test "aicron: add rejects an unknown flag and a second job name" {
    _aicron add hello --dry-run
    assert_failure 1
    _aicron add hello boom
    assert_failure 1
    run cmp "${_CRONTAB_FILE}" "${_BASELINE}"
    assert_success
}

# ---------------------------------------------------------------------------
# degraded state dir and lock probe (F4, F5)
# ---------------------------------------------------------------------------

@test "aicron: an unwritable state dir warns that single-instance protection is gone too" {
    chmod 500 "${_STATE_DIR}"
    _aicron run hello
    chmod 700 "${_STATE_DIR}"
    assert_success
    assert_output --partial "single-instance protection"
    run cat "${_MARK}"
    assert_output --partial "ran args="
}

@test "aicron: status reports running as unknown when the lock probe cannot answer" {
    # The lock file exists, so the job may well be running — but with no flock
    # the probe cannot tell, and "no" would read as a healthy idle job.
    : >"${_STATE_DIR}/hello.lock"

    run env PATH="$(_path_without flock)" \
        HOME="${HOME}" \
        AICRON_MANIFEST="${_MANIFEST}" \
        AICRON_STATE_DIR="${_STATE_DIR}" \
        bash "${SCRIPT}" status hello
    assert_success
    assert_output --partial "unknown"
    assert_output --partial "could not probe the run lock"

    run env PATH="$(_path_without flock)" \
        HOME="${HOME}" \
        AICRON_MANIFEST="${_MANIFEST}" \
        AICRON_STATE_DIR="${_STATE_DIR}" \
        bash -c 'exec bash "$0" "$@" 2>/dev/null' "${SCRIPT}" status hello --json
    assert_success
    _capture_json
    run jq -e . "${_JSON}"
    assert_success
    run jq -r .running "${_JSON}"
    assert_output "null"
}

# ---------------------------------------------------------------------------
# the pre-commit gate this tool has to pass (F1, F2)
# ---------------------------------------------------------------------------

# The hook checks read staged content first, so these tests run from a
# non-repo cwd: that makes `git cat-file` fail, the worktree fallback take
# over, and the files ON DISK — the ones this PR changes — be what is judged.
_load_hook_checks() {
    # shellcheck source=/dev/null
    source "${DOTFILES_ROOT}/git/hooks/checks/shared.sh"
    # shellcheck source=/dev/null
    source "${DOTFILES_ROOT}/git/hooks/checks/direct_exec_guard_check.sh"
    # shellcheck source=/dev/null
    source "${DOTFILES_ROOT}/git/hooks/checks/custom_tools_entrypoint_check.sh"
}

@test "aicron: custom_tool_class exempts custom/lib/ only, not every subdirectory" {
    _load_hook_checks
    run custom_tool_class "shell-common/tools/custom/aicron.sh"
    assert_output "entrypoint"
    run custom_tool_class "shell-common/tools/custom/lib/aicron_run.sh"
    assert_output "lib"
    # A future nested layout is not silently exempt from the entry-point
    # policy — it falls through to the generic rules.
    run custom_tool_class "shell-common/tools/custom/nested/tool.sh"
    assert_output ""
}

@test "aicron: the direct-exec guard gate rejects a file that only mentions the basename pattern" {
    _load_hook_checks
    local _root="${_WORK_DIR}/hookrepo"
    mkdir -p "${_root}/shell-common/tools/custom"
    cat >"${_root}/shell-common/tools/custom/mention_only.sh" <<'MENTION'
#!/bin/bash
main() {
    printf 'no guard here\n'
}
# This file merely names "${0##*/}" in a comment; it never tests it.
main "$@"
MENTION
    cd "${_WORK_DIR}"

    run check_direct_exec_guard "${_root}" "${_WORK_DIR}" \
        "shell-common/tools/custom/mention_only.sh" "${_WORK_DIR}/hook.out"
    assert_failure
    run cat "${_WORK_DIR}/hook.out"
    assert_output --partial "Missing direct-exec guard"

    run check_auto_executable_in_custom "${_root}" "${_WORK_DIR}" \
        "shell-common/tools/custom/mention_only.sh" "${_WORK_DIR}/hook2.out"
    assert_failure
}

@test "aicron: the direct-exec guard gate still accepts aicron.sh and ensure_jq.sh" {
    _load_hook_checks
    local _root="${_WORK_DIR}/hookrepo"
    mkdir -p "${_root}/shell-common/tools/custom"
    local _f
    for _f in aicron.sh ensure_jq.sh; do
        cp "${DOTFILES_ROOT}/shell-common/tools/custom/${_f}" \
            "${_root}/shell-common/tools/custom/${_f}"
    done
    cd "${_WORK_DIR}"

    for _f in aicron.sh ensure_jq.sh; do
        run check_direct_exec_guard "${_root}" "${_WORK_DIR}" \
            "shell-common/tools/custom/${_f}" "${_WORK_DIR}/hook.out"
        assert_success
        run check_auto_executable_in_custom "${_root}" "${_WORK_DIR}" \
            "shell-common/tools/custom/${_f}" "${_WORK_DIR}/hook.out"
        assert_success
    done
}

# ---------------------------------------------------------------------------
# The shipped manifest (issue #1561)
# ---------------------------------------------------------------------------
#
# Like the "shipped manifest" section above, these read the real
# shell-common/tools/custom/cron-jobs.json rather than a fixture. They are the
# exception the header rule anticipates: what these two jobs are routed at is
# not a property of aicron, it is a property of the file that ships, and #1561
# turned on that routing — an unattended pane opened on the wrong account is an
# account that was never logged in, so every prompt stalls.
#
# Asserted through aicron_manifest_env, not through a re-implemented jq
# expression: that is the function aicron_run_exec feeds to `env`, so this pins
# what the job would actually be started with, defaults ∪ job merge included.
# The account itself lives in `defaults.env` and is deliberately *not* repeated
# on each job — the manifest is version-controlled and the account name is
# per-PC (aicron_manifest.sh, `docs/.ssot/pc-environment.md`), so one machine's
# value is written once, in the one place that already carries machine values.

# The KEY=VALUE lines aicron would hand `env` for job <1> of the shipped
# manifest.
_shipped_env() {
    (
        AICRON_MANIFEST="${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/custom/cron-jobs.json"
        export AICRON_MANIFEST
        # shellcheck source=/dev/null
        . "${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/custom/lib/aicron_manifest.sh"
        aicron_manifest_env "$1"
    )
}

@test "aicron: the shipped issue-watcher job is routed at the work1 account" {
    run _shipped_env issue-watcher
    assert_success
    assert_line "CLAUDE_DEFAULT_ACCOUNT=work1"
}

@test "aicron: the shipped merge-train job is routed at the work1 account" {
    run _shipped_env merge-train
    assert_success
    assert_line "CLAUDE_DEFAULT_ACCOUNT=work1"
}
