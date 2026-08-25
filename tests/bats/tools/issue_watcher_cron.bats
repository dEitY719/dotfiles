#!/usr/bin/env bats
# tests/bats/tools/issue_watcher_cron.bats
# Tests for issue_watcher_cron.sh — the 5-minute issue-watcher tick
# (issues #1389, #1436, #1440).
#
# Since #1440 the tick does the watching and dispatching itself, so the suite
# covers the whole pipeline rather than a single dispatcher prompt. Three PATH
# stubs stand in for the outside world and log every invocation to ${_LOG} so
# the tests can assert on *which* calls were made:
#
#   gh     `search issues` (canned result set, steerable per test) and
#          `api graphql` (blockedBy). Every other subcommand is logged and
#          refused — the tick must never write to an issue.
#   herdr  workspace/tab/agent, with canned JSON matching the shapes measured
#          on a live herdr server.
#   gwt    real `git worktree` calls against a real fixture repo, so the
#          worktree dedup criterion is exercised for real rather than mocked.

load '../test_helper'

SCRIPT="${DOTFILES_ROOT}/shell-common/tools/custom/issue_watcher_cron.sh"

setup() {
    setup_isolated_home
    _WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/issue-watcher-test.XXXXXX")"
    _BIN_DIR="${_WORK_DIR}/bin"
    _STATE_HOME="${_WORK_DIR}/state"
    _STATE_DIR="${_STATE_HOME}/issue-watcher"
    _LIMIT_FILE="${_STATE_DIR}/rate-limit.json"
    _LOCK_FILE="${_STATE_DIR}/.lock"
    _LOG="${_WORK_DIR}/calls.log"
    _REPO_DIR="${_WORK_DIR}/dotfiles"
    _WATCH_FILE="${_WORK_DIR}/watched-repos.json"
    _LOCK_HOLDER_PID=""
    mkdir -p "${_BIN_DIR}"
    : >"${_LOG}"

    # CLAUDE_CONFIG_DIR account routing (issue #1393): the tick resolves the
    # claude account dir before it opens any pane and fails fast when it is
    # missing, so the default account must exist inside the isolated $HOME.
    # Pinned here (not inherited) so the developer's own shell env cannot
    # steer the tests.
    export CLAUDE_ENABLED_ACCOUNTS="personal"
    unset CLAUDE_DEFAULT_ACCOUNT
    mkdir -p "${HOME}/.claude-personal"

    _make_repo
    _write_watch_file '[{"repo":"acme/dotfiles","path":"'"${_REPO_DIR}"'","host":"github.com"}]'
    _set_issues '[{"number":11,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}]'
    _install_stubs
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
# Fixtures
# ---------------------------------------------------------------------------

# A real git repo, because the dedup criterion is `git worktree list` output.
# Mocking that away would test the mock, not the criterion.
_make_repo() {
    mkdir -p "${_REPO_DIR}"
    git -C "${_REPO_DIR}" init -q
    git -C "${_REPO_DIR}" config user.email "test@example.com"
    git -C "${_REPO_DIR}" config user.name "test"
    printf 'seed\n' >"${_REPO_DIR}/README.md"
    git -C "${_REPO_DIR}" add -A
    git -C "${_REPO_DIR}" commit -qm "seed"
}

# Register an existing worktree for issue <1>, the way a previous cycle would
# have left it.
_add_worktree() {
    git -C "${_REPO_DIR}" worktree add -q -b "wt/issue-$1/1" \
        "${_WORK_DIR}/dotfiles-issue-$1-1" HEAD
}

_write_watch_file() {
    printf '%s\n' "$1" >"${_WATCH_FILE}"
}

# The `gh search issues` result set for this test.
_set_issues() {
    printf '%s\n' "$1" >"${_WORK_DIR}/issues.json"
}

# One issue with the given labels, e.g. _issues_with_labels 11 wontfix
_issues_with_labels() {
    local _n="$1" _labels="" _sep=""
    shift
    for _l in "$@"; do
        _labels="${_labels}${_sep}{\"name\":\"${_l}\"}"
        _sep=","
    done
    _set_issues "[{\"number\":${_n},\"repository\":{\"nameWithOwner\":\"acme/dotfiles\"},\"labels\":[${_labels}]}]"
}

# ---------------------------------------------------------------------------
# Stubs
# ---------------------------------------------------------------------------

# gh: only `search issues` and `api graphql` are answered. Anything else is
# logged and fails — the tick is read-only on issues by contract, and this is
# what makes "no comment, label or assignee change" a test rather than a claim.
#
#   GH_SEARCH_FAIL=1   `search issues` errors
#   GH_BLOCKED_BY      issue numbers whose blockedBy answer carries an OPEN
#                      blocker, space-separated (default: none)
#   GH_GRAPHQL_FAIL=1  `api graphql` errors (fail-open path)
_install_gh_stub() {
    cat >"${_BIN_DIR}/gh" <<'EOF'
#!/bin/sh
printf 'gh %s\n' "$*" >>"${CALL_LOG}"

case "$1 $2" in
"search issues")
    [ "${GH_SEARCH_FAIL:-0}" = "1" ] && exit 1
    cat "${GH_ISSUES_FILE}"
    exit 0
    ;;
"api graphql")
    # The real `gh api` reads stdin. Draining it here is what makes the
    # candidate-loop fd-3 test meaningful: on plain stdin this swallows the
    # remaining search results (PR #1447 agy review).
    cat >/dev/null 2>&1 || true
    [ "${GH_GRAPHQL_FAIL:-0}" = "1" ] && exit 1
    _num=""
    for _a in "$@"; do
        case "${_a}" in number=*) _num="${_a#number=}" ;; esac
    done
    for _b in ${GH_BLOCKED_BY:-}; do
        if [ "${_b}" = "${_num}" ]; then
            printf '%s\n' '{"data":{"repository":{"issue":{"blockedBy":{"nodes":[{"number":9,"state":"OPEN"}]}}}}}'
            exit 0
        fi
    done
    printf '%s\n' '{"data":{"repository":{"issue":{"blockedBy":{"nodes":[]}}}}}'
    exit 0
    ;;
esac

printf 'gh: refusing unexpected subcommand: %s\n' "$*" >&2
exit 64
EOF
    chmod +x "${_BIN_DIR}/gh"
}

# herdr: the four call groups the tick makes.
#
#   HERDR_WORKSPACE_EXISTS=1  `workspace list` already carries the repo label
#   HERDR_TAB_FAIL=1          `tab create` errors
#   HERDR_TAB_FAIL_AFTER=N    the first N `tab create` calls succeed, the rest
#                             error — lets one issue fail two different ways
#                             across its retry attempts
#   HERDR_START_FAIL=1        `agent start` errors
#   HERDR_AGENT_STATUS        status reported by `agent get` (default: idle)
#   HERDR_AGENT_GET_FAIL=1    `agent get` returns agent_not_found and exits 1
#   HERDR_PROMPT_MODE         `agent prompt` behaviour (default: always ok)
#                               stall-once  first call stalled, rest ok
#                               stall       every call stalled
#                               fail        every call a non-stall error
#   HERDR_PROMPT_FAIL_TIMES   first N `agent prompt` calls stall, then ok
# Each herdr invocation is a fresh process, so the per-call sequences count
# through marker files next to ${CALL_LOG} rather than through shell state.
_install_herdr_stub() {
    cat >"${_BIN_DIR}/herdr" <<'EOF'
#!/bin/sh
printf 'herdr %s\n' "$*" >>"${CALL_LOG}"

_bump() {
    _n=$(cat "$1" 2>/dev/null || printf 0)
    _n=$((_n + 1))
    printf '%s' "${_n}" >"$1"
    printf '%s' "${_n}"
}

case "$1 $2" in
"workspace list")
    if [ "${HERDR_WORKSPACE_EXISTS:-0}" = "1" ]; then
        printf '{"id":"cli:workspace:list","result":{"workspaces":[{"label":"%s","workspace_id":"ws-existing"}]}}\n' \
            "${HERDR_WORKSPACE_LABEL:-dotfiles}"
    else
        printf '%s\n' '{"id":"cli:workspace:list","result":{"workspaces":[]}}'
    fi
    ;;
"workspace create")
    printf '%s\n' '{"id":"cli:workspace:create","result":{"workspace":{"workspace_id":"ws-test-1"},"root_pane":{"pane_id":"ws-test-1:p1"}}}'
    ;;
"tab create")
    [ "${HERDR_TAB_FAIL:-0}" = "1" ] && exit 1
    if [ -n "${HERDR_TAB_FAIL_AFTER:-}" ]; then
        _n=$(_bump "${CALL_LOG}.tabcount")
        [ "${_n}" -gt "${HERDR_TAB_FAIL_AFTER}" ] && exit 1
    fi
    printf '%s\n' '{"id":"cli:tab:create","result":{"tab":{"tab_id":"ws-test-1:t9"},"pane":{"pane_id":"ws-test-1:p9"}}}'
    ;;
"tab close")
    printf '%s\n' '{"id":"cli:tab:close","result":{"ok":true}}'
    ;;
"agent start")
    [ "${HERDR_START_FAIL:-0}" = "1" ] && exit 1
    printf '%s\n' '{"id":"cli:agent:start","result":{"agent":{"agent_status":"idle","pane_id":"ws-test-1:p9"}}}'
    ;;
"agent get")
    if [ "${HERDR_AGENT_GET_FAIL:-0}" = "1" ]; then
        printf '%s\n' '{"error":{"code":"agent_not_found","message":"agent target not found"},"id":"cli:agent:get"}'
        exit 1
    fi
    printf '{"id":"cli:agent:get","result":{"agent":{"agent_status":"%s"}}}\n' "${HERDR_AGENT_STATUS:-idle}"
    ;;
"agent prompt")
    if [ -n "${HERDR_PROMPT_FAIL_TIMES:-}" ]; then
        _n=$(_bump "${CALL_LOG}.promptcount")
        if [ "${_n}" -le "${HERDR_PROMPT_FAIL_TIMES}" ]; then
            printf '%s\n' '{"error":{"code":"agent_prompt_stalled","message":"no agent state change observed within 5000ms"},"id":"cli:agent:prompt"}'
            exit 1
        fi
        printf '%s\n' '{"id":"cli:agent:prompt","result":{"ok":true}}'
        exit 0
    fi
    case "${HERDR_PROMPT_MODE:-ok}" in
    stall-once)
        _n=$(_bump "${CALL_LOG}.promptcount")
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
        printf '%s\n' '{"error":{"code":"agent_not_found","message":"agent target not found"},"id":"cli:agent:prompt"}'
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

# gwt: real `git worktree` work, so `_iw_worktree_for_issue` sees what a real
# spawn would leave behind.
#
#   GWT_SPAWN_MODE=fail        never creates, always exits 1
#   GWT_SPAWN_MODE=fail-after  creates the worktree, then exits 1 (the case
#                              where cleanup has to find a worktree the failed
#                              attempt did not report)
#   GWT_SPAWN_FAIL_TIMES=N     first N spawns fail, the rest succeed
_install_gwt_stub() {
    cat >"${_BIN_DIR}/gwt" <<'EOF'
#!/bin/sh
printf 'gwt %s\n' "$*" >>"${CALL_LOG}"

_bump() {
    _n=$(cat "$1" 2>/dev/null || printf 0)
    _n=$((_n + 1))
    printf '%s' "${_n}" >"$1"
    printf '%s' "${_n}"
}

case "$1" in
spawn)
    shift
    _name=""
    while [ $# -gt 0 ]; do
        case "$1" in
        --wt-name) _name="$2"; shift 2 ;;
        *) shift ;;
        esac
    done
    _n="${_name#issue-}"

    _fail=0
    if [ -n "${GWT_SPAWN_FAIL_TIMES:-}" ]; then
        _c=$(_bump "${CALL_LOG}.spawncount")
        [ "${_c}" -le "${GWT_SPAWN_FAIL_TIMES}" ] && _fail=1
    fi
    [ "${GWT_SPAWN_MODE:-ok}" = "fail" ] && _fail=1

    [ "${_fail}" = "1" ] && [ "${GWT_SPAWN_MODE:-ok}" != "fail-after" ] && exit 1

    _idx=1
    while git rev-parse --verify --quiet "refs/heads/wt/issue-${_n}/${_idx}" >/dev/null 2>&1; do
        _idx=$((_idx + 1))
    done
    git worktree add -q -b "wt/issue-${_n}/${_idx}" \
        "$(git rev-parse --show-toplevel)-issue-${_n}-${_idx}" HEAD >/dev/null 2>&1 || exit 1

    [ "${GWT_SPAWN_MODE:-ok}" = "fail-after" ] && exit 1
    [ "${_fail}" = "1" ] && exit 1
    exit 0
    ;;
remove)
    _target="$2"
    _branch=$(git worktree list --porcelain 2>/dev/null |
        awk -v p="worktree ${_target}" '
            $0 == p { found = 1; next }
            found && /^branch / { print substr($0, 8); exit }
        ')
    git worktree remove --force "${_target}" >/dev/null 2>&1 || true
    [ -z "${_branch}" ] || git branch -D "${_branch#refs/heads/}" >/dev/null 2>&1 || true
    exit 0
    ;;
esac
exit 0
EOF
    chmod +x "${_BIN_DIR}/gwt"
}

_install_stubs() {
    _install_gh_stub
    _install_herdr_stub
    _install_gwt_stub
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Run one tick with the stubs on PATH and an isolated XDG_STATE_HOME.
#
#   _run_tick [-u VAR ...] [VAR=VALUE ...] [-- script-flag ...]
#
# `-u VAR` pairs must come first — `env` only parses options ahead of the first
# NAME=VALUE. The VAR=VALUE assignments are appended after the defaults, and
# `env` applies assignments left to right, so a test can override any of them
# (PATH included) without restating the whole sandbox.
_run_tick() {
    local _unset=() _env=()
    while [ "$#" -gt 1 ] && [ "$1" = "-u" ]; do
        _unset+=(-u "$2")
        shift 2
    done
    while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
        _env+=("$1")
        shift
    done
    [ "$#" -eq 0 ] || shift

    run env \
        "${_unset[@]}" \
        "PATH=${_BIN_DIR}:${PATH}" \
        "CALL_LOG=${_LOG}" \
        "GH_ISSUES_FILE=${_WORK_DIR}/issues.json" \
        "IW_WATCHED_REPOS=${_WATCH_FILE}" \
        "XDG_STATE_HOME=${_STATE_HOME}" \
        "IW_IDLE_POLL_SLEEP=0" \
        "${_env[@]}" \
        bash "${SCRIPT}" "$@"
}

_log_count() {
    grep -c -- "$1" "${_LOG}" 2>/dev/null || true
}

# Call-log assertions that leave `$output` and `$status` alone. Tests routinely
# pair these with `assert_output` on the tick's own output, and a `run grep`
# here would overwrite it — which used to make the order of the two
# load-bearing, and silently assert against grep's output when it was wrong.
_assert_logged() {
    grep -qF -- "$1" "${_LOG}" || fail "expected in call log: $1"
}

_refute_logged() {
    ! grep -qF -- "$1" "${_LOG}" || fail "unexpected in call log: $1"
}

# A PATH that carries only the stub dir plus symlinks to the system binaries
# the tick needs — minus the ones named as arguments. Deleting a stub is not
# enough to make a binary missing: `command -v` keeps walking the inherited
# PATH and finds the real herdr, which then talks to the developer's live
# session. Every "X not found" test has to build its PATH instead of pruning
# one.
_path_without() {
    local _d="${_WORK_DIR}/sysbin" _b _p _skip
    rm -rf "${_d}"
    mkdir -p "${_d}"

    for _b in sh bash env git jq awk sed grep egrep head tail cat cut tr sort \
        uniq date mkdir rmdir rm ln basename dirname sleep mktemp flock tput \
        uname wc chmod find id stty locale; do
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
    assert_output --partial "--dry-run"
}

@test "issue_watcher_cron: --help documents the crontab registration example" {
    run bash "${SCRIPT}" --help
    assert_success
    assert_output --partial "*/5 * * * *"
    assert_output --partial "issue_watcher_cron.sh"
    assert_output --partial "cron.log"
}

@test "issue_watcher_cron: --help documents the watch list and its override" {
    run bash "${SCRIPT}" --help
    assert_success
    assert_output --partial "watched-repos.json"
    assert_output --partial "IW_WATCHED_REPOS"
}

@test "issue_watcher_cron: --help documents the filters and the per-cycle cap" {
    run bash "${SCRIPT}" --help
    assert_success
    assert_output --partial "gh search issues"
    assert_output --partial "wontfix"
    assert_output --partial "blockedBy"
    assert_output --partial "at most 3 issues per cycle"
}

@test "issue_watcher_cron: --help documents the rate-limit gate and its state file" {
    run bash "${SCRIPT}" --help
    assert_success
    assert_output --partial "rate-limit gate"
    assert_output --partial "rate-limit.json"
    assert_output --partial "30m"
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
    run bash "${SCRIPT}" --nope
    assert_failure
    assert_output --partial "Unknown option"
}

@test "issue_watcher_cron: --cwd without a value fails" {
    run bash "${SCRIPT}" --cwd
    assert_failure
    assert_output --partial "--cwd requires a PATH"
}

# ---------------------------------------------------------------------------
# The dispatch path (#1440)
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: an assigned issue is spawned, tabbed and prompted" {
    _run_tick
    assert_success
    _assert_logged "gwt spawn --wt-name issue-11"
    _assert_logged "tab create --workspace"
    _assert_logged "agent start iw-acme-dotfiles-11 --kind claude --pane ws-test-1:p9"
    _assert_logged "agent prompt iw-acme-dotfiles-11 /gh-issue-flow 11"
}

@test "issue_watcher_cron: the prompt is the slash command, not a subagent instruction" {
    _run_tick
    assert_success
    _assert_logged "/gh-issue-flow 11"
    # The pre-#1440 prompt told the receiving session to run another agent,
    # which is the ambiguity #1394 was about. Nothing may reintroduce it.
    _refute_logged "issue-watcher:dispatcher"
    _refute_logged "Agent 도구"
}

@test "issue_watcher_cron: the dispatched pane runs claude with --dangerously-skip-permissions" {
    _run_tick
    assert_success
    _assert_logged "agent start iw-acme-dotfiles-11 --kind claude --pane ws-test-1:p9 -- --dangerously-skip-permissions"
}

@test "issue_watcher_cron: the tab is labelled with the issue number" {
    _run_tick
    assert_success
    _assert_logged "--label #11"
}

@test "issue_watcher_cron: the tab opens on the issue's worktree, not the checkout" {
    _run_tick
    assert_success
    _assert_logged "--cwd ${_WORK_DIR}/dotfiles-issue-11-1"
}

@test "issue_watcher_cron: an existing workspace with the repo label is reused" {
    _run_tick "HERDR_WORKSPACE_EXISTS=1"
    assert_success
    _assert_logged "tab create --workspace ws-existing"
    _refute_logged "workspace create"
}

@test "issue_watcher_cron: a missing workspace is created against the checkout" {
    _run_tick
    assert_success
    _assert_logged "workspace create --cwd ${_REPO_DIR} --label dotfiles --no-focus"
}

@test "issue_watcher_cron: the tick reports how many issues it dispatched" {
    _run_tick
    assert_success
    assert_output --partial "1 issue(s) dispatched"
}

# ---------------------------------------------------------------------------
# Filters (issue #1440 verification list)
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: an issue labelled wontfix is not dispatched" {
    _issues_with_labels 11 wontfix
    _run_tick
    assert_success
    assert_output --partial "excluded label"
    _refute_logged "gwt spawn"
    _refute_logged "agent prompt"
}

@test "issue_watcher_cron: an issue labelled 보류 is not dispatched" {
    _issues_with_labels 11 보류
    _run_tick
    assert_success
    _refute_logged "gwt spawn"
}

@test "issue_watcher_cron: an issue labelled not-implement is not dispatched" {
    _issues_with_labels 11 not-implement
    _run_tick
    assert_success
    _refute_logged "gwt spawn"
}

@test "issue_watcher_cron: an excluded label among several still parks the issue" {
    _issues_with_labels 11 refactor wontfix
    _run_tick
    assert_success
    _refute_logged "gwt spawn"
}

@test "issue_watcher_cron: a label that merely starts with an excluded one is not excluded" {
    _issues_with_labels 11 wontfix-later
    _run_tick
    assert_success
    _assert_logged "gwt spawn --wt-name issue-11"
}

@test "issue_watcher_cron: a label containing a space is matched exactly" {
    _issues_with_labels 11 "on hold"
    _run_tick "IW_EXCLUDE_LABELS=on hold"
    assert_success
    _refute_logged "gwt spawn"
}

@test "issue_watcher_cron: an issue with an OPEN blockedBy is skipped" {
    _run_tick "GH_BLOCKED_BY=11"
    assert_success
    assert_output --partial "blocked by open"
    _refute_logged "gwt spawn"
}

@test "issue_watcher_cron: the same issue dispatches once its blocker closes" {
    _run_tick
    assert_success
    _assert_logged "gwt spawn --wt-name issue-11"
}

@test "issue_watcher_cron: a failing blockedBy query fails open" {
    _run_tick "GH_GRAPHQL_FAIL=1"
    assert_success
    assert_output --partial "fail-open"
    _assert_logged "gwt spawn --wt-name issue-11"
}

@test "issue_watcher_cron: an issue outside the watch list is never touched" {
    _set_issues '[{"number":77,"repository":{"nameWithOwner":"other/elsewhere"},"labels":[]}]'
    _run_tick
    assert_success
    assert_output --partial "No dispatchable issue"
    _refute_logged "gwt spawn"
}

@test "issue_watcher_cron: an issue that already has a worktree is skipped" {
    _add_worktree 11
    _run_tick
    assert_success
    assert_output --partial "worktree already exists"
    _refute_logged "gwt spawn"
}

@test "issue_watcher_cron: a watched repo whose path is gone is skipped with a warning" {
    _write_watch_file '[{"repo":"acme/dotfiles","path":"'"${_WORK_DIR}"'/gone","host":"github.com"}]'
    _run_tick
    assert_success
    assert_output --partial "missing path"
    _refute_logged "gwt spawn"
}

@test "issue_watcher_cron: a watch entry without a path is ignored" {
    _write_watch_file '[{"repo":"acme/dotfiles","host":"github.com"}]'
    _run_tick
    assert_success
    assert_output --partial "No dispatchable issue"
}

@test "issue_watcher_cron: the watch list also accepts the {repos:[...]} shape" {
    _write_watch_file '{"repos":[{"repo":"acme/dotfiles","path":"'"${_REPO_DIR}"'"}]}'
    _run_tick
    assert_success
    _assert_logged "gwt spawn --wt-name issue-11"
}

@test "issue_watcher_cron: a watch entry without a host defaults to github.com" {
    _write_watch_file '[{"repo":"acme/dotfiles","path":"'"${_REPO_DIR}"'"}]'
    _run_tick
    assert_success
    _assert_logged "gwt spawn --wt-name issue-11"
}

@test "issue_watcher_cron: at most three issues are dispatched per cycle" {
    _set_issues '[
      {"number":11,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":13,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":14,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}
    ]'
    _run_tick
    assert_success
    assert_output --partial "3 issue(s) dispatched"
    [ "$(_log_count 'gwt spawn')" -eq 3 ]
    _refute_logged "gwt spawn --wt-name issue-14"
}

@test "issue_watcher_cron: a failing issue search leaves the tick a no-op" {
    _run_tick "GH_SEARCH_FAIL=1"
    assert_success
    assert_output --partial "No dispatchable issue"
    _refute_logged "gwt spawn"
}

# ---------------------------------------------------------------------------
# PR #1447 review regressions
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: the search is scoped to the watched repos" {
    _run_tick
    assert_success
    # Without repo: qualifiers --limit truncates every assigned issue on the
    # account and a watched repo can starve outside the window.
    _assert_logged "search issues repo:acme/dotfiles"
}

@test "issue_watcher_cron: each watched repo contributes its own repo: qualifier" {
    mkdir -p "${_WORK_DIR}/other"
    git -C "${_WORK_DIR}/other" init -q
    _write_watch_file '[{"repo":"acme/dotfiles","path":"'"${_REPO_DIR}"'"},{"repo":"acme/other","path":"'"${_WORK_DIR}"'/other"}]'
    _run_tick
    assert_success
    _assert_logged "repo:acme/dotfiles repo:acme/other"
}

@test "issue_watcher_cron: the search result order is pinned, not relevance-ranked" {
    _run_tick
    assert_success
    _assert_logged "--sort updated --order desc"
}

@test "issue_watcher_cron: a stdin-consuming child cannot truncate the candidate loop" {
    # The blockedBy query runs inside the candidate loop and drains stdin. On
    # plain stdin that eats the remaining search results and the cycle silently
    # dispatches one issue instead of three.
    _set_issues '[
      {"number":11,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":13,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}
    ]'
    _run_tick
    assert_success
    assert_output --partial "3 issue(s) dispatched"
}

@test "issue_watcher_cron: a stdin-consuming child cannot truncate the dispatch loop" {
    _set_issues '[
      {"number":11,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":13,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}
    ]'
    _run_tick
    assert_success
    [ "$(_log_count 'agent prompt')" -eq 3 ]
}

@test "issue_watcher_cron: the agent name carries the repo, not just the number" {
    _run_tick
    assert_success
    # Two watched repos both having an issue #11 would otherwise share one herdr
    # agent name, and the second prompt would land on the first one's pane.
    _assert_logged "agent start iw-acme-dotfiles-11"
    _refute_logged "agent start iw-11 "
}

@test "issue_watcher_cron: repos with colliding directory names get distinct workspaces" {
    mkdir -p "${_WORK_DIR}/nest/dotfiles"
    git -C "${_WORK_DIR}/nest/dotfiles" init -q
    _write_watch_file '[{"repo":"acme/dotfiles","path":"'"${_REPO_DIR}"'"},{"repo":"other/dotfiles","path":"'"${_WORK_DIR}"'/nest/dotfiles"}]'
    _run_tick
    assert_success
    # Both leaf directories are "dotfiles", so the basename label would merge
    # two repos onto one workspace — the slug disambiguates.
    _assert_logged "--label acme/dotfiles"
    _refute_logged "--label dotfiles "
}

@test "issue_watcher_cron: a unique directory name still labels the workspace plainly" {
    _run_tick
    assert_success
    _assert_logged "workspace create --cwd ${_REPO_DIR} --label dotfiles --no-focus"
}

@test "issue_watcher_cron: a cold agent is polled for idle before it is prompted" {
    _run_tick
    assert_success
    # `herdr agent start` returning does not prove the key-input loop accepts
    # Enter yet (#1399) — prompting a cold pane drops the first keystroke.
    run grep -n "agent get iw-acme-dotfiles-11" "${_LOG}"
    assert_success
    _agent_get_line=$(grep -n "agent get iw-acme-dotfiles-11" "${_LOG}" | head -1 | cut -d: -f1)
    _prompt_line=$(grep -n "agent prompt iw-acme-dotfiles-11" "${_LOG}" | head -1 | cut -d: -f1)
    [ "${_agent_get_line}" -lt "${_prompt_line}" ]
}

@test "issue_watcher_cron: the dedup check picks the highest worktree index" {
    _add_worktree 11
    git -C "${_REPO_DIR}" worktree add -q -b "wt/issue-11/2" "${_WORK_DIR}/dotfiles-issue-11-2" HEAD
    _run_tick
    assert_success
    assert_output --partial "worktree already exists"
}

@test "issue_watcher_cron: a stale attempt error code cannot book a quota strike" {
    # Attempt 1 stalls (quota-shaped); attempts 2-3 die at tab create, which is
    # not quota-shaped. The gate must read the *last* attempt, not the first.
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle" "HERDR_TAB_FAIL_AFTER=1"
    assert_failure
    assert_output --partial "not a token-limit signature"
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: --dry-run does not take the tick lock" {
    _hold_lock
    _run_tick -- --dry-run
    assert_success
    assert_output --partial "acme/dotfiles#11"
    refute_output --partial "already running"
}

@test "issue_watcher_cron: --dry-run leaves an expired gate file on disk" {
    mkdir -p "${_STATE_DIR}"
    printf '{ "strikes": "0", "backoff_until": "%s" }\n' "$(($(date +%s) - 60))" >"${_LIMIT_FILE}"
    _run_tick -- --dry-run
    assert_success
    # Evaluating the gate clears an expired file — a state change in the mode
    # documented as changing nothing.
    [ -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: --dry-run reports even while the gate is closed" {
    mkdir -p "${_STATE_DIR}"
    printf '{ "strikes": "0", "backoff_until": "%s" }\n' "$(($(date +%s) + 900))" >"${_LIMIT_FILE}"
    _run_tick -- --dry-run
    assert_success
    assert_output --partial "acme/dotfiles#11"
}

# ---------------------------------------------------------------------------
# Read-only on issues
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: the tick never writes to an issue" {
    _run_tick
    assert_success
    # The gh stub refuses everything but the two read calls, so a write would
    # already have failed the dispatch. Assert on the log too, so the reason a
    # future regression fails is legible.
    _refute_logged "gh issue comment"
    _refute_logged "gh issue edit"
    _refute_logged "gh issue close"
    run grep -E '^gh (issue|api graphql -f query=mutation)' "${_LOG}"
    assert_failure
}

@test "issue_watcher_cron: only search and graphql reach gh" {
    _run_tick
    assert_success
    run grep -cE '^gh (search issues|api graphql)' "${_LOG}"
    assert_success
    run grep -vE '^gh (search issues|api graphql)' "${_LOG}"
    refute_output --partial "gh "
}

# ---------------------------------------------------------------------------
# Retry + cleanup
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: a failed dispatch is retried up to three times" {
    _run_tick "HERDR_PROMPT_MODE=fail"
    assert_failure
    [ "$(_log_count 'gwt spawn')" -eq 3 ]
    assert_output --partial "Giving up on acme/dotfiles#11 after 3 attempts"
}

@test "issue_watcher_cron: each failed attempt removes its worktree before retrying" {
    _run_tick "HERDR_PROMPT_MODE=fail"
    assert_failure
    [ "$(_log_count 'gwt remove')" -eq 3 ]
    # Nothing may survive: a leftover worktree is what the dedup check keys on,
    # so it would retire the issue without it ever having been worked.
    run git -C "${_REPO_DIR}" worktree list --porcelain
    refute_output --partial "wt/issue-11/"
}

@test "issue_watcher_cron: a spawn that fails after creating the worktree still cleans up" {
    _run_tick "GWT_SPAWN_MODE=fail-after"
    assert_failure
    run git -C "${_REPO_DIR}" worktree list --porcelain
    refute_output --partial "wt/issue-11/"
}

@test "issue_watcher_cron: a dispatch that succeeds on the second attempt keeps its worktree" {
    _run_tick "HERDR_PROMPT_FAIL_TIMES=2" "HERDR_AGENT_STATUS=idle"
    assert_success
    run git -C "${_REPO_DIR}" worktree list --porcelain
    assert_output --partial "wt/issue-11/"
}

@test "issue_watcher_cron: a tab-create failure is retried and then given up on" {
    _run_tick "HERDR_TAB_FAIL=1"
    assert_failure
    [ "$(_log_count 'tab create')" -eq 3 ]
    assert_output --partial "herdr tab create failed"
}

@test "issue_watcher_cron: an agent-start failure closes the tab it opened" {
    _run_tick "HERDR_START_FAIL=1"
    assert_failure
    _assert_logged "tab close ws-test-1:t9"
}

@test "issue_watcher_cron: a spawn failure that never resolves gives up without a prompt" {
    _run_tick "GWT_SPAWN_MODE=fail"
    assert_failure
    assert_output --partial "Worktree spawn failed"
    _refute_logged "agent prompt"
}

@test "issue_watcher_cron: a spawn that fails once then succeeds still dispatches" {
    _run_tick "GWT_SPAWN_FAIL_TIMES=1"
    assert_success
    _assert_logged "agent prompt iw-acme-dotfiles-11 /gh-issue-flow 11"
}

@test "issue_watcher_cron: agent_prompt_stalled is retried once and then succeeds" {
    _run_tick "HERDR_PROMPT_MODE=stall-once"
    assert_success
    [ "$(_log_count 'agent prompt')" -eq 2 ]
    assert_output --partial "retrying once"
}

@test "issue_watcher_cron: a non-stall prompt failure is not retried within the attempt" {
    _run_tick "HERDR_PROMPT_MODE=fail"
    assert_failure
    # Three attempts, one prompt each — never two prompts inside one attempt.
    [ "$(_log_count 'agent prompt')" -eq 3 ]
}

@test "issue_watcher_cron: agent_prompt_stalled retry is skipped when the agent is already working" {
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=working"
    assert_success
    [ "$(_log_count 'agent prompt')" -eq 1 ]
    assert_output --partial "treating as delivered"
}

# ---------------------------------------------------------------------------
# --dry-run
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: --dry-run lists the candidates it would dispatch" {
    _run_tick -- --dry-run
    assert_success
    assert_output --partial "Dry run"
    assert_output --partial "acme/dotfiles#11"
}

@test "issue_watcher_cron: --dry-run creates no worktree and sends no prompt" {
    _run_tick -- --dry-run
    assert_success
    _refute_logged "gwt spawn"
    _refute_logged "agent prompt"
    _refute_logged "tab create"
    run git -C "${_REPO_DIR}" worktree list --porcelain
    refute_output --partial "wt/issue-11/"
}

@test "issue_watcher_cron: --dry-run applies the same filters as a real tick" {
    _issues_with_labels 11 wontfix
    _run_tick -- --dry-run
    assert_success
    assert_output --partial "No dispatchable issue"
}

@test "issue_watcher_cron: --dry-run works without herdr installed" {
    rm -f "${_BIN_DIR}/herdr"
    _run_tick "PATH=$(_path_without herdr)" -- --dry-run
    assert_success
    assert_output --partial "acme/dotfiles#11"
}

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: missing herdr binary fails with a clear error" {
    rm -f "${_BIN_DIR}/herdr"
    _run_tick "PATH=$(_path_without herdr)"
    assert_failure
    assert_output --partial "herdr not found"
}

@test "issue_watcher_cron: a missing watch list fails with a clear error" {
    _run_tick "IW_WATCHED_REPOS=${_WORK_DIR}/nope.json"
    assert_failure
    assert_output --partial "Watch list not found"
}

@test "issue_watcher_cron: --cwd pointing nowhere fails" {
    _run_tick -- --cwd "${_WORK_DIR}/nope"
    assert_failure
    assert_output --partial "Cannot cd"
}

@test "issue_watcher_cron: a relative watch-list path resolves against --cwd" {
    _write_watch_file '[{"repo":"acme/dotfiles","path":"dotfiles","host":"github.com"}]'
    _run_tick -- --cwd "${_WORK_DIR}"
    assert_success
    _assert_logged "gwt spawn --wt-name issue-11"
}

# ---------------------------------------------------------------------------
# Locking
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: a tick is skipped while another instance holds the lock" {
    _hold_lock
    _run_tick
    assert_success
    assert_output --partial "already running"
    _refute_logged "gwt spawn"
}

@test "issue_watcher_cron: the lock is released so the next tick runs" {
    _run_tick
    assert_success
    _add_worktree 12
    _set_issues '[{"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}]'
    _run_tick
    assert_success
    assert_output --partial "worktree already exists"
}

@test "issue_watcher_cron: missing flock degrades to a warning, not a failure" {
    _run_tick "PATH=$(_path_without flock)"
    assert_success
    assert_output --partial "without single-instance protection"
    _assert_logged "agent prompt iw-acme-dotfiles-11"
}

# ---------------------------------------------------------------------------
# CLAUDE_CONFIG_DIR routing (issue #1393)
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: dispatch routes CLAUDE_CONFIG_DIR to the default account" {
    _run_tick
    assert_success
    _assert_logged "--env CLAUDE_CONFIG_DIR=${HOME}/.claude-personal"
}

@test "issue_watcher_cron: CLAUDE_DEFAULT_ACCOUNT selects the account dir" {
    mkdir -p "${HOME}/.claude-work"
    _run_tick "CLAUDE_ENABLED_ACCOUNTS=personal work" "CLAUDE_DEFAULT_ACCOUNT=work"
    assert_success
    _assert_logged "--env CLAUDE_CONFIG_DIR=${HOME}/.claude-work"
}

@test "issue_watcher_cron: internal setup mode uses ~/.claude without account resolution" {
    printf 'internal\n' >"${HOME}/.dotfiles-setup-mode"
    mkdir -p "${HOME}/.claude"
    _run_tick "CLAUDE_ENABLED_ACCOUNTS="
    assert_success
    _assert_logged "--env CLAUDE_CONFIG_DIR=${HOME}/.claude"
}

@test "issue_watcher_cron: missing account directory fails fast before opening a tab" {
    rm -rf "${HOME}/.claude-personal"
    _run_tick
    assert_failure
    assert_output --partial "Claude account directory missing"
    _refute_logged "tab create"
}

@test "issue_watcher_cron: unknown account name fails fast with the available list" {
    _run_tick "CLAUDE_DEFAULT_ACCOUNT=ghost"
    assert_failure
    assert_output --partial "Unknown claude account: ghost"
}

@test "issue_watcher_cron: falls back to plain ~/.claude when no multi-account setup exists" {
    mkdir -p "${HOME}/.claude"
    _run_tick -u CLAUDE_ENABLED_ACCOUNTS -u CLAUDE_DEFAULT_ACCOUNT
    assert_success
    _assert_logged "--env CLAUDE_CONFIG_DIR=${HOME}/.claude"
}

@test "issue_watcher_cron: the single-account fallback still fails fast without ~/.claude" {
    rm -rf "${HOME}/.claude" "${HOME}/.claude-personal"
    _run_tick -u CLAUDE_ENABLED_ACCOUNTS -u CLAUDE_DEFAULT_ACCOUNT
    assert_failure
}

@test "issue_watcher_cron: the account dir is resolved once for the whole cycle" {
    _set_issues '[
      {"number":11,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}
    ]'
    _run_tick
    assert_success
    # Two dispatches, both carrying the same routing.
    [ "$(_log_count '--env CLAUDE_CONFIG_DIR=')" -ge 2 ]
    _refute_logged "CLAUDE_CONFIG_DIR=${HOME}/.claude "
}

@test "issue_watcher_cron: unset HOME and XDG_STATE_HOME does not trip set -u" {
    local _tmp="${_WORK_DIR}/nohome-tmp"
    mkdir -p "${_tmp}"
    # Open-coded rather than via _run_tick: this test needs XDG_STATE_HOME
    # *absent*, and the helper always assigns it — `env` applies assignments
    # after its own -u options, so -u could not win.
    run env -u HOME -u XDG_STATE_HOME \
        "PATH=${_BIN_DIR}:${PATH}" \
        "CALL_LOG=${_LOG}" \
        "GH_ISSUES_FILE=${_WORK_DIR}/issues.json" \
        "IW_WATCHED_REPOS=${_WATCH_FILE}" \
        "TMPDIR=${_tmp}" \
        "IW_IDLE_POLL_SLEEP=0" \
        bash "${SCRIPT}"
    refute_output --partial "unbound variable"
}

# ---------------------------------------------------------------------------
# Rate-limit gate (issue #1436)
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: a healthy dispatch leaves no rate-limit state behind" {
    _run_tick
    assert_success
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: a stalled dispatch records a strike and still exits 1" {
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle"
    assert_failure
    run cat "${_LIMIT_FILE}"
    assert_output --partial '"strikes": "1"'
    assert_output --partial '"backoff_until": "0"'
}

@test "issue_watcher_cron: two consecutive stalled dispatches close the gate" {
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle"
    assert_failure
    _add_worktree 11
    _set_issues '[{"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}]'
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle"
    assert_failure
    assert_output --partial "Rate-limit gate closed for 30m"
    run cat "${_LIMIT_FILE}"
    assert_output --partial '"strikes": "0"'
    refute_output --partial '"backoff_until": "0"'
}

@test "issue_watcher_cron: a closed gate holds the tick without dispatching" {
    mkdir -p "${_STATE_DIR}"
    printf '{ "strikes": "0", "backoff_until": "%s" }\n' "$(($(date +%s) + 900))" >"${_LIMIT_FILE}"
    _run_tick
    assert_success
    assert_output --partial "Rate-limit gate closed"
    _refute_logged "agent prompt"
}

@test "issue_watcher_cron: a held tick creates no worktree" {
    mkdir -p "${_STATE_DIR}"
    printf '{ "strikes": "0", "backoff_until": "%s" }\n' "$(($(date +%s) + 900))" >"${_LIMIT_FILE}"
    _run_tick
    assert_success
    _refute_logged "gwt spawn"
    run git -C "${_REPO_DIR}" worktree list --porcelain
    refute_output --partial "wt/issue-11/"
}

@test "issue_watcher_cron: a held tick leaves the gate deadline untouched" {
    mkdir -p "${_STATE_DIR}"
    local _until=$(($(date +%s) + 900))
    printf '{ "strikes": "0", "backoff_until": "%s" }\n' "${_until}" >"${_LIMIT_FILE}"
    _run_tick
    assert_success
    run cat "${_LIMIT_FILE}"
    assert_output --partial "\"backoff_until\": \"${_until}\""
}

@test "issue_watcher_cron: an expired backoff reopens the gate and dispatches" {
    mkdir -p "${_STATE_DIR}"
    printf '{ "strikes": "0", "backoff_until": "%s" }\n' "$(($(date +%s) - 60))" >"${_LIMIT_FILE}"
    _run_tick
    assert_success
    assert_output --partial "Rate-limit gate reopened"
    _assert_logged "agent prompt iw-acme-dotfiles-11"
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: an out-of-range future deadline is treated as expired" {
    mkdir -p "${_STATE_DIR}"
    printf '{ "strikes": "0", "backoff_until": "%s" }\n' "$(($(date +%s) + 999999))" >"${_LIMIT_FILE}"
    _run_tick
    assert_success
    assert_output --partial "Rate-limit gate reopened"
}

@test "issue_watcher_cron: a corrupt gate file fails open" {
    mkdir -p "${_STATE_DIR}"
    printf 'not json at all\n' >"${_LIMIT_FILE}"
    _run_tick
    assert_success
    _assert_logged "agent prompt iw-acme-dotfiles-11"
}

@test "issue_watcher_cron: a non-numeric deadline fails open" {
    mkdir -p "${_STATE_DIR}"
    printf '{ "strikes": "0", "backoff_until": "soon" }\n' >"${_LIMIT_FILE}"
    _run_tick
    assert_success
    assert_output --partial "dispatching anyway"
    _assert_logged "agent prompt iw-acme-dotfiles-11"
}

@test "issue_watcher_cron: a successful dispatch clears accumulated strikes" {
    mkdir -p "${_STATE_DIR}"
    printf '{ "strikes": "1", "backoff_until": "0" }\n' >"${_LIMIT_FILE}"
    _run_tick
    assert_success
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: a stalled dispatch with the agent working earns no strike" {
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=working"
    assert_success
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: a non-quota dispatch failure earns no strike" {
    _run_tick "HERDR_PROMPT_MODE=fail"
    assert_failure
    assert_output --partial "not a token-limit signature"
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: a non-quota failure leaves an existing strike untouched" {
    mkdir -p "${_STATE_DIR}"
    printf '{ "strikes": "1", "backoff_until": "0" }\n' >"${_LIMIT_FILE}"
    _run_tick "HERDR_PROMPT_MODE=fail"
    assert_failure
    run cat "${_LIMIT_FILE}"
    assert_output --partial '"strikes": "1"'
}

@test "issue_watcher_cron: a gate that shuts mid-cycle stops the remaining issues" {
    _set_issues '[
      {"number":11,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":13,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}
    ]'
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle"
    assert_failure
    # Two strikes shut the gate, so the third issue is never attempted.
    _refute_logged "gwt spawn --wt-name issue-13"
}

@test "issue_watcher_cron: a state dir with no gate file ticks exactly as before" {
    mkdir -p "${_STATE_DIR}"
    _run_tick
    assert_success
    _assert_logged "agent prompt iw-acme-dotfiles-11"
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: an unwritable state dir warns but does not change the exit code" {
    mkdir -p "${_STATE_DIR}"
    chmod 500 "${_STATE_DIR}"
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle"
    assert_failure
    assert_output --partial "rate-limit gate will not survive this tick"
    chmod 700 "${_STATE_DIR}"
}
