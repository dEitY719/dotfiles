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
    _STATE_FILE="${_STATE_HOME}/issue-watcher/herdr-watch.json"
    _LOG="${_WORK_DIR}/herdr.log"
    mkdir -p "${_BIN_DIR}"
    : >"${_LOG}"
}

teardown() {
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
_install_herdr_stub() {
    cat >"${_BIN_DIR}/herdr" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${HERDR_LOG}"
case "$1 $2" in
"workspace create")
    printf '%s\n' '{"id":"cli:workspace:create","result":{"workspace":{"workspace_id":"ws-test-1"},"root_pane":{"pane_id":"ws-test-1:p1"}}}'
    ;;
"agent start")
    printf '%s\n' '{"id":"cli:agent:start","result":{"agent":{"agent_status":"idle","pane_id":"ws-test-1:p1"}}}'
    ;;
"agent get")
    if [ "${HERDR_AGENT_GET_FAIL:-0}" = "1" ]; then
        printf '%s\n' '{"error":{"code":"agent_not_found","message":"agent target iw-watch not found"},"id":"cli:agent:get"}'
        exit 1
    fi
    printf '{"id":"cli:agent:get","result":{"agent":{"agent_status":"%s"}}}\n' "${HERDR_AGENT_STATUS:-idle}"
    ;;
"agent prompt")
    printf '%s\n' '{"id":"cli:agent:prompt","result":{"ok":true}}'
    ;;
esac
exit 0
EOF
    chmod +x "${_BIN_DIR}/herdr"
}

# Run one tick with the stub on PATH and an isolated XDG_STATE_HOME.
# Extra env assignments may be passed as leading VAR=VALUE arguments.
_run_tick() {
    run env \
        "PATH=${_BIN_DIR}:${PATH}" \
        "HERDR_LOG=${_LOG}" \
        "XDG_STATE_HOME=${_STATE_HOME}" \
        "$@" \
        bash "${SCRIPT}" --cwd "${_WORK_DIR}"
}

_log_count() {
    grep -c -- "$1" "${_LOG}" 2>/dev/null || true
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
}

@test "issue_watcher_cron: state file lives under XDG_STATE_HOME/issue-watcher" {
    _install_herdr_stub
    _run_tick
    assert_success
    [ -f "${_STATE_HOME}/issue-watcher/herdr-watch.json" ]
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

# ---------------------------------------------------------------------------
# Dispatch decision by agent status
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: idle agent gets the dispatcher prompt with --wait --timeout" {
    _install_herdr_stub
    _run_tick HERDR_AGENT_STATUS=idle
    assert_success

    run grep -F -- "agent prompt iw-watch" "${_LOG}"
    assert_success
    run grep -F -- "@issue-watcher:dispatcher" "${_LOG}"
    assert_success
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

    [ "$(find "${_STATE_HOME}/issue-watcher" -maxdepth 1 -type f | wc -l)" -eq 1 ]
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
