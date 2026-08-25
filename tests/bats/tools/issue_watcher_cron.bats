#!/usr/bin/env bats
# tests/bats/tools/issue_watcher_cron.bats
# Tests for issue_watcher_cron.sh — the 5-minute issue-watcher tick (issue #1389).
#
# The real `herdr` binary is never invoked: a PATH-shadowing stub answers the
# four subcommands the script uses (`workspace create`, `agent start`,
# `agent get`, `agent prompt`) with canned JSON matching the shapes measured on
# a live herdr server, and appends every invocation to ${_LOG} so the tests can
# assert on *which* calls were made (bootstrap vs. reuse).

load '../test_helper'

SCRIPT="${DOTFILES_ROOT}/shell-common/tools/custom/issue_watcher_cron.sh"

setup() {
    setup_isolated_home
    _WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/issue-watcher-test.XXXXXX")"
    _BIN_DIR="${_WORK_DIR}/bin"
    _STATE_HOME="${_WORK_DIR}/state"
    _STATE_DIR="${_STATE_HOME}/issue-watcher"
    _STATE_FILE="${_STATE_DIR}/herdr-watch.json"
    _LIMIT_FILE="${_STATE_DIR}/rate-limit.json"
    _LOCK_FILE="${_STATE_DIR}/.lock"
    _LOG="${_WORK_DIR}/herdr.log"
    # Overridable per test; _run_tick passes it as --cwd.
    _TICK_CWD=""
    _LOCK_HOLDER_PID=""
    mkdir -p "${_BIN_DIR}"
    : >"${_LOG}"

    # CLAUDE_CONFIG_DIR account routing (issue #1393): the tick resolves the
    # claude account dir before it touches herdr and fails fast when it is
    # missing, so the default account must exist inside the isolated $HOME.
    # Pinned here (not inherited) so the developer's own shell env cannot
    # steer the tests.
    export CLAUDE_ENABLED_ACCOUNTS="personal"
    unset CLAUDE_DEFAULT_ACCOUNT
    mkdir -p "${HOME}/.claude-personal"
}

teardown() {
    if [ -n "${_LOCK_HOLDER_PID}" ]; then
        kill "${_LOCK_HOLDER_PID}" 2>/dev/null || true
        wait "${_LOCK_HOLDER_PID}" 2>/dev/null || true
    fi
    # The unwritable-state-dir test chmods ${_STATE_DIR} to 500. A `bats`
    # assertion aborts the test body at the failing line, so restoring the mode
    # there is not enough — an early failure would leave the directory
    # read-only and take `rm -rf` down with it, turning one red test into a
    # broken teardown (PR #1439 agy review).
    [ -d "${_STATE_DIR}" ] && chmod 700 "${_STATE_DIR}" 2>/dev/null || true
    rm -rf "${_WORK_DIR}"
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Stub `herdr` on PATH. Behaviour is steered per-test through env vars:
#   HERDR_AGENT_STATUS      status reported by `agent get` (default: idle)
#   HERDR_AGENT_GET_FAIL=1  `agent get` returns the real agent_not_found error
#                           payload and exits 1 (agent missing / pane closed)
#   HERDR_AGENT_GET_SEQ     space-separated per-call `agent get` script, one
#                           word consumed per invocation, last word repeating.
#                           `fail` = agent_not_found + exit 1; anything else is
#                           reported as that agent_status. Used to prove the
#                           post-re-bootstrap idle poll really polls (#1399).
#   HERDR_PROMPT_MODE       `agent prompt` behaviour (default: always ok)
#                             stall-once  first call agent_prompt_stalled, rest ok
#                             stall       every call agent_prompt_stalled
#                             fail        every call a non-stall error
# Each herdr invocation is a fresh process, so the per-call sequences count
# through marker files next to ${HERDR_LOG} rather than through shell state.
_install_herdr_stub() {
    cat >"${_BIN_DIR}/herdr" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${HERDR_LOG}"

_bump() {
    _n=$(cat "$1" 2>/dev/null || printf 0)
    _n=$((_n + 1))
    printf '%s' "${_n}" >"$1"
    printf '%s' "${_n}"
}

case "$1 $2" in
"workspace create")
    printf '%s\n' '{"id":"cli:workspace:create","result":{"workspace":{"workspace_id":"ws-test-1"},"root_pane":{"pane_id":"ws-test-1:p1"}}}'
    ;;
"agent start")
    printf '%s\n' '{"id":"cli:agent:start","result":{"agent":{"agent_status":"idle","pane_id":"ws-test-1:p1"}}}'
    ;;
"agent get")
    if [ -n "${HERDR_AGENT_GET_SEQ:-}" ]; then
        _n=$(_bump "${HERDR_LOG}.getcount")
        # Word-splitting is the point: the sequence is a list of responses.
        # shellcheck disable=SC2086
        set -- ${HERDR_AGENT_GET_SEQ}
        [ "${_n}" -le "$#" ] || _n=$#
        shift "$((_n - 1))"
        _resp="$1"
        if [ "${_resp}" = "fail" ]; then
            printf '%s\n' '{"error":{"code":"agent_not_found","message":"agent target iw-watch not found"},"id":"cli:agent:get"}'
            exit 1
        fi
        printf '{"id":"cli:agent:get","result":{"agent":{"agent_status":"%s"}}}\n' "${_resp}"
        exit 0
    fi
    if [ "${HERDR_AGENT_GET_FAIL:-0}" = "1" ]; then
        printf '%s\n' '{"error":{"code":"agent_not_found","message":"agent target iw-watch not found"},"id":"cli:agent:get"}'
        exit 1
    fi
    printf '{"id":"cli:agent:get","result":{"agent":{"agent_status":"%s"}}}\n' "${HERDR_AGENT_STATUS:-idle}"
    ;;
"agent prompt")
    case "${HERDR_PROMPT_MODE:-ok}" in
    stall-once)
        _n=$(_bump "${HERDR_LOG}.promptcount")
        if [ "${_n}" = "1" ]; then
            printf '%s\n' '{"error":{"code":"agent_prompt_stalled","message":"no agent state change observed within 5000ms"},"id":"cli:agent:prompt"}'
            exit 1
        fi
        ;;
    stall)
        printf '%s\n' '{"error":{"code":"agent_prompt_stalled","message":"no agent state change observed within 5000ms"},"id":"cli:agent:prompt"}'
        exit 1
        ;;
    fail)
        printf '%s\n' '{"error":{"code":"agent_not_found","message":"agent target iw-watch not found"},"id":"cli:agent:prompt"}'
        exit 1
        ;;
    esac
    printf '%s\n' '{"id":"cli:agent:prompt","result":{"ok":true}}'
    ;;
esac
exit 0
EOF
    chmod +x "${_BIN_DIR}/herdr"
}

# Run one tick with the stub on PATH and an isolated XDG_STATE_HOME.
# Extra env assignments may be passed as leading VAR=VALUE arguments.
# Set _TICK_CWD to pass a --cwd other than the default work dir.
_run_tick() {
    run env \
        "PATH=${_BIN_DIR}:${PATH}" \
        "HERDR_LOG=${_LOG}" \
        "XDG_STATE_HOME=${_STATE_HOME}" \
        "$@" \
        bash "${SCRIPT}" --cwd "${_TICK_CWD:-${_WORK_DIR}}"
}

_log_count() {
    grep -c -- "$1" "${_LOG}" 2>/dev/null || true
}

# claude-yolo parity (issue #1393): the two assertions repeated across the
# CLAUDE_CONFIG_DIR-routing tests below.
_assert_config_dir() {
    run grep -F -- "--env CLAUDE_CONFIG_DIR=$1" "${_LOG}"
    assert_success
}

_assert_skip_permissions_start() {
    run grep -F -- "agent start iw-watch --kind claude --pane ws-test-1:p1 -- --dangerously-skip-permissions" "${_LOG}"
    assert_success
}

# Run a tick with CLAUDE_ENABLED_ACCOUNTS / CLAUDE_DEFAULT_ACCOUNT unset —
# _run_tick can only add/override env vars, not unset them (env -u).
_run_tick_no_account_env() {
    run env -u CLAUDE_ENABLED_ACCOUNTS -u CLAUDE_DEFAULT_ACCOUNT \
        "PATH=${_BIN_DIR}:${PATH}" \
        "HERDR_LOG=${_LOG}" \
        "XDG_STATE_HOME=${_STATE_HOME}" \
        bash "${SCRIPT}" --cwd "${_WORK_DIR}"
}

# Run a tick with HOME (and XDG_STATE_HOME) unset, redirecting state under a
# throwaway TMPDIR. Shared by both "unset HOME ..." tests below.
# Sets (not local — callers read it after this returns): _NOHOME_TMP.
_run_tick_no_home() {
    _NOHOME_TMP="${_WORK_DIR}/nohome-tmp"
    mkdir -p "${_NOHOME_TMP}"
    run env -u HOME -u XDG_STATE_HOME \
        "PATH=${_BIN_DIR}:${PATH}" \
        "HERDR_LOG=${_LOG}" \
        "TMPDIR=${_NOHOME_TMP}" \
        bash "${SCRIPT}" --cwd "${_WORK_DIR}"
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

# ---------------------------------------------------------------------------
# Syntax & help
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: bash syntax check" {
    run bash -n "${SCRIPT}"
    assert_success
}

@test "issue_watcher_cron: --help exits 0 and prints usage" {
    run bash "${SCRIPT}" --help
    assert_success
    assert_output --partial "Usage: issue_watcher_cron.sh"
    assert_output --partial "--cwd"
}

@test "issue_watcher_cron: --help documents the crontab registration example" {
    run bash "${SCRIPT}" --help
    assert_success
    assert_output --partial "*/5 * * * *"
    assert_output --partial "issue_watcher_cron.sh"
    assert_output --partial "cron.log"
}

@test "issue_watcher_cron: -h is equivalent to --help" {
    run bash "${SCRIPT}" -h
    assert_success
    assert_output --partial "Usage: issue_watcher_cron.sh"
}

@test "issue_watcher_cron: bare 'help' is equivalent to --help" {
    run bash "${SCRIPT}" help
    assert_success
    assert_output --partial "Usage: issue_watcher_cron.sh"
}

@test "issue_watcher_cron: unknown option exits non-zero" {
    run bash "${SCRIPT}" --bogus
    assert_failure
    assert_output --partial "Unknown option"
}

# ---------------------------------------------------------------------------
# Bootstrap (no state file yet)
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: first run creates the workspace and starts the agent" {
    _install_herdr_stub
    _run_tick
    assert_success

    run grep -F -- "workspace create --cwd ${_WORK_DIR} --label issue-watcher --no-focus" "${_LOG}"
    assert_success

    run grep -F -- "agent start iw-watch --kind claude --pane ws-test-1:p1" "${_LOG}"
    assert_success
}

@test "issue_watcher_cron: first run writes the state file with the expected JSON shape" {
    _install_herdr_stub
    _run_tick
    assert_success

    [ -f "${_STATE_FILE}" ]

    run cat "${_STATE_FILE}"
    assert_output --partial '"workspace_id": "ws-test-1"'
    assert_output --partial '"pane_id": "ws-test-1:p1"'
    assert_output --partial '"agent_name": "iw-watch"'
    assert_output --partial "\"cwd\": \"${_WORK_DIR}\""
}

@test "issue_watcher_cron: state file lives under XDG_STATE_HOME/issue-watcher" {
    _install_herdr_stub
    _run_tick
    assert_success
    [ -f "${_STATE_HOME}/issue-watcher/herdr-watch.json" ]
}

# ---------------------------------------------------------------------------
# claude-yolo parity: CLAUDE_CONFIG_DIR routing + skipped permission prompts
# (issue #1393 — herdr's --kind enum has no `claude-yolo`, so the wrapper's two
# effects are reproduced through --env and the `-- ARG...` passthrough tail.)
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: bootstrap routes CLAUDE_CONFIG_DIR to the default account" {
    _install_herdr_stub
    _run_tick
    assert_success

    _assert_config_dir "${HOME}/.claude-personal"
}

@test "issue_watcher_cron: bootstrap starts claude with --dangerously-skip-permissions" {
    _install_herdr_stub
    _run_tick
    assert_success

    _assert_skip_permissions_start
}

@test "issue_watcher_cron: CLAUDE_DEFAULT_ACCOUNT selects the account dir" {
    _install_herdr_stub
    mkdir -p "${HOME}/.claude-work"

    _run_tick CLAUDE_ENABLED_ACCOUNTS="personal work" CLAUDE_DEFAULT_ACCOUNT=work
    assert_success

    _assert_config_dir "${HOME}/.claude-work"
    run grep -F -- ".claude-personal" "${_LOG}"
    assert_failure
}

@test "issue_watcher_cron: internal setup mode uses ~/.claude without account resolution" {
    _install_herdr_stub
    printf '%s\n' 'internal' >"${HOME}/.dotfiles-setup-mode"
    mkdir -p "${HOME}/.claude"

    # No CLAUDE_ENABLED_ACCOUNTS at all: the internal branch must run *before*
    # account resolution, or an empty whitelist would fail the tick (#571 F-2).
    _run_tick_no_account_env
    assert_success

    _assert_config_dir "${HOME}/.claude"
    # Never the multi-account layout: no ~/.claude-<name> anywhere in the call.
    run grep -F -- ".claude-" "${_LOG}"
    assert_failure
}

@test "issue_watcher_cron: missing account directory fails fast before touching herdr" {
    _install_herdr_stub
    # CLAUDE_ENABLED_ACCOUNTS accepts the name, but the directory never exists.
    _run_tick CLAUDE_ENABLED_ACCOUNTS=ghost CLAUDE_DEFAULT_ACCOUNT=ghost
    assert_failure
    assert_output --partial "${HOME}/.claude-ghost"

    run grep -F -- "workspace create" "${_LOG}"
    assert_failure
    run grep -F -- "agent start" "${_LOG}"
    assert_failure
}

@test "issue_watcher_cron: unknown account name fails fast with the available list" {
    _install_herdr_stub
    _run_tick CLAUDE_ENABLED_ACCOUNTS=personal CLAUDE_DEFAULT_ACCOUNT=nosuch
    assert_failure
    assert_output --partial "Unknown claude account: nosuch"

    run grep -F -- "workspace create" "${_LOG}"
    assert_failure
}

@test "issue_watcher_cron: the implicit 'personal' default fails fast when its dir is absent" {
    _install_herdr_stub
    rmdir "${HOME}/.claude-personal"

    # Neither CLAUDE_DEFAULT_ACCOUNT nor an internal override — the
    # `${CLAUDE_DEFAULT_ACCOUNT:-personal}` fallback must be validated too.
    _run_tick
    assert_failure
    assert_output --partial "${HOME}/.claude-personal"

    run grep -F -- "workspace create" "${_LOG}"
    assert_failure
}

@test "issue_watcher_cron: falls back to plain ~/.claude when no multi-account setup exists" {
    _install_herdr_stub
    mkdir -p "${HOME}/.claude"

    # Never ran `claude-accounts setup` and never named an account: the
    # pre-#1393 single-account user must keep working (PR #1395 review).
    _run_tick_no_account_env
    assert_success
    assert_output --partial "CLAUDE_ENABLED_ACCOUNTS not configured"

    _assert_config_dir "${HOME}/.claude"
    _assert_skip_permissions_start
}

@test "issue_watcher_cron: the single-account fallback still fails fast without ~/.claude" {
    _install_herdr_stub
    # Same "no opt-in" env as above, but nothing to fall back to.
    _run_tick_no_account_env
    assert_failure
    assert_output --partial "Unknown claude account: personal"

    run grep -F -- "workspace create" "${_LOG}"
    assert_failure
    run grep -F -- "agent start" "${_LOG}"
    assert_failure
}

@test "issue_watcher_cron: re-bootstrap after stale state keeps both claude-yolo flags" {
    _install_herdr_stub
    mkdir -p "${_STATE_DIR}"
    printf '{ "workspace_id": "ws-stale", "pane_id": "ws-stale:p9", "agent_name": "iw-watch" }\n' \
        >"${_STATE_FILE}"

    _run_tick HERDR_AGENT_GET_FAIL=1
    assert_success

    _assert_config_dir "${HOME}/.claude-personal"
    _assert_skip_permissions_start
}

@test "issue_watcher_cron: unset HOME degrades to no --env instead of failing" {
    _install_herdr_stub

    # Nothing to route against without HOME — the tick must still run (the
    # pre-#1393 behaviour) rather than fail-fast on an uncomputable path.
    _run_tick_no_home
    assert_success
    assert_output --partial "HOME is unset"

    run grep -F -- "CLAUDE_CONFIG_DIR" "${_LOG}"
    assert_failure
    _assert_skip_permissions_start
}

# ---------------------------------------------------------------------------
# Reuse (state file present)
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: second run reuses state and skips bootstrap" {
    _install_herdr_stub
    _run_tick
    assert_success

    : >"${_LOG}"
    _run_tick
    assert_success

    run grep -F -- "workspace create" "${_LOG}"
    assert_failure
    run grep -F -- "agent start" "${_LOG}"
    assert_failure
    run grep -F -- "agent get iw-watch" "${_LOG}"
    assert_success
}

@test "issue_watcher_cron: reuse with a different --cwd warns and keeps the workspace" {
    _install_herdr_stub
    _run_tick
    assert_success

    : >"${_LOG}"
    local _other="${_WORK_DIR}/other-repo"
    mkdir -p "${_other}"
    _TICK_CWD="${_other}"
    _run_tick
    assert_success
    assert_output --partial "${_WORK_DIR}"
    assert_output --partial "ignoring --cwd ${_other}"

    # Informational only — no re-bootstrap, and the state file is untouched.
    run grep -F -- "workspace create" "${_LOG}"
    assert_failure
    run grep -F -- "agent start" "${_LOG}"
    assert_failure
    run grep -F -- "agent get iw-watch" "${_LOG}"
    assert_success

    run cat "${_STATE_FILE}"
    assert_output --partial "\"cwd\": \"${_WORK_DIR}\""
}

@test "issue_watcher_cron: reuse with the same --cwd does not warn" {
    _install_herdr_stub
    _run_tick
    assert_success

    _run_tick
    assert_success
    refute_output --partial "ignoring --cwd"
}

# ---------------------------------------------------------------------------
# Single-instance lock
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: a tick is skipped while another instance holds the lock" {
    _install_herdr_stub
    _hold_lock

    _run_tick
    assert_success
    assert_output --partial "already running"
    assert_output --partial "skip"

    # No herdr call at all — the tick bailed before touching the state.
    run grep -F -- "agent get" "${_LOG}"
    assert_failure
    run grep -F -- "agent prompt" "${_LOG}"
    assert_failure
    run grep -F -- "workspace create" "${_LOG}"
    assert_failure
}

@test "issue_watcher_cron: the lock is released so the next tick runs" {
    _install_herdr_stub
    _run_tick
    assert_success
    refute_output --partial "already running"

    _run_tick
    assert_success
    refute_output --partial "already running"
    [ "$(_log_count 'agent prompt')" -eq 2 ]
}

@test "issue_watcher_cron: missing flock degrades to a warning, not a failure" {
    _install_herdr_stub
    # A PATH without flock: only the stub dir plus a dir holding the coreutils
    # the script needs, minus flock itself.
    local _nolock="${_WORK_DIR}/nolock"
    mkdir -p "${_nolock}"
    local _cmd
    for _cmd in bash sh dirname cat sed awk head mkdir git grep jq tput; do
        if command -v "${_cmd}" >/dev/null 2>&1; then
            ln -sf "$(command -v "${_cmd}")" "${_nolock}/${_cmd}"
        fi
    done

    run env \
        "PATH=${_BIN_DIR}:${_nolock}" \
        "HERDR_LOG=${_LOG}" \
        "XDG_STATE_HOME=${_STATE_HOME}" \
        bash "${SCRIPT}" --cwd "${_WORK_DIR}"
    assert_success
    assert_output --partial "flock not found"

    run grep -F -- "agent prompt iw-watch" "${_LOG}"
    assert_success
}

# ---------------------------------------------------------------------------
# Dispatch decision by agent status
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: idle agent gets the dispatcher prompt with --wait --timeout" {
    _install_herdr_stub
    _run_tick HERDR_AGENT_STATUS=idle
    assert_success

    run grep -F -- "agent prompt iw-watch" "${_LOG}"
    assert_success
    run grep -F -- "issue-watcher:dispatcher 를 Agent 도구로 실행해" "${_LOG}"
    assert_success
    # 세션 언어 설정에 덜 흔들리도록 영어 지시문을 병기한다 (PR #1396 agy 리뷰).
    run grep -F -- "run the issue-watcher:dispatcher agent via the Agent tool" "${_LOG}"
    assert_success
    # 회귀 가드: "@" 접두사가 다시 붙으면 받는 세션이 Skill/Agent 를 헷갈린다 (#1394).
    run grep -F -- "@issue-watcher:dispatcher" "${_LOG}"
    assert_failure
    run grep -F -- "--wait --timeout 240000" "${_LOG}"
    assert_success
}

@test "issue_watcher_cron: done agent also gets the dispatcher prompt" {
    _install_herdr_stub
    _run_tick HERDR_AGENT_STATUS=done
    assert_success
    run grep -F -- "agent prompt iw-watch" "${_LOG}"
    assert_success
}

@test "issue_watcher_cron: working agent skips the tick and exits 0 with a warning" {
    _install_herdr_stub
    _run_tick HERDR_AGENT_STATUS=working
    assert_success
    assert_output --partial "working"
    assert_output --partial "skip"

    run grep -F -- "agent prompt" "${_LOG}"
    assert_failure
}

@test "issue_watcher_cron: blocked agent skips the tick and exits 0 with a warning" {
    _install_herdr_stub
    _run_tick HERDR_AGENT_STATUS=blocked
    assert_success
    assert_output --partial "blocked"
    assert_output --partial "skip"

    run grep -F -- "agent prompt" "${_LOG}"
    assert_failure
}

# ---------------------------------------------------------------------------
# Stale state (agent missing / pane closed)
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: agent_not_found re-bootstraps and still dispatches" {
    _install_herdr_stub
    # Seed a state file pointing at an agent the stub reports as missing.
    mkdir -p "$(dirname "${_STATE_FILE}")"
    printf '{ "workspace_id": "ws-stale", "pane_id": "ws-stale:p9", "agent_name": "iw-watch" }\n' \
        >"${_STATE_FILE}"

    _run_tick HERDR_AGENT_GET_FAIL=1
    assert_success

    run grep -F -- "workspace create --cwd ${_WORK_DIR} --label issue-watcher --no-focus" "${_LOG}"
    assert_success
    run grep -F -- "agent start iw-watch --kind claude --pane ws-test-1:p1" "${_LOG}"
    assert_success
    run grep -F -- "agent prompt iw-watch" "${_LOG}"
    assert_success
}

@test "issue_watcher_cron: re-bootstrap overwrites the stale state file" {
    _install_herdr_stub
    mkdir -p "$(dirname "${_STATE_FILE}")"
    printf '{ "workspace_id": "ws-stale", "pane_id": "ws-stale:p9", "agent_name": "iw-watch" }\n' \
        >"${_STATE_FILE}"

    _run_tick HERDR_AGENT_GET_FAIL=1
    assert_success

    run cat "${_STATE_FILE}"
    assert_output --partial '"workspace_id": "ws-test-1"'
    refute_output --partial "ws-stale"
}

# ---------------------------------------------------------------------------
# Dispatch readiness after a re-bootstrap (issue #1399)
#
# A freshly started claude can render its prompt box before its key-input loop
# accepts Enter; prompting into that gap loses the submission and herdr fails
# the tick with `agent_prompt_stalled`. Two guards: poll for idle after the
# re-bootstrap, and retry that one error class once.
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: re-bootstrap polls for idle before dispatching" {
    _install_herdr_stub
    mkdir -p "${_STATE_DIR}"
    printf '{ "workspace_id": "ws-stale", "pane_id": "ws-stale:p9", "agent_name": "iw-watch" }\n' \
        >"${_STATE_FILE}"

    # Call 1 is the stale-state probe that triggers the re-bootstrap; the poll
    # that follows must keep asking until the agent stops being `starting`.
    _run_tick HERDR_AGENT_GET_SEQ="fail starting starting idle"
    assert_success

    [ "$(_log_count 'agent get')" -eq 4 ]
    [ "$(_log_count 'agent prompt')" -eq 1 ]

    # The prompt is last: every status query happened before the dispatch.
    run tail -n 1 "${_LOG}"
    assert_output --partial "agent prompt iw-watch"
}

@test "issue_watcher_cron: the idle poll gives up after its cap and still dispatches" {
    _install_herdr_stub
    mkdir -p "${_STATE_DIR}"
    printf '{ "workspace_id": "ws-stale", "pane_id": "ws-stale:p9", "agent_name": "iw-watch" }\n' \
        >"${_STATE_FILE}"

    # Never idle: the tick must not newly fail over a slow pane.
    _run_tick HERDR_AGENT_GET_SEQ="fail starting"
    assert_success
    assert_output --partial "did not report idle"

    [ "$(_log_count 'agent get')" -eq 11 ]
    run grep -F -- "agent prompt iw-watch" "${_LOG}"
    assert_success
}

@test "issue_watcher_cron: agent_prompt_stalled is retried once and then succeeds" {
    _install_herdr_stub

    _run_tick HERDR_PROMPT_MODE=stall-once
    assert_success
    assert_output --partial "agent_prompt_stalled"

    [ "$(_log_count 'agent prompt')" -eq 2 ]
}

@test "issue_watcher_cron: a non-stall prompt failure is not retried" {
    _install_herdr_stub

    _run_tick HERDR_PROMPT_MODE=fail
    assert_failure
    assert_output --partial "herdr agent prompt failed"
    refute_output --partial "retrying once"

    [ "$(_log_count 'agent prompt')" -eq 1 ]
}

@test "issue_watcher_cron: agent_prompt_stalled retry is skipped when the agent is already working" {
    _install_herdr_stub

    # Call 1 (main()'s idle|done check) reports idle, so dispatch is attempted.
    # HERDR_PROMPT_MODE=stall makes the first `agent prompt` stall; call 2 is
    # the pre-retry status check this fixes — it reports `working`, meaning
    # the stalled call actually landed, so no second prompt should be sent
    # (PR #1400 codex review: `agent_prompt_stalled` alone doesn't prove the
    # keystroke was dropped).
    _run_tick HERDR_AGENT_GET_SEQ="idle working" HERDR_PROMPT_MODE=stall
    assert_success
    assert_output --partial "already working"
    refute_output --partial "retrying once"

    [ "$(_log_count 'agent get')" -eq 2 ]
    [ "$(_log_count 'agent prompt')" -eq 1 ]
}

@test "issue_watcher_cron: the idle-poll give-up warning reports health-check failure count" {
    _install_herdr_stub
    mkdir -p "${_STATE_DIR}"
    printf '{ "workspace_id": "ws-stale", "pane_id": "ws-stale:p9", "agent_name": "iw-watch" }\n' \
        >"${_STATE_FILE}"

    # Every poll call (including the stale-state probe) reports agent_not_found:
    # a genuinely gone agent, not merely a slow one.
    _run_tick HERDR_AGENT_GET_SEQ="fail"
    assert_success
    assert_output --partial "did not report idle"
    assert_output --partial "10/10 health-check failures"
}

@test "issue_watcher_cron: a stall on the retry falls through to the failure path" {
    _install_herdr_stub

    _run_tick HERDR_PROMPT_MODE=stall
    assert_failure
    assert_output --partial "herdr agent prompt failed"

    # Exactly one retry — never a loop.
    [ "$(_log_count 'agent prompt')" -eq 2 ]
}

@test "issue_watcher_cron: a reused idle agent is dispatched without an extra poll" {
    _install_herdr_stub
    _run_tick
    assert_success

    : >"${_LOG}"
    _run_tick
    assert_success

    # The reuse path is unchanged by #1399: one status query, then the prompt.
    [ "$(_log_count 'agent get')" -eq 1 ]
    [ "$(_log_count 'agent prompt')" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Corrupted state file
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: an empty state file falls back to bootstrap" {
    _install_herdr_stub
    mkdir -p "${_STATE_DIR}"
    : >"${_STATE_FILE}"

    _run_tick
    assert_success

    run grep -F -- "workspace create --cwd ${_WORK_DIR} --label issue-watcher --no-focus" "${_LOG}"
    assert_success
    # The default agent name must survive an unusable state file — a clobbered
    # _IW_AGENT_NAME would make this `agent start  --kind claude`.
    run grep -F -- "agent start iw-watch --kind claude --pane ws-test-1:p1" "${_LOG}"
    assert_success
    run grep -F -- "agent prompt iw-watch" "${_LOG}"
    assert_success

    run cat "${_STATE_FILE}"
    assert_output --partial '"workspace_id": "ws-test-1"'
    assert_output --partial '"agent_name": "iw-watch"'
}

@test "issue_watcher_cron: a garbage state file falls back to bootstrap" {
    _install_herdr_stub
    mkdir -p "${_STATE_DIR}"
    printf '%s\n' 'not json at all {{{ "workspace_id" ,,, ' >"${_STATE_FILE}"

    _run_tick
    assert_success

    run grep -F -- "workspace create --cwd ${_WORK_DIR} --label issue-watcher --no-focus" "${_LOG}"
    assert_success
    # The default agent name must survive an unusable state file — a clobbered
    # _IW_AGENT_NAME would make this `agent start  --kind claude`.
    run grep -F -- "agent start iw-watch --kind claude --pane ws-test-1:p1" "${_LOG}"
    assert_success
    run grep -F -- "agent prompt iw-watch" "${_LOG}"
    assert_success

    run cat "${_STATE_FILE}"
    assert_output --partial '"workspace_id": "ws-test-1"'
    assert_output --partial '"agent_name": "iw-watch"'
}

@test "issue_watcher_cron: valid JSON missing the required fields falls back to bootstrap" {
    _install_herdr_stub
    mkdir -p "${_STATE_DIR}"
    printf '%s\n' '{ "workspace_id": "ws-partial" }' >"${_STATE_FILE}"

    _run_tick
    assert_success

    run grep -F -- "workspace create --cwd ${_WORK_DIR} --label issue-watcher --no-focus" "${_LOG}"
    assert_success
    run cat "${_STATE_FILE}"
    refute_output --partial "ws-partial"
}

# ---------------------------------------------------------------------------
# Idempotency
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: repeated ticks create the workspace exactly once" {
    _install_herdr_stub
    _run_tick
    assert_success
    _run_tick
    assert_success
    _run_tick
    assert_success

    [ "$(_log_count 'workspace create')" -eq 1 ]
    [ "$(_log_count 'agent start')" -eq 1 ]
    [ "$(_log_count 'agent prompt')" -eq 3 ]
}

@test "issue_watcher_cron: repeated ticks keep a single stable state file" {
    _install_herdr_stub
    _run_tick
    assert_success
    local _first
    _first="$(cat "${_STATE_FILE}")"

    _run_tick
    assert_success

    # The single-instance .lock lives here too and is not state.
    [ "$(find "${_STATE_HOME}/issue-watcher" -maxdepth 1 -type f ! -name '.lock' | wc -l)" -eq 1 ]
    [ "${_first}" = "$(cat "${_STATE_FILE}")" ]
}

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: missing herdr binary fails with a clear error" {
    run env \
        "PATH=${_BIN_DIR}:/usr/bin:/bin" \
        "HERDR_LOG=${_LOG}" \
        "XDG_STATE_HOME=${_STATE_HOME}" \
        bash "${SCRIPT}" --cwd "${_WORK_DIR}"
    assert_failure
    assert_output --partial "herdr"
}

@test "issue_watcher_cron: --cwd without a value fails" {
    run bash "${SCRIPT}" --cwd
    assert_failure
}

@test "issue_watcher_cron: unset HOME and XDG_STATE_HOME does not trip set -u" {
    _install_herdr_stub

    # `set -u` + `${XDG_STATE_HOME:-$HOME/.local/state}` used to abort the
    # state-dir expansion with "HOME: unbound variable" when both were unset.
    # Contract: fall back to ${TMPDIR:-/tmp} and keep running.
    _run_tick_no_home
    assert_success
    refute_output --partial "unbound variable"

    [ -f "${_NOHOME_TMP}/.local/state/issue-watcher/herdr-watch.json" ]

    run grep -F -- "agent prompt iw-watch" "${_LOG}"
    assert_success
}

# ---------------------------------------------------------------------------
# Rate-limit gate (issue #1436)
# ---------------------------------------------------------------------------

# Seed a reusable state file so the gate tests exercise the reuse path (no
# bootstrap noise in ${_LOG}) and every `agent get` call belongs to the gate.
_seed_state() {
    mkdir -p "${_STATE_DIR}"
    printf '{ "workspace_id": "ws-test-1", "pane_id": "ws-test-1:p1", "agent_name": "iw-watch", "cwd": "%s" }\n' \
        "${_WORK_DIR}" >"${_STATE_FILE}"
}

_seed_gate() {
    mkdir -p "${_STATE_DIR}"
    printf '{ "strikes": "%s", "backoff_until": "%s" }\n' "$1" "$2" >"${_LIMIT_FILE}"
}

_now() {
    date +%s
}

@test "issue_watcher_cron: a healthy dispatch leaves no rate-limit state behind" {
    _install_herdr_stub
    _run_tick
    assert_success

    [ ! -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: a stalled dispatch records a strike and still exits 1" {
    _install_herdr_stub
    _seed_state

    _run_tick HERDR_PROMPT_MODE=stall
    assert_failure
    assert_output --partial "1/2"

    run cat "${_LIMIT_FILE}"
    assert_output --partial '"strikes": "1"'
    assert_output --partial '"backoff_until": "0"'
}

@test "issue_watcher_cron: two consecutive stalled dispatches close the gate" {
    _install_herdr_stub
    _seed_state

    _run_tick HERDR_PROMPT_MODE=stall
    assert_failure

    _run_tick HERDR_PROMPT_MODE=stall
    assert_failure
    assert_output --partial "Rate-limit gate closed for 30m"

    # Strikes are reset by the closure; the deadline is what holds later ticks.
    run cat "${_LIMIT_FILE}"
    assert_output --partial '"strikes": "0"'
    refute_output --partial '"backoff_until": "0"'
}

@test "issue_watcher_cron: a closed gate holds the tick without dispatching" {
    _install_herdr_stub
    _seed_state
    _seed_gate 0 "$(($(_now) + 600))"

    _run_tick
    assert_success
    assert_output --partial "Rate-limit gate closed"
    assert_output --partial "holding dispatch"

    [ "$(_log_count 'agent prompt')" -eq 0 ]
}

@test "issue_watcher_cron: a held tick never sends the dispatcher prompt that spawns worktrees" {
    _install_herdr_stub
    _seed_state
    _seed_gate 0 "$(($(_now) + 600))"

    _run_tick
    assert_success

    # The tick creates no worktree itself — the dispatcher it prompts does.
    # Proving the prompt never left is proving no `issue-<n>` worktree can
    # appear this tick (issue #1436 F-1).
    run grep -F -- "issue-watcher:dispatcher" "${_LOG}"
    assert_failure
}

@test "issue_watcher_cron: a held tick leaves the gate deadline untouched" {
    _install_herdr_stub
    _seed_state
    local _until
    _until="$(($(_now) + 600))"
    _seed_gate 0 "${_until}"

    _run_tick
    assert_success

    run cat "${_LIMIT_FILE}"
    assert_output --partial "\"backoff_until\": \"${_until}\""
}

@test "issue_watcher_cron: an expired backoff reopens the gate and dispatches" {
    _install_herdr_stub
    _seed_state
    _seed_gate 0 "$(($(_now) - 60))"

    _run_tick
    assert_success
    assert_output --partial "Rate-limit gate reopened"

    run grep -F -- "agent prompt iw-watch" "${_LOG}"
    assert_success
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: an out-of-range future deadline is treated as expired" {
    _install_herdr_stub
    _seed_state
    # Further out than twice the backoff: only a clock jump or a hand edit can
    # write this, and stalling forever on it would break F-3.
    _seed_gate 0 "$(($(_now) + 999999))"

    _run_tick
    assert_success
    assert_output --partial "Rate-limit gate reopened"

    run grep -F -- "agent prompt iw-watch" "${_LOG}"
    assert_success
}

@test "issue_watcher_cron: a corrupt gate file fails open" {
    _install_herdr_stub
    _seed_state
    mkdir -p "${_STATE_DIR}"
    printf '%s\n' 'not json at all {{{ "backoff_until" ,,, ' >"${_LIMIT_FILE}"

    _run_tick
    assert_success
    assert_output --partial "no backoff deadline"

    run grep -F -- "agent prompt iw-watch" "${_LOG}"
    assert_success
}

@test "issue_watcher_cron: a non-numeric deadline fails open" {
    _install_herdr_stub
    _seed_state
    _seed_gate 0 "soon"

    _run_tick
    assert_success
    assert_output --partial "unreadable"

    run grep -F -- "agent prompt iw-watch" "${_LOG}"
    assert_success
}

@test "issue_watcher_cron: a successful dispatch clears accumulated strikes" {
    _install_herdr_stub
    _seed_state
    _seed_gate 1 0

    _run_tick
    assert_success

    [ ! -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: a stalled dispatch with the agent working earns no strike" {
    _install_herdr_stub
    _seed_state

    # Call 1 is main()'s idle|done check. Call 2 is _iw_dispatch's pre-retry
    # probe — it must NOT say `working`, or the stall is treated as delivered
    # and never reaches the gate. Call 3 is the gate asking whether the stall
    # was a token wall; `working` says the agent is alive and busy after all.
    _run_tick HERDR_AGENT_GET_SEQ="idle idle working" HERDR_PROMPT_MODE=stall
    assert_failure
    assert_output --partial "not a token-limit signal"

    [ ! -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: a non-quota dispatch failure earns no strike" {
    _install_herdr_stub
    _seed_state

    # `fail` mode answers `agent_not_found` — a broken pane, an expired auth or
    # a dead socket look like this too. None of them mean the account ran dry,
    # so none may push the watcher toward a 30-minute hold (PR #1439 codex
    # review).
    _run_tick HERDR_PROMPT_MODE=fail
    assert_failure
    assert_output --partial "not a token-limit signature"
    assert_output --partial "agent_not_found"

    [ ! -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: repeated non-quota failures never close the gate" {
    _install_herdr_stub
    _seed_state

    # Three rounds — one more than _IW_LIMIT_STRIKES. A herdr outage must not
    # accumulate into a token-limit verdict no matter how long it lasts.
    _run_tick HERDR_PROMPT_MODE=fail
    assert_failure
    _run_tick HERDR_PROMPT_MODE=fail
    assert_failure
    _run_tick HERDR_PROMPT_MODE=fail
    assert_failure
    refute_output --partial "Rate-limit gate closed"

    [ ! -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: a non-quota failure leaves an existing strike untouched" {
    _install_herdr_stub
    _seed_state
    _seed_gate 1 0

    # Neither exhaustion evidence nor health evidence: the count stands.
    _run_tick HERDR_PROMPT_MODE=fail
    assert_failure

    run cat "${_LIMIT_FILE}"
    assert_output --partial '"strikes": "1"'
}

@test "issue_watcher_cron: the gate never runs on the working|blocked skip path" {
    _install_herdr_stub
    _seed_state
    _seed_gate 0 "$(($(_now) + 600))"

    # NF-2: a busy agent is skipped by the pre-existing gate, with the
    # pre-existing message — the rate-limit gate must not shadow it.
    _run_tick HERDR_AGENT_STATUS=working
    assert_success
    assert_output --partial "skip this tick"
    refute_output --partial "Rate-limit gate"
}

@test "issue_watcher_cron: a state dir with no gate file ticks exactly as before" {
    _install_herdr_stub
    # Pre-#1436 layout: workspace state only, and without the later `cwd` field.
    mkdir -p "${_STATE_DIR}"
    printf '{ "workspace_id": "ws-test-1", "pane_id": "ws-test-1:p1", "agent_name": "iw-watch" }\n' \
        >"${_STATE_FILE}"

    _run_tick
    assert_success
    refute_output --partial "Rate-limit gate"

    [ "$(_log_count 'agent prompt')" -eq 1 ]
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: an unwritable state dir warns but does not change the exit code" {
    [ "$(id -u)" -ne 0 ] || skip "root ignores directory permissions"
    _install_herdr_stub
    _seed_state
    # The lock file must exist before the dir goes read-only, or flock's own
    # soft-degrade path would mask what this test is about.
    : >"${_LOCK_FILE}"
    chmod 500 "${_STATE_DIR}"

    _run_tick HERDR_PROMPT_MODE=stall
    assert_failure
    assert_output --partial "rate-limit gate will not survive this tick"
}

@test "issue_watcher_cron: --help documents the rate-limit gate and its state file" {
    run bash "${SCRIPT}" --help
    assert_success
    assert_output --partial "rate-limit gate"
    assert_output --partial "rate-limit.json"
}
