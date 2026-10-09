#!/usr/bin/env bats
# tests/bats/tools/herdr_pane.bats
# Unit tests for shell-common/tools/custom/lib/herdr_pane.sh — the herdr pane
# helpers both cron dispatchers share (refactor F2). The lib is sourced on its
# own (plus ux_lib), so these pin the argument contract the dispatchers'
# wrappers rely on. Script-level behaviour is pinned by cron_herdr_helpers.bats.

load '../test_helper'

LIB="${DOTFILES_ROOT}/shell-common/tools/custom/lib/herdr_pane.sh"

setup() {
    setup_isolated_home
    _WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/herdr-pane-lib.XXXXXX")"
    _BIN_DIR="${_WORK_DIR}/bin"
    _LOG="${_WORK_DIR}/calls.log"
    mkdir -p "${_BIN_DIR}"
    : >"${_LOG}"
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
"workspace list") printf '%s\n' '{"result":{"workspaces":[]}}' ;;
"workspace create") printf '%s\n' '{"result":{"workspace":{"workspace_id":"ws-9"}}}' ;;
esac
exit 0
EOF
    chmod +x "${_BIN_DIR}/herdr"
    _install_sleep_stub
    _install_frozen_clock_stub
}

teardown() {
    rm -rf "${_WORK_DIR}"
    teardown_isolated_home
}

# _lib <snippet> [VAR=VALUE ...] — source ux_lib + the lib, then eval.
_lib() {
    local _snippet="$1"
    shift
    run env \
        "PATH=${_BIN_DIR}:${PATH}" \
        "CALL_LOG=${_LOG}" \
        "UX_LIB=${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" \
        "LIB=${LIB}" \
        "$@" \
        bash -c 'set -u; . "$UX_LIB"; . "$LIB" || exit 99; eval "$1"' _ "${_snippet}"
}

@test "herdr_pane: sources cleanly under set -u and defines only _hp_ functions" {
    # Only what the lib adds: bats exports helper functions into the child.
    run bash -c 'set -u; b=$(declare -F); . "$1" || exit 1; diff <(echo "$b") <(declare -F) | sed -n "s/^> declare -f //p"' _ "${LIB}"
    assert_success
    assert_output --partial "_hp_settle"
    refute_output --regexp '(^|[[:space:]])([^_]|_[^h]|_h[^p]|_hp[^_])'
}

@test "herdr_pane: state_dir takes the subdir as an argument" {
    _lib '_hp_state_dir some-job' "XDG_STATE_HOME=/s"
    assert_output "/s/some-job"
}

@test "herdr_pane: acquire_lock names the given tick when the lock is held" {
    # The subshell drops the inherited fd 9 and opens its own, so the parent's
    # lock is held against it.
    _lib '_hp_acquire_lock "$D" .mylock my_tick && echo first; ( exec 9>&-; _hp_acquire_lock "$D" .mylock my_tick; echo "rc=$?" )' \
        "D=${_WORK_DIR}/st"
    assert_output --partial "first"
    assert_output --partial "another my_tick tick is already running — skip"
    assert_output --partial "rc=1"
    [ -f "${_WORK_DIR}/st/.mylock" ]
}

@test "herdr_pane: herdr_create adds --env only for a non-empty config dir" {
    _lib '_hp_herdr_create /cfg /cwd lbl tab create; _hp_herdr_create "" /cwd lbl tab create'
    run cat "${_LOG}"
    assert_line --index 0 "herdr tab create --cwd /cwd --label lbl --no-focus --env CLAUDE_CONFIG_DIR=/cfg"
    assert_line --index 1 "herdr tab create --cwd /cwd --label lbl --no-focus"
}

@test "herdr_pane: workspace_for_label passes the config dir to the create" {
    _lib '_hp_workspace_for_label /cfg lbl /cwd'
    assert_output "ws-9"
    run grep -F 'herdr workspace create --cwd /cwd --label lbl --no-focus --env CLAUDE_CONFIG_DIR=/cfg' "${_LOG}"
    assert_success
}

@test "herdr_pane: wait_for_idle honours max checks and the verb" {
    _lib '_hp_wait_for_idle a1 3 0 frobbing' "HERDR_AGENT_STATUS=starting"
    assert_output --partial "Agent a1 never reported idle in 3 checks — frobbing anyway."
    run grep -c 'agent get' "${_LOG}"
    assert_output "3"
}

@test "herdr_pane: pane_text reads the requested line count and drops herdr errors" {
    _lib '_hp_pane_text a1 42'
    assert_output "ready"
    run grep -F 'herdr agent read a1 --lines 42 --format text' "${_LOG}"
    assert_success
    _lib '_hp_pane_text a1 5' 'HERDR_READ_TEXT={"error":{"code":"agent_not_found"}}'
    assert_output ""
}

@test "herdr_pane: pane_settled needs three equal non-empty reads without the mark" {
    _lib '_hp_pane_settled x x x MARK && echo yes'
    assert_output "yes"
    _lib '_hp_pane_settled x x y MARK || echo no'
    assert_output "no"
    _lib '_hp_pane_settled "" "" "" MARK || echo no'
    assert_output "no"
    _lib '_hp_pane_settled "a MARK b" "a MARK b" "a MARK b" MARK || echo no'
    assert_output "no"
}

@test "herdr_pane: settle_max_polls is ceil(s/gap), floored at 2, capped at 1000" {
    _lib 'echo "$(_hp_settle_max_polls 13 1) $(_hp_settle_max_polls 13 4) $(_hp_settle_max_polls 13 13) $(_hp_settle_max_polls 13 0.001) $(_hp_settle_max_polls 13 0) $(_hp_settle_max_polls 13 .0)"'
    assert_output "13 4 2 1000 13 13"
}

@test "herdr_pane: settle uses the given lines and mark" {
    _lib '_hp_settle a1 4 1 9 ready'
    assert_output --partial "Agent a1 pane never settled within 4s — prompting anyway."
    run grep -c 'herdr agent read a1 --lines 9 --format text' "${_LOG}"
    assert_output "4"
}

@test "herdr_pane: settle accepts a leading-zero cap as decimal" {
    _lib '_hp_settle a1 08 1 15 MARK; echo "rc=$?"' "HERDR_READ_TEXT=~"
    assert_output --partial "never settled within 08s"
    assert_output --partial "rc=0"
}

@test "herdr_pane: resolve_config_dir sends account hints to the chosen stream" {
    _lib 'out=$(_hp_resolve_config_dir "$SHELL_COMMON" job-x stderr 2>/dev/null); echo "rc=$? out=[${out}]"' \
        "SHELL_COMMON=${SHELL_COMMON}" "CLAUDE_ENABLED_ACCOUNTS=personal"
    assert_output "rc=1 out=[]"
    _lib 'out=$(_hp_resolve_config_dir "$SHELL_COMMON" job-x stdout 2>/dev/null); echo "rc=$? out=[${out}]"' \
        "SHELL_COMMON=${SHELL_COMMON}" "CLAUDE_ENABLED_ACCOUNTS=personal"
    assert_output --partial "Run: claude-accounts setup"
    _lib '_hp_resolve_config_dir "$SHELL_COMMON" job-x stderr 2>&1' \
        "SHELL_COMMON=${SHELL_COMMON}" "CLAUDE_ENABLED_ACCOUNTS=personal"
    assert_output --partial "cannot bootstrap the job-x pane."
}

@test "herdr_pane: resolve_config_dir fails on a bad shell-common path" {
    _lib '_hp_resolve_config_dir /nonexistent job-x stderr 2>&1; echo "rc=$?"'
    assert_output --partial "Cannot load /nonexistent/tools/integrations/claude.sh"
    assert_output --partial "rc=1"
}
