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

    run grep -F -- "--env CLAUDE_CONFIG_DIR=${HOME}/.claude-personal" "${_LOG}"
    assert_success
}

@test "issue_watcher_cron: bootstrap starts claude with --dangerously-skip-permissions" {
    _install_herdr_stub
    _run_tick
    assert_success

    run grep -F -- "agent start iw-watch --kind claude --pane ws-test-1:p1 -- --dangerously-skip-permissions" "${_LOG}"
    assert_success
}

@test "issue_watcher_cron: CLAUDE_DEFAULT_ACCOUNT selects the account dir" {
    _install_herdr_stub
    mkdir -p "${HOME}/.claude-work"

    _run_tick CLAUDE_ENABLED_ACCOUNTS="personal work" CLAUDE_DEFAULT_ACCOUNT=work
    assert_success

    run grep -F -- "--env CLAUDE_CONFIG_DIR=${HOME}/.claude-work" "${_LOG}"
    assert_success
    run grep -F -- ".claude-personal" "${_LOG}"
    assert_failure
}

@test "issue_watcher_cron: internal setup mode uses ~/.claude without account resolution" {
    _install_herdr_stub
    printf '%s\n' 'internal' >"${HOME}/.dotfiles-setup-mode"
    mkdir -p "${HOME}/.claude"

    # No CLAUDE_ENABLED_ACCOUNTS at all: the internal branch must run *before*
    # account resolution, or an empty whitelist would fail the tick (#571 F-2).
    run env -u CLAUDE_ENABLED_ACCOUNTS -u CLAUDE_DEFAULT_ACCOUNT \
        "PATH=${_BIN_DIR}:${PATH}" \
        "HERDR_LOG=${_LOG}" \
        "XDG_STATE_HOME=${_STATE_HOME}" \
        bash "${SCRIPT}" --cwd "${_WORK_DIR}"
    assert_success

    run grep -F -- "--env CLAUDE_CONFIG_DIR=${HOME}/.claude" "${_LOG}"
    assert_success
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

@test "issue_watcher_cron: re-bootstrap after stale state keeps both claude-yolo flags" {
    _install_herdr_stub
    mkdir -p "${_STATE_DIR}"
    printf '{ "workspace_id": "ws-stale", "pane_id": "ws-stale:p9", "agent_name": "iw-watch" }\n' \
        >"${_STATE_FILE}"

    _run_tick HERDR_AGENT_GET_FAIL=1
    assert_success

    run grep -F -- "--env CLAUDE_CONFIG_DIR=${HOME}/.claude-personal" "${_LOG}"
    assert_success
    run grep -F -- "agent start iw-watch --kind claude --pane ws-test-1:p1 -- --dangerously-skip-permissions" "${_LOG}"
    assert_success
}

@test "issue_watcher_cron: unset HOME degrades to no --env instead of failing" {
    _install_herdr_stub
    local _tmp="${_WORK_DIR}/nohome-tmp"
    mkdir -p "${_tmp}"

    # Nothing to route against without HOME — the tick must still run (the
    # pre-#1393 behaviour) rather than fail-fast on an uncomputable path.
    run env -u HOME -u XDG_STATE_HOME \
        "PATH=${_BIN_DIR}:${PATH}" \
        "HERDR_LOG=${_LOG}" \
        "TMPDIR=${_tmp}" \
        bash "${SCRIPT}" --cwd "${_WORK_DIR}"
    assert_success
    assert_output --partial "HOME is unset"

    run grep -F -- "CLAUDE_CONFIG_DIR" "${_LOG}"
    assert_failure
    run grep -F -- "agent start iw-watch --kind claude --pane ws-test-1:p1 -- --dangerously-skip-permissions" "${_LOG}"
    assert_success
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
    local _tmp="${_WORK_DIR}/nohome-tmp"
    mkdir -p "${_tmp}"

    run env -u HOME -u XDG_STATE_HOME \
        "PATH=${_BIN_DIR}:${PATH}" \
        "HERDR_LOG=${_LOG}" \
        "TMPDIR=${_tmp}" \
        bash "${SCRIPT}" --cwd "${_WORK_DIR}"
    assert_success
    refute_output --partial "unbound variable"

    [ -f "${_tmp}/.local/state/issue-watcher/herdr-watch.json" ]

    run grep -F -- "agent prompt iw-watch" "${_LOG}"
    assert_success
}
