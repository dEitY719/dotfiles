#!/usr/bin/env bats
# tests/bats/tools/cron_herdr_helpers.bats
# Characterization of the herdr-pane helpers issue_watcher_cron.sh and
# pr_merge_train_cron.sh share (refactor F2).
#
# Both dispatchers carry the same helpers under their own prefix (`_iw_*` /
# `_pmt_*`). Every test here runs the same assertions against both scripts, so
# the two copies are pinned to one behaviour before they are folded into one
# implementation — and stay pinned after. Only the deliberate differences
# (state subdir, lock message, idle verb, pane noun, hint stream) vary per
# script, and those are asserted explicitly.
#
# The helpers are reached by sourcing the script in a child bash. `$0` is set
# to a sibling path that does not exist: its dirname still finds init.sh, and
# because it differs from BASH_SOURCE[0] the script's `main` guard stays shut.

load '../test_helper'

CUSTOM_DIR="${DOTFILES_ROOT}/shell-common/tools/custom"

setup() {
    setup_isolated_home
    _WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cron-herdr-helpers.XXXXXX")"
    _BIN_DIR="${_WORK_DIR}/bin"
    _LOG="${_WORK_DIR}/calls.log"
    _LOCK_HOLDER_PID=""
    mkdir -p "${_BIN_DIR}"
    : >"${_LOG}"
    _install_herdr_stub
    _install_sleep_stub
    _install_frozen_clock_stub
}

teardown() {
    if [ -n "${_LOCK_HOLDER_PID}" ]; then
        kill "${_LOCK_HOLDER_PID}" 2>/dev/null || true
        wait "${_LOCK_HOLDER_PID}" 2>/dev/null || true
    fi
    rm -rf "${_WORK_DIR}"
    teardown_isolated_home
}

# herdr: logs every call; answers are steered per test.
#   HERDR_READ_TEXT      body of `agent read` (`~` = empty read)
#   HERDR_AGENT_STATUS   agent_status of `agent get`; `fail` = exit 1
#   HERDR_WS_LIST        stdout of `workspace list`
#   HERDR_WS_CREATE      stdout of `workspace create`
_install_herdr_stub() {
    cat >"${_BIN_DIR}/herdr" <<'EOF'
#!/bin/sh
printf 'herdr %s\n' "$*" >>"${CALL_LOG}"
case "$1 $2" in
"agent read")
    [ "${HERDR_READ_TEXT:-ready}" = "~" ] || printf '%s\n' "${HERDR_READ_TEXT:-ready}"
    ;;
"agent get")
    [ "${HERDR_AGENT_STATUS:-idle}" = "fail" ] && exit 1
    printf '{"result":{"agent":{"agent_status":"%s"}}}\n' "${HERDR_AGENT_STATUS:-idle}"
    ;;
"agent start")
    printf '%s\n' 'start-stderr' >&2
    printf '%s\n' '{"result":{"agent":{"agent_status":"idle"}}}'
    ;;
"workspace list")
    _def='{"result":{"workspaces":[]}}'
    printf '%s\n' "${HERDR_WS_LIST:-${_def}}"
    ;;
"workspace create")
    _def='{"result":{"workspace":{"workspace_id":"ws-new"}}}'
    printf '%s\n' "${HERDR_WS_CREATE:-${_def}}"
    ;;
esac
exit 0
EOF
    chmod +x "${_BIN_DIR}/herdr"
}

_script_for() {
    case "$1" in
    iw) printf '%s' "${CUSTOM_DIR}/issue_watcher_cron.sh" ;;
    pmt) printf '%s' "${CUSTOM_DIR}/pr_merge_train_cron.sh" ;;
    esac
}

# _in <iw|pmt> <snippet> [VAR=VALUE ...]
# Sources the script and evals <snippet>, with @P@ / @U@ replaced by the
# function prefix (_iw / _pmt) and variable infix (IW / PMT).
_in() {
    local _p="$1" _snippet="$2" _u
    shift 2
    _u=$(printf '%s' "${_p}" | tr '[:lower:]' '[:upper:]')
    _snippet="${_snippet//@P@/_${_p}}"
    _snippet="${_snippet//@U@/${_u}}"
    run env \
        "PATH=${_BIN_DIR}:${PATH}" \
        "CALL_LOG=${_LOG}" \
        "XDG_STATE_HOME=${_WORK_DIR}/state" \
        "DOTFILES_TEST_MODE=1" \
        "$@" \
        bash -c '. "$1" || exit 99; eval "$2"' \
        "${CUSTOM_DIR}/.char-driver" "$(_script_for "${_p}")" "${_snippet}"
}

# ---------------------------------------------------------------------------
# state dir + lock
# ---------------------------------------------------------------------------

@test "cron herdr helpers: state dir honours XDG_STATE_HOME, then HOME" {
    _in iw '_iw_state_dir'
    assert_success
    assert_output "${_WORK_DIR}/state/issue-watcher"
    _in pmt '_pmt_state_dir'
    assert_success
    assert_output "${_WORK_DIR}/state/pr-merge-train"

    _in iw 'unset XDG_STATE_HOME; _iw_state_dir'
    assert_output "${HOME}/.local/state/issue-watcher"
    _in pmt 'unset XDG_STATE_HOME; _pmt_state_dir'
    assert_output "${HOME}/.local/state/pr-merge-train"
}

@test "cron herdr helpers: acquire_lock takes the lock and creates the lock file" {
    _in iw '_iw_acquire_lock && echo LOCKED'
    assert_success
    assert_output --partial "LOCKED"
    [ -f "${_WORK_DIR}/state/issue-watcher/.lock" ]

    _in pmt '_pmt_acquire_lock && echo LOCKED'
    assert_success
    assert_output --partial "LOCKED"
    [ -f "${_WORK_DIR}/state/pr-merge-train/.lock" ]
}

@test "cron herdr helpers: acquire_lock refuses a second tick with the script's own name" {
    local _p _sub _name
    for _p in iw pmt; do
        case "${_p}" in
        iw) _sub=issue-watcher _name=issue_watcher_cron ;;
        pmt) _sub=pr-merge-train _name=pr_merge_train_cron ;;
        esac
        mkdir -p "${_WORK_DIR}/state/${_sub}"
        flock -x "${_WORK_DIR}/state/${_sub}/.lock" sleep 30 &
        _LOCK_HOLDER_PID=$!
        # Wait until the holder really holds it.
        local _i=0
        while flock -n "${_WORK_DIR}/state/${_sub}/.lock" true 2>/dev/null; do
            _i=$((_i + 1))
            [ "${_i}" -lt 100 ] || fail "lock holder never took the lock"
            command sleep 0.05
        done

        _in "${_p}" '@P@_acquire_lock; echo "rc=$?"'
        assert_output --partial "another ${_name} tick is already running — skip"
        assert_output --partial "rc=1"

        kill "${_LOCK_HOLDER_PID}" 2>/dev/null || true
        wait "${_LOCK_HOLDER_PID}" 2>/dev/null || true
        _LOCK_HOLDER_PID=""
    done
}

@test "cron herdr helpers: acquire_lock degrades when the state dir cannot be made" {
    : >"${_WORK_DIR}/blocker"
    local _p
    for _p in iw pmt; do
        _in "${_p}" '@P@_acquire_lock; echo "rc=$?"' "XDG_STATE_HOME=${_WORK_DIR}/blocker"
        assert_output --partial "Cannot create state directory"
        assert_output --partial "running without single-instance protection"
        assert_output --partial "rc=0"
    done
}

# ---------------------------------------------------------------------------
# herdr workspace / create
# ---------------------------------------------------------------------------

@test "cron herdr helpers: workspace_for_label reuses an existing workspace" {
    local _p
    for _p in iw pmt; do
        : >"${_LOG}"
        _in "${_p}" '@P@_workspace_for_label mylabel /some/cwd' \
            'HERDR_WS_LIST={"result":{"workspaces":[{"label":"other","workspace_id":"ws-o"},{"label":"mylabel","workspace_id":"ws-7"}]}}'
        assert_success
        assert_output "ws-7"
        run grep -c 'workspace create' "${_LOG}"
        assert_output "0"
    done
}

@test "cron herdr helpers: workspace_for_label creates a missing workspace with the config dir" {
    local _p
    for _p in iw pmt; do
        : >"${_LOG}"
        _in "${_p}" '_@U@_CONFIG_DIR=/cfg/dir; @P@_workspace_for_label mylabel /some/cwd'
        assert_success
        assert_output "ws-new"
        run grep -F 'herdr workspace create --cwd /some/cwd --label mylabel --no-focus --env CLAUDE_CONFIG_DIR=/cfg/dir' "${_LOG}"
        assert_success
    done
}

@test "cron herdr helpers: herdr_create omits --env without a config dir" {
    local _p
    for _p in iw pmt; do
        : >"${_LOG}"
        _in "${_p}" '_@U@_CONFIG_DIR=""; @P@_herdr_create /c lbl tab create --workspace ws-1'
        assert_success
        run cat "${_LOG}"
        assert_output "herdr tab create --workspace ws-1 --cwd /c --label lbl --no-focus"
    done
}

@test "cron herdr helpers: workspace_for_label fails when create yields no id" {
    local _p
    for _p in iw pmt; do
        _in "${_p}" '@P@_workspace_for_label mylabel /c; echo "rc=$?"' 'HERDR_WS_CREATE={}'
        assert_output "rc=1"
    done
}

# ---------------------------------------------------------------------------
# agent status / start / error code / clock
# ---------------------------------------------------------------------------

@test "cron herdr helpers: agent_status prints the status, fails when get fails" {
    local _p
    for _p in iw pmt; do
        _in "${_p}" '_hp_agent_status a1' 'HERDR_AGENT_STATUS=working'
        assert_success
        assert_output "working"
        _in "${_p}" '_hp_agent_status a1; echo "rc=$?"' 'HERDR_AGENT_STATUS=fail'
        assert_output "rc=1"
    done
}

@test "cron herdr helpers: agent_start passes kind, pane and the stderr file" {
    local _p
    for _p in iw pmt; do
        : >"${_LOG}"
        _in "${_p}" "_hp_agent_start name1 pane1 ${_WORK_DIR}/err.${_p}"
        assert_success
        run cat "${_LOG}"
        assert_output "herdr agent start name1 --kind claude --pane pane1 -- --dangerously-skip-permissions"
        run cat "${_WORK_DIR}/err.${_p}"
        assert_output "start-stderr"
    done
}

@test "cron herdr helpers: herdr_error_code reads stdout first, then the stderr file" {
    printf '%s\n' '{"error":{"code":"from_stderr"}}' >"${_WORK_DIR}/errfile"
    : >"${_WORK_DIR}/empty"
    local _p
    for _p in iw pmt; do
        _in "${_p}" "_hp_herdr_error_code '{\"error\":{\"code\":\"from_stdout\"}}' ${_WORK_DIR}/errfile"
        assert_output "from_stdout"
        _in "${_p}" "_hp_herdr_error_code '' ${_WORK_DIR}/errfile"
        assert_output "from_stderr"
        _in "${_p}" "_hp_herdr_error_code '' ${_WORK_DIR}/empty"
        assert_output ""
    done
}

@test "cron herdr helpers: now prints epoch seconds" {
    local _p
    for _p in iw pmt; do
        _in "${_p}" '_hp_now'
        assert_success
        [[ "${output}" =~ ^[0-9]+$ ]]
    done
}

# ---------------------------------------------------------------------------
# wait_for_idle
# ---------------------------------------------------------------------------

@test "cron herdr helpers: wait_for_idle returns quietly on idle" {
    local _p
    for _p in iw pmt; do
        _in "${_p}" '_@U@_IDLE_POLL_SLEEP=0; @P@_wait_for_idle a1'
        assert_success
        assert_output ""
    done
}

@test "cron herdr helpers: wait_for_idle warns with the script's verb after the poll cap" {
    _in iw '_IW_IDLE_POLL_SLEEP=0; _iw_wait_for_idle a1' 'HERDR_AGENT_STATUS=starting'
    assert_success
    assert_output --partial "Agent a1 never reported idle in 10 checks — dispatching anyway."
    _in pmt '_PMT_IDLE_POLL_SLEEP=0; _pmt_wait_for_idle a1' 'HERDR_AGENT_STATUS=starting'
    assert_success
    assert_output --partial "Agent a1 never reported idle in 10 checks — prompting anyway."
}

@test "cron herdr helpers: wait_for_idle counts health-check failures" {
    local _p
    for _p in iw pmt; do
        _in "${_p}" '_@U@_IDLE_POLL_SLEEP=0; @P@_wait_for_idle a1' 'HERDR_AGENT_STATUS=fail'
        assert_output --partial "never reported idle in 10 checks (10/10 health-check failures)"
    done
}

# ---------------------------------------------------------------------------
# settle
# ---------------------------------------------------------------------------

@test "cron herdr helpers: settle with 0 seconds never reads the pane" {
    local _p
    for _p in iw pmt; do
        : >"${_LOG}"
        _in "${_p}" '_@U@_SETTLE_SECONDS=0; @P@_settle a1'
        assert_success
        run grep -c 'agent read' "${_LOG}"
        assert_output "0"
    done
}

@test "cron herdr helpers: settle returns once three reads agree" {
    local _p
    for _p in iw pmt; do
        : >"${_LOG}"
        _in "${_p}" '_@U@_SETTLE_SECONDS=13; _@U@_SETTLE_POLL_SLEEP=1; @P@_settle a1'
        assert_success
        refute_output --partial "never settled"
        run grep -c 'herdr agent read a1 --lines 15 --format text' "${_LOG}"
        assert_output "3"
    done
}

@test "cron herdr helpers: settle warns when the pane never settles" {
    local _p
    for _p in iw pmt; do
        : >"${_LOG}"
        _in "${_p}" '_@U@_SETTLE_SECONDS=7; _@U@_SETTLE_POLL_SLEEP=1; @P@_settle a1' 'HERDR_READ_TEXT=~'
        assert_success
        assert_output --partial "Agent a1 pane never settled within 7s — prompting anyway."
        run grep -c 'agent read' "${_LOG}"
        assert_output "7"
    done
}

@test "cron herdr helpers: settle treats the not-ready mark as unsettled" {
    local _p
    for _p in iw pmt; do
        _in "${_p}" '_@U@_SETTLE_SECONDS=5; _@U@_SETTLE_POLL_SLEEP=1; @P@_settle a1' 'HERDR_READ_TEXT=Not logged in'
        assert_output --partial "pane never settled within 5s"
    done
}

@test "cron herdr helpers: a fractional settle cap is one flat sleep" {
    local _p
    for _p in iw pmt; do
        : >"${_LOG}"
        _in "${_p}" '_@U@_SETTLE_SECONDS=0.5; @P@_settle a1'
        assert_success
        run cat "${_LOG}"
        assert_output "sleep 0.5"
    done
}

@test "cron herdr helpers: settle poll count scales with the gap and is capped" {
    local _p
    for _p in iw pmt; do
        : >"${_LOG}"
        _in "${_p}" '_@U@_SETTLE_SECONDS=13; _@U@_SETTLE_POLL_SLEEP=4; @P@_settle a1' 'HERDR_READ_TEXT=~'
        run grep -c 'agent read' "${_LOG}"
        assert_output "4"
        : >"${_LOG}"
        _in "${_p}" '_@U@_SETTLE_SECONDS=13; _@U@_SETTLE_POLL_SLEEP=0.001; @P@_settle a1' 'HERDR_READ_TEXT=~'
        run grep -c 'agent read' "${_LOG}"
        assert_output "1000"
    done
}

# ---------------------------------------------------------------------------
# resolve_config_dir
# ---------------------------------------------------------------------------

@test "cron herdr helpers: resolve_config_dir returns 2 without HOME" {
    local _p
    for _p in iw pmt; do
        _in "${_p}" 'unset HOME; @P@_resolve_config_dir; echo "rc=$?"'
        assert_output "rc=2"
    done
}

@test "cron herdr helpers: resolve_config_dir prints a logged-in account dir" {
    _make_account "${HOME}/.claude-personal"
    local _p
    for _p in iw pmt; do
        _in "${_p}" '@P@_resolve_config_dir' "CLAUDE_ENABLED_ACCOUNTS=personal"
        assert_success
        assert_output "${HOME}/.claude-personal"
    done
}

@test "cron herdr helpers: resolve_config_dir names the script's pane on an unknown account" {
    _in iw 'out=$(_iw_resolve_config_dir 2>/dev/null); echo "rc=$? out=[${out}]"; _iw_resolve_config_dir 2>&1 >/dev/null' \
        "CLAUDE_ENABLED_ACCOUNTS=personal" "CLAUDE_DEFAULT_ACCOUNT=bogus"
    assert_output --partial "Unknown claude account: bogus — cannot set CLAUDE_CONFIG_DIR for the watcher pane."
    assert_output --partial "rc=1"
    # issue_watcher's "Available:" hint goes to stdout (the discarded capture).
    assert_output --partial "out=[ℹ"
    _in pmt 'out=$(_pmt_resolve_config_dir 2>/dev/null); echo "rc=$? out=[${out}]"; _pmt_resolve_config_dir 2>&1 >/dev/null' \
        "CLAUDE_ENABLED_ACCOUNTS=personal" "CLAUDE_DEFAULT_ACCOUNT=bogus"
    assert_output --partial "Unknown claude account: bogus — cannot set CLAUDE_CONFIG_DIR for the merge-train pane."
    assert_output --partial "rc=1 out=[]"
    assert_output --partial "Available:"
}

@test "cron herdr helpers: resolve_config_dir names the script's pane on a missing dir" {
    _in iw '_iw_resolve_config_dir 2>&1' "CLAUDE_ENABLED_ACCOUNTS=personal"
    assert_failure
    assert_output --partial "Claude account directory missing: ${HOME}/.claude-personal — cannot bootstrap the watcher pane."
    _in pmt '_pmt_resolve_config_dir 2>&1' "CLAUDE_ENABLED_ACCOUNTS=personal"
    assert_failure
    assert_output --partial "Claude account directory missing: ${HOME}/.claude-personal — cannot bootstrap the merge-train pane."
}

@test "cron herdr helpers: resolve_config_dir refuses a logged-out account" {
    mkdir -p "${HOME}/.claude-personal"
    local _p
    for _p in iw pmt; do
        _in "${_p}" 'out=$(@P@_resolve_config_dir 2>/dev/null); echo "rc=$? out=[${out}]"; @P@_resolve_config_dir 2>&1 >/dev/null' \
            "CLAUDE_ENABLED_ACCOUNTS=personal"
        assert_output --partial "rc=1 out=[]"
        assert_output --partial "Claude account not logged in"
    done
}

@test "cron herdr helpers: resolve_config_dir falls back to ~/.claude for a pre-#1393 user" {
    mkdir -p "${HOME}/.claude"
    local _p
    for _p in iw pmt; do
        _in "${_p}" 'unset CLAUDE_ENABLED_ACCOUNTS CLAUDE_DEFAULT_ACCOUNT; @P@_resolve_config_dir 2>/dev/null'
        assert_success
        assert_output "${HOME}/.claude"
    done
}
