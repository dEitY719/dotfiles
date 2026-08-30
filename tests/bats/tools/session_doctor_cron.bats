#!/usr/bin/env bats
# tests/bats/tools/session_doctor_cron.bats
# Tests for session_doctor_cron.sh — the stuck-session cron doctor (#1581).
#
# The job answers one question per herdr pane and then types one line into the
# panes that fail it, so this suite is organised around that question and its
# blast radius:
#
#   F-2/F-3/F-4  which panes are candidates — and, far more importantly, which
#                are not. AC-3 makes zero false positives a hard requirement,
#                so the "never flagged" tests outnumber the "flagged" ones on
#                purpose: prose that quotes the error, a notification relaying
#                a subagent's error, a session that already recovered, a
#                working pane, a pane with no transcript at all.
#   F-5/AC-4     one `/devx:restart` per detection, and nothing else typed
#   F-6/F-7      the per-tab budget, and what a refused injection does to it
#   NF-1         one tick at a time
#   AC-6         no herdr, or a herdr that will not answer — a silent skip
#
# Two PATH stubs stand in for the outside world:
#
#   herdr   `agent list` / `agent prompt` only, canned and steerable per test.
#           Every other subcommand is logged and refused: this job talks to
#           herdr in exactly two ways, and that is a test rather than a claim.
#   crontab (aicron section only) reads and writes a fixture file so the
#           developer's real table is never touched.
#
# The transcripts are fabricated rather than captured, but their shapes are
# not invented: the API-error fixture is byte-for-byte the event Claude Code
# writes when a turn dies mid-stream (`isApiErrorMessage`, `model` of
# `<synthetic>`), measured on a live transcript while #1581 was implemented.

load '../test_helper'

SCRIPT="${DOTFILES_ROOT}/shell-common/tools/custom/session_doctor_cron.sh"
AICRON="${DOTFILES_ROOT}/shell-common/tools/custom/aicron.sh"

setup() {
    setup_isolated_home
    _WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/session-doctor-test.XXXXXX")"
    _BIN_DIR="${_WORK_DIR}/bin"
    _STATE_HOME="${_WORK_DIR}/state"
    _STATE_DIR="${_STATE_HOME}/session-doctor"
    _STATE_FILE="${_STATE_DIR}/state.json"
    _LOCK_FILE="${_STATE_DIR}/.lock"
    _AGENTS_FILE="${_WORK_DIR}/agents.json"
    _LOG="${_WORK_DIR}/calls.log"
    _PROJECTS="${HOME}/.claude-personal/projects"
    _LOCK_HOLDER_PID=""
    mkdir -p "${_BIN_DIR}" "${_PROJECTS}"
    : >"${_LOG}"

    _install_herdr_stub
    # No panes at all is the default: every test that needs one says so.
    _set_panes
}

teardown() {
    if [ -n "${_LOCK_HOLDER_PID}" ]; then
        kill "${_LOCK_HOLDER_PID}" 2>/dev/null || true
        wait "${_LOCK_HOLDER_PID}" 2>/dev/null || true
    fi
    rm -rf "${_WORK_DIR}"
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# Fixtures — panes
# ---------------------------------------------------------------------------

# Claude Code's project-directory name for a working directory. Deliberately a
# second implementation of `session_doctor_cwd_slug`, not a call into it: the
# rule ("every non-alphanumeric character becomes a dash") is what the feature
# depends on, so a test that reused the function could not catch it changing.
_slug_of() {
    printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'
}

# The `herdr agent list` answer, from `<tab_id>|<agent_status>|<cwd>` triples.
# The response shape (`.result.agents[]`, and the field names on each) is the
# one a live herdr server answers with.
_set_panes() {
    local _out _spec _tab _rest _status _cwd
    _out='[]'
    for _spec in "$@"; do
        _tab="${_spec%%|*}"
        _rest="${_spec#*|}"
        _status="${_rest%%|*}"
        _cwd="${_rest#*|}"
        _out=$(printf '%s' "${_out}" | jq \
            --arg t "${_tab}" --arg s "${_status}" --arg c "${_cwd}" \
            '. + [{agent:"claude", tab_id:$t, agent_status:$s, cwd:$c,
                   foreground_cwd:$c, pane_id:"w1:p1", workspace_id:"w1"}]')
    done
    printf '%s' "${_out}" |
        jq '{id:"cli:agent:list", result:{agents:., type:"agent_list"}}' >"${_AGENTS_FILE}"
}

# ---------------------------------------------------------------------------
# Fixtures — transcripts
# ---------------------------------------------------------------------------

# One transcript for working directory <1>, holding the JSONL on stdin. The
# file is named like a real one (a session UUID) because the newest-file rule
# is what picks between several, and nothing else about the name matters.
_write_transcript() {
    local _dir
    _dir="${_PROJECTS}/$(_slug_of "$1")"
    mkdir -p "${_dir}"
    cat >"${_dir}/${2:-11111111-2222-3333-4444-555555555555}.jsonl"
}

# A normal turn: the assistant answered and stopped. Nothing here is an error,
# and nothing here may ever be flagged (AC-3).
_transcript_clean() {
    _write_transcript "$1" "${2:-}" <<'EOF'
{"type":"user","message":{"role":"user","content":"go"},"uuid":"u1"}
{"type":"assistant","message":{"model":"claude-opus-5","role":"assistant","content":[{"type":"text","text":"Done — the change is in place."}]},"uuid":"a1"}
EOF
}

# The turn that died mid-stream. Claude Code mints it as a synthetic assistant
# message carrying both markers this job keys on.
_transcript_api_error() {
    _write_transcript "$1" "${2:-}" <<'EOF'
{"type":"user","message":{"role":"user","content":"go"},"uuid":"u1"}
{"type":"assistant","message":{"model":"claude-opus-5","role":"assistant","content":[{"type":"text","text":"Reading the file."}]},"uuid":"a1"}
{"type":"assistant","isApiErrorMessage":true,"error":"server_error","truncatedAfterOutput":true,"message":{"model":"<synthetic>","role":"assistant","stop_reason":"stop_sequence","content":[{"type":"text","text":"API Error: Connection lost mid-response. The response above may be incomplete."}]},"uuid":"a2"}
EOF
}

# The same cut-off turn from a Claude Code build that does not set
# `isApiErrorMessage` — the second marker (`<synthetic>` plus the text
# signature) has to carry it alone.
_transcript_api_error_unflagged() {
    _write_transcript "$1" "${2:-}" <<'EOF'
{"type":"user","message":{"role":"user","content":"go"},"uuid":"u1"}
{"type":"assistant","message":{"model":"<synthetic>","role":"assistant","content":[{"type":"text","text":"API Error: 529 Overloaded. This is a server-side issue."}]},"uuid":"a2"}
EOF
}

# A real assistant turn that *writes about* the error signature. This is the
# false positive that matters most in this repo — a session implementing
# #1581 quotes all three phrases — and it must never be flagged.
_transcript_prose_about_the_error() {
    _write_transcript "$1" "${2:-}" <<'EOF'
{"type":"user","message":{"role":"user","content":"what do we match on?"},"uuid":"u1"}
{"type":"assistant","message":{"model":"claude-opus-5","role":"assistant","content":[{"type":"text","text":"We match on API Error, Connection lost, and response may be incomplete."}]},"uuid":"a1"}
EOF
}

# A subagent died on an API error and the harness relayed it to the parent as
# a task notification. The parent's own turn finished normally, so the parent
# is not stuck — the words are in a `user` event, not an assistant one.
_transcript_notification_only() {
    _write_transcript "$1" "${2:-}" <<'EOF'
{"type":"assistant","message":{"model":"claude-opus-5","role":"assistant","content":[{"type":"text","text":"Delegating."}]},"uuid":"a1"}
{"type":"queue-operation","operation":"enqueue","content":"<task-notification><status>failed</status><summary>Agent terminated early due to an API error: API Error: Connection lost mid-response. The response above may be incomplete.</summary></task-notification>"}
{"type":"user","message":{"role":"user","content":"<task-notification><summary>API Error: Connection lost mid-response. The response above may be incomplete.</summary></task-notification>"},"uuid":"u2"}
{"type":"assistant","message":{"model":"claude-opus-5","role":"assistant","content":[{"type":"text","text":"The subagent failed; re-running it."}]},"uuid":"a2"}
EOF
}

# The session hit an API error and then carried on — a human retried, or a
# previous tick's injection worked. The last assistant turn is normal again.
_transcript_recovered() {
    _write_transcript "$1" "${2:-}" <<'EOF'
{"type":"assistant","isApiErrorMessage":true,"message":{"model":"<synthetic>","role":"assistant","content":[{"type":"text","text":"API Error: Connection lost mid-response. The response above may be incomplete."}]},"uuid":"a1"}
{"type":"user","message":{"role":"user","content":"/devx:restart"},"uuid":"u2"}
{"type":"assistant","message":{"model":"claude-opus-5","role":"assistant","content":[{"type":"text","text":"Resumed — finishing the edit."}]},"uuid":"a2"}
EOF
}

# ---------------------------------------------------------------------------
# Stubs
# ---------------------------------------------------------------------------

# herdr: `agent list` and `agent prompt`, and nothing else.
#
#   HERDR_LIST_FAIL=1     `agent list` errors (the AC-6 silent-skip path)
#   HERDR_LIST_EMPTY=1    `agent list` answers with nothing at all — a herdr
#                         that is up but unhealthy, which must not read as
#                         "no panes are running"
#   HERDR_PROMPT_FAIL=1   `agent prompt` is refused (`agent_pane_busy`, on
#                         stderr, where herdr really answers a prompt failure)
_install_herdr_stub() {
    cat >"${_BIN_DIR}/herdr" <<'EOF'
#!/bin/sh
printf 'herdr %s\n' "$*" >>"${CALL_LOG}"

case "$1 $2" in
"agent list")
    [ "${HERDR_LIST_FAIL:-0}" = "1" ] && exit 1
    [ "${HERDR_LIST_EMPTY:-0}" = "1" ] && exit 0
    cat "${HERDR_AGENTS_FILE}"
    exit 0
    ;;
"agent prompt")
    if [ "${HERDR_PROMPT_FAIL:-0}" = "1" ]; then
        printf '%s\n' '{"error":{"code":"agent_pane_busy","message":"agent target pane is not an available shell"},"id":"cli:agent:prompt"}' >&2
        exit 1
    fi
    printf '%s\n' '{"id":"cli:agent:prompt","result":{"ok":true}}'
    exit 0
    ;;
esac
exit 1
EOF
    chmod +x "${_BIN_DIR}/herdr"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Run one tick with the stubs on PATH and an isolated XDG_STATE_HOME.
#
#   _run_tick [VAR=VALUE ...] [-- script-flag ...]
#
# `env` applies assignments left to right, so a test can override any of the
# defaults (PATH included) without restating the whole sandbox.
_run_tick() {
    local _env=()
    while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
        _env+=("$1")
        shift
    done
    [ "$#" -eq 0 ] || shift

    run env \
        "PATH=${_BIN_DIR}:${PATH}" \
        "CALL_LOG=${_LOG}" \
        "HERDR_AGENTS_FILE=${_AGENTS_FILE}" \
        "XDG_STATE_HOME=${_STATE_HOME}" \
        "SESSION_DOCTOR_TIMEOUT_MS=2000" \
        "${_env[@]}" \
        bash "${SCRIPT}" "$@"
}

# Call-log assertions that leave `$output` and `$status` alone — tests pair
# these with `assert_output` on the tick's own output, and a `run grep` here
# would overwrite both.
_assert_logged() {
    grep -qF -- "$1" "${_LOG}" || fail "expected in call log: $1"
}

_refute_logged() {
    ! grep -qF -- "$1" "${_LOG}" || fail "unexpected in call log: $1"
}

_log_count() {
    grep -cF -- "$1" "${_LOG}" 2>/dev/null || true
}

# One field of tab <1>'s state entry (<2> = a jq path fragment, e.g.
# `.injections`). Echoes nothing when the file, the tab or the field is absent.
_state_of() {
    [ -f "${_STATE_FILE}" ] || return 0
    jq -r --arg t "$1" "(.tabs[\$t]$2) // empty" "${_STATE_FILE}" 2>/dev/null
}

# Seed tab <1> with <2> injections already spent.
_seed_injections() {
    mkdir -p "${_STATE_DIR}"
    jq -n --arg t "$1" --argjson n "$2" \
        '{tabs: {($t): {injections: $n, last_injection: "2026-08-31T00:00:00Z"}}}' \
        >"${_STATE_FILE}"
}

# A PATH that carries only the stub dir plus symlinks to the system binaries
# the tick needs — minus the ones named as arguments. Deleting a stub is not
# enough to make a binary missing: `command -v` keeps walking the inherited
# PATH and finds the real one.
_path_without() {
    local _d="${_WORK_DIR}/sysbin" _b _p _skip
    rm -rf "${_d}"
    mkdir -p "${_d}"

    for _b in sh bash env git jq awk sed grep head tail cat cut tr sort \
        uniq date mkdir rmdir rm ln basename dirname sleep mktemp flock tput \
        uname wc chmod find id stty locale ls mv; do
        _skip=0
        for _p in "$@"; do
            [ "${_b}" != "${_p}" ] || _skip=1
        done
        [ "${_skip}" -eq 0 ] || continue
        _p=$(command -v "${_b}" 2>/dev/null) || continue
        ln -sf "${_p}" "${_d}/${_b}" 2>/dev/null || true
    done

    printf '%s:%s' "${_BIN_DIR}" "${_d}"
}

# Hold an exclusive flock on the tick's lock file in a background process
# until teardown kills it, so the script under test sees a contended lock.
# Blocks until the holder has actually acquired the lock.
_hold_lock() {
    local _ready="${_WORK_DIR}/lock-held"
    mkdir -p "${_STATE_DIR}"
    flock -x "${_LOCK_FILE}" \
        sh -c "printf held >'${_ready}'; sleep 30" >/dev/null 2>&1 &
    _LOCK_HOLDER_PID=$!

    local _i=0
    while [ ! -s "${_ready}" ] && [ "${_i}" -lt 200 ]; do
        sleep 0.05
        _i=$((_i + 1))
    done
    [ -s "${_ready}" ]
}

# The standard single-candidate setup: one idle pane whose last assistant turn
# died on an API error.
_one_stuck_pane() {
    _CWD="${_WORK_DIR}/repo"
    mkdir -p "${_CWD}"
    _transcript_api_error "${_CWD}"
    _set_panes "w1:t1|idle|${_CWD}"
}

# ---------------------------------------------------------------------------
# Syntax & help
# ---------------------------------------------------------------------------

@test "session_doctor_cron: bash syntax check" {
    run bash -n "${SCRIPT}"
    assert_success
}

@test "session_doctor_cron: the libraries are POSIX-sh clean" {
    run sh -n "${DOTFILES_ROOT}/shell-common/tools/custom/lib/session_doctor_detect.sh"
    assert_success
    run sh -n "${DOTFILES_ROOT}/shell-common/tools/custom/lib/session_doctor_state.sh"
    assert_success
}

@test "session_doctor_cron: --help exits 0 and prints usage" {
    run bash "${SCRIPT}" --help
    assert_success
    assert_output --partial "Usage: session_doctor_cron.sh"
    assert_output --partial "--dry-run"
    assert_output --partial "/devx:restart"
}

@test "session_doctor_cron: --help makes no herdr calls" {
    run env "PATH=${_BIN_DIR}:${PATH}" "CALL_LOG=${_LOG}" bash "${SCRIPT}" --help
    assert_success
    _refute_logged "herdr "
}

@test "session_doctor_cron: --help documents the crontab registration example" {
    # The same drift class #1579/#1586 caught for the two sibling jobs: a
    # reader following --help literally must not install a cadence the shipped
    # manifest disagrees with.
    run bash "${SCRIPT}" --help
    assert_success
    assert_output --partial "*/1 * * * *"
    assert_output --partial "session_doctor_cron.sh"
}

@test "session_doctor_cron: an unknown option fails with usage guidance" {
    run bash "${SCRIPT}" --nope
    assert_failure
    assert_output --partial "Unknown option: --nope"
}

# ---------------------------------------------------------------------------
# AC-6 — herdr missing, or herdr that will not answer
# ---------------------------------------------------------------------------

@test "session_doctor_cron: a missing herdr is a silent skip, not a failure" {
    rm -f "${_BIN_DIR}/herdr"
    _run_tick "PATH=$(_path_without herdr)"
    assert_success
    assert_output ""
}

@test "session_doctor_cron: a failing herdr agent list is a silent skip" {
    _one_stuck_pane
    _run_tick HERDR_LIST_FAIL=1
    assert_success
    assert_output ""
    _refute_logged "herdr agent prompt"
}

@test "session_doctor_cron: a herdr that answers nothing is a skip, not 'no panes'" {
    _one_stuck_pane
    _run_tick HERDR_LIST_EMPTY=1
    assert_success
    assert_output ""
    _refute_logged "herdr agent prompt"
}

@test "session_doctor_cron: a missing jq ends the tick with exit 0" {
    # Reported rather than silent — a machine without jq needs fixing — but
    # still exit 0, because cron mails on non-zero and this job runs each
    # minute.
    _run_tick "PATH=$(_path_without jq)"
    assert_success
    assert_output --partial "jq not found"
}

# ---------------------------------------------------------------------------
# AC-2 — the candidate
# ---------------------------------------------------------------------------

@test "session_doctor_cron: an idle tab cut off by an API error is flagged and injected" {
    _one_stuck_pane
    _run_tick
    assert_success
    assert_output --partial "w1:t1"
    _assert_logged "herdr agent prompt w1:t1 /devx:restart --wait"
}

@test "session_doctor_cron: the second marker alone (synthetic + text) is enough" {
    _CWD="${_WORK_DIR}/repo"
    mkdir -p "${_CWD}"
    _transcript_api_error_unflagged "${_CWD}"
    _set_panes "w1:t1|idle|${_CWD}"
    _run_tick
    assert_success
    _assert_logged "herdr agent prompt w1:t1"
}

@test "session_doctor_cron: --dry-run reports the candidate and injects nothing" {
    _one_stuck_pane
    _run_tick -- --dry-run
    assert_success
    assert_output --partial "1 stuck on an API error"
    _refute_logged "herdr agent prompt"
    [ ! -f "${_STATE_FILE}" ] || fail "--dry-run wrote state"
}

@test "session_doctor_cron: the newest transcript for the cwd is the one judged" {
    _CWD="${_WORK_DIR}/repo"
    mkdir -p "${_CWD}"
    _transcript_api_error "${_CWD}" "aaaaaaaa-0000-0000-0000-000000000000"
    sleep 1
    _transcript_clean "${_CWD}" "bbbbbbbb-0000-0000-0000-000000000000"
    _set_panes "w1:t1|idle|${_CWD}"
    _run_tick
    assert_success
    _refute_logged "herdr agent prompt"
}

# ---------------------------------------------------------------------------
# AC-3 — zero false positives. The reason this file exists.
# ---------------------------------------------------------------------------

@test "session_doctor_cron: a normally completed idle tab is never flagged" {
    _CWD="${_WORK_DIR}/repo"
    mkdir -p "${_CWD}"
    _transcript_clean "${_CWD}"
    _set_panes "w1:t1|idle|${_CWD}"
    _run_tick
    assert_success
    assert_output ""
    _refute_logged "herdr agent prompt"
}

@test "session_doctor_cron: an assistant turn that merely quotes the error is never flagged" {
    _CWD="${_WORK_DIR}/repo"
    mkdir -p "${_CWD}"
    _transcript_prose_about_the_error "${_CWD}"
    _set_panes "w1:t1|idle|${_CWD}"
    _run_tick
    assert_success
    _refute_logged "herdr agent prompt"
}

@test "session_doctor_cron: a relayed subagent API error is never flagged" {
    _CWD="${_WORK_DIR}/repo"
    mkdir -p "${_CWD}"
    _transcript_notification_only "${_CWD}"
    _set_panes "w1:t1|idle|${_CWD}"
    _run_tick
    assert_success
    _refute_logged "herdr agent prompt"
}

@test "session_doctor_cron: a session that already recovered is never flagged" {
    _CWD="${_WORK_DIR}/repo"
    mkdir -p "${_CWD}"
    _transcript_recovered "${_CWD}"
    _set_panes "w1:t1|idle|${_CWD}"
    _run_tick
    assert_success
    _refute_logged "herdr agent prompt"
}

@test "session_doctor_cron: a working pane is never typed into, error or not" {
    _CWD="${_WORK_DIR}/repo"
    mkdir -p "${_CWD}"
    _transcript_api_error "${_CWD}"
    _set_panes "w1:t1|working|${_CWD}" "w1:t2|blocked|${_CWD}"
    _run_tick
    assert_success
    _refute_logged "herdr agent prompt"
}

@test "session_doctor_cron: a cwd with no transcript is excluded, not guessed at" {
    _CWD="${_WORK_DIR}/repo"
    mkdir -p "${_CWD}"
    _set_panes "w1:t1|idle|${_CWD}"
    _run_tick
    assert_success
    _refute_logged "herdr agent prompt"
}

@test "session_doctor_cron: a pane whose directory is gone is excluded" {
    _CWD="${_WORK_DIR}/repo"
    mkdir -p "${_CWD}"
    _transcript_api_error "${_CWD}"
    _set_panes "w1:t1|idle|${_CWD} (deleted)"
    _run_tick
    assert_success
    _refute_logged "herdr agent prompt"
}

@test "session_doctor_cron: a subagent transcript is out of scope" {
    # It lives one level deeper, under <session-uuid>/subagents/. A subagent's
    # death is reported to its parent, and the parent is what would need
    # restarting — so the parent's own transcript is the only thing judged.
    _CWD="${_WORK_DIR}/repo"
    mkdir -p "${_CWD}"
    _transcript_clean "${_CWD}"
    mkdir -p "${_PROJECTS}/$(_slug_of "${_CWD}")/11111111-2222-3333-4444-555555555555/subagents"
    _transcript_api_error "${_CWD}" >/dev/null
    cp "${_PROJECTS}/$(_slug_of "${_CWD}")/11111111-2222-3333-4444-555555555555.jsonl" \
        "${_PROJECTS}/$(_slug_of "${_CWD}")/11111111-2222-3333-4444-555555555555/subagents/agent-x.jsonl"
    _transcript_clean "${_CWD}"
    _set_panes "w1:t1|idle|${_CWD}"
    _run_tick
    assert_success
    _refute_logged "herdr agent prompt"
}

# ---------------------------------------------------------------------------
# AC-4 / F-5 — one injection per detection, and nothing else typed
# ---------------------------------------------------------------------------

@test "session_doctor_cron: a detected tab is injected exactly once per tick" {
    _one_stuck_pane
    _run_tick
    assert_success
    [ "$(_log_count "herdr agent prompt")" -eq 1 ] ||
        fail "expected exactly one injection, got $(_log_count "herdr agent prompt")"
}

@test "session_doctor_cron: only agent list and agent prompt are ever called" {
    _one_stuck_pane
    _run_tick
    assert_success
    _refute_logged "herdr tab"
    _refute_logged "herdr workspace"
    _refute_logged "herdr agent start"
    _refute_logged "herdr notification"
}

@test "session_doctor_cron: every stuck tab in one tick gets its own injection" {
    _CWD="${_WORK_DIR}/repo-a"
    _CWD_B="${_WORK_DIR}/repo-b"
    mkdir -p "${_CWD}" "${_CWD_B}"
    _transcript_api_error "${_CWD}"
    _transcript_api_error "${_CWD_B}"
    _set_panes "w1:t1|idle|${_CWD}" "w1:t2|idle|${_CWD_B}"
    _run_tick
    assert_success
    _assert_logged "herdr agent prompt w1:t1"
    _assert_logged "herdr agent prompt w1:t2"
    [ "$(_state_of 'w1:t1' '.injections')" = "1" ] || fail "w1:t1 not counted"
    [ "$(_state_of 'w1:t2' '.injections')" = "1" ] || fail "w1:t2 not counted"
}

# ---------------------------------------------------------------------------
# F-6 / F-7 — the per-tab state and its budget
# ---------------------------------------------------------------------------

@test "session_doctor_cron: a landed injection records the detection, the count and the stamp" {
    _one_stuck_pane
    _run_tick
    assert_success
    [ "$(_state_of 'w1:t1' '.injections')" = "1" ] || fail "injections not incremented"
    [ -n "$(_state_of 'w1:t1' '.last_detected')" ] || fail "last_detected not written"
    [ -n "$(_state_of 'w1:t1' '.last_injection')" ] || fail "last_injection not written"
}

@test "session_doctor_cron: the count accumulates across ticks" {
    _one_stuck_pane
    _run_tick
    assert_success
    _run_tick
    assert_success
    [ "$(_state_of 'w1:t1' '.injections')" = "2" ] || fail "expected 2, got $(_state_of 'w1:t1' '.injections')"
}

@test "session_doctor_cron: a refused injection warns and leaves the budget untouched" {
    # Nothing was typed, so nothing was spent — the next tick has to be free
    # to try again, which is exactly what a busy pane needs.
    _one_stuck_pane
    _run_tick HERDR_PROMPT_FAIL=1
    assert_success
    assert_output --partial "herdr agent prompt failed"
    assert_output --partial "retry budget is untouched"
    [ -z "$(_state_of 'w1:t1' '.injections')" ] || fail "a refused injection was counted"
    [ -n "$(_state_of 'w1:t1' '.last_detected')" ] || fail "the detection itself was not recorded"
}

@test "session_doctor_cron: a tab at the cap is warned about, never injected again" {
    _one_stuck_pane
    _seed_injections 'w1:t1' 3
    _run_tick
    assert_success
    assert_output --partial "spent its injection budget (3/3)"
    _refute_logged "herdr agent prompt"
    [ "$(_state_of 'w1:t1' '.capped')" = "true" ] || fail "the cap was not recorded in the state file"
    [ -n "$(_state_of 'w1:t1' '.capped_at')" ] || fail "capped_at not written"
    [ "$(_state_of 'w1:t1' '.injections')" = "3" ] || fail "the count moved past the cap"
}

@test "session_doctor_cron: the third injection is allowed and the fourth is not" {
    _one_stuck_pane
    _seed_injections 'w1:t1' 2
    _run_tick
    assert_success
    _assert_logged "herdr agent prompt w1:t1"
    [ "$(_state_of 'w1:t1' '.injections')" = "3" ] || fail "the third injection did not land"

    : >"${_LOG}"
    _run_tick
    assert_success
    _refute_logged "herdr agent prompt"
    assert_output --partial "spent its injection budget"
}

@test "session_doctor_cron: the cap is configurable" {
    _one_stuck_pane
    _seed_injections 'w1:t1' 1
    _run_tick SESSION_DOCTOR_CAP=1
    assert_success
    _refute_logged "herdr agent prompt"
    assert_output --partial "(1/1)"
}

# ---------------------------------------------------------------------------
# NF-1 — one tick at a time
# ---------------------------------------------------------------------------

@test "session_doctor_cron: a contended lock skips the tick without injecting" {
    _one_stuck_pane
    _hold_lock
    _run_tick
    assert_success
    _refute_logged "herdr agent prompt"
}

@test "session_doctor_cron: missing flock degrades to a warning, not a skipped tick" {
    _one_stuck_pane
    _run_tick "PATH=$(_path_without flock)"
    assert_success
    assert_output --partial "without single-instance protection"
    _assert_logged "herdr agent prompt w1:t1"
}

# ---------------------------------------------------------------------------
# AC-1 — the aicron registration
# ---------------------------------------------------------------------------
#
# These read the *shipped* shell-common/tools/custom/cron-jobs.json, not a
# fixture: what this job is registered as, and how often it runs, is a
# property of the file that ships. Same exception aicron.bats' own
# "shipped manifest" section carries.

_shipped_manifest_call() {
    local _fn="$1"
    shift
    (
        AICRON_MANIFEST="${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/custom/cron-jobs.json"
        export AICRON_MANIFEST
        # shellcheck source=/dev/null
        . "${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/custom/lib/aicron_manifest.sh"
        "${_fn}" "$@"
    )
}

@test "session_doctor_cron: the shipped manifest registers session-doctor every minute" {
    run _shipped_manifest_call aicron_manifest_schedule session-doctor
    assert_success
    assert_output "*/1 * * * *"
}

@test "session_doctor_cron: the shipped manifest points at this script" {
    run _shipped_manifest_call aicron_manifest_script session-doctor
    assert_success
    assert_output --partial "shell-common/tools/custom/session_doctor_cron.sh"
    [ -f "${output}" ] || fail "the manifest's script path does not exist: ${output}"
}

# A `crontab` that reads and writes a fixture file instead of the user's real
# table — the same stub shape aicron.bats installs.
_install_crontab_stub() {
    _CRONTAB_FILE="${_WORK_DIR}/crontab.txt"
    : >"${_CRONTAB_FILE}"
    cat >"${_BIN_DIR}/crontab" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
    -l) cat "${_CRONTAB_FILE}"; exit 0 ;;
    -)  cat >"${_CRONTAB_FILE}"; exit 0 ;;
esac
exit 1
EOF
    chmod +x "${_BIN_DIR}/crontab"
}

_run_aicron() {
    run env \
        "PATH=${_BIN_DIR}:${PATH}" \
        "CALL_LOG=${_LOG}" \
        "HERDR_AGENTS_FILE=${_AGENTS_FILE}" \
        "AICRON_MANIFEST=${DOTFILES_ROOT}/shell-common/tools/custom/cron-jobs.json" \
        "AICRON_STATE_DIR=${_WORK_DIR}/aicron" \
        "XDG_STATE_HOME=${_STATE_HOME}" \
        "SESSION_DOCTOR_TIMEOUT_MS=2000" \
        bash "${AICRON}" "$@"
}

@test "session_doctor_cron: aicron add installs it and status --json reports the last run" {
    _install_crontab_stub

    _run_aicron add session-doctor
    assert_success
    grep -qF "# BEGIN aicron:session-doctor" "${_CRONTAB_FILE}" ||
        fail "no aicron marker block for session-doctor"
    grep -qF "*/1 * * * *" "${_CRONTAB_FILE}" ||
        fail "the installed entry does not carry the manifest's schedule"
    # The installed line dispatches through `aicron run <job>` rather than
    # naming the job's script — the manifest stays the SSOT for the script
    # path, args and env, so a job can be re-pointed without touching the
    # crontab (aicron_crontab.sh, `aicron_crontab_block`).
    grep -qF "aicron.sh run session-doctor" "${_CRONTAB_FILE}" ||
        fail "the installed entry does not dispatch through aicron run"

    # One real run through aicron's own executor, on a machine with no stuck
    # panes — the point is that `status --json` can report its result.
    _run_aicron run session-doctor
    assert_success

    _run_aicron status session-doctor --json
    assert_success
    run jq -r '.last_exit' <<<"${output}"
    assert_output "0"
}
