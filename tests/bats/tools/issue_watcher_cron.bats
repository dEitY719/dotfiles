#!/usr/bin/env bats
# tests/bats/tools/issue_watcher_cron.bats
# Tests for issue_watcher_cron.sh — the issue-watcher tick
# (issues #1389, #1436, #1440, #1453).
#
# Since #1440 the tick does the watching and dispatching itself, so the suite
# covers the whole pipeline rather than a single dispatcher prompt. Three PATH
# stubs stand in for the outside world and log every invocation to ${_LOG} so
# the tests can assert on *which* calls were made:
#
#   gh     `search issues`, `pr list` (the already-handled signal), `issue view`
#          (the collectable signal) and `api graphql` (blockedBy) — all canned
#          and steerable per test. Every other subcommand is logged and refused:
#          the tick must never write to an issue.
#   herdr  workspace/tab/agent plus `agent list` (the running-now signal), with
#          canned JSON matching the shapes measured on a live herdr server.
#   gwt    real `git worktree` calls against a real fixture repo, so worktree
#          creation and collection are exercised for real rather than mocked.
#
# Since #1453 a worktree's existence decides nothing (NF-1). The three signals
# it used to stand in for are stubbed separately: `herdr agent list` says what
# is running, `gh pr list` says what is already handled, and `gh issue view`
# says what may be collected.

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

# A real git repo — the tick creates and collects real worktrees, and mocking
# `git worktree` away would test the mock, not the behavior. Defaults to the
# main checkout; pass a path for a second watched repo.
_make_repo() {
    local _dir="${1:-${_REPO_DIR}}"
    mkdir -p "${_dir}"
    git -C "${_dir}" init -q
    git -C "${_dir}" config user.email "test@example.com"
    git -C "${_dir}" config user.name "test"
    printf 'seed\n' >"${_dir}/README.md"
    git -C "${_dir}" add -A
    git -C "${_dir}" commit -qm "seed"
}

# Register an existing worktree for issue <1>, the way a previous cycle would
# have left it.
_add_worktree() {
    git -C "${_REPO_DIR}" worktree add -q -b "wt/issue-$1/1" \
        "$(_worktree_path "$1")" HEAD
}

_write_watch_file() {
    printf '%s\n' "$1" >"${_WATCH_FILE}"
}

# The `gh search issues` result set for this test.
_set_issues() {
    printf '%s\n' "$1" >"${_WORK_DIR}/issues.json"
}

# The open-PR set `gh pr list` answers with, as a JSON object keyed by repo.
_set_open_prs() {
    printf '%s\n' "$1" >"${_WORK_DIR}/prs.json"
}

# The worktree path `_add_worktree <n>` creates — also what a live agent pane
# working that issue reports as its cwd.
_worktree_path() {
    printf '%s/dotfiles-issue-%s-1' "${_WORK_DIR}" "$1"
}

# A live herdr agent pane sitting in each given worktree path. This is the
# whole "is it running" signal: `herdr agent list` has no agent-name field, so
# the tick recognises its own panes by the worktree they were opened on.
_set_live_agents() {
    local _json="" _sep="" _p
    for _p in "$@"; do
        _json="${_json}${_sep}{\"agent\":\"claude\",\"agent_status\":\"working\",\"cwd\":\"${_p}\",\"foreground_cwd\":\"${_p}\",\"pane_id\":\"wV:p1\"}"
        _sep=","
    done
    printf '{"id":"cli:agent:list","result":{"agents":[%s]}}\n' "${_json}" \
        >"${_WORK_DIR}/agents.json"
}

# A pane whose shell has walked away from where it was opened: `cwd` still says
# the worktree, `foreground_cwd` says $2.
_set_live_agent_moved() {
    printf '{"id":"cli:agent:list","result":{"agents":[{"agent":"claude","agent_status":"working","cwd":"%s","foreground_cwd":"%s","pane_id":"wV:p1"}]}}\n' \
        "$1" "$2" >"${_WORK_DIR}/agents.json"
}

# A pane that reports only `foreground_cwd` — inside the worktree, not its root.
_set_live_agent_subdir() {
    printf '{"id":"cli:agent:list","result":{"agents":[{"agent":"claude","agent_status":"working","foreground_cwd":"%s","pane_id":"wV:p1"}]}}\n' \
        "$1" >"${_WORK_DIR}/agents.json"
}

# N open PRs in <1>, none of which closes any watched issue — used to fill the
# `gh pr list` window so truncation can be observed.
_set_filler_prs() {
    local _repo="$1" _n="$2" _i=1 _json="" _sep=""
    while [ "${_i}" -le "${_n}" ]; do
        _json="${_json}${_sep}{\"number\":${_i},\"headRefName\":\"filler/${_i}\",\"body\":\"nothing\"}"
        _sep=","
        _i=$((_i + 1))
    done
    printf '{"%s":[%s]}\n' "${_repo}" "${_json}" >"${_WORK_DIR}/prs.json"
}

# The given issues are *running*: a worktree each, with a live pane sitting in
# it. Both halves are required — that pairing is the running-now signal — so
# they are set together rather than restated at every concurrency test.
_set_running() {
    local _paths=() _n
    for _n in "$@"; do
        _add_worktree "${_n}"
        _paths+=("$(_worktree_path "${_n}")")
    done
    _set_live_agents "${_paths[@]}"
}

# The rate-limit gate state file: _set_limit_state <strikes> <backoff_until>.
# Both fields are written as JSON *strings* because _iw_limit_write does, and
# the quoting is a back-compat guarantee rather than an accident — so the
# on-disk schema is spelled out here once instead of at every gate test.
_set_limit_state() {
    mkdir -p "${_STATE_DIR}"
    printf '{ "strikes": "%s", "backoff_until": "%s" }\n' "$1" "$2" >"${_LIMIT_FILE}"
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

# gh: only the four read calls are answered. Anything else is logged and fails
# — the tick is read-only on issues by contract, and this is what makes "no
# comment, label or assignee change" a test rather than a claim.
#
#   GH_SEARCH_FAIL=1      `search issues` errors
#   GH_BLOCKED_BY         issue numbers whose blockedBy answer carries an OPEN
#                         blocker, space-separated (default: none)
#   GH_GRAPHQL_FAIL=1     `api graphql` errors (fail-open path)
#   GH_PRS_FILE           JSON object, repo -> open-PR array (default: none)
#   GH_PR_LIST_FAIL=1     `pr list` errors (fail-closed path, D-6)
#   GH_CLOSED_ISSUES      issue numbers `issue view` reports CLOSED for
#   GH_ISSUE_VIEW_FAIL=1  `issue view` errors (worktree is left in place)
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
"pr list")
    [ "${GH_PR_LIST_FAIL:-0}" = "1" ] && exit 1
    _repo=""
    _prev=""
    for _a in "$@"; do
        [ "${_prev}" = "--repo" ] && _repo="${_a}"
        _prev="${_a}"
    done
    if [ -f "${GH_PRS_FILE:-}" ]; then
        jq -c --arg r "${_repo}" '.[$r] // []' "${GH_PRS_FILE}"
    else
        printf '%s\n' '[]'
    fi
    exit 0
    ;;
"issue view")
    # Read-only, like the two above: the cleanup step asks whether an issue is
    # closed before it collects that issue's worktree.
    [ "${GH_ISSUE_VIEW_FAIL:-0}" = "1" ] && exit 1
    for _c in ${GH_CLOSED_ISSUES:-}; do
        if [ "${_c}" = "$3" ]; then
            printf 'CLOSED\n'
            exit 0
        fi
    done
    printf 'OPEN\n'
    exit 0
    ;;
"api graphql")
    # The real `gh api` reads stdin. Draining it here is what makes the
    # candidate-loop fd-3 test meaningful: on plain stdin this swallows the
    # remaining search results (PR #1447 agy review).
    #
    # Skipped when stdin is a terminal (PR #1469 agy review). Running the suite
    # straight from an interactive shell leaves the tick's stdin on the tty, and
    # an unconditional `cat` then blocks on the keyboard forever — the run looks
    # hung with no failing test to point at. A tty is never the fd-3 case this
    # drain exists to model: the candidate list always arrives on a pipe or a
    # heredoc, so guarding it costs the test nothing.
    [ -t 0 ] || cat >/dev/null 2>&1 || true
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
#   HERDR_AGENTS_FILE         canned `agent list` JSON (default: no agents)
#   HERDR_AGENT_LIST_FAIL=1   `agent list` errors — the tick must hold
#   HERDR_WORKSPACE_EXISTS=1  `workspace list` already carries the repo label
#   HERDR_TAB_FAIL=1          `tab create` errors
#   HERDR_TAB_FAIL_AFTER=N    the first N `tab create` calls succeed, the rest
#                             error — lets one issue fail two different ways
#                             across its retry attempts
#   HERDR_START_FAIL=1        `agent start` errors
#   HERDR_AGENT_STATUS        status reported by `agent get` (default: idle)
#   HERDR_AGENT_GET_FAIL=1    `agent get` returns agent_not_found and exits 1
#   HERDR_PROMPT_MODE         `agent prompt` behaviour (default: always ok)
#                               stall       every call stalled
#                               fail        every call a non-stall error
#   HERDR_PROMPT_FAIL_TIMES   first N `agent prompt` calls stall, then ok
#
# Stall recovery (issue #1443). A stall leaves the command typed but unsent, so
# the tick presses Enter rather than retyping; `state_change_seq` is what proves
# the keystroke landed.
#
#   HERDR_SENDKEYS_MODE       `agent send-keys` behaviour
#                               nobump  (default) exits 0, seq unchanged — the
#                                       input loop is still not listening, which
#                                       is what every pre-#1443 stall test means
#                                       by "stalled", so their meaning is
#                                       preserved verbatim
#                               ok      exits 0 and bumps state_change_seq
#                               fail    exits 1 with agent_not_found — herdr
#                                       cannot reach the target at all
#   HERDR_SEQ_MODE=absent     `agent get` omits state_change_seq entirely (the
#                             baseline-read blip the status fallback covers)
#   HERDR_STATUS_AFTER_SENDKEYS  once any `send-keys` has run, `agent get`
#                             reports this status instead of HERDR_AGENT_STATUS
#
# Rate-limit gate (issue #1444). The gate judges what an agent does *after* its
# prompt lands, so the stub has to be able to answer differently before and
# after that point, and per agent — one tick can dispatch several.
#
#   HERDR_STATUS_AFTER_PROMPT       status `agent get` reports for an agent
#                                   that has already been prompted
#   HERDR_STATUS_AFTER_PROMPT_GETS  apply it only to that agent's first N
#                                   post-prompt `agent get` calls, then fall
#                                   back to HERDR_AGENT_STATUS — this is how an
#                                   agent that reaches `working` and then drops
#                                   out of it inside the window is staged
#   HERDR_WORKING_AGENTS            space-separated agent names that report
#                                   `working` once prompted, whatever the
#                                   settings above say
#   HERDR_READ_MODE=missing         `agent read` answers agent_not_found (the
#                                   evidence capture has nothing to log)
#   HERDR_GET_FAIL_AFTER_PROMPT=1   `agent get` errors once that agent has been
#                                   prompted — herdr unreachable during the
#                                   observation window only, leaving dispatch
#                                   itself untouched
#   HERDR_GET_FAIL_AFTER_PROMPT_SKIP=N  let that agent's first N post-prompt
#                                   `agent get` calls answer normally, then
#                                   error — stages "readable early in the
#                                   window, unreadable at the poll that decides"
#
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
"agent list")
    if [ "${HERDR_AGENT_LIST_FAIL:-0}" = "1" ]; then
        printf '%s\n' '{"error":{"code":"internal","message":"no server"},"id":"cli:agent:list"}'
        exit 1
    fi
    if [ -f "${HERDR_AGENTS_FILE:-}" ]; then
        cat "${HERDR_AGENTS_FILE}"
    else
        printf '%s\n' '{"id":"cli:agent:list","result":{"agents":[]}}'
    fi
    ;;
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
    _status="${HERDR_AGENT_STATUS:-idle}"
    if [ -f "${CALL_LOG}.prompt.$3" ]; then
        if [ "${HERDR_GET_FAIL_AFTER_PROMPT:-0}" = "1" ]; then
            _n=$(_bump "${CALL_LOG}.postget.$3")
            if [ "${_n}" -gt "${HERDR_GET_FAIL_AFTER_PROMPT_SKIP:-0}" ]; then
                printf '%s\n' '{"error":{"code":"agent_not_found","message":"agent target not found"},"id":"cli:agent:get"}'
                exit 1
            fi
        fi
        if [ -n "${HERDR_STATUS_AFTER_PROMPT:-}" ]; then
            _n=$(_bump "${CALL_LOG}.postget.$3")
            if [ -z "${HERDR_STATUS_AFTER_PROMPT_GETS:-}" ] ||
                [ "${_n}" -le "${HERDR_STATUS_AFTER_PROMPT_GETS}" ]; then
                _status="${HERDR_STATUS_AFTER_PROMPT}"
            fi
        fi
        for _w in ${HERDR_WORKING_AGENTS:-}; do
            [ "${_w}" = "$3" ] && _status="working"
        done
    fi
    if [ -n "${HERDR_STATUS_AFTER_SENDKEYS:-}" ] && [ -f "${CALL_LOG}.sendkeys" ]; then
        _status="${HERDR_STATUS_AFTER_SENDKEYS}"
    fi
    if [ "${HERDR_SEQ_MODE:-ok}" = "absent" ]; then
        printf '{"id":"cli:agent:get","result":{"agent":{"agent_status":"%s"}}}\n' "${_status}"
    else
        _seq=$(cat "${CALL_LOG}.seq" 2>/dev/null || printf 0)
        printf '{"id":"cli:agent:get","result":{"agent":{"agent_status":"%s","state_change_seq":%s}}}\n' \
            "${_status}" "${_seq:-0}"
    fi
    ;;
"agent send-keys")
    if [ "${HERDR_SENDKEYS_MODE:-nobump}" = "fail" ]; then
        printf '%s\n' '{"error":{"code":"agent_not_found","message":"agent target not found"},"id":"cli:agent:send-keys"}'
        exit 1
    fi
    [ "${HERDR_SENDKEYS_MODE:-nobump}" != "ok" ] || _bump "${CALL_LOG}.seq" >/dev/null
    _bump "${CALL_LOG}.sendkeys" >/dev/null
    printf '%s\n' '{"id":"cli:agent:send-keys","result":{"ok":true}}'
    ;;
"agent read")
    # Evidence capture only (issue #1444). `--format text` gives plain pane
    # lines; an error comes back as JSON on stdout with exit 0, which is what
    # the caller has to recognise and skip.
    if [ "${HERDR_READ_MODE:-ok}" = "missing" ]; then
        printf '%s\n' '{"error":{"code":"agent_not_found","message":"agent target not found"},"id":"cli:agent:read"}'
        exit 0
    fi
    printf '> /gh-issue-flow 11\n5-hour limit reached. Resets at 3pm.\n'
    ;;
"agent prompt")
    _bump "${CALL_LOG}.prompt.$3" >/dev/null
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
        "GH_PRS_FILE=${_WORK_DIR}/prs.json" \
        "HERDR_AGENTS_FILE=${_WORK_DIR}/agents.json" \
        "IW_WATCHED_REPOS=${_WATCH_FILE}" \
        "XDG_STATE_HOME=${_STATE_HOME}" \
        "IW_IDLE_POLL_SLEEP=0" \
        "IW_STALL_RECOVER_SLEEP=0" \
        "IW_LIMIT_OBSERVE_SLEEP=0" \
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
#
# `3>&-` is load-bearing, not tidiness: bats streams TAP on fd 3 and will not
# finish a test until every inheritor closes it. teardown kills the `flock`
# process, but the inner `sh -c` is orphaned and would hold fd 3 open for the
# rest of its `sleep 30` — turning each lock test into a 30-second wait.
_hold_lock() {
    local _ready="${_WORK_DIR}/lock-held"
    mkdir -p "${_STATE_DIR}"
    flock -x "${_LOCK_FILE}" \
        sh -c "printf held >'${_ready}'; sleep 30" >/dev/null 2>&1 3>&- &
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

@test "issue_watcher_cron: --help documents the filters and the per-tick cap" {
    run bash "${SCRIPT}" --help
    assert_success
    assert_output --partial "gh search issues"
    assert_output --partial "wontfix"
    assert_output --partial "blockedBy"
    assert_output --partial "at most 1 issue(s) per tick"
}

@test "issue_watcher_cron: --help documents the concurrency limits and the cursor" {
    run bash "${SCRIPT}" --help
    assert_success
    assert_output --partial "7 running in total"
    assert_output --partial "3 in one repo"
    assert_output --partial "round-robin"
    assert_output --partial "select.json"
}

@test "issue_watcher_cron: --help documents the rate-limit gate and its state file" {
    run bash "${SCRIPT}" --help
    assert_success
    assert_output --partial "rate-limit gate"
    assert_output --partial "rate-limit.json"
    assert_output --partial "30m"
}

@test "issue_watcher_cron: --help documents --status" {
    run bash "${SCRIPT}" --help
    assert_success
    assert_output --partial "--status"
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

@test "issue_watcher_cron: an existing worktree no longer retires the issue" {
    # The bug this replaces: /gh-issue-flow stops at "PR opened", so a worktree
    # removed before the merge used to re-dispatch, and one kept until the merge
    # piled up — while an issue whose session had died was never offered again,
    # because its worktree was still there. A worktree is a workspace now.
    _add_worktree 11
    _run_tick
    assert_success
    _assert_logged "gwt spawn --wt-name issue-11"
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

@test "issue_watcher_cron: only one issue is dispatched per tick" {
    # Intake rate, not total load: five ready issues must not all enter their
    # token-heavy implement phase in the same minute.
    _set_issues '[
      {"number":11,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":13,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":14,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":15,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}
    ]'
    _run_tick
    assert_success
    assert_output --partial "1 issue(s) dispatched"
    [ "$(_log_count 'gwt spawn')" -eq 1 ]
}

@test "issue_watcher_cron: the lowest issue number in a repo goes first" {
    _set_issues '[
      {"number":31,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":25,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}
    ]'
    _run_tick
    assert_success
    _assert_logged "gwt spawn --wt-name issue-12"
    _refute_logged "gwt spawn --wt-name issue-25"
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
    # The candidate loop reads on fd 3. On plain stdin a child that drains it —
    # `gh` does — would eat the remaining search results and the tick would pick
    # from a silently shortened list. Blocking #11 proves the loop reached #12.
    _set_issues '[
      {"number":11,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":13,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}
    ]'
    _run_tick "GH_BLOCKED_BY=11"
    assert_success
    _assert_logged "gwt spawn --wt-name issue-12"
}

@test "issue_watcher_cron: a stdin-consuming child cannot truncate the dispatch loop" {
    _set_issues '[
      {"number":11,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":13,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}
    ]'
    _run_tick "IW_DISPATCH_PER_TICK=3"
    assert_success
    [ "$(_log_count 'agent prompt')" -eq 3 ]
}

@test "issue_watcher_cron: a stdin-consuming child cannot truncate the cleanup loop" {
    # Same hazard one step earlier: the cleanup loop runs `gh issue view` per
    # worktree, so on plain stdin the first call would eat the rest of the list
    # and every worktree after the first would survive its closed issue.
    _add_worktree 11
    _add_worktree 12
    _add_worktree 13
    _run_tick "GH_CLOSED_ISSUES=11 12 13"
    assert_success
    run git -C "${_REPO_DIR}" worktree list --porcelain
    refute_output --partial "wt/issue-12/"
    refute_output --partial "wt/issue-13/"
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

@test "issue_watcher_cron: the pane opens on the newest worktree index" {
    # A cleanup that failed leaves wt/issue-11/1 behind and the next spawn makes
    # /2. Handing the tab the stale /1 path would open the session on the wrong
    # worktree, so _iw_worktree_for_issue reads back the highest index.
    _add_worktree 11
    _run_tick
    assert_success
    _assert_logged "--cwd ${_WORK_DIR}/dotfiles-issue-11-2"
    _refute_logged "--cwd ${_WORK_DIR}/dotfiles-issue-11-1"
}

@test "issue_watcher_cron: a dispatch that never lands is not judged at all" {
    # Attempt 1 stalls, attempts 2-3 die at tab create. Since #1444 the gate no
    # longer classifies *why* a dispatch failed — no error code, from any
    # attempt, can book a strike. Only a prompt confirmed submitted is judged.
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle" "HERDR_TAB_FAIL_AFTER=1"
    assert_failure
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
    _set_limit_state "0" "$(($(date +%s) - 60))"
    _run_tick -- --dry-run
    assert_success
    # Evaluating the gate clears an expired file — a state change in the mode
    # documented as changing nothing.
    [ -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: --dry-run reports even while the gate is closed" {
    _set_limit_state "0" "$(($(date +%s) + 900))"
    _run_tick -- --dry-run
    assert_success
    assert_output --partial "acme/dotfiles#11"
}

# ---------------------------------------------------------------------------
# The three signals (issue #1453)
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: only open issues assigned to me are ever searched" {
    # The "already closed" half of the handled signal is the search itself: a
    # closed issue never enters the candidate list to begin with.
    _run_tick
    assert_success
    _assert_logged "--assignee @me --state open"
}

@test "issue_watcher_cron: an issue an open PR closes is skipped" {
    _set_open_prs '{"acme/dotfiles":[{"number":90,"headRefName":"feature/x","body":"Closes #11"}]}'
    _run_tick
    assert_success
    assert_output --partial "an open PR already closes it"
    _refute_logged "gwt spawn"
}

@test "issue_watcher_cron: the closing keyword is matched case-insensitively" {
    _set_open_prs '{"acme/dotfiles":[{"number":90,"headRefName":"feature/x","body":"fixes #11"}]}'
    _run_tick
    assert_success
    _refute_logged "gwt spawn"
}

@test "issue_watcher_cron: a PR on the issue branch counts even without the keyword" {
    # A PR opened by hand may carry no `Closes #<n>`, but gwt always branches
    # wt/issue-<n>/<index>, so the branch name is the second, independent mark.
    _set_open_prs '{"acme/dotfiles":[{"number":90,"headRefName":"wt/issue-11/1","body":"no keyword here"}]}'
    _run_tick
    assert_success
    _refute_logged "gwt spawn"
}

@test "issue_watcher_cron: a PR closing a longer number does not retire this issue" {
    # Without the word boundary, `Closes #115` would read as closing #11 and
    # retire it for as long as that PR stayed open.
    _set_open_prs '{"acme/dotfiles":[{"number":90,"headRefName":"feature/x","body":"Closes #115"}]}'
    _run_tick
    assert_success
    _assert_logged "gwt spawn --wt-name issue-11"
}

@test "issue_watcher_cron: an open PR on another repo does not retire this issue" {
    _set_open_prs '{"other/elsewhere":[{"number":90,"headRefName":"wt/issue-11/1","body":"Closes #11"}]}'
    _run_tick
    assert_success
    _assert_logged "gwt spawn --wt-name issue-11"
}

@test "issue_watcher_cron: a worktree with no PR and no session is offered again" {
    # The failure this closes: dispatch is fire-and-forget, so a claude session
    # that died after its worktree existed used to retire the issue forever.
    _add_worktree 11
    _run_tick
    assert_success
    _assert_logged "gwt spawn --wt-name issue-11"
}

@test "issue_watcher_cron: an issue whose session is live is not dispatched again" {
    _add_worktree 11
    _set_live_agents "$(_worktree_path 11)"
    _run_tick
    assert_success
    assert_output --partial "already running"
    _refute_logged "gwt spawn"
}

@test "issue_watcher_cron: a failing open-PR query skips the repo, not the tick" {
    # Fail-closed on purpose (D-6): guessing "unhandled" here opens a second PR
    # on an issue that already has one, and the next tick re-evaluates anyway.
    _run_tick "GH_PR_LIST_FAIL=1"
    assert_success
    assert_output --partial "Cannot list open PRs"
    _refute_logged "gwt spawn"
}

# ---------------------------------------------------------------------------
# Concurrency limits (issue #1453 D-2)
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: the tick holds once the global limit is reached" {
    _set_running 21 22 23 24 25 26 27
    _run_tick
    assert_success
    assert_output --partial "7 issue session(s) already running"
    _refute_logged "gwt spawn"
}

@test "issue_watcher_cron: one session short of the limit still dispatches" {
    _set_running 21 22 23 24 25 26
    _run_tick "IW_MAX_PER_REPO=9"
    assert_success
    _assert_logged "gwt spawn --wt-name issue-11"
}

@test "issue_watcher_cron: a repo at its own limit is skipped" {
    _set_running 21 22 23
    _run_tick
    assert_success
    assert_output --partial "3 of its issues are already running"
    _refute_logged "gwt spawn"
}

@test "issue_watcher_cron: a repo at its limit does not stop another repo" {
    _two_repo_fixture
    _set_running 21 22 23
    _run_tick
    assert_success
    _assert_logged "gwt spawn --wt-name issue-41"
}

@test "issue_watcher_cron: an unreachable herdr holds the tick instead of dispatching" {
    # "How many are running" has no safe default: guessing "none" would lift the
    # cap exactly when herdr is unhealthy.
    _run_tick "HERDR_AGENT_LIST_FAIL=1"
    assert_success
    assert_output --partial "holding this tick"
    _refute_logged "gwt spawn"
}

# ---------------------------------------------------------------------------
# Round-robin cursor (issue #1453 D-3)
# ---------------------------------------------------------------------------

_two_repo_fixture() {
    local _other="${_WORK_DIR}/other"
    _make_repo "${_other}"
    _write_watch_file '[{"repo":"acme/dotfiles","path":"'"${_REPO_DIR}"'","host":"github.com"},
                        {"repo":"acme/other","path":"'"${_other}"'","host":"github.com"}]'
    _set_issues '[
      {"number":11,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":41,"repository":{"nameWithOwner":"acme/other"},"labels":[]}
    ]'
}

@test "issue_watcher_cron: consecutive ticks take turns between repos" {
    _two_repo_fixture
    _run_tick
    assert_success
    _assert_logged "gwt spawn --wt-name issue-11"

    : >"${_LOG}"
    _set_live_agents "$(_worktree_path 11)"
    _run_tick
    assert_success
    _assert_logged "gwt spawn --wt-name issue-41"
}

@test "issue_watcher_cron: the cursor is persisted for the next tick" {
    _two_repo_fixture
    _run_tick
    assert_success
    run cat "${_STATE_DIR}/select.json"
    assert_output --partial '"last_repo": "acme/dotfiles"'
}

@test "issue_watcher_cron: a state dir with no cursor starts at the first repo" {
    _two_repo_fixture
    mkdir -p "${_STATE_DIR}"
    [ ! -f "${_STATE_DIR}/select.json" ]
    _run_tick
    assert_success
    _assert_logged "gwt spawn --wt-name issue-11"
}

@test "issue_watcher_cron: an unwritable state dir does not stop the dispatch" {
    _two_repo_fixture
    mkdir -p "${_STATE_DIR}"
    chmod 500 "${_STATE_DIR}"
    _run_tick
    assert_success
    _assert_logged "gwt spawn --wt-name issue-11"
}

@test "issue_watcher_cron: --dry-run does not advance the cursor" {
    _two_repo_fixture
    _run_tick -- --dry-run
    assert_success
    [ ! -f "${_STATE_DIR}/select.json" ]
}

# ---------------------------------------------------------------------------
# Worktree collection (issue #1453 D-4)
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: a closed issue's idle worktree is collected" {
    _add_worktree 21
    _run_tick "GH_CLOSED_ISSUES=21"
    assert_success
    assert_output --partial "Collected worktree"
    run git -C "${_REPO_DIR}" worktree list --porcelain
    refute_output --partial "wt/issue-21/"
}

@test "issue_watcher_cron: an open issue's worktree is left alone" {
    _add_worktree 21
    _run_tick
    assert_success
    run git -C "${_REPO_DIR}" worktree list --porcelain
    assert_output --partial "wt/issue-21/"
}

@test "issue_watcher_cron: a closed issue whose session is still live is left alone" {
    _add_worktree 21
    _set_live_agents "$(_worktree_path 21)"
    _run_tick "GH_CLOSED_ISSUES=21"
    assert_success
    run git -C "${_REPO_DIR}" worktree list --porcelain
    assert_output --partial "wt/issue-21/"
}

@test "issue_watcher_cron: an unreadable issue state leaves the worktree in place" {
    _add_worktree 21
    _run_tick "GH_ISSUE_VIEW_FAIL=1"
    assert_success
    assert_output --partial "leaving its worktree in place"
    run git -C "${_REPO_DIR}" worktree list --porcelain
    assert_output --partial "wt/issue-21/"
}

@test "issue_watcher_cron: a failed collection warns and the tick continues" {
    _add_worktree 21
    # git refuses to remove a working tree whose .git link is gone, so this is a
    # real removal failure rather than a mocked one. Deleting the *admin*
    # directory instead would drop the entry from `git worktree list` entirely,
    # and there would be nothing left to fail on.
    rm -f "$(_worktree_path 21)/.git"
    _run_tick "GH_CLOSED_ISSUES=21"
    assert_success
    assert_output --partial "Leaving worktree"
    _assert_logged "gwt spawn --wt-name issue-11"
}

@test "issue_watcher_cron: collection runs before the dispatch it frees room for" {
    # Ordering matters twice over: the room it frees is usable in the same tick,
    # and a collection failure must not be able to hold up a dispatch.
    _add_worktree 21
    _run_tick "GH_CLOSED_ISSUES=21"
    assert_success
    local _collected="${output%%Collected worktree*}"
    local _dispatched="${output%%dispatched*}"
    [ "${#_collected}" -lt "${#_dispatched}" ]
}

@test "issue_watcher_cron: --dry-run collects nothing" {
    _add_worktree 21
    _run_tick "GH_CLOSED_ISSUES=21" -- --dry-run
    assert_success
    run git -C "${_REPO_DIR}" worktree list --porcelain
    assert_output --partial "wt/issue-21/"
}

# ---------------------------------------------------------------------------
# PR #1456 review regressions
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: a full open-PR window is treated as unknown, not as an answer" {
    # 100 open PRs means the window is full; the issue's own PR may sit outside
    # it, so answering "unhandled" would reinstate the duplicate-PR failure.
    _set_filler_prs "acme/dotfiles" 100
    _run_tick
    assert_success
    assert_output --partial "cannot rule out a duplicate"
    _refute_logged "gwt spawn"
}

@test "issue_watcher_cron: a window with room to spare still answers" {
    _set_filler_prs "acme/dotfiles" 99
    _run_tick
    assert_success
    _assert_logged "gwt spawn --wt-name issue-11"
}

@test "issue_watcher_cron: 'Closes: #N' counts as an open PR closing the issue" {
    _set_open_prs '{"acme/dotfiles":[{"number":90,"headRefName":"feature/x","body":"Closes: #11"}]}'
    _run_tick
    assert_success
    _refute_logged "gwt spawn"
}

@test "issue_watcher_cron: a cross-repo 'Closes owner/repo#N' counts too" {
    _set_open_prs '{"acme/dotfiles":[{"number":90,"headRefName":"feature/x","body":"Closes acme/dotfiles#11"}]}'
    _run_tick
    assert_success
    _refute_logged "gwt spawn"
}

@test "issue_watcher_cron: a session that cd-ed away is still counted as running" {
    _add_worktree 11
    _set_live_agent_moved "$(_worktree_path 11)" "${_WORK_DIR}"
    _run_tick
    assert_success
    assert_output --partial "already running"
    _refute_logged "gwt spawn"
}

@test "issue_watcher_cron: a session in a subdirectory of its worktree still counts" {
    _add_worktree 11
    mkdir -p "$(_worktree_path 11)/sub/dir"
    _set_live_agent_subdir "$(_worktree_path 11)/sub/dir"
    _run_tick
    assert_success
    assert_output --partial "already running"
    _refute_logged "gwt spawn"
}

@test "issue_watcher_cron: a worktree with uncommitted work is never collected" {
    # An issue can be closed by hand while its session still holds unsaved work.
    # Routine hygiene must not be a data-loss path.
    _add_worktree 21
    printf 'unsaved\n' >"$(_worktree_path 21)/WIP.txt"
    git -C "$(_worktree_path 21)" add WIP.txt
    _run_tick "GH_CLOSED_ISSUES=21"
    assert_success
    assert_output --partial "uncommitted or untracked changes"
    run git -C "${_REPO_DIR}" worktree list --porcelain
    assert_output --partial "wt/issue-21/"
    [ -f "${_WORK_DIR}/dotfiles-issue-21-1/WIP.txt" ]
}

@test "issue_watcher_cron: an untracked file also blocks collection" {
    _add_worktree 21
    printf 'scratch\n' >"$(_worktree_path 21)/scratch.txt"
    _run_tick "GH_CLOSED_ISSUES=21"
    assert_success
    run git -C "${_REPO_DIR}" worktree list --porcelain
    assert_output --partial "wt/issue-21/"
}

@test "issue_watcher_cron: the tick never collects the worktree it is standing in" {
    _add_worktree 21
    _run_tick "GH_CLOSED_ISSUES=21" -- --cwd "$(_worktree_path 21)"
    assert_success
    run git -C "${_REPO_DIR}" worktree list --porcelain
    assert_output --partial "wt/issue-21/"
}

@test "issue_watcher_cron: nor one it is standing inside" {
    _add_worktree 21
    mkdir -p "$(_worktree_path 21)/nested"
    _run_tick "GH_CLOSED_ISSUES=21" -- --cwd "$(_worktree_path 21)/nested"
    assert_success
    run git -C "${_REPO_DIR}" worktree list --porcelain
    assert_output --partial "wt/issue-21/"
}

@test "issue_watcher_cron: a raised per-tick cap cannot exceed the per-repo cap" {
    # Two already running plus a per-tick allowance of three: only one slot is
    # left in this repo, so only one issue may start.
    local _paths=() _n
    for _n in 21 22; do
        _add_worktree "${_n}"
        _paths+=("$(_worktree_path "${_n}")")
    done
    _set_live_agents "${_paths[@]}"
    _set_issues '[
      {"number":11,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":13,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}
    ]'
    _run_tick "IW_DISPATCH_PER_TICK=3"
    assert_success
    [ "$(_log_count 'gwt spawn')" -eq 1 ]
}

@test "issue_watcher_cron: a raised per-tick cap cannot exceed the global cap" {
    local _paths=() _n
    for _n in 21 22 23 24 25 26; do
        _add_worktree "${_n}"
        _paths+=("$(_worktree_path "${_n}")")
    done
    _set_live_agents "${_paths[@]}"
    _set_issues '[
      {"number":11,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":13,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}
    ]'
    # Per-repo headroom is lifted so the global ceiling is the only thing left
    # to hold the line: six running, seven allowed, so exactly one may start.
    _run_tick "IW_DISPATCH_PER_TICK=3" "IW_MAX_PER_REPO=9"
    assert_success
    [ "$(_log_count 'gwt spawn')" -eq 1 ]
}

@test "issue_watcher_cron: a non-integer cap override falls back to the default" {
    _run_tick "IW_MAX_CONCURRENT=abc"
    assert_success
    assert_output --partial "not a positive integer"
    _assert_logged "gwt spawn --wt-name issue-11"
}

@test "issue_watcher_cron: an empty cap override is silently the default" {
    # Unset-vs-empty must not warn: `IW_MAX_CONCURRENT=` in a cron env is the
    # same intent as not setting it at all.
    _run_tick "IW_MAX_CONCURRENT="
    assert_success
    refute_output --partial "not a positive integer"
    _assert_logged "gwt spawn --wt-name issue-11"
}

@test "issue_watcher_cron: --help reports the effective cap, not the default" {
    run env "IW_MAX_CONCURRENT=5" bash "${SCRIPT}" --help
    assert_success
    assert_output --partial "5 running in total"
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
    # `issue view` is a read and is expected; every other `gh issue` verb is a
    # write, and so is a graphql mutation.
    run grep -E '^gh issue [a-z-]+' "${_LOG}"
    refute_output --regexp '^gh issue (comment|edit|close|reopen|create|delete|lock|unlock|pin|unpin|transfer|develop)'
    run grep -E '^gh api graphql -f query=mutation' "${_LOG}"
    assert_failure
}

@test "issue_watcher_cron: only the four read calls reach gh" {
    _add_worktree 11
    _run_tick
    assert_success
    run grep -cE '^gh (search issues|pr list|issue view|api graphql)' "${_LOG}"
    assert_success
    run grep -vE '^gh (search issues|pr list|issue view|api graphql)' "${_LOG}"
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

@test "issue_watcher_cron: a non-stall prompt failure is not retried within the attempt" {
    _run_tick "HERDR_PROMPT_MODE=fail"
    assert_failure
    # Three attempts, one prompt each — never two prompts inside one attempt.
    [ "$(_log_count 'agent prompt')" -eq 3 ]
}

# ---------------------------------------------------------------------------
# Stall recovery (issue #1443)
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: agent_prompt_stalled is recovered by pressing Enter, never retyped" {
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle" "HERDR_SENDKEYS_MODE=ok"
    assert_success
    # The stalled command is already sitting in the input box unsubmitted, so a
    # second `agent prompt` would type it on top of itself and Enter would still
    # never land. Exactly one prompt, ever.
    [ "$(_log_count 'agent prompt')" -eq 1 ]
    _assert_logged "agent send-keys iw-acme-dotfiles-11 Enter"
    [ "$(_log_count 'agent send-keys')" -eq 1 ]
}

@test "issue_watcher_cron: the Enter recovery stops as soon as state_change_seq moves" {
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle" "HERDR_SENDKEYS_MODE=ok"
    assert_success
    assert_output --partial "state_change_seq"
    assert_output --partial "Dispatched to iw-acme-dotfiles-11"
}

@test "issue_watcher_cron: an unresolved stall presses Enter three times and still reports the stall" {
    # HERDR_SENDKEYS_MODE defaults to nobump: Enter is accepted but the input
    # loop never submits, so the counter never moves.
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle"
    assert_failure
    # Three attempts of three presses each, and still only one prompt per
    # attempt.
    [ "$(_log_count 'agent send-keys')" -eq 9 ]
    [ "$(_log_count 'agent prompt')" -eq 3 ]
    assert_output --partial "agent_prompt_stalled"
    # Regression lock for issue #1444. This is the *cold start* signature #1443
    # measured: the prompt was typed but never submitted, so nothing is known
    # about the quota. Pre-#1444 this exact run booked a strike, and two of them
    # shut the gate for 30 minutes with the account untouched.
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: agent_prompt_stalled recovery is skipped when the agent is already working" {
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=working"
    assert_success
    [ "$(_log_count 'agent prompt')" -eq 1 ]
    assert_output --partial "treating as delivered"
    # `working` is positive evidence the prompt landed — nothing to submit.
    _refute_logged "agent send-keys"
}

@test "issue_watcher_cron: a blipped seq baseline falls back to the working status" {
    # Regression (PR #1449 codex review, BLOCKER A): when the pre-prompt
    # `agent get` yields no state_change_seq, a sequence comparison can never
    # succeed afterwards — a one-off local herdr blip would become a permanent
    # hard failure. HERDR_SENDKEYS_MODE stays at nobump so the counter is
    # provably not what carries this test.
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle" \
        "HERDR_SEQ_MODE=absent" "HERDR_STATUS_AFTER_SENDKEYS=working"
    assert_success
    [ "$(_log_count 'agent send-keys')" -eq 1 ]
    [ "$(_log_count 'agent prompt')" -eq 1 ]
    assert_output --partial "no seq baseline"
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: a failing send-keys abandons recovery instead of burning attempts" {
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle" "HERDR_SENDKEYS_MODE=fail"
    assert_failure
    # One press per dispatch attempt, not three: retrying against a pane herdr
    # cannot reach at all is pure waste.
    [ "$(_log_count 'agent send-keys')" -eq 3 ]
    [ "$(_log_count 'agent prompt')" -eq 3 ]
    assert_output --partial "pane unreachable"
}

@test "issue_watcher_cron: a broken pane is named as an outage, not booked as a strike" {
    # PR #1449 codex review, BLOCKER B: an unreachable pane must not read as a
    # spent quota. Since #1444 that follows from the dispatch failing at all —
    # the distinct code survives only so the cron log names the real fault.
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle" "HERDR_SENDKEYS_MODE=fail"
    assert_failure
    assert_output --partial "herdr_send_keys_failed"
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: a broken pane leaves an existing strike count untouched" {
    _set_limit_state "1" "0"
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle" "HERDR_SENDKEYS_MODE=fail"
    assert_failure
    run cat "${_LIMIT_FILE}"
    assert_output --partial '"strikes": "1"'
    refute_output --partial '"strikes": "2"'
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
    : >"${_LOG}"
    _set_issues '[{"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}]'
    _run_tick
    assert_success
    _assert_logged "gwt spawn --wt-name issue-12"
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
    _run_tick "IW_DISPATCH_PER_TICK=2"
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
        "IW_LIMIT_OBSERVE_SLEEP=0" \
        bash "${SCRIPT}"
    refute_output --partial "unbound variable"
}

# ---------------------------------------------------------------------------
# Rate-limit gate (issues #1436, #1444)
# ---------------------------------------------------------------------------
#
# Since #1444 the gate reads two things and nothing else: was the prompt
# confirmed submitted, and did the agent that received it hold `working` for
# _IW_LIMIT_OBSERVE_SEC afterwards. `HERDR_STATUS_AFTER_PROMPT` is what stages
# the second half — the default `idle` means "the dispatch landed and then
# nothing happened", which is the quota signature.

@test "issue_watcher_cron: a dispatch whose agent holds working leaves no gate state" {
    _run_tick "HERDR_STATUS_AFTER_PROMPT=working"
    assert_success
    assert_output --partial "held 'working' for 60s"
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: a confirmed dispatch that never reaches working records a strike" {
    # The prompt landed — `agent prompt` succeeded — and a minute later the pane
    # is still idle. One /gh-issue-flow runs for minutes, so the work never
    # started.
    _run_tick
    assert_success
    assert_output --partial "No dispatched agent reached 'working' within 60s (1/2)"
    run cat "${_LIMIT_FILE}"
    assert_output --partial '"strikes": "1"'
    assert_output --partial '"backoff_until": "0"'
}

@test "issue_watcher_cron: an agent that reaches working and falls back records a strike" {
    # Working for the first two polls of the window, idle for the remaining
    # four. `working` has to be *held*, not merely touched — and the log has to
    # say which of the two failures this was.
    _run_tick "HERDR_STATUS_AFTER_PROMPT=working" "HERDR_STATUS_AFTER_PROMPT_GETS=2"
    assert_success
    assert_output --partial "reached 'working' and fell back inside 60s (1/2)"
    run cat "${_LIMIT_FILE}"
    assert_output --partial '"strikes": "1"'
}

@test "issue_watcher_cron: a dispatch that never lands leaves the strike count alone" {
    # Not a strike and not a clear: an unsubmitted prompt is evidence about the
    # input loop, not about the quota (issue #1444).
    mkdir -p "${_STATE_DIR}"
    printf '{ "strikes": "1", "backoff_until": "0" }\n' >"${_LIMIT_FILE}"
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle"
    assert_failure
    run cat "${_LIMIT_FILE}"
    assert_output --partial '"strikes": "1"'
    refute_output --partial '"strikes": "2"'
}

@test "issue_watcher_cron: two consecutive unproductive ticks close the gate" {
    _run_tick
    assert_success
    # A different issue next tick: strikes count consecutive *ticks*, and the
    # first one already left a worktree behind for #11.
    _set_issues '[{"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}]'
    _run_tick
    assert_success
    assert_output --partial "Rate-limit gate closed for 30m"
    run cat "${_LIMIT_FILE}"
    assert_output --partial '"strikes": "0"'
    refute_output --partial '"backoff_until": "0"'
}

@test "issue_watcher_cron: one healthy agent clears the slate for the whole tick" {
    # Issue #1444, 확정 3: one account, one quota. An agent holding `working`
    # proves the account is not spent, so the tick earns no strike even though
    # its other dispatches went nowhere — those are issue-specific failures, not
    # evidence about the quota.
    _set_issues '[
      {"number":11,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":13,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}
    ]'
    _run_tick "IW_DISPATCH_PER_TICK=3" "HERDR_WORKING_AGENTS=iw-acme-dotfiles-12"
    assert_success
    assert_output --partial "Agent iw-acme-dotfiles-12 held 'working'"
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: every dispatch in a tick is judged, not just the first" {
    # The mirror of the test above: with none of the three holding `working` the
    # tick books exactly one strike, not one per dispatch.
    _set_issues '[
      {"number":11,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":13,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}
    ]'
    _run_tick "IW_DISPATCH_PER_TICK=3"
    assert_success
    run cat "${_LIMIT_FILE}"
    assert_output --partial '"strikes": "1"'
}

@test "issue_watcher_cron: an unreadable agent status is not booked as idle" {
    # Regression (PR #1468 codex review, BLOCKER): `_iw_agent_status` reports a
    # failed `herdr agent get` as an empty string, and the gate used to fall
    # through that into the strike branch — so one transient herdr blip during
    # the window read as a spent quota. Absence of evidence is not evidence of
    # idleness; the strike needs a status actually read.
    _run_tick "HERDR_GET_FAIL_AFTER_PROMPT=1"
    assert_success
    assert_output --partial "No dispatched agent's status could be read after 60s"
    assert_output --partial "gate untouched"
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: an unreadable deciding poll leaves an existing strike alone" {
    # The gate must not accumulate on unreadable evidence either — not a strike
    # and not a clear.
    mkdir -p "${_STATE_DIR}"
    printf '{ "strikes": "1", "backoff_until": "0" }\n' >"${_LIMIT_FILE}"
    _run_tick "HERDR_GET_FAIL_AFTER_PROMPT=1"
    assert_success
    run cat "${_LIMIT_FILE}"
    assert_output --partial '"strikes": "1"'
    refute_output --partial '"strikes": "2"'
}

@test "issue_watcher_cron: readable early polls do not rescue an unreadable deciding poll" {
    # Intermittent herdr: the first two polls answer `idle`, the remaining four
    # error. Only the poll that decides counts, and it read nothing — so the
    # early `idle` readings must not be promoted into a strike.
    _run_tick "HERDR_GET_FAIL_AFTER_PROMPT=1" "HERDR_GET_FAIL_AFTER_PROMPT_SKIP=2"
    assert_success
    assert_output --partial "No dispatched agent's status could be read after 60s"
    [ ! -f "${_LIMIT_FILE}" ]
}

# ---------------------------------------------------------------------------
# Evidence capture (issue #1444) — logged, never gated on
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: a strike logs the pane tail as evidence" {
    _run_tick
    assert_success
    _assert_logged "agent read iw-acme-dotfiles-11 --lines 40 --format text"
    assert_output --partial "Pane tail for iw-acme-dotfiles-11 (evidence only"
    assert_output --partial "5-hour limit reached"
}

@test "issue_watcher_cron: a healthy tick captures no pane evidence" {
    _run_tick "HERDR_STATUS_AFTER_PROMPT=working"
    assert_success
    _refute_logged "agent read"
}

@test "issue_watcher_cron: an unreadable pane does not break the strike" {
    # `agent read` answers JSON-on-stdout with exit 0 when the target is gone.
    # Logging that as if it were pane content would be worse than saying
    # nothing, and it must not disturb the verdict either way.
    _run_tick "HERDR_READ_MODE=missing"
    assert_success
    assert_output --partial "No pane output captured for iw-acme-dotfiles-11"
    refute_output --partial '{"error"'
    run cat "${_LIMIT_FILE}"
    assert_output --partial '"strikes": "1"'
}

@test "issue_watcher_cron: pane text cannot open the gate" {
    # The pane is shouting about a rate limit and the agent is working anyway.
    # The behaviour decides; the banner is a log line. A claude release that
    # reworded it changes nothing here — which is the whole reason the wording
    # is not a gate input (issue #1444, 확정 2).
    _run_tick "HERDR_STATUS_AFTER_PROMPT=working"
    assert_success
    [ ! -f "${_LIMIT_FILE}" ]
}

# ---------------------------------------------------------------------------
# Backoff, expiry and fail-open (issue #1436 behaviour, preserved)
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: a closed gate holds the tick without dispatching" {
    _set_limit_state "0" "$(($(date +%s) + 900))"
    _run_tick
    assert_success
    assert_output --partial "Rate-limit gate closed"
    _refute_logged "agent prompt"
}

@test "issue_watcher_cron: a held tick creates no worktree" {
    _set_limit_state "0" "$(($(date +%s) + 900))"
    _run_tick
    assert_success
    _refute_logged "gwt spawn"
    run git -C "${_REPO_DIR}" worktree list --porcelain
    refute_output --partial "wt/issue-11/"
}

@test "issue_watcher_cron: a held tick leaves the gate deadline untouched" {
    local _until=$(($(date +%s) + 900))
    _set_limit_state "0" "${_until}"
    _run_tick
    assert_success
    # Positive control (issue #1442): the deadline surviving is only evidence
    # of a *working* gate if the gate ran at all. Without this line a build
    # that never reads the state file passes too — absence and correctness
    # would look identical.
    assert_output --partial "Rate-limit gate closed"
    run cat "${_LIMIT_FILE}"
    assert_output --partial "\"backoff_until\": \"${_until}\""
}

@test "issue_watcher_cron: an expired backoff reopens the gate and dispatches" {
    _set_limit_state "0" "$(($(date +%s) - 60))"
    _run_tick "HERDR_STATUS_AFTER_PROMPT=working"
    assert_success
    assert_output --partial "Rate-limit gate reopened"
    _assert_logged "agent prompt iw-acme-dotfiles-11"
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: an out-of-range future deadline is treated as expired" {
    _set_limit_state "0" "$(($(date +%s) + 999999))"
    _run_tick "HERDR_STATUS_AFTER_PROMPT=working"
    assert_success
    assert_output --partial "Rate-limit gate reopened"
}

@test "issue_watcher_cron: a corrupt gate file fails open" {
    mkdir -p "${_STATE_DIR}"
    printf 'not json at all\n' >"${_LIMIT_FILE}"
    _run_tick "HERDR_STATUS_AFTER_PROMPT=working"
    assert_success
    _assert_logged "agent prompt iw-acme-dotfiles-11"
}

@test "issue_watcher_cron: a non-numeric deadline fails open" {
    _set_limit_state "0" "soon"
    _run_tick "HERDR_STATUS_AFTER_PROMPT=working"
    assert_success
    assert_output --partial "dispatching anyway"
    _assert_logged "agent prompt iw-acme-dotfiles-11"
}

@test "issue_watcher_cron: a productive tick clears accumulated strikes" {
    _set_limit_state "1" "0"
    _run_tick "HERDR_STATUS_AFTER_PROMPT=working"
    assert_success
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: a stalled dispatch with the agent working earns no strike" {
    # herdr says `agent_prompt_stalled` but the agent is already working, so
    # _iw_prompt_issue treats it as delivered — and the same `working` carries
    # it through the observation window.
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=working"
    assert_success
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: a non-quota dispatch failure earns no strike" {
    _run_tick "HERDR_PROMPT_MODE=fail"
    assert_failure
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: a non-quota failure leaves an existing strike untouched" {
    _set_limit_state "1" "0"
    _run_tick "HERDR_PROMPT_MODE=fail"
    assert_failure
    # Positive control (issue #1442; rationale at "a held tick leaves the gate
    # deadline untouched") — must precede `run cat`, which replaces $output.
    # Since #1444 the gate judges submission, not error codes, so the line that
    # proves it ran is the no-confirmed-dispatch notice.
    assert_output --partial "nothing to judge, gate untouched"
    run cat "${_LIMIT_FILE}"
    assert_output --partial '"strikes": "1"'
}

@test "issue_watcher_cron: repeated non-quota failures never close the gate" {
    _run_tick "HERDR_PROMPT_MODE=fail"
    assert_failure
    assert_output --partial "nothing to judge, gate untouched"
    _set_issues '[{"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}]'
    _run_tick "HERDR_PROMPT_MODE=fail"
    assert_failure
    # Positive control (issue #1442; same rationale): two unproductive ticks
    # shut the gate, two ticks whose prompts never landed must not.
    assert_output --partial "nothing to judge, gate untouched"
    refute_output --partial "Rate-limit gate closed"
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: repeated non-quota failures never close a gate holding a strike" {
    mkdir -p "${_STATE_DIR}"
    printf '{ "strikes": "1", "backoff_until": "0" }\n' >"${_LIMIT_FILE}"
    _run_tick "HERDR_PROMPT_MODE=fail"
    assert_failure
    assert_output --partial "nothing to judge, gate untouched"
    _set_issues '[{"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}]'
    _run_tick "HERDR_PROMPT_MODE=fail"
    assert_failure
    # PR #1462 codex FOLLOW-UP: a strike already on record is the state where a
    # miscounted non-quota failure tips the gate shut — one more reaches
    # _IW_LIMIT_STRIKES. The clean-state sibling above cannot reach that edge,
    # so the dirty start is the case that actually pins the classification.
    # #1444 keeps the edge and moves the classifier: an unlanded prompt is not
    # judged at all, so the strike count must be untouched either way.
    assert_output --partial "nothing to judge, gate untouched"
    refute_output --partial "Rate-limit gate closed"
    run cat "${_LIMIT_FILE}"
    assert_output --partial '"strikes": "1"'
}

@test "issue_watcher_cron: a state dir with no gate file ticks exactly as before" {
    mkdir -p "${_STATE_DIR}"
    _run_tick "HERDR_STATUS_AFTER_PROMPT=working"
    assert_success
    _assert_logged "agent prompt iw-acme-dotfiles-11"
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: an unwritable state dir warns but does not change the exit code" {
    mkdir -p "${_STATE_DIR}"
    chmod 500 "${_STATE_DIR}"
    _run_tick
    assert_success
    assert_output --partial "rate-limit gate will not survive this tick"
    chmod 700 "${_STATE_DIR}"
}

# ---------------------------------------------------------------------------
# --status (issue #1441, AC 11)
# ---------------------------------------------------------------------------

@test "issue_watcher_cron: --status reports an open gate and runs no tick" {
    _run_tick -- --status
    assert_success
    assert_output --partial "Rate-limit gate open"
    _refute_logged "agent prompt"
    _refute_logged "search issues"
}

@test "issue_watcher_cron: --status names the state file it read" {
    _run_tick -- --status
    assert_success
    assert_output --partial "rate-limit.json"
}

@test "issue_watcher_cron: --status reports a closed gate with the time left" {
    _set_limit_state "0" "$(($(date +%s) + 900))"
    _run_tick -- --status
    assert_success
    assert_output --partial "Rate-limit gate closed"
    assert_output --partial "15m"
    _refute_logged "agent prompt"
}

@test "issue_watcher_cron: --status reports accumulated strikes while the gate is open" {
    _set_limit_state "1" "0"
    _run_tick -- --status
    assert_success
    assert_output --partial "1/2"
    assert_output --partial "Rate-limit gate open"
}

@test "issue_watcher_cron: --status leaves an expired gate file on disk" {
    _set_limit_state "0" "$(($(date +%s) - 60))"
    _run_tick -- --status
    assert_success
    assert_output --partial "Rate-limit gate open"
    # Reporting is not deciding: only a real tick may clear an expired file,
    # the same reason --dry-run stays clear of the gate check.
    [ -f "${_LIMIT_FILE}" ]
}

@test "issue_watcher_cron: --status treats an out-of-range deadline as expired" {
    _set_limit_state "0" "$(($(date +%s) + 999999))"
    _run_tick -- --status
    assert_success
    assert_output --partial "Rate-limit gate open"
}

@test "issue_watcher_cron: --status fails open on a corrupt gate file" {
    mkdir -p "${_STATE_DIR}"
    printf 'not json at all\n' >"${_LIMIT_FILE}"
    _run_tick -- --status
    assert_success
    assert_output --partial "unreadable"
}

@test "issue_watcher_cron: --status does not take the tick lock" {
    _hold_lock
    _run_tick -- --status
    assert_success
    refute_output --partial "already running"
}

@test "issue_watcher_cron: --status answers even without herdr on PATH" {
    rm -f "${_BIN_DIR}/herdr"
    _run_tick "PATH=$(_path_without herdr)" -- --status
    assert_success
    assert_output --partial "Rate-limit gate open"
    refute_output --partial "herdr not found"
}
