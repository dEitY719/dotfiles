#!/usr/bin/env bats
# tests/bats/functions/git_worktree_at.bats
# `gwt at` (#2355): frontend help, strict HH:MM, schedule-time validation, the
# job JSON contract, list status derivation (lost / pid reuse), cancel guards,
# the late (missed) rule and the herdr dispatch sequence — all against a herdr
# stub and GWT_AT_NOW, so nothing sleeps and no real herdr server is touched.

load '../test_helper'

SCRIPT="${DOTFILES_ROOT}/shell-common/tools/custom/gwt_at_dispatch.sh"

setup() {
    setup_isolated_home
    _WORK="$(mktemp -d "${TMPDIR:-/tmp}/gwt-at-test.XXXXXX")"
    export XDG_STATE_HOME="${_WORK}/state"
    _STATE="${XDG_STATE_HOME}/gwt-at"
    export HERDR_LOG="${_WORK}/herdr.log"
    : >"${HERDR_LOG}"
    export AGENTS_JSON='{"result":{"agents":[]}}'
    export AGENT_LIST_RC=0 START_RC=0 PROMPT_RC=0
    export GWT_AT_NOW=1800000000
    export GWT_AT_NO_DETACH=1 GWT_AT_RETRY_SLEEP=0 GWT_AT_START_RETRY_SLEEP=0
    export GWT_AT_IDLE_POLL_SLEEP=0 GWT_AT_SETTLE_SECONDS=0 GWT_AT_ENTER_SLEEP=0
    unset CLAUDE_ENABLED_ACCOUNTS CLAUDE_DEFAULT_ACCOUNT
    mkdir -p "${HOME}/.claude"

    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
    _REPO="${_WORK}/proj/repo"
    git init -q --initial-branch=main "${_REPO}"
    (cd "${_REPO}" && echo base >base.txt && git add base.txt && git commit -q -m base)

    _write_stub
}

teardown() {
    [ -z "${_BG_PID-}" ] || kill "${_BG_PID}" 2>/dev/null || true
    rm -rf "${_WORK}"
    teardown_isolated_home
}

# herdr stand-in, exported into the script (and its subshells) as a function.
# Every call is logged with argument boundaries: [a][b c].
_write_stub() {
    cat >"${_WORK}/stub.sh" <<'STUB'
herdr() {
    { printf '[%s]' "$@"; printf '\n'; } >>"${HERDR_LOG}"
    case "$1 $2" in
    "agent list")
        [ "${AGENT_LIST_RC}" -eq 0 ] || return "${AGENT_LIST_RC}"
        printf '%s' "${AGENTS_JSON}" ;;
    "workspace list") printf '{"result":{"workspaces":[]}}' ;;
    "workspace create") printf '{"result":{"workspace":{"workspace_id":"w1"},"root_pane":{"pane_id":"p0"}}}' ;;
    "tab create") printf '{"result":{"tab":{"tab_id":"t1"},"pane":{"pane_id":"p1"}}}' ;;
    "agent start")
        [ "${START_RC}" -eq 0 ] && return 0
        printf '{"error":{"code":"agent_spawn_failed","message":"boom from herdr"}}'
        return "${START_RC}" ;;
    "agent get") printf '{"result":{"agent":{"agent_status":"idle"}}}' ;;
    "agent prompt")
        [ "${PROMPT_RC}" -eq 0 ] && { printf '{"result":{}}'; return 0; }
        printf '{"error":{"code":"agent_gone","message":"pane closed"}}'
        return "${PROMPT_RC}" ;;
    *) return 0 ;;
    esac
}
export -f herdr
STUB
}

_run() {
    run bash -c ". '${_WORK}/stub.sh'; cd '${1}' && shift && bash '${SCRIPT}' \"\$@\"" _ "$@"
}

# Write a job JSON by hand: <id> <status> <fire_at> [pid] [starttime]
_job() {
    mkdir -p "${_STATE}"
    jq -n --arg id "$1" --arg st "$2" --argjson f "$3" --argjson p "${4:-0}" --arg s "${5:-}" \
        --arg repo "${_REPO}" \
        '{id:$id, fire_at:$f, repo:$repo, wt_name:"issue-92", base:"", prompt:"do the thing now",
          account:"", agent_name:"ga-repo-issue-92", pid:$p, pid_starttime:$s, status:$st,
          created_at:$f, finished_at:null, exit_reason:""}' >"${_STATE}/$1.json"
}

_status() { jq -r .status "${_STATE}/$1.json"; }

# --- frontend help ---------------------------------------------------------

@test "bash: gwt at --help / -h / no args print the spawn-style help, rc 0" {
    for a in --help -h ""; do
        run_in_bash "gwt at ${a}"
        assert_success
        assert_output --partial "gwt at - schedule a one-shot unattended run"
        assert_output --partial "Usage: gwt at <HH:MM> --wt-name <slug>"
        assert_output --partial "Required:"
        assert_output --partial "Optional (order-independent):"
        assert_output --partial "Trailing (must be LAST if used):"
        assert_output --partial "Examples:"
        assert_output --partial "dangerously-skip-permissions"
    done
}

@test "gwt at without git_worktree_at (vendored copy) fails with a clear message" {
    run_in_bash "unset -f git_worktree_at; gwt at list"
    assert_failure
    assert_output --partial "gwt at is not available here"
}

@test "dispatch picks the newly spawned worktree, not an older higher index" {
    git -C "${_REPO}" worktree add -q -b wt/issue-92/7 "${_WORK}/proj/old-tree"
    _job pick pending "${GWT_AT_NOW}"
    _run "${_REPO}" --run "${_STATE}/pick.json"
    assert_success
    run grep -F "[tab][create]" "${HERDR_LOG}"
    assert_output --partial "[--cwd][${_WORK}/proj/repo-issue-92-"
    refute_output --partial "old-tree"
}

@test "zsh: gwt at --help prints the help, rc 0" {
    run_in_zsh "gwt at --help"
    assert_success
    assert_output --partial "Subcommands:"
}

@test "gwt-help at documents the permission warning and lifetime" {
    run_in_bash "gwt_help at"
    assert_success
    assert_output --partial "WITHOUT permission prompts"
    assert_output --partial "Lost on reboot"
    run_in_bash "gwt_help"
    refute_output --partial "tmux"
}

# --- HH:MM ------------------------------------------------------------------

@test "non-HH:MM times are usage errors and write no job" {
    for t in 8pm 20 tomorrow 24:00 7:30 20:60; do
        _run "${_REPO}" "${t}" --wt-name issue-92
        assert_failure 2
        assert_output --partial "Invalid time"
    done
    [ ! -d "${_STATE}" ] || [ -z "$(ls "${_STATE}")" ]
}

@test "a future HH:MM fires today; a passed or equal HH:MM fires tomorrow" {
    now=$(date -d "2027-01-15 12:00" +%s)
    export GWT_AT_NOW="${now}"
    _run "${_REPO}" 13:00 --wt-name a1
    assert_success
    assert_output --partial "2027-01-15"
    _run "${_REPO}" 12:00 --wt-name a2
    assert_output --partial "2027-01-16"
    _run "${_REPO}" 08:00 --wt-name a3
    assert_output --partial "2027-01-16"
    [ "$(jq -s 'map(.fire_at) | sort | .[0]' "${_STATE}"/*.json)" = "$(date -d '2027-01-15 13:00' +%s)" ]
}

# --- schedule validation + job contract --------------------------------------

@test "schedule writes a 600 job JSON in a 700 dir with the full contract" {
    _run "${_REPO}/." 20:00 --base main --wt-name issue-92 --prompt /wave 32 --user x
    assert_success
    f=$(ls "${_STATE}"/*.json)
    [ "$(stat -c %a "${_STATE}")" = 700 ]
    [ "$(stat -c %a "${f}")" = 600 ]
    [ "$(stat -c %a "${f%.json}.log")" = 600 ]
    run jq -r '[.repo, .wt_name, .base, .prompt, .agent_name, .status] | join("|")' "${f}"
    assert_output "${_REPO}|issue-92|main|/wave 32 --user x|ga-repo-issue-92|pending"
    run jq -r 'has("pid_starttime") and has("created_at") and has("finished_at") and has("exit_reason")' "${f}"
    assert_output true
}

@test "schedule from a linked worktree records the main checkout" {
    git -C "${_REPO}" worktree add -q -b side "${_WORK}/proj/side"
    _run "${_WORK}/proj/side" 20:00 --wt-name issue-92
    assert_success
    [ "$(jq -r .repo "${_STATE}"/*.json)" = "${_REPO}" ]
}

@test "schedule-time failures exit non-zero and write no job" {
    _run "${_WORK}" 20:00 --wt-name issue-92
    assert_failure
    assert_output --partial "Not inside a git repository"

    _run "${_REPO}" 20:00 --wt-name this-name-is-far-too-long-for-herdr
    assert_failure
    assert_output --partial "over 32 chars"

    _run "${_REPO}" 20:00
    assert_failure
    assert_output --partial "--wt-name <slug> is required"

    export AGENT_LIST_RC=1
    _run "${_REPO}" 20:00 --wt-name issue-92
    assert_failure
    assert_output --partial "not reachable"

    export AGENT_LIST_RC=0 AGENTS_JSON='{"result":{"agents":[{"name":"ga-repo-issue-92"}]}}'
    _run "${_REPO}" 20:00 --wt-name issue-92
    assert_failure
    assert_output --partial "already running"

    [ ! -d "${_STATE}" ] || [ -z "$(ls "${_STATE}"/*.json 2>/dev/null)" ]
}

@test "a second pending job for the same agent is rejected" {
    sleep 300 &
    _BG_PID=$!
    st=$(awk '{print $22}' "/proc/${_BG_PID}/stat")
    _job j1 pending 1800003600 "${_BG_PID}" "${st}"
    _run "${_REPO}" 20:00 --wt-name issue-92
    assert_failure
    assert_output --partial "already targets agent ga-repo-issue-92"
}

# --- list / cancel ----------------------------------------------------------

@test "list derives lost from a dead pid and from a reused pid (starttime mismatch)" {
    sleep 300 &
    _BG_PID=$!
    _job dead pending 1800003600 999999 123
    _job reused pending 1800003600 "${_BG_PID}" 1
    _job ok done 1800000000
    _run "${_REPO}" list
    assert_success
    assert_line --regexp "dead .*lost"
    assert_line --regexp "reused .*lost"
    assert_line --regexp "ok .*done"
}

@test "list hides finished jobs older than the window unless --all" {
    _job oldjob done 1700000000
    _run "${_REPO}" list
    refute_output --partial "oldjob"
    _run "${_REPO}" list --all
    assert_output --partial "oldjob"
}

@test "cancel never kills a reused pid" {
    sleep 300 &
    _BG_PID=$!
    st=$(awk '{print $22}' "/proc/${_BG_PID}/stat")
    # Same pid AND starttime, but the cmdline is not this job's runner.
    _job stranger pending 1800003600 "${_BG_PID}" "${st}"
    _run "${_REPO}" cancel stranger
    assert_failure
    assert_output --partial "not this job's runner"
    kill -0 "${_BG_PID}"
    [ "$(_status stranger)" = pending ]
}

@test "cancel stops a pending runner; running jobs are refused" {
    _job live pending 1800003600
    GWT_AT_TICK_S=1 bash -c ". '${_WORK}/stub.sh'; exec bash '${SCRIPT}' --run '${_STATE}/live.json'" \
        >/dev/null 2>&1 &
    _BG_PID=$!
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [ "$(jq -r .pid "${_STATE}/live.json")" != 0 ] && break
        sleep 0.2
    done
    _run "${_REPO}" cancel live
    assert_success
    [ "$(_status live)" = cancelled ]
    sleep 0.3
    run kill -0 "${_BG_PID}"
    assert_failure

    sleep 300 &
    _BG_PID=$!
    _job fired running 1800000000 "${_BG_PID}" "$(awk '{print $22}' "/proc/${_BG_PID}/stat")"
    _run "${_REPO}" cancel fired
    assert_failure
    assert_output --partial "already fired"
}

# --- --run --------------------------------------------------------------------

@test "a runner waking more than 30m late records missed and dispatches nothing" {
    _job late pending $((GWT_AT_NOW - 1801))
    _run "${_REPO}" --run "${_STATE}/late.json"
    assert_success
    [ "$(_status late)" = missed ]
    run grep -c "agent start" "${HERDR_LOG}"
    assert_output 0
}

@test "a cancelled job's runner exits without dispatching" {
    _job c cancelled "${GWT_AT_NOW}"
    _run "${_REPO}" --run "${_STATE}/c.json"
    assert_success
    [ "$(_status c)" = cancelled ]
    [ ! -s "${HERDR_LOG}" ]
}

@test "dispatch: spawn, tab with CLAUDE_CONFIG_DIR, agent start, prompt as one arg -> done" {
    _job go pending "${GWT_AT_NOW}"
    _run "${_REPO}" --run "${_STATE}/go.json"
    assert_success
    [ "$(_status go)" = done ]
    [ -d "${_WORK}/proj/repo-issue-92-1" ]
    run grep -F "[tab][create]" "${HERDR_LOG}"
    assert_output --partial "[--cwd][${_WORK}/proj/repo-issue-92-1][--label][ga-repo-issue-92]"
    assert_output --partial "[--env][CLAUDE_CONFIG_DIR=${HOME}/.claude]"
    run grep -F "[agent][prompt]" "${HERDR_LOG}"
    assert_output --partial "[ga-repo-issue-92][do the thing now][--wait][--until][working][--until][blocked]"
}

@test "dispatch failure records failed with herdr's code and sentence" {
    export START_RC=1
    _job bad pending "${GWT_AT_NOW}"
    _run "${_REPO}" --run "${_STATE}/bad.json"
    assert_failure
    [ "$(_status bad)" = failed ]
    run jq -r .exit_reason "${_STATE}/bad.json"
    assert_output "agent_spawn_failed: boom from herdr"
    run grep -c "\[tab\]\[close\]" "${HERDR_LOG}"
    assert_output 3
}
