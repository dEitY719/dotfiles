#!/usr/bin/env bats
# tests/bats/skills/run_trigger_eval.bats
# Unit coverage for claude/tools/run-trigger-eval.sh — the manual
# trigger-accuracy harness (#1417).
#
# Why this file exists: tests/integration/test_trigger_eval_sets.py pins the
# eval JSON sets and two string constants, but never executes the harness's
# scheduling, aggregation or exit-status paths — which is exactly where the
# PR #1429 review found three ways for a broken run to report success. The
# harness now wraps its top-level flow in main() behind a
# `[ "${BASH_SOURCE[0]}" = "$0" ]` guard (the tests/test idiom from #1397), so
# those functions can be driven here with hand-built inputs.
#
# Nothing below invokes `claude`, the network or run_eval.py: the seam is the
# `python3 -m scripts.run_eval` call, stubbed via PATH.
#
# PR #1429 review checklist:
#   D-1  an empty or failed _describe never reaches a measurement — it must
#        not fall through to run_eval's `args.description or original`, which
#        would measure the after-description against itself and always PASS
#   D-2  zero data rows, or any job that did not complete, exits non-zero with
#        a HARNESS message instead of "0 skill(s) below contract" and exit 0
#   D-3  a stale <skill>.<arm>.tsv in a REUSED --out-dir never enters the
#        verdict; the run aggregates only the files it wrote itself
#   D-4  the copied .credentials.json is 0600 from creation, never at the
#        umask default
#   D-5  a missing required command fails fast, before any temp dir exists
#   D-6  the CLI surface and the source guard still behave

load '../test_helper'

HARNESS="${_BATS_REAL_DOTFILES_ROOT}/claude/tools/run-trigger-eval.sh"

setup() {
    setup_isolated_home
    # Safe: every top-level statement is a definition or a default assignment,
    # and main() runs only under the BASH_SOURCE guard.
    # shellcheck source=/dev/null
    . "$HARNESS"

    OUT_DIR="${TEST_TEMP_HOME}/out"
    mkdir -p "$OUT_DIR"
    JOB_TSVS=()
    SCHED_FAILURES=0
}

teardown() {
    teardown_isolated_home
}

# ---- fixture builders ----------------------------------------------------

# A job that completed: its row exists AND is registered as this run's output.
_seed_job() {  # skill arm passed total pct
    local f="${OUT_DIR}/${1}.${2}.tsv"
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" > "$f"
    JOB_TSVS+=("$f")
}

# A job that was launched and then died: registered, but no row on disk.
_seed_failed_job() {  # skill arm
    JOB_TSVS+=("${OUT_DIR}/${1}.${2}.tsv")
}

# A row an EARLIER run left in the same --out-dir. Deliberately NOT registered.
_seed_stale_row() {  # skill arm passed total pct
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" \
        > "${OUT_DIR}/${1}.${2}.tsv"
}

# Everything _run_job reads from the environment, pointed at throwaway paths,
# plus the PATH stub that stands in for `python3 -m scripts.run_eval`.
_stage_job_env() {
    SESSION_TMP="${TEST_TEMP_HOME}/session"
    SRC_CONFIG="${TEST_TEMP_HOME}/srcconfig"
    SKILLS_SRC="${TEST_TEMP_HOME}/skills"
    SKILL_CREATE="${SKILLS_SRC}/skill-create"
    EVAL_SET_REL="evals/trigger-eval.json"
    mkdir -p "$SESSION_TMP" "$SRC_CONFIG"
    printf '{"not":"a real token"}\n' > "${SRC_CONFIG}/.credentials.json"

    PROBE_BIN="${TEST_TEMP_HOME}/bin"
    PROBE_STDOUT_FILE="${TEST_TEMP_HOME}/probe-stdout"
    PROBE_PERM_FILE="${TEST_TEMP_HOME}/probe-perm"
    export PROBE_STDOUT_FILE PROBE_PERM_FILE
    mkdir -p "$PROBE_BIN"

    cat > "${PROBE_BIN}/python3" <<'STUB'
#!/usr/bin/env bash
# Stands in for `python3 -m scripts.run_eval`: no claude, no network, no
# run_eval.py. Records the mode of the credentials copy as it exists WHILE a
# probe would be running (the harness deletes the copy right afterwards), then
# replays a canned result document.
if [ -n "${PROBE_PERM_FILE:-}" ] && [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    stat -c '%a' "${CLAUDE_CONFIG_DIR}/.credentials.json" > "$PROBE_PERM_FILE" 2>/dev/null \
        || stat -f '%Lp' "${CLAUDE_CONFIG_DIR}/.credentials.json" > "$PROBE_PERM_FILE"
fi
cat "$PROBE_STDOUT_FILE"
STUB
    chmod +x "${PROBE_BIN}/python3"
    PATH="${PROBE_BIN}:${PATH}"
    hash -r 2> /dev/null || true

    printf '%s\n' '{"summary":{"passed":18,"total":20},"results":[{"should_trigger":true,"pass":true},{"should_trigger":false,"pass":false}]}' \
        > "$PROBE_STDOUT_FILE"
}

# ---- D-6: the source guard and the CLI surface ---------------------------

@test "guard: sourcing the harness defines main() and executes nothing" {
    run bash -c ". '$HARNESS'; printf 'defined:%s\n' \"\$(declare -F main)\""
    assert_success
    assert_output 'defined:main'
}

@test "cli: --help prints usage, documents the exit codes, and exits 0" {
    run bash "$HARNESS" --help
    assert_success
    assert_output --partial 'Usage: run-trigger-eval.sh'
    assert_output --partial 'Exit status:'
    assert_output --partial 'HARNESS'
}

@test "cli: no skill named exits 2" {
    run bash "$HARNESS"
    [ "$status" -eq 2 ]
    assert_output --partial 'no skill named'
}

@test "cli: an unknown option exits 2" {
    run bash "$HARNESS" --definitely-not-an-option gh-commit
    [ "$status" -eq 2 ]
    assert_output --partial 'unknown option'
}

@test "cli: a bad --arm exits 2" {
    run bash "$HARNESS" --arm sideways gh-commit
    [ "$status" -eq 2 ]
    assert_output --partial 'must be before|after|both'
}

# ---- D-5: dependency preflight -------------------------------------------

@test "D-5: a missing required command fails fast and names what is missing" {
    local empty="${TEST_TEMP_HOME}/emptybin"
    mkdir -p "$empty"
    # Sourcing and _preflight need no external command at all, so an empty
    # PATH isolates exactly the check under test.
    run bash -c "PATH='$empty'; . '$HARNESS'; _preflight"
    [ "$status" -eq 2 ]
    assert_output --partial 'missing required command'
    assert_output --partial 'jq'
    assert_output --partial 'claude'
}

@test "D-5: preflight passes when every required command resolves" {
    # Stubs rather than the real tools, so the check under test is the only
    # variable — CI has no `claude` on PATH.
    local bin="${TEST_TEMP_HOME}/allbin" cmd
    mkdir -p "$bin"
    for cmd in jq python3 git claude; do
        printf '#!/bin/sh\nexit 0\n' > "${bin}/${cmd}"
        chmod +x "${bin}/${cmd}"
    done
    run bash -c "PATH='$bin'; . '$HARNESS'; _preflight"
    assert_success
}

# ---- D-1: an unusable description never reaches a measurement -------------

@test "D-1: an EMPTY description is a job failure, not a silent fallback" {
    _describe() { printf ''; }          # exits 0, yields nothing
    _spawn() { printf 'SPAWNED\n'; }
    run _schedule_arm gh-commit before "${TEST_TEMP_HOME}/before-src"
    assert_failure
    refute_output --partial 'SPAWNED'
    assert_output --partial 'ERROR'
}

@test "D-1: a FAILING _describe is a job failure, not a silent fallback" {
    _describe() { printf 'traceback\n' >&2; return 1; }
    _spawn() { printf 'SPAWNED\n'; }
    run _schedule_arm gh-commit before "${TEST_TEMP_HOME}/before-src"
    assert_failure
    refute_output --partial 'SPAWNED'
    assert_output --partial 'ERROR'
}

@test "D-1: a usable description is handed to the job verbatim" {
    _describe() { printf 'Use for /gh:commit, 커밋해.'; }
    _spawn() { printf 'SPAWNED:%s|%s|%s\n' "$1" "$2" "$3"; }
    run _schedule_arm gh-commit before "${TEST_TEMP_HOME}/before-src"
    assert_success
    assert_output 'SPAWNED:gh-commit|before|Use for /gh:commit, 커밋해.'
}

@test "D-1: a failed arm is counted, so the run cannot finish green" {
    _describe() { printf ''; }
    _spawn() { :; }
    _schedule_arm gh-commit before "${TEST_TEMP_HOME}/before-src" > /dev/null || true
    [ "$SCHED_FAILURES" -eq 1 ]

    # Another skill measured cleanly; the run must still fail as a HARNESS
    # failure rather than reporting the healthy pair as a green result.
    _seed_job sh-check before 18 20 90.0
    _seed_job sh-check after 18 20 90.0
    run _verdict
    [ "$status" -eq 3 ]
    assert_output --partial 'HARNESS FAILURE'
}

# ---- verdict math --------------------------------------------------------

@test "verdict: after exactly at the margin is PASS" {
    _seed_job gh-commit before 18 20 90.0
    _seed_job gh-commit after 17 20 85.0
    run _verdict
    assert_success
    assert_output --partial 'PASS'
    refute_output --partial 'FAIL'
    assert_output --partial '0 skill(s) below contract'
}

@test "verdict: after one tenth past the margin is FAIL and exits 1" {
    _seed_job gh-commit before 18 20 90.0
    _seed_job gh-commit after 17 20 84.9
    run _verdict
    [ "$status" -eq 1 ]
    assert_output --partial 'FAIL'
    assert_output --partial '1 skill(s) below contract'
}

@test "verdict: a skipped before arm reads INCOMPLETE, not PASS" {
    _seed_job gh-commit after 17 20 85.0
    run _verdict
    assert_success
    assert_output --partial 'INCOMPLETE'
    refute_output --partial 'PASS'
    assert_output --partial '0 skill(s) below contract'
}

# ---- D-2: a broken run must never read as a clean one --------------------

@test "D-2: zero data rows is a HARNESS failure, not '0 skill(s) below contract'" {
    run _verdict
    [ "$status" -eq 3 ]
    assert_output --partial 'HARNESS FAILURE'
    assert_output --partial 'NOT a contract result'
    refute_output --partial 'skill(s) below contract'
}

@test "D-2: every job failing is a HARNESS failure, not a green run" {
    _seed_failed_job gh-commit before
    _seed_failed_job gh-commit after
    run _verdict
    [ "$status" -eq 3 ]
    assert_output --partial 'HARNESS FAILURE'
    refute_output --partial 'skill(s) below contract'
}

@test "D-2: one failed job fails the run even when other jobs produced rows" {
    _seed_job gh-commit before 18 20 90.0
    _seed_job gh-commit after 18 20 90.0
    _seed_failed_job sh-check after
    run _verdict
    [ "$status" -eq 3 ]
    # The completed pair is still rendered — the table stays useful …
    assert_output --partial 'PASS'
    # … but the run is explicitly reported as inconclusive.
    assert_output --partial 'HARNESS FAILURE'
    assert_output --partial '1 measurement(s) did not complete'
}

# ---- D-3: a reused --out-dir must not leak an earlier run's rows ---------

@test "D-3: a stale row from an earlier run stays out of the verdict" {
    _seed_stale_row leftover-skill before 0 20 0.0
    _seed_stale_row leftover-skill after 20 20 100.0
    _seed_job gh-commit before 18 20 90.0
    _seed_job gh-commit after 17 20 85.0

    run _verdict
    assert_success
    refute_output --partial 'leftover-skill'

    run cat "${OUT_DIR}/summary.tsv"
    refute_output --partial 'leftover-skill'
}

@test "D-3: a stale row for THIS run's own job is dropped before launch" {
    # Same --out-dir, same skill and arm as last time: without the explicit
    # removal in _spawn, this row would survive a failed job and be counted
    # as though the job had succeeded.
    _seed_stale_row gh-commit before 0 20 0.0
    _throttle() { :; }
    _run_job() { :; }

    _spawn gh-commit before 'a description'
    wait

    [ ! -e "${OUT_DIR}/gh-commit.before.tsv" ]
    [ "${#JOB_TSVS[@]}" -eq 1 ]
    [ "${JOB_TSVS[0]}" = "${OUT_DIR}/gh-commit.before.tsv" ]

    # And the now-dead job is reported as a harness failure, not as 0.0%.
    run _verdict
    [ "$status" -eq 3 ]
    refute_output --partial '0.0'
}

# ---- D-4: the credentials copy is never world-readable, even briefly -----

@test "D-4: the credentials copy exists at 0600 while the probe runs" {
    _stage_job_env
    umask 022    # without the fix, cp would leave the copy at 0644

    run _run_job gh-commit after 'a description'
    assert_success
    assert_output --partial '18/20'
    [ -f "$PROBE_PERM_FILE" ]
    run cat "$PROBE_PERM_FILE"
    assert_output '600'
}

@test "D-4: a completed job writes exactly one data row" {
    _stage_job_env
    run _run_job gh-commit after 'a description'
    assert_success
    run cat "${OUT_DIR}/gh-commit.after.tsv"
    assert_output "$(printf 'gh-commit\tafter\t18\t20\t90')"
}

@test "job: an unparseable probe result yields an ERROR row and no data row" {
    _stage_job_env
    printf 'this is not json\n' > "$PROBE_STDOUT_FILE"

    run _run_job gh-commit after 'a description'
    assert_failure
    assert_output --partial 'ERROR'
    [ ! -e "${OUT_DIR}/gh-commit.after.tsv" ]
}
