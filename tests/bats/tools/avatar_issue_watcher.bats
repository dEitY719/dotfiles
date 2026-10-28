#!/usr/bin/env bats
# tests/bats/tools/avatar_issue_watcher.bats
# Tests for avatar_issue_watcher.sh — the issue-watcher tick
# (issues #1389, #1436, #1440, #1453).
#
# Since #1440 the tick does the watching and dispatching itself, so the suite
# covers the whole pipeline rather than a single dispatcher prompt. Two PATH
# stubs stand in for the outside world and log every invocation to ${_LOG} so
# the tests can assert on *which* calls were made:
#
#   gh     `search issues`, `pr list` (the already-handled signal), `issue view`
#          (the collectable signal) and `api graphql` (blockedBy) — all canned
#          and steerable per test. Every other subcommand is logged and refused:
#          the tick must never write to an issue.
#   herdr  workspace/tab/agent plus `workspace list` + `tab list` + `agent list`
#          (the running-now signal), with canned JSON matching the shapes
#          measured on a live herdr server.
#
# Before the tab opens the tick acquires the issue worktree (#2281): it reuses
# a `wt/issue-<n>/*` one, else runs the real `gwt spawn --wt-name issue-<n>`
# against a real fixture repo, so the tests prove which worktree the pane
# starts in and that the main checkout is left alone. Removing it is the
# user's manual step. `gh pr list` says what is already handled and
# `gh issue view` feeds the zombie check (#1596).

load '../test_helper'

SCRIPT="${DOTFILES_ROOT}/shell-common/tools/custom/avatar_issue_watcher.sh"

setup() {
    setup_isolated_home
    _WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/issue-watcher-test.XXXXXX")"
    _BIN_DIR="${_WORK_DIR}/bin"
    _STATE_HOME="${_WORK_DIR}/state"
    _STATE_DIR="${_STATE_HOME}/avatar-issue-watcher"
    _LIMIT_FILE="${_STATE_DIR}/rate-limit.json"
    _CASUALTY_FILE="${_STATE_DIR}/rate-limit-casualties.tsv"
    _SATURATION_FILE="${_STATE_DIR}/saturation.json"
    _ZOMBIE_FILE="${_STATE_DIR}/zombie-candidates.tsv"
    _LOCK_FILE="${_STATE_DIR}/.lock"
    _LOG="${_WORK_DIR}/calls.log"
    _REPO_DIR="${_WORK_DIR}/dotfiles"
    _WATCH_FILE="${_WORK_DIR}/watched-repos.json"
    _LABEL_FILE="${_WORK_DIR}/excluded-labels.json"
    _LOCK_HOLDER_PID=""
    _RUN_DIR=""
    mkdir -p "${_BIN_DIR}"
    : >"${_LOG}"

    # CLAUDE_CONFIG_DIR account routing (issue #1393): the tick resolves the
    # claude account dir before it opens any pane and fails fast when it is
    # missing, so the default account must exist inside the isolated $HOME.
    # Pinned here (not inherited) so the developer's own shell env cannot
    # steer the tests.
    export CLAUDE_ENABLED_ACCOUNTS="personal"
    unset CLAUDE_DEFAULT_ACCOUNT
    _make_account "${HOME}/.claude-personal"

    _make_repo
    _write_watch_file '[{"repo":"acme/dotfiles","path":"'"${_REPO_DIR}"'","host":"github.com"}]'
    _set_issues '[{"number":11,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}]'
    _install_stubs
}

teardown() {
    # `_run_child_suite` opens the child's stdin fifo on fd 8 and closes it
    # itself once the child bats run returns — but bash's `errexit` can abort
    # the helper between the `mkfifo`/`exec` that opens fd 8 and the `exec`
    # that closes it, leaving fd 8 open with no test-body assertion to blame.
    # This backstop closes it unconditionally, the same reason the two
    # cleanups below live here.
    exec 8>&- 2>/dev/null || true
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

# `_make_account` — a logged-in claude account directory, here with the gh-flow
# plugin installed: since #2209 the tick dispatches only once it has resolved
# the account's /gh-flow:wave entry point. The base fixture lives in
# ../test_helper.bash; pr_merge_train_cron.bats fixtures the same rule.
_make_account() {
    mkdir -p "$1/plugins"
    printf '{"claudeAiOauth":{"accessToken":"test"}}\n' >"$1/.credentials.json"
    printf '{"plugins":{"gh-flow@test":[{}]}}\n' >"$1/plugins/installed_plugins.json"
}

# _write_skill <account-dir> <dir-name> <frontmatter-body> — a flat skill copy
# the way the Agent Factory app installs one (#2209).
_write_skill() {
    mkdir -p "$1/skills/$2"
    printf -- '---\n%s\n---\n\n# body\n' "$3" >"$1/skills/$2/SKILL.md"
}

# The `gh search issues` result set for this test.
_set_issues() {
    printf '%s\n' "$1" >"${_WORK_DIR}/issues.json"
}

# The open-PR set `gh pr list` answers with, as a JSON object keyed by repo.
_set_open_prs() {
    printf '%s\n' "$1" >"${_WORK_DIR}/prs.json"
}

# The worktree path `_add_worktree <n>` creates — the same shape the tick's
# `gwt spawn` leaves behind (`wt/issue-<n>/<idx>`). The tick never removes one.
_worktree_path() {
    printf '%s/dotfiles-issue-%s-1' "${_WORK_DIR}" "$1"
}

# _set_tabs <status> <label>... — the running-now signal: one herdr tab per
# label inside the `dotfiles` workspace, each with one agent pane in the given
# `agent_status`. The pane's cwd is not what identifies the session: `herdr
# agent list` carries no agent-name field, so the tick recognises a session by
# its tab label (`issue-<n>` by hand, `iw-<repo>-issue-<n>` by the watcher) and the
# tab id the pane reports.
_set_tabs() {
    local _status="$1" _tabs="" _agents="" _sep="" _l _i=0
    shift
    for _l in "$@"; do
        _i=$((_i + 1))
        _tabs="${_tabs}${_sep}{\"agent_status\":\"${_status}\",\"label\":\"${_l}\",\"tab_id\":\"ws-existing:t${_i}\",\"workspace_id\":\"ws-existing\"}"
        _agents="${_agents}${_sep}{\"agent\":\"claude\",\"agent_status\":\"${_status}\",\"cwd\":\"${_REPO_DIR}\",\"foreground_cwd\":\"${_REPO_DIR}\",\"pane_id\":\"ws-existing:p${_i}\",\"tab_id\":\"ws-existing:t${_i}\",\"workspace_id\":\"ws-existing\"}"
        _sep=","
    done
    printf '{"id":"cli:workspace:list","result":{"workspaces":[{"label":"dotfiles","workspace_id":"ws-existing"}]}}\n' \
        >"${_WORK_DIR}/workspaces.json"
    printf '{"id":"cli:tab:list","result":{"tabs":[%s]}}\n' "${_tabs}" >"${_WORK_DIR}/tabs.json"
    printf '{"id":"cli:agent:list","result":{"agents":[%s]}}\n' "${_agents}" \
        >"${_WORK_DIR}/agents.json"
}

# A live watcher-opened session (`iw-dotfiles-issue-<n>` tab) for each given issue.
_set_live_agents() {
    _set_agents_with_status working "$@"
}

# The same sessions with an explicit `agent_status` (issue #1596). `idle`/`done`
# is the zombie tab: the session outlived its work and nobody closed the tab.
_set_agents_with_status() {
    local _status="$1" _labels=() _n
    shift
    for _n in "$@"; do
        _labels+=("iw-dotfiles-issue-${_n}")
    done
    _set_tabs "${_status}" "${_labels[@]}"
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

# The given issues are *running*. Kept as names the concurrency tests read
# naturally; all three are the tab+agent pair _set_tabs writes.
_set_running() {
    _set_agents_with_status working "$@"
}

_set_running_with_status() {
    _set_agents_with_status "$@"
}

# Replace the running set mid-test: dropping one issue frees exactly one slot.
_set_panes_for() {
    _set_agents_with_status working "$@"
}

# The rate-limit gate state file: _set_limit_state <strikes> <backoff_until>.
# Both fields are written as JSON *strings* because _iw_limit_write does, and
# the quoting is a back-compat guarantee rather than an accident — so the
# on-disk schema is spelled out here once instead of at every gate test.
_set_limit_state() {
    mkdir -p "${_STATE_DIR}"
    printf '{ "strikes": "%s", "backoff_until": "%s" }\n' "$1" "$2" >"${_LIMIT_FILE}"
}

# The saturation counter (#1606): _set_saturation_state <ticks> <last_notified>.
# Quoted strings for the same reason _set_limit_state quotes its two — the
# on-disk schema is a back-compat guarantee, so it is spelled out here once
# rather than restated at every test that seeds an episode already in progress.
_set_saturation_state() {
    mkdir -p "${_STATE_DIR}"
    printf '{ "ticks": "%s", "last_notified": "%s" }\n' "$1" "$2" >"${_SATURATION_FILE}"
}

# The zombie grace clock (#1596): one
# <repo>\t<number>\t<first-observed-stopped-epoch> line per pane seen
# stopped-on-a-closed-issue but not yet believed dead. The schema is spelled
# out here once for the same reason _set_limit_state spells out the gate file's.
# _seed_zombie_candidate <number> <epoch>
_seed_zombie_candidate() {
    mkdir -p "${_STATE_DIR}"
    printf 'acme/dotfiles\t%s\t%s\n' "$1" "$2" >>"${_ZOMBIE_FILE}"
}

# Wind every clock already on disk back past the grace window — a deterministic
# stand-in for the ten real minutes a second observation would otherwise need.
# Kept well inside the file's own prune horizon (6x the window) so the aged rows
# are still there for the next tick to read.
_age_zombie_candidates() {
    local _old
    _old=$(($(date +%s) - 1200))
    awk -F '\t' -v OFS='\t' -v t="${_old}" 'NF == 3 { $3 = t } 1' \
        "${_ZOMBIE_FILE}" >"${_ZOMBIE_FILE}.aged"
    mv "${_ZOMBIE_FILE}.aged" "${_ZOMBIE_FILE}"
}

# The rate-limit casualty list (#1604): one
# <repo>\t<number>\t<booked-epoch>\t<attempts> line per issue a strike killed.
# One column wider than the zombie clock's row — the fourth is the retry budget
# _IW_MAX_ATTEMPTS bounds. Spelled out here once, for the same reason
# _set_limit_state and _seed_zombie_candidate spell theirs out.
# _seed_casualty <number> <attempts>
_seed_casualty() {
    mkdir -p "${_STATE_DIR}"
    printf 'acme/dotfiles\t%s\t%s\t%s\n' "$1" "$(date +%s)" "${2:-0}" \
        >>"${_CASUALTY_FILE}"
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
#   GH_NO_SEARCH=1        gh predates `search` (apt gh 2.4.0, #1849): every
#                         `search ...` call, `--help` included, fails the way
#                         that gh does
#   GH_BLOCKED_BY         issue numbers whose blockedBy answer carries an OPEN
#                         blocker, space-separated (default: none)
#   GH_GRAPHQL_FAIL=1     `api graphql` errors (fail-open path)
#   GH_PRS_FILE           JSON object, repo -> open-PR array (default: none)
#   GH_PR_LIST_FAIL=1     `pr list` errors (fail-closed path, D-6)
#   GH_CLOSED_ISSUES      issue numbers `issue view` reports CLOSED for
#   GH_ISSUE_VIEW_FAIL=1  `issue view` errors (worktree is left in place)
#   GH_ISSUE_LABELS       label names (space-separated) on the issue a
#                         targeted run reads with `issue view --json ...`
_install_gh_stub() {
    cat >"${_BIN_DIR}/gh" <<'EOF'
#!/bin/sh
printf 'gh %s\n' "$*" >>"${CALL_LOG}"

if [ "$1" = "search" ] && [ "${GH_NO_SEARCH:-0}" = "1" ]; then
    printf 'unknown command "search" for "gh"\n' >&2
    exit 1
fi

case "$1 $2" in
"search issues")
    if [ "$3" = "--help" ]; then
        printf '  --json fields   Output JSON with the specified fields\n'
        exit 0
    fi
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
    _state=OPEN
    for _c in ${GH_CLOSED_ISSUES:-}; do
        [ "${_c}" != "$3" ] || _state=CLOSED
    done
    # The targeted run's read (`--json number,state,labels`): the issue as
    # JSON, labelled with GH_ISSUE_LABELS (space-separated names).
    case " $* " in
    *" number,state,labels "*)
        _labels=""
        for _l in ${GH_ISSUE_LABELS:-}; do
            _labels="${_labels:+${_labels},}{\"name\":\"${_l}\"}"
        done
        printf '{"number":%s,"state":"%s","labels":[%s]}\n' "$3" "${_state}" "${_labels}"
        exit 0
        ;;
    esac
    printf '%s\n' "${_state}"
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
#   HERDR_TABS_FILE           canned `tab list` JSON (default: no tabs)
#   HERDR_TAB_LIST_FAIL=1     `tab list` errors — the tick must hold
#   HERDR_TABS_AFTER_CREATE_FILE  `tab list` JSON served once a `tab create`
#                             has succeeded (a tab this tick opened)
#   HERDR_WORKSPACES_FILE     canned `workspace list` JSON (wins over the flag)
#   HERDR_WORKSPACE_EXISTS=1  `workspace list` already carries the repo label
#   HERDR_TAB_FAIL=1          `tab create` errors
#   HERDR_TAB_FAIL_AFTER=N    the first N `tab create` calls succeed, the rest
#                             error — lets one issue fail two different ways
#                             across its retry attempts
#   HERDR_START_FAIL=1        `agent start` errors, saying nothing at all — the
#                             unexplained failure, with no parsable error code
#   HERDR_START_NAME_TAKEN=1  `agent start` refuses because a live agent already
#                             holds the name (herdr's `agent_name_taken`), on
#                             stdout — a named failure that is not the pane race
#   HERDR_START_PANE_BUSY=N   the first N `agent start` calls lose the #1525
#                             race (`agent_pane_busy`), the rest succeed; a
#                             number above the attempt budget loses it every
#                             time. The document goes to **stderr**, which is
#                             where herdr really put it — a dispatcher that
#                             redirects that stream to /dev/null sees an
#                             unexplained failure instead of a named race.
#   HERDR_START_NOT_READY=1   `agent start` answers `agent_not_ready` (claude is
#                             stopped at a startup dialog); HERDR_PANE_TEXT is
#                             what `pane read` then shows
#   HERDR_TAB_RENAME_FAIL=1   `tab rename` errors during final prompt escalation
#   HERDR_NOTIFY_FAIL=1       `notification show` errors during final prompt escalation
#   HERDR_AGENT_STATUS        status reported by `agent get` (default: idle)
#   HERDR_AGENT_GET_FAIL=1    `agent get` returns agent_not_found and exits 1
#   HERDR_AGENT_MISSING       one agent name whose `agent get` answers
#                             agent_not_found for its first
#                             HERDR_AGENT_MISSING_TIMES (default 1) calls and
#                             normally thereafter — the pane that died during an
#                             outage and is findable again once redispatched
#                             (#1604). Unlike HERDR_AGENT_GET_FAIL this is
#                             scoped to one agent, so the rest of the tick still
#                             sees a healthy herdr.
#   HERDR_PROMPT_MODE         `agent prompt` behaviour (default: always ok)
#                               stall       every call stalled
#                               fail        every call a non-stall error
#   HERDR_PROMPT_FAIL_TIMES   first N `agent prompt` calls stall, then ok
#
# Every one of those failures writes its error document to **stderr** and only
# the success payload to stdout — the same split `agent start` already models
# above, measured on a live herdr (issue #1559). A dispatcher that sends that
# stream to /dev/null reads every failure as `(unknown)`, which is what made
# both recovery branches below dead code in production.
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
#   HERDR_READ_MODE=missing         every `agent read` answers agent_not_found
#                                   (the evidence capture has nothing to log,
#                                   and the settle poll never sees a frame)
#   HERDR_SETTLE_READ_SEQUENCE=A|B  bodies the *settle* read (#1570, the short
#                                   one) answers on successive calls per agent;
#                                   the last entry is held once the list runs
#                                   out, and `~` stands for an empty read. The
#                                   40-line evidence read (#1444) is a separate
#                                   call and is not scripted by this
#   HERDR_READ_AFTER_PROMPT=TEXT    the short read answers TEXT once that agent
#                                   has been prompted — the pane claude leaves
#                                   behind after it rejects the command (#2300)
#   HERDR_READ_AFTER_PROMPT_PAD=N   follow that TEXT with N blank/status lines,
#                                   and answer only the last `--lines` of the
#                                   result — a real 66-row pane where the
#                                   rejection sits far above the bottom (#2306)
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
"tab list")
    if [ "${HERDR_TAB_LIST_FAIL:-0}" = "1" ]; then
        printf '%s\n' '{"error":{"code":"internal","message":"no server"},"id":"cli:tab:list"}'
        exit 1
    fi
    if [ -f "${CALL_LOG}.tabcreated" ] && [ -f "${HERDR_TABS_AFTER_CREATE_FILE:-}" ]; then
        cat "${HERDR_TABS_AFTER_CREATE_FILE}"
    elif [ -f "${HERDR_TABS_FILE:-}" ]; then
        cat "${HERDR_TABS_FILE}"
    else
        printf '%s\n' '{"id":"cli:tab:list","result":{"tabs":[]}}'
    fi
    ;;
"workspace list")
    if [ -f "${HERDR_WORKSPACES_FILE:-}" ]; then
        cat "${HERDR_WORKSPACES_FILE}"
    elif [ "${HERDR_WORKSPACE_EXISTS:-0}" = "1" ]; then
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
    : >"${CALL_LOG}.tabcreated"
    if [ -n "${HERDR_TAB_FAIL_AFTER:-}" ]; then
        _n=$(_bump "${CALL_LOG}.tabcount")
        [ "${_n}" -gt "${HERDR_TAB_FAIL_AFTER}" ] && exit 1
    fi
    printf '%s\n' '{"id":"cli:tab:create","result":{"tab":{"tab_id":"ws-test-1:t9"},"pane":{"pane_id":"ws-test-1:p9"}}}'
    ;;
"tab close")
    printf '%s\n' '{"id":"cli:tab:close","result":{"ok":true}}'
    ;;
"tab rename")
    [ "${HERDR_TAB_RENAME_FAIL:-0}" = "1" ] && exit 1
    printf '%s\n' '{"id":"cli:tab:rename","result":{"ok":true}}'
    ;;
"notification show")
    [ "${HERDR_NOTIFY_FAIL:-0}" = "1" ] && exit 1
    printf '%s\n' '{"id":"cli:notification:show","result":{"ok":true}}'
    ;;
"agent start")
    [ "${HERDR_START_FAIL:-0}" = "1" ] && exit 1
    if [ "${HERDR_START_NAME_TAKEN:-0}" = "1" ]; then
        printf '%s\n' '{"error":{"code":"agent_name_taken","message":"agent name is already used; candidates: status=Idle"},"id":"cli:agent:start"}'
        exit 1
    fi
    if [ "${HERDR_START_NOT_READY:-0}" = "1" ]; then
        printf '%s\n' '{"error":{"code":"agent_not_ready","message":"agent is blocked during startup and is not ready for prompts"},"id":"cli:agent:start"}'
        exit 1
    fi
    if [ "${HERDR_START_PANE_BUSY:-0}" != "0" ]; then
        _n=$(_bump "${CALL_LOG}.startbusy")
        if [ "${_n}" -le "${HERDR_START_PANE_BUSY}" ]; then
            printf '%s\n' '{"error":{"code":"agent_pane_busy","message":"agent target pane ws-test-1:p9 is not an available shell"},"id":"cli:agent:start"}' >&2
            exit 1
        fi
    fi
    printf '%s\n' '{"id":"cli:agent:start","result":{"agent":{"agent_status":"idle","pane_id":"ws-test-1:p9"}}}'
    ;;
"pane read")
    printf '%s\n' "${HERDR_PANE_TEXT:-}"
    ;;
"pane send-keys")
    ;;
"agent get")
    if [ "${HERDR_AGENT_GET_FAIL:-0}" = "1" ]; then
        printf '%s\n' '{"error":{"code":"agent_not_found","message":"agent target not found"},"id":"cli:agent:get"}'
        exit 1
    fi
    if [ "${HERDR_AGENT_MISSING:-}" = "$3" ]; then
        _n=$(_bump "${CALL_LOG}.missing.$3")
        if [ "${_n}" -le "${HERDR_AGENT_MISSING_TIMES:-1}" ]; then
            printf '%s\n' '{"error":{"code":"agent_not_found","message":"agent target not found"},"id":"cli:agent:get"}'
            exit 1
        fi
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
    # Two callers, told apart by the `--lines` count they ask for: the 40-line
    # evidence capture (issue #1444) and the short settle-readiness poll
    # (issue #1570). `--format text` gives plain pane lines; an error comes
    # back as JSON on stdout with exit 0, which is what both callers have to
    # recognise and skip.
    if [ "${HERDR_READ_MODE:-ok}" = "missing" ]; then
        printf '%s\n' '{"error":{"code":"agent_not_found","message":"agent target not found"},"id":"cli:agent:read"}'
        exit 0
    fi
    if [ "$5" = "40" ]; then
        printf '> /gh-flow:wave 11\n5-hour limit reached. Resets at 3pm.\n'
        exit 0
    fi
    if [ -n "${HERDR_READ_AFTER_PROMPT:-}" ] && [ -f "${CALL_LOG}.prompt.$3" ]; then
        {
            printf '%s\n' "${HERDR_READ_AFTER_PROMPT}"
            _i=0
            while [ "${_i}" -lt "${HERDR_READ_AFTER_PROMPT_PAD:-0}" ]; do
                if [ $((_i % 2)) -eq 0 ]; then printf '\n'; else printf '  status line %s\n' "${_i}"; fi
                _i=$((_i + 1))
            done
        } | tail -n "$5"
        exit 0
    fi
    _seq="${HERDR_SETTLE_READ_SEQUENCE:-> claude ready}"
    _n=$(_bump "${CALL_LOG}.settleread.$3")
    _body=$(printf '%s' "${_seq}" | cut -d'|' -f"${_n}")
    [ -n "${_body}" ] || _body="${_seq##*|}"
    [ "${_body}" = "~" ] || printf '%s\n' "${_body}"
    ;;
"agent prompt")
    _bump "${CALL_LOG}.prompt.$3" >/dev/null
    if [ -n "${HERDR_PROMPT_FAIL_TIMES:-}" ]; then
        _n=$(_bump "${CALL_LOG}.promptcount")
        if [ "${_n}" -le "${HERDR_PROMPT_FAIL_TIMES}" ]; then
            printf '%s\n' '{"error":{"code":"agent_prompt_stalled","message":"no agent state change observed within 5000ms"},"id":"cli:agent:prompt"}' >&2
            exit 1
        fi
        printf '%s\n' '{"id":"cli:agent:prompt","result":{"ok":true}}'
        exit 0
    fi
    case "${HERDR_PROMPT_MODE:-ok}" in
    stall)
        printf '%s\n' '{"error":{"code":"agent_prompt_stalled","message":"no agent state change observed within 5000ms"},"id":"cli:agent:prompt"}' >&2
        exit 1
        ;;
    fail)
        printf '%s\n' '{"error":{"code":"agent_not_found","message":"agent target not found"},"id":"cli:agent:prompt"}' >&2
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

# Make the tick's one `mktemp` call fail. The script has exactly one (the
# herdr-stderr capture file in _iw_start_agent_retrying), so shadowing the
# binary for the tick's own PATH exercises that fallback and nothing else —
# bats' own mktemp calls run in the parent, before this stub is on PATH.
_install_failing_mktemp() {
    cat >"${_BIN_DIR}/mktemp" <<'EOF'
#!/bin/sh
printf 'mktemp %s\n' "$*" >>"${CALL_LOG}"
printf 'mktemp: failed to create file\n' >&2
exit 1
EOF
    chmod +x "${_BIN_DIR}/mktemp"
}

# `_install_sleep_stub` — the #1560 settle-wait stub. Lives in
# ../test_helper.bash; pr_merge_train_cron.bats installs the same one.

_install_stubs() {
    _install_gh_stub
    _install_herdr_stub
    _install_sleep_stub
    _install_ssh_stub
}

# ssh: only `ssh -G <host>` (cwd mode's alias resolution, #2243), so the
# developer's own ~/.ssh/config cannot steer the tests. `gh-work` is a
# multi-account alias for github.com; github.com itself goes through the
# port-443 `ssh.github.com` (#2247); every other host resolves to itself.
_install_ssh_stub() {
    cat >"${_BIN_DIR}/ssh" <<'EOF2'
#!/bin/sh
[ "$1" = "-G" ] || exit 255
case "$2" in
gh-work) printf 'user git\nhostname github.com\n' ;;
github.com) printf 'user git\nhostname ssh.github.com\nport 443\n' ;;
*) printf 'user git\nhostname %s\n' "$2" ;;
esac
EOF2
    chmod +x "${_BIN_DIR}/ssh"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Run "$@" — an invocation ending in `bash "${SCRIPT}" ...` — with stdin and
# bats' TAP fd closed. Load-bearing, not tidiness (issue #1473), the same fd
# hazard `_hold_lock` documents, one layer out:
#
#   </dev/null  the tick shells out to the `gh` stub, whose `api graphql`
#               branch drains stdin the way the real `gh api` does. Without
#               this the stub inherits *bats' own* stdin, and whenever that is
#               a pipe whose writer never closes (an agent harness, `ssh`
#               without `-n`, any `cmd | bats` wrapper) the `cat` blocks
#               forever: the tick never exits, `run` never returns and the test
#               prints no TAP line at all — the whole run hangs with nothing to
#               point at. The stub already excused a tty (PR #1469), which
#               covered only the interactive case. The tick is a cron job, so
#               /dev/null is also what it gets in production.
#   3>&-        bats streams TAP on fd 3 and will not finish a test until every
#               inheritor closes it. Closing it for the tick means a child that
#               outlives the script cannot freeze the run into a result-less
#               hang; the worst it can do is fail loudly.
#
# Every call site that invokes the tick script goes through this — not a
# per-call-site `</dev/null 3>&-` — so a future call site cannot silently drop
# the fix by omission.
_run_script() {
    # From a non-repo dir by default: inside a checkout with an origin remote
    # the tick switches to cwd mode (#2243). _RUN_DIR opts a test into a repo.
    cd "${_RUN_DIR:-${_WORK_DIR}}" || return 1
    "$@" </dev/null 3>&-
}

# Run one tick with the stubs on PATH and an isolated XDG_STATE_HOME.
#
#   _run_tick [-u VAR ...] [VAR=VALUE ...] [-- script-flag ...]
#
# `-u VAR` pairs must come first — `env` only parses options ahead of the first
# NAME=VALUE. The VAR=VALUE assignments are appended after the defaults, and
# `env` applies assignments left to right, so a test can override any of them
# (PATH included) without restating the whole sandbox.
#
# The concurrency caps are pinned here for the same reason as the sleeps: a tick
# test asserts a *boundary*, not whichever numbers the script currently ships.
# Pinning them once keeps the whole suite from moving every time the shipped
# defaults are tuned (#1579 raised them). The defaults themselves are asserted
# behaviorally, in exactly one place — the `--help` test.
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

    run _run_script env \
        -u IW_EXCLUDE_LABELS \
        "${_unset[@]}" \
        "PATH=${_BIN_DIR}:${PATH}" \
        "CALL_LOG=${_LOG}" \
        "GH_ISSUES_FILE=${_WORK_DIR}/issues.json" \
        "GH_PRS_FILE=${_WORK_DIR}/prs.json" \
        "HERDR_AGENTS_FILE=${_WORK_DIR}/agents.json" \
        "HERDR_TABS_FILE=${_WORK_DIR}/tabs.json" \
        "HERDR_WORKSPACES_FILE=${_WORK_DIR}/workspaces.json" \
        "HERDR_TABS_AFTER_CREATE_FILE=${_WORK_DIR}/tabs-after-create.json" \
        "IW_WATCHED_REPOS=${_WATCH_FILE}" \
        "IW_EXCLUDE_LABELS_FILE=${_LABEL_FILE}" \
        "XDG_STATE_HOME=${_STATE_HOME}" \
        "IW_IDLE_POLL_SLEEP=0" \
        "IW_STALL_RECOVER_SLEEP=0" \
        "IW_START_RETRY_SLEEP=0" \
        "IW_LIMIT_OBSERVE_SLEEP=0" \
        "IW_MAX_PER_REPO=3" \
        "IW_MAX_CONCURRENT=7" \
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
        uname wc chmod find id stty locale python3; do
        _skip=0
        for _p in "$@"; do
            [ "${_b}" != "${_p}" ] || _skip=1
        done
        [ "${_skip}" -eq 0 ] || continue
        _p=$(command -v "${_b}" 2>/dev/null) || continue
        # A pyenv/asdf shim is a script that needs its manager on PATH; link
        # the interpreter it resolves to instead.
        [ "${_b}" != python3 ] ||
            _p=$(python3 -c 'import os, sys; print(os.path.realpath(sys.executable))') || continue
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

# Run the @test cases fed on stdin as a throwaway suite in a *child* bats, and
# leave that child's exit status and TAP output in `$status` / `$output`.
#
# This is how the "a red test reports red instead of hanging" guarantee becomes
# a test: bats has no native "expect this case to fail", so the subject has to
# be a bats run of its own. The child suite is this file's own helper section —
# everything above the first `@test` — so it inherits the real setup, teardown
# and stubs, and any future change to them is exercised here too.
#
# Two things make the child run the *hanging* configuration (issue #1473):
#
#   fd 8      a fifo opened read-write, so the child's stdin is a pipe with a
#             live writer that never sends EOF — the shape an agent harness,
#             `ssh` without `-n` or a `cmd | bats` wrapper hands to bats, and
#             the shape that used to leave a stdin-draining stub blocked
#             forever inside the tick. Opening it `<>` from this process is
#             what keeps the reproduction free of a background writer that
#             would itself have to be reaped.
#   watchdog  the outer bound. A regression must surface as a bounded 124, not
#             as a hang that takes the whole suite down with it — every
#             assertion below therefore refutes 124 explicitly.

# The bound a child bats run is held to. A child here runs one case and comes
# back in well under a second even counting bats' own startup, so this is a
# wide margin — and still short enough that a returning hang costs CI seconds
# rather than the minutes the old 60 would have.
_CHILD_SUITE_TIMEOUT=15

# The bound, without `timeout(1)`. That binary is coreutils, and stock macOS
# ships neither it nor a `gtimeout` on PATH — gating on it meant these cases
# skipped wholesale on a platform this repo supports, quietly retiring the one
# guarantee they exist to hold. So the bound is bash's own.
#
# The child runs as a background job under `set -m`, which makes it a process
# *group* leader; a watchdog kills that whole group once the bound elapses.
# The group, not the pid, is the point: a hung bats has grandchildren — issue
# #1473 is exactly a grandchild blocked on a read — and killing only the
# immediate child would leave them alive holding the fds the caller waits on.
#
# The child's real exit code reaches us only through a file it writes itself,
# just before exiting. So a missing file *is* "the watchdog got there first",
# with no need to tell a killed child's 137 from an honest one.
_bounded_bats() {
    local _out="${_WORK_DIR}/child.out"
    local _rc="${_WORK_DIR}/child.rc"
    rm -f "${_out}" "${_rc}" "${_rc}.part"

    local _monitor=0
    case $- in *m*) _monitor=1 ;; esac
    set -m

    # bats' `run` executes inside a command substitution, and POSIX says the
    # stdin of an asynchronous list with no explicit redirection is `/dev/null`
    # — `set -m` does not change that. Without `<&9` here, the child below runs
    # on `/dev/null` instead of the fifo `_run_script` handed us, and every
    # never-EOF-stdin regression case in this file passes for the wrong reason.
    exec 9<&0
    {
        "$@" >"${_out}" 2>&1 <&9
        printf '%s\n' "$?" >"${_rc}.part"
        mv -f "${_rc}.part" "${_rc}"
    } &
    local _child=$!

    # The watchdog holds no stdout, no stdin and no fd 3. An inherited write
    # end here would outlive the kill and stall the caller's capture — the
    # same trap the orphaned `sleep` in `_hold_lock` documents.
    #
    # The pid kill after the group kill is the belt to that brace: should
    # `set -m` ever not take, `-${_child}` names no group and the `wait` below
    # would never return. A live leader owns its own pgid, so the negative
    # form can only ever reach this job's own tree.
    (
        sleep "${_CHILD_SUITE_TIMEOUT}"
        kill -9 -"${_child}" 2>/dev/null
        kill -9 "${_child}" 2>/dev/null
    ) >/dev/null 2>&1 <&- 3>&- &
    local _watchdog=$!

    [ "${_monitor}" -eq 1 ] || set +m

    wait "${_child}" >/dev/null 2>&1

    # Whichever of the two got there first, the other one goes now — by group
    # as well, or the watchdog's `sleep` would outlive the subshell holding it.
    kill -9 -"${_watchdog}" >/dev/null 2>&1
    kill -9 "${_watchdog}" >/dev/null 2>&1
    wait "${_watchdog}" >/dev/null 2>&1

    cat "${_out}" 2>/dev/null

    [ -f "${_rc}" ] || return 124
    return "$(cat "${_rc}")"
}

_run_child_suite() {
    local _dir="${_WORK_DIR}/probe"
    local _file="${_dir}/probe.bats"
    mkdir -p "${_dir}"

    # `load '../test_helper'` resolves against the *child* file's directory, so
    # it has to be re-pointed at the real tree before the copy leaves it.
    #
    # Invariant this `sed` rests on: every `@test` in this file comes *after*
    # the helper section, so cutting from the first one takes the helpers and
    # nothing else. Move a case above them and the child suite silently
    # swallows it.
    sed -e "/^@test /,\$d" \
        -e "s|^load '../test_helper'$|load '${DOTFILES_ROOT}/tests/bats/test_helper'|" \
        "${BATS_TEST_FILENAME}" >"${_file}"
    cat >>"${_file}"

    mkfifo "${_dir}/stdin"
    exec 8<>"${_dir}/stdin"
    # The child must not inherit the runner's BATS_TEST_TIMEOUT (#2054): its
    # per-test countdown hung the child under this never-EOF stdin (all three
    # red-assertion cases "hung" only when tests/test exported it), and the
    # orphaned countdown then held this file's own TAP pipe for the full 300s.
    # _bounded_bats' own watchdog already bounds the child.
    run _bounded_bats env -u BATS_TEST_TIMEOUT \
        "${DOTFILES_ROOT}/tests/bats/lib/bats-core/bin/bats" "${_file}" <&8
    exec 8>&-
}

# `$status` 124 is `_bounded_bats`' "the child never finished" — the exact
# defect these cases exist to catch, so it gets its own message rather than
# being folded into a generic status assertion.
_assert_not_hung() {
    [ "${status}" -ne 124 ] || fail "the child bats run hung (timeout): $1"
}

# ---------------------------------------------------------------------------
# Syntax & help
# ---------------------------------------------------------------------------

@test "avatar_issue_watcher: bash syntax check" {
    run bash -n "${SCRIPT}"
    assert_success
}

@test "avatar_issue_watcher: --help exits 0 and prints usage" {
    run bash "${SCRIPT}" --help
    assert_success
    assert_output --partial "Usage: avatar_issue_watcher.sh"
    assert_output --partial "--cwd"
    assert_output --partial "--dry-run"
}

@test "avatar_issue_watcher: --help documents the crontab registration example" {
    # #1579 codex review: the example must match the shipped cron-jobs.json
    # cadence (*/4), or a reader following --help literally installs a
    # cron entry running more slowly than the manifest's own default.
    run bash "${SCRIPT}" --help
    assert_success
    assert_output --partial "*/4 * * * *"
    assert_output --partial "avatar_issue_watcher.sh"
    assert_output --partial "cron.log"
}

@test "avatar_issue_watcher: --help documents the watch list and its override" {
    run bash "${SCRIPT}" --help
    assert_success
    assert_output --partial "/.avatars/issue-watcher/watched-repos.json"
    refute_output --partial ".agent-factory"
    assert_output --partial "IW_WATCHED_REPOS"
}

@test "avatar_issue_watcher: --help documents the filters and the per-tick cap" {
    run bash "${SCRIPT}" --help
    assert_success
    assert_output --partial "gh search issues"
    assert_output --partial "default: wontfix,not-implement,TODO,manual"
    assert_output --partial "IW_EXCLUDE_LABELS_FILE"
    assert_output --partial "blockedBy"
    assert_output --partial "at most 1 issue(s) per tick"
}

@test "avatar_issue_watcher: --help documents the concurrency limits and the cursor" {
    # Shipped defaults (5/3 since #1627); unset any operator override so the
    # assertion pins the defaults, not the caller's environment.
    run env -u IW_MAX_CONCURRENT -u IW_MAX_PER_REPO bash "${SCRIPT}" --help
    assert_success
    assert_output --partial "5 running in total"
    assert_output --partial "3 in one repo"
    assert_output --partial "round-robin"
    assert_output --partial "select.json"
}

@test "avatar_issue_watcher: --help documents the two tab labels and the manual cleanup" {
    run bash "${SCRIPT}" --help
    assert_success
    assert_output --partial "iw-<repo>-issue-<N>"
    assert_output --partial "issue-<N>"
    refute_output --partial "a worktree is collected"
    refute_output --partial "in an issue's worktree"
}

@test "avatar_issue_watcher: --help documents the rate-limit gate and its state file" {
    run bash "${SCRIPT}" --help
    assert_success
    assert_output --partial "rate-limit gate"
    assert_output --partial "rate-limit.json"
    assert_output --partial "30m"
}

@test "avatar_issue_watcher: --help documents the saturation alert and its state file" {
    run bash "${SCRIPT}" --help
    assert_success
    assert_output --partial "saturation alert"
    assert_output --partial "saturation.json"
    assert_output --partial "20 consecutive ticks"
    assert_output --partial "3h"
}

@test "avatar_issue_watcher: --help documents --status" {
    run bash "${SCRIPT}" --help
    assert_success
    assert_output --partial "--status"
}

@test "avatar_issue_watcher: -h is equivalent to --help" {
    run bash "${SCRIPT}" -h
    assert_success
    assert_output --partial "Usage: avatar_issue_watcher.sh"
}

@test "avatar_issue_watcher: bare 'help' is equivalent to --help" {
    run bash "${SCRIPT}" help
    assert_success
    assert_output --partial "Usage: avatar_issue_watcher.sh"
}

@test "avatar_issue_watcher: unknown option exits non-zero" {
    run bash "${SCRIPT}" --nope
    assert_failure
    assert_output --partial "Unknown option"
}

@test "avatar_issue_watcher: --cwd without a value fails" {
    run bash "${SCRIPT}" --cwd
    assert_failure
    assert_output --partial "--cwd requires a PATH"
}

# ---------------------------------------------------------------------------
# The dispatch path (#1440)
# ---------------------------------------------------------------------------

@test "avatar_issue_watcher: an assigned issue is tabbed and prompted" {
    _run_tick
    assert_success
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
    _assert_logged "tab create --workspace"
    _assert_logged "agent start iw-dotfiles-issue-11 --kind claude --pane ws-test-1:p9"
    _assert_logged "agent prompt iw-dotfiles-issue-11 /gh-flow:wave 11"
}

@test "avatar_issue_watcher: the prompt is the slash command, not a subagent instruction" {
    _run_tick
    assert_success
    _assert_logged "/gh-flow:wave 11"
    # The pre-#1440 prompt told the receiving session to run another agent,
    # which is the ambiguity #1394 was about. Nothing may reintroduce it.
    _refute_logged "issue-watcher:dispatcher"
    _refute_logged "Agent 도구"
}

@test "avatar_issue_watcher: the dispatched pane runs claude with --dangerously-skip-permissions" {
    _run_tick
    assert_success
    _assert_logged "agent start iw-dotfiles-issue-11 --kind claude --pane ws-test-1:p9 -- --dangerously-skip-permissions"
}

@test "avatar_issue_watcher: the tab is labelled iw-<repo>-issue-<N>, apart from a hand-made issue-<N>" {
    _run_tick
    assert_success
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
    _refute_logged "--label #11"
    _refute_logged "--label iw-issue-11 "
}

@test "avatar_issue_watcher: the tab label is the herdr agent name (_iw_agent_name)" {
    # One SSOT for both: the repo slug in the label is the one the agent name
    # carries, so _iw_live_agents can attribute the tab to exactly that repo.
    _run_tick
    assert_success
    local _name
    _name=$(bash -c '. "$1"; herdr_agent_name iw acme/dotfiles issue-11' _ \
        "${DOTFILES_ROOT}/shell-common/lib/herdr_agent_name.sh")
    [ "${_name}" = "iw-dotfiles-issue-11" ]
    _assert_logged "--label ${_name} --no-focus"
    _assert_logged "agent start ${_name} --kind claude"
}

# ---------------------------------------------------------------------------
# The issue worktree, acquired before the tab (#2281)
# ---------------------------------------------------------------------------

# Every `wt/issue-<1>/*` branch the fixture repo has a worktree on, one per line.
_issue_worktree_branches() {
    git -C "${_REPO_DIR}" worktree list --porcelain |
        awk -v p="branch refs/heads/wt/issue-$1/" 'index($0, p) == 1'
}

@test "avatar_issue_watcher: the tab opens on a gwt-spawned issue worktree, not the checkout" {
    local _main_branch
    _main_branch=$(git -C "${_REPO_DIR}" symbolic-ref --short HEAD)
    _run_tick
    assert_success
    # gwt spawn's layout: <parent>/<project>-issue-<N>-<k> on wt/issue-<N>/<k>.
    _assert_logged "tab create --workspace ws-test-1 --cwd $(_worktree_path 11) --label iw-dotfiles-issue-11"
    _refute_logged "--cwd ${_REPO_DIR} --label iw-"
    _assert_logged "agent prompt iw-dotfiles-issue-11 /gh-flow:wave 11"
    [ "$(_issue_worktree_branches 11)" = "branch refs/heads/wt/issue-11/1" ]
    # The main checkout is left exactly as it was: same branch, clean tree.
    [ "$(git -C "${_REPO_DIR}" symbolic-ref --short HEAD)" = "${_main_branch}" ]
    [ -z "$(git -C "${_REPO_DIR}" status --porcelain)" ]
}

@test "avatar_issue_watcher: an existing wt/issue-<N> worktree is reused, not duplicated" {
    _add_worktree 11
    _run_tick
    assert_success
    _assert_logged "--cwd $(_worktree_path 11) --label iw-dotfiles-issue-11"
    [ "$(_issue_worktree_branches 11 | wc -l)" -eq 1 ]
    [ ! -e "${_WORK_DIR}/dotfiles-issue-11-2" ]
}

@test "avatar_issue_watcher: of several issue worktrees the highest index is reused" {
    _add_worktree 11
    git -C "${_REPO_DIR}" worktree add -q -b wt/issue-11/3 "${_WORK_DIR}/dotfiles-issue-11-3" HEAD
    # Issue 110 shares the prefix `issue-11` and must not be mistaken for it.
    git -C "${_REPO_DIR}" worktree add -q -b wt/issue-110/9 "${_WORK_DIR}/dotfiles-issue-110-9" HEAD
    _run_tick
    assert_success
    _assert_logged "--cwd ${_WORK_DIR}/dotfiles-issue-11-3 --label iw-dotfiles-issue-11"
}

@test "avatar_issue_watcher: a half-built issue worktree (empty index) is not reused" {
    # What a spawn that failed after `worktree add --no-checkout` leaves behind.
    git -C "${_REPO_DIR}" worktree add -q --no-checkout -b wt/issue-11/1 "$(_worktree_path 11)" HEAD
    git -C "$(_worktree_path 11)" read-tree --empty
    _run_tick
    assert_success
    _assert_logged "--cwd ${_WORK_DIR}/dotfiles-issue-11-2 --label iw-dotfiles-issue-11"
}

@test "avatar_issue_watcher: a second tick reuses the worktree the first one spawned" {
    _run_tick
    assert_success
    _set_tabs idle
    : >"${_LOG}"
    _run_tick
    assert_success
    _assert_logged "--cwd $(_worktree_path 11) --label iw-dotfiles-issue-11"
    [ "$(_issue_worktree_branches 11 | wc -l)" -eq 1 ]
}

@test "avatar_issue_watcher: failed attempts share one worktree and leave it in place" {
    _run_tick HERDR_TAB_FAIL=1
    assert_output --partial "Giving up on acme/dotfiles#11 after 3 attempts."
    [ "$(_log_count 'tab create')" -eq 3 ]
    [ "$(_log_count "--cwd $(_worktree_path 11) ")" -eq 3 ]
    # Spawned once, outside the retry loop, and not removed by the cleanup.
    [ "$(_issue_worktree_branches 11)" = "branch refs/heads/wt/issue-11/1" ]
    [ -d "$(_worktree_path 11)" ]
}

@test "avatar_issue_watcher: no worktree means no dispatch, never the main checkout" {
    # A file where gwt spawn would put the worktree makes `git worktree add` fail.
    : >"$(_worktree_path 11)"
    _run_tick
    assert_output --partial "Not dispatching acme/dotfiles#11 — could not acquire a wt/issue-11 worktree"
    _refute_logged "tab create"
    _refute_logged "agent start"
    [ -z "$(_issue_worktree_branches 11)" ]
}

@test "avatar_issue_watcher: a worktree path on the watch list dispatches from its main checkout" {
    _add_worktree 7
    _write_watch_file '[{"repo":"acme/dotfiles","path":"'"$(_worktree_path 7)"'","host":"github.com"}]'
    _run_tick
    assert_success
    _assert_logged "--cwd $(_worktree_path 11) --label iw-dotfiles-issue-11"
    # The workspace is the main checkout's, labelled by its basename.
    _assert_logged "--label dotfiles"
}

@test "avatar_issue_watcher: cwd mode inside a worktree records the main checkout" {
    _cwd_repo "https://github.com/acme/dotfiles.git"
    _add_worktree 7
    _RUN_DIR="$(_worktree_path 7)"
    _run_tick "IW_WATCHED_REPOS=${_WORK_DIR}/nope.json" -- --dry-run
    assert_success
    assert_output --partial "acme/dotfiles#11  (${_REPO_DIR}, github.com)"
}

@test "avatar_issue_watcher: cwd mode inside a worktree dispatches into the issue worktree" {
    _cwd_repo "https://github.com/acme/dotfiles.git"
    _add_worktree 7
    _RUN_DIR="$(_worktree_path 7)"
    _run_tick "IW_WATCHED_REPOS=${_WORK_DIR}/nope.json"
    assert_success
    _assert_logged "--cwd $(_worktree_path 11) --label iw-dotfiles-issue-11"
    [ "$(_issue_worktree_branches 11)" = "branch refs/heads/wt/issue-11/1" ]
}

@test "avatar_issue_watcher: a hand-made issue-<N> tab with an agent counts as running" {
    _set_tabs working issue-11
    _run_tick
    assert_success
    assert_output --partial "acme/dotfiles#11 — already running"
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: a watcher-made iw-<repo>-issue-<N> tab with an agent counts as running" {
    _set_tabs working iw-dotfiles-issue-11
    _run_tick
    assert_success
    assert_output --partial "acme/dotfiles#11 — already running"
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: a legacy iw-issue-<N> tab still counts as running" {
    # Tabs opened before the label carried the repo are read like a hand-made
    # issue-<N> tab, so an upgrade does not double-dispatch a live session.
    _set_tabs working iw-issue-11
    _run_tick
    assert_success
    assert_output --partial "acme/dotfiles#11 — already running"
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: an issue tab with no agent in it does not count" {
    _set_tabs working issue-11
    printf '%s\n' '{"id":"cli:agent:list","result":{"agents":[]}}' >"${_WORK_DIR}/agents.json"
    _run_tick
    assert_success
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
}

@test "avatar_issue_watcher: only an exact issue-<N> label counts" {
    _set_tabs working issue-110 xissue-11 issue-11-notes iw-issue-1 \
        iw-dotfiles-issue-110 iw-dotfiles-issue-11-x iw-other-issue-11 xiw-dotfiles-issue-11
    _run_tick
    assert_success
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
}

@test "avatar_issue_watcher: an issue tab in another repo's workspace does not count" {
    _set_tabs working issue-11
    printf '{"id":"cli:workspace:list","result":{"workspaces":[{"label":"elsewhere","workspace_id":"ws-existing"}]}}\n' \
        >"${_WORK_DIR}/workspaces.json"
    _run_tick
    assert_success
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
}

@test "avatar_issue_watcher: one issue tab in a workspace shared by three repos counts once" {
    # Three repos on one path share one workspace (_iw_workspace_label). The
    # watcher tab names its repo, so it is one session, not one per repo.
    _write_watch_file '[{"repo":"acme/dotfiles","path":"'"${_REPO_DIR}"'","host":"github.com"},
      {"repo":"acme/two","path":"'"${_REPO_DIR}"'","host":"github.com"},
      {"repo":"acme/three","path":"'"${_REPO_DIR}"'","host":"github.com"}]'
    _set_tabs working iw-dotfiles-issue-12
    _run_tick "IW_MAX_CONCURRENT=2"
    assert_success
    refute_output --partial "Holding this tick"
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
}

@test "avatar_issue_watcher: one hand-made issue tab shared by three repos counts once" {
    # A hand-made issue-12 tab names no repo, so every sharing repo gets a row
    # for it. Counted per row it read as 3 sessions and held a tick capped at 2.
    _write_watch_file '[{"repo":"acme/dotfiles","path":"'"${_REPO_DIR}"'","host":"github.com"},
      {"repo":"acme/two","path":"'"${_REPO_DIR}"'","host":"github.com"},
      {"repo":"acme/three","path":"'"${_REPO_DIR}"'","host":"github.com"}]'
    _set_tabs working issue-12
    _run_tick "IW_MAX_CONCURRENT=2"
    assert_success
    refute_output --partial "Holding this tick"
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
}

# Two repos on one path (one shared workspace), each with an issue #12.
_shared_two_repos() {
    _write_watch_file '[{"repo":"acme/dotfiles","path":"'"${_REPO_DIR}"'","host":"github.com"},
      {"repo":"acme/two","path":"'"${_REPO_DIR}"'","host":"github.com"}]'
}

@test "avatar_issue_watcher: another sharing repo's watcher tab does not hold the same issue number" {
    _shared_two_repos
    _set_issues '[{"number":12,"repository":{"nameWithOwner":"acme/two"},"labels":[]}]'
    _set_tabs working iw-dotfiles-issue-12
    _run_tick
    assert_success
    refute_output --partial "acme/two#12 — already running"
    _assert_logged "--label iw-two-issue-12 --no-focus"
}

@test "avatar_issue_watcher: a sharing repo's own watcher tab holds its issue" {
    _shared_two_repos
    _set_issues '[{"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}]'
    _set_tabs working iw-dotfiles-issue-12
    _run_tick
    assert_success
    assert_output --partial "acme/dotfiles#12 — already running"
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: a hand-made issue tab holds the number in every sharing repo" {
    _shared_two_repos
    _set_issues '[{"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":12,"repository":{"nameWithOwner":"acme/two"},"labels":[]}]'
    _set_tabs working issue-12
    _run_tick "IW_DISPATCH_PER_TICK=2"
    assert_success
    assert_output --partial "acme/dotfiles#12 — already running"
    assert_output --partial "acme/two#12 — already running"
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: a tab with one working agent among stopped ones stays live" {
    # Stopped means *every* agent in the tab stopped. One still working keeps
    # the session live even on a closed issue past its grace window.
    _set_tabs working iw-dotfiles-issue-21
    printf '%s\n' '{"id":"cli:agent:list","result":{"agents":[{"agent_status":"idle","pane_id":"ws-existing:p1","tab_id":"ws-existing:t1","workspace_id":"ws-existing"},{"agent_status":"working","pane_id":"ws-existing:p2","tab_id":"ws-existing:t1","workspace_id":"ws-existing"},{"agent_status":"done","pane_id":"ws-existing:p3","tab_id":"ws-existing:t1","workspace_id":"ws-existing"}]}}' \
        >"${_WORK_DIR}/agents.json"
    _seed_zombie_candidate 21 "$(($(date +%s) - 1200))"
    _run_tick "IW_MAX_CONCURRENT=1" "GH_CLOSED_ISSUES=21"
    assert_success
    assert_output --partial "Holding this tick — 1 issue session(s) already running"
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: a dispatched issue whose tab survives is not dispatched again" {
    _run_tick "HERDR_STATUS_AFTER_PROMPT=working"
    assert_success
    assert_output --partial "Dispatched to iw-dotfiles-issue-11"
    [ "$(_log_count 'tab create')" -eq 1 ]

    # The tab the first tick opened is still there with its agent.
    _set_live_agents 11
    _run_tick "HERDR_STATUS_AFTER_PROMPT=working"
    assert_success
    assert_output --partial "acme/dotfiles#11 — already running"
    [ "$(_log_count 'tab create')" -eq 1 ]
}

# Shapes captured from a live herdr server (2026-10-23), trimmed to the fields
# the tick reads plus a few it ignores; ids, paths and session ids are fake.
_real_herdr_fixture() {
    printf '%s\n' '{"id":"cli:workspace:list","result":{"type":"workspace_list","workspaces":[{"active_tab_id":"w2A:t3R","agent_status":"idle","focused":true,"label":"dotfiles","number":3,"pane_count":2,"tab_count":2,"workspace_id":"w2A"}]}}' \
        >"${_WORK_DIR}/workspaces.json"
    printf '%s\n' '{"id":"cli:tab:list","result":{"tabs":[{"agent_status":"working","focused":false,"label":"review","number":119,"pane_count":1,"tab_id":"w2A:t3Q","workspace_id":"w2A"},{"agent_status":"idle","focused":true,"label":"'"$1"'","number":120,"pane_count":1,"tab_id":"w2A:t3R","workspace_id":"w2A"}]}}' \
        >"${_WORK_DIR}/tabs.json"
    printf '%s\n' '{"id":"cli:agent:list","result":{"agents":[{"agent":"claude","agent_session":{"agent":"claude","kind":"id","source":"herdr:claude","value":"00000000-0000-0000-0000-000000000001"},"agent_status":"working","cwd":"/fake/dotfiles","focused":false,"foreground_cwd":"/fake/dotfiles","pane_id":"w2A:p3Q","revision":4,"state_change_seq":303,"tab_id":"'"$2"'","workspace_id":"w2A"},{"agent":"claude","agent_session":{"agent":"claude","kind":"id","source":"herdr:claude","value":"00000000-0000-0000-0000-000000000002"},"agent_status":"idle","cwd":"/fake/dotfiles","focused":true,"foreground_cwd":"/fake/dotfiles","name":"iw-dotfiles-issue-1774","pane_id":"w2A:p3R","revision":4,"state_change_seq":305,"tab_id":"'"$3"'","workspace_id":"w2A"}],"type":"agent_list"}}' \
        >"${_WORK_DIR}/agents.json"
}

@test "avatar_issue_watcher: real herdr shapes join an iw-issue tab to its agent" {
    _real_herdr_fixture iw-dotfiles-issue-11 w2A:t3Q w2A:t3R
    _run_tick
    assert_success
    assert_output --partial "acme/dotfiles#11 — already running"
    refute_output --partial "matches no agent"
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: agents matching no listed tab warn that the issue tabs read as idle" {
    # Schema drift: the issue tab is there, but no agent's tab_id names any
    # listed tab. The tick still reads that as nothing running (unchanged) —
    # the warning is how a lifted cap gets noticed.
    _real_herdr_fixture iw-dotfiles-issue-11 drift:1 drift:2
    _run_tick
    assert_success
    assert_output --partial "matches no agent"
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
}

@test "avatar_issue_watcher: ordinary tabs alone raise no tab/agent mismatch warning" {
    _real_herdr_fixture review w2A:t3Q w2A:t3R
    _run_tick
    assert_success
    refute_output --partial "matches no agent"
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
}

@test "avatar_issue_watcher: an unreachable herdr tab list holds the tick" {
    _run_tick "HERDR_TAB_LIST_FAIL=1"
    assert_success
    assert_output --partial "holding this tick"
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: a closed issue's worktree is never touched" {
    # The worktree belongs to /gh-flow:wave and the user removes it after
    # review; the session's pane stands in the checkout root, so "no agent in
    # the worktree" would read as abandoned while the user is still reading it.
    _add_worktree 21
    printf 'review notes\n' >"$(_worktree_path 21)/notes.txt"
    _run_tick "GH_CLOSED_ISSUES=21"
    assert_success
    refute_output --partial "Collected worktree"
    run git -C "${_REPO_DIR}" worktree list --porcelain
    assert_output --partial "wt/issue-21/"
    [ -f "$(_worktree_path 21)/notes.txt" ]
}

@test "avatar_issue_watcher: repos sharing one path share one workspace" {
    # gh-verify-skills, gh-flow-skills ... all live under ~/para/project/skills:
    # one project directory, so one herdr workspace named after it.
    _write_watch_file '[{"repo":"acme/dotfiles","path":"'"${_REPO_DIR}"'","host":"github.com"},
      {"repo":"acme/other","path":"'"${_REPO_DIR}"'","host":"github.com"}]'
    _set_issues '[{"number":11,"repository":{"nameWithOwner":"acme/other"},"labels":[]}]'
    _run_tick
    assert_success
    _assert_logged "workspace create --cwd ${_REPO_DIR} --label dotfiles --no-focus"
    _refute_logged "--label acme/other"
}

@test "avatar_issue_watcher: repos at different paths with one leaf name still split" {
    _make_repo "${_WORK_DIR}/b/dotfiles"
    _write_watch_file '[{"repo":"acme/dotfiles","path":"'"${_REPO_DIR}"'","host":"github.com"},
      {"repo":"other/dotfiles","path":"'"${_WORK_DIR}"'/b/dotfiles","host":"github.com"}]'
    _run_tick
    assert_success
    _assert_logged "workspace create --cwd ${_REPO_DIR} --label acme/dotfiles --no-focus"
}

@test "avatar_issue_watcher: an existing workspace with the repo label is reused" {
    _run_tick "HERDR_WORKSPACE_EXISTS=1"
    assert_success
    _assert_logged "tab create --workspace ws-existing"
    _refute_logged "workspace create"
}

@test "avatar_issue_watcher: a missing workspace is created against the checkout" {
    _run_tick
    assert_success
    _assert_logged "workspace create --cwd ${_REPO_DIR} --label dotfiles --no-focus"
}

@test "avatar_issue_watcher: the tick reports how many issues it dispatched" {
    _run_tick
    assert_success
    assert_output --partial "1 issue(s) dispatched"
}

# ---------------------------------------------------------------------------
# Filters (issue #1440 verification list)
# ---------------------------------------------------------------------------

@test "avatar_issue_watcher: an issue labelled wontfix is not dispatched" {
    _issues_with_labels 11 wontfix
    _run_tick
    assert_success
    assert_output --partial "excluded label"
    _refute_logged "tab create"
    _refute_logged "agent prompt"
}

@test "avatar_issue_watcher: an issue labelled manual is not dispatched" {
    _issues_with_labels 11 manual
    _run_tick
    assert_success
    assert_output --partial "excluded label"
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: an issue labelled TODO is not dispatched" {
    _issues_with_labels 11 TODO
    _run_tick
    assert_success
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: 보류 is no longer in the default exclude set" {
    _issues_with_labels 11 보류
    _run_tick
    assert_success
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
}

@test "avatar_issue_watcher: an issue labelled not-implement is not dispatched" {
    _issues_with_labels 11 not-implement
    _run_tick
    assert_success
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: an excluded label among several still parks the issue" {
    _issues_with_labels 11 refactor wontfix
    _run_tick
    assert_success
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: a label that merely starts with an excluded one is not excluded" {
    _issues_with_labels 11 wontfix-later
    _run_tick
    assert_success
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
}

@test "avatar_issue_watcher: a label containing a space is matched exactly" {
    _issues_with_labels 11 "on hold"
    _run_tick "IW_EXCLUDE_LABELS=on hold"
    assert_success
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: an issue with an OPEN blockedBy is skipped" {
    _run_tick "GH_BLOCKED_BY=11"
    assert_success
    assert_output --partial "blocked by open"
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: the same issue dispatches once its blocker closes" {
    _run_tick
    assert_success
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
}

@test "avatar_issue_watcher: a failing blockedBy query fails open" {
    _run_tick "GH_GRAPHQL_FAIL=1"
    assert_success
    assert_output --partial "fail-open"
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
}

@test "avatar_issue_watcher: an issue outside the watch list is never touched" {
    _set_issues '[{"number":77,"repository":{"nameWithOwner":"other/elsewhere"},"labels":[]}]'
    _run_tick
    assert_success
    assert_output --partial "No dispatchable issue"
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: an existing worktree no longer retires the issue" {
    # The bug this replaces: /gh-flow:issue stops at "PR opened", so a worktree
    # removed before the merge used to re-dispatch, and one kept until the merge
    # piled up — while an issue whose session had died was never offered again,
    # because its worktree was still there. A worktree is a workspace now.
    _add_worktree 11
    _run_tick
    assert_success
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
}

@test "avatar_issue_watcher: a watched repo whose path is gone is skipped with a warning" {
    _write_watch_file '[{"repo":"acme/dotfiles","path":"'"${_WORK_DIR}"'/gone","host":"github.com"}]'
    _run_tick
    assert_success
    assert_output --partial "missing path"
    _refute_logged "tab create"
}

# The collision herdr_agent_name.sh documents but cannot see: agent names drop
# the owner, so two watched repos sharing a basename share `iw-dotfiles-issue-
# <N>`. Nothing tracked gates this list, so the warning is the only signal.
@test "avatar_issue_watcher: watched repos sharing a basename raise a warning" {
    _make_repo "${_WORK_DIR}/dotfiles2"
    _write_watch_file '[{"repo":"acme/dotfiles","path":"'"${_REPO_DIR}"'","host":"github.com"},
      {"repo":"other/dotfiles","path":"'"${_WORK_DIR}"'/dotfiles2","host":"github.com"}]'
    _run_tick
    assert_success
    assert_output --partial "sharing a basename"
    assert_output --partial "dotfiles"
}

# Advisory guards earn their keep by staying quiet: the one-entry list `setup`
# writes must not tax every tick with a warning about a collision it cannot have.
@test "avatar_issue_watcher: a watch list without a basename clash stays silent" {
    _run_tick
    assert_success
    refute_output --partial "sharing a basename"
}

# The herdr name herdr_agent_name uses is not the raw basename — it is
# herdr_agent_repo_slug's output (case-folded, unsafe chars mapped to `-`).
# `acme/My-Repo` and `other/my.repo` are different raw basenames but both
# slug to `my-repo`, so herdr would route their dispatches into the same
# pane even though a literal-basename comparison sees no collision (PR #1584
# agy/codex review).
@test "avatar_issue_watcher: basenames that only collide after herdr's slug normalization also raise a warning" {
    _make_repo "${_WORK_DIR}/dotfiles2"
    _write_watch_file '[{"repo":"acme/My-Repo","path":"'"${_REPO_DIR}"'","host":"github.com"},
      {"repo":"other/my.repo","path":"'"${_WORK_DIR}"'/dotfiles2","host":"github.com"}]'
    _run_tick
    assert_success
    assert_output --partial "sharing a basename"
    assert_output --partial "my-repo"
}

@test "avatar_issue_watcher: a watch entry without a path is ignored" {
    _write_watch_file '[{"repo":"acme/dotfiles","host":"github.com"}]'
    _run_tick
    assert_success
    assert_output --partial "No dispatchable issue"
}

@test "avatar_issue_watcher: the watch list also accepts the {repos:[...]} shape" {
    _write_watch_file '{"repos":[{"repo":"acme/dotfiles","path":"'"${_REPO_DIR}"'"}]}'
    _run_tick
    assert_success
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
}

@test "avatar_issue_watcher: a watch entry without a host defaults to github.com" {
    _write_watch_file '[{"repo":"acme/dotfiles","path":"'"${_REPO_DIR}"'"}]'
    _run_tick
    assert_success
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
}

@test "avatar_issue_watcher: only one issue is dispatched per tick" {
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
    [ "$(_log_count 'tab create')" -eq 1 ]
}

@test "avatar_issue_watcher: the lowest issue number in a repo goes first" {
    _set_issues '[
      {"number":31,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":25,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}
    ]'
    _run_tick
    assert_success
    _assert_logged "--label iw-dotfiles-issue-12 --no-focus"
    _refute_logged "--label iw-dotfiles-issue-25 --no-focus"
}

@test "avatar_issue_watcher: a gh without search names gh's own error in the warning (#1849)" {
    _run_tick "GH_NO_SEARCH=1"
    assert_success
    assert_output --partial 'gh search issues failed on github.com: unknown command "search" for "gh"'
}

@test "avatar_issue_watcher: a failing issue search leaves the tick a no-op" {
    _run_tick "GH_SEARCH_FAIL=1"
    assert_success
    assert_output --partial "No dispatchable issue"
    _refute_logged "tab create"
}

# ---------------------------------------------------------------------------
# PR #1447 review regressions
# ---------------------------------------------------------------------------

@test "avatar_issue_watcher: the search is scoped to the watched repos" {
    _run_tick
    assert_success
    # Without repo: qualifiers --limit truncates every assigned issue on the
    # account and a watched repo can starve outside the window.
    _assert_logged "search issues repo:acme/dotfiles"
}

@test "avatar_issue_watcher: each watched repo contributes its own repo: qualifier" {
    mkdir -p "${_WORK_DIR}/other"
    git -C "${_WORK_DIR}/other" init -q
    _write_watch_file '[{"repo":"acme/dotfiles","path":"'"${_REPO_DIR}"'"},{"repo":"acme/other","path":"'"${_WORK_DIR}"'/other"}]'
    _run_tick
    assert_success
    _assert_logged "repo:acme/dotfiles repo:acme/other"
}

@test "avatar_issue_watcher: the search result order is pinned, not relevance-ranked" {
    _run_tick
    assert_success
    _assert_logged "--sort updated --order desc"
}

@test "avatar_issue_watcher: a stdin-consuming child cannot truncate the candidate loop" {
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
    _assert_logged "--label iw-dotfiles-issue-12 --no-focus"
}

@test "avatar_issue_watcher: a stdin-consuming child cannot truncate the dispatch loop" {
    _set_issues '[
      {"number":11,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":13,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}
    ]'
    _run_tick "IW_DISPATCH_PER_TICK=3"
    assert_success
    [ "$(_log_count 'agent prompt')" -eq 3 ]
}

@test "avatar_issue_watcher: the agent name carries the repo, not just the number" {
    _run_tick
    assert_success
    # Two watched repos both having an issue #11 would otherwise share one herdr
    # agent name, and the second prompt would land on the first one's pane.
    _assert_logged "agent start iw-dotfiles-issue-11"
    _refute_logged "agent start iw-issue-11 "
}

# Same overrun scenario as `herdr_agent_name.bats` T18b (#1553), run
# end-to-end here to also pin the permanent-skip WARN wording: the tick must
# say this is a *permanent* skip, not a transient one.
@test "avatar_issue_watcher: a name overrunning herdr's budget is flagged as a permanent skip" {
    _write_watch_file '[{"repo":"acme/sixteen-char-rep","path":"'"${_REPO_DIR}"'","host":"github.com"}]'
    _set_issues '[{"number":1234567,"repository":{"nameWithOwner":"acme/sixteen-char-rep"},"labels":[]}]'
    _run_tick
    assert_success
    assert_output --partial "the composed name is invalid or exceeds herdr's 32-char limit"
    assert_output --partial "skipped on every tick"
    assert_output --partial "Tick complete — 0 issue(s) dispatched, 1 skipped, 0 failed."
    _refute_logged "agent start"

    # The WARN claims this recurs on *every* tick, not just this one (PR #1589
    # review, codex/agy) — a second tick against the same unchanged input must
    # reproduce the identical rejection, since nothing about the run mutates
    # the repo slug or the issue number between ticks.
    : >"${_LOG}"
    _run_tick
    assert_success
    assert_output --partial "the composed name is invalid or exceeds herdr's 32-char limit"
    assert_output --partial "Tick complete — 0 issue(s) dispatched, 1 skipped, 0 failed."
    _refute_logged "agent start"
}

@test "avatar_issue_watcher: a mixed case with one skipped and one failed issue exits with failure" {
    _write_watch_file '[{"repo":"acme/sixteen-char-rep","path":"'"${_REPO_DIR}"'","host":"github.com"}]'
    _set_issues '[
      {"number":1234567,"repository":{"nameWithOwner":"acme/sixteen-char-rep"},"labels":[]},
      {"number":11,"repository":{"nameWithOwner":"acme/sixteen-char-rep"},"labels":[]}
    ]'
    _run_tick "IW_DISPATCH_PER_TICK=2" "HERDR_START_FAIL=1"
    assert_failure
    assert_output --partial "the composed name is invalid or exceeds herdr's 32-char limit"
    assert_output --partial "Tick complete — 0 dispatched, 1 skipped, 1 failed."
}

# herdr refuses `agent start` unless the name matches
# `^[a-z][a-z0-9_-]{0,31}$`. The pre-#1530 name folded the owner in verbatim
# (`iw-<owner>-<repo>-<N>`), so a real owner like `dEitY719` made every name
# invalid and the watcher dispatched nothing in 21 attempts.
@test "avatar_issue_watcher: the dispatched agent's name satisfies herdr's rule" {
    _run_tick
    assert_success

    local _name
    _name=$(awk '$2 == "agent" && $3 == "start" { print $4; exit }' "${_LOG}")
    assert_valid_herdr_name "${_name}"
}

# An owner with uppercase is the exact shape that broke production — the fold
# has to happen, and the repo (not the owner) has to be what survives.
@test "avatar_issue_watcher: a mixed-case owner still yields a valid name" {
    _write_watch_file '[{"repo":"dEitY719/DotFiles","path":"'"${_REPO_DIR}"'"}]'
    _set_issues '[{"repository":{"nameWithOwner":"dEitY719/DotFiles"},"number":11,"title":"t","labels":[]}]'
    _run_tick
    assert_success
    _assert_logged "agent start iw-dotfiles-issue-11"
}

@test "avatar_issue_watcher: repos with colliding directory names get distinct workspaces" {
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

@test "avatar_issue_watcher: a unique directory name still labels the workspace plainly" {
    _run_tick
    assert_success
    _assert_logged "workspace create --cwd ${_REPO_DIR} --label dotfiles --no-focus"
}

@test "avatar_issue_watcher: a cold agent is polled for idle before it is prompted" {
    _run_tick
    assert_success
    # `herdr agent start` returning does not prove the key-input loop accepts
    # Enter yet (#1399) — prompting a cold pane drops the first keystroke.
    run grep -n "agent get iw-dotfiles-issue-11" "${_LOG}"
    assert_success
    _agent_get_line=$(grep -n "agent get iw-dotfiles-issue-11" "${_LOG}" | head -1 | cut -d: -f1)
    _prompt_line=$(grep -n "agent prompt iw-dotfiles-issue-11" "${_LOG}" | head -1 | cut -d: -f1)
    [ "${_agent_get_line}" -lt "${_prompt_line}" ]
}

# ---------------------------------------------------------------------------
# Settle wait after agent start (issue #1560, polled since #1570)
# ---------------------------------------------------------------------------
#
# The idle poll above is a health check, not a wait: `herdr agent start` already
# answers `"agent_status":"idle"`, so _iw_wait_for_idle returns on its first
# poll and ~0s pass before the prompt. That is exactly why raising the poll
# budget fixes nothing — the pane is idle and still not listening.
#
# The wait that does the work reads the pane's own text instead (#1570). 13
# is still the number, but as the poll's *cap*: a pane that reads stable leaves
# early, and only one that never does pays the whole budget — and it still
# prompts when it does, which is the pre-#1570 behaviour kept reachable.

@test "avatar_issue_watcher: a pane that reads stable is prompted before the cap" {
    _run_tick
    assert_success
    _assert_logged "agent prompt iw-dotfiles-issue-11"
    # Three agreeing reads end the poll (PR #1611 review, 5th pass — two was
    # not enough evidence the input loop, not just the render, had settled),
    # so two gaps are spent, not thirteen.
    [ "$(_log_count '^sleep 1$')" -eq 2 ]
    refute_output --partial "never settled"
}

@test "avatar_issue_watcher: the settle poll reads the pane, not the sequence counter" {
    _run_tick
    assert_success
    # 15 lines, not 3 (PR #1611 review, 5th pass) — a real pane's banner and
    # input row sit above what a 3-line tail window ever reaches.
    _assert_logged "agent read iw-dotfiles-issue-11 --lines 15 --format text"
}

@test "avatar_issue_watcher: the settle poll happens after the idle check, not before" {
    _run_tick
    assert_success
    _idle_line=$(grep -n "agent get iw-dotfiles-issue-11" "${_LOG}" | head -1 | cut -d: -f1)
    _settle_line=$(grep -n "agent read iw-dotfiles-issue-11 --lines 15" "${_LOG}" | head -1 | cut -d: -f1)
    _prompt_line=$(grep -n "agent prompt iw-dotfiles-issue-11" "${_LOG}" | head -1 | cut -d: -f1)
    [ "${_idle_line}" -lt "${_settle_line}" ]
    [ "${_settle_line}" -lt "${_prompt_line}" ]
}

# The no-regression case: today's behaviour (wait the whole budget, then prompt
# regardless) has to stay reachable, because a pane that never stabilises is
# exactly the one the flat 13s was protecting.
@test "avatar_issue_watcher: a pane that never settles still warns and prompts at the cap" {
    _run_tick "HERDR_SETTLE_READ_SEQUENCE=~"
    assert_success
    assert_output --partial "never settled within 13s"
    _assert_logged "agent prompt iw-dotfiles-issue-11"
    [ "$(_log_count '^sleep 1$')" -eq 12 ]
}

# `Not logged in` is perfectly stable and means the opposite of ready (#1561).
# A bare state_change_seq comparison cannot tell it from a settled prompt,
# which is why the pane text is the signal.
@test "avatar_issue_watcher: a stable 'Not logged in' pane is not read as ready" {
    _run_tick "HERDR_SETTLE_READ_SEQUENCE=Not logged in"
    assert_success
    assert_output --partial "never settled within 13s"
    _assert_logged "agent prompt iw-dotfiles-issue-11"
}

# An empty frame twice over is not a settled pane either — it is a pane that
# has not drawn anything yet.
@test "avatar_issue_watcher: two empty reads do not count as a stable pane" {
    _run_tick "HERDR_SETTLE_READ_SEQUENCE=~|~|> claude ready"
    assert_success
    _assert_logged "agent prompt iw-dotfiles-issue-11"
    # Reads 1-2 are empty, 3-5 agree (three-in-a-row, PR #1611 review 5th
    # pass) — four gaps, still well inside 13.
    [ "$(_log_count '^sleep 1$')" -eq 4 ]
    refute_output --partial "never settled"
}

# A read that herdr refuses is "not ready yet", never a reason to end the tick.
@test "avatar_issue_watcher: an unreadable pane degrades to not-ready, never aborts" {
    _run_tick "HERDR_READ_MODE=missing"
    assert_success
    assert_output --partial "never settled within 13s"
    _assert_logged "agent prompt iw-dotfiles-issue-11"
}

@test "avatar_issue_watcher: IW_SETTLE_SECONDS=0 removes the settle wait entirely" {
    _run_tick "IW_SETTLE_SECONDS=0"
    assert_success
    _assert_logged "agent prompt iw-dotfiles-issue-11"
    _refute_logged "sleep "
    _refute_logged "agent read iw-dotfiles-issue-11 --lines 15"
}

@test "avatar_issue_watcher: IW_SETTLE_SECONDS caps the poll, not one flat sleep" {
    _run_tick "IW_SETTLE_SECONDS=7" "HERDR_SETTLE_READ_SEQUENCE=~"
    assert_success
    assert_output --partial "never settled within 7s"
    [ "$(_log_count '^sleep 1$')" -eq 6 ]
    _refute_logged "sleep 7"
}

# A fractional override predates the poll and cannot bound a poll count, so it
# still means the flat wait it always meant.
@test "avatar_issue_watcher: a fractional settle cap stays a flat wait" {
    _run_tick "IW_SETTLE_SECONDS=0.5"
    assert_success
    _assert_logged "sleep 0.5"
    _assert_logged "agent prompt iw-dotfiles-issue-11"
    _refute_logged "agent read iw-dotfiles-issue-11 --lines 15"
}

@test "avatar_issue_watcher: the settle poll interval is overridable" {
    # 3, not 13/1=13: the poll count scales with the gap
    # (ceil(13/4)=4 polls, 3 sleeps) so a wide gap no longer multiplies the
    # cap instead of dividing it — a gap of 4 pre-fix meant 13 polls of 4s
    # each, a 52s wait against a documented 13s cap (agy/codex, PR #1611
    # review).
    _run_tick "IW_SETTLE_POLL_SLEEP=4" "HERDR_SETTLE_READ_SEQUENCE=~"
    assert_success
    [ "$(_log_count '^sleep 4$')" -eq 3 ]
    [ "$(_log_count '^sleep 1$')" -eq 0 ]
}

@test "avatar_issue_watcher: a sub-1s poll interval does not cut the wait short" {
    # The inverse of the case above: ceil(13/0.5)=26 polls, 25 sleeps —
    # without the scaling fix the old fixed 13-poll count hit its bound at
    # 6.5s of real sleeping, half the documented cap (agy, PR #1611 review).
    _run_tick "IW_SETTLE_POLL_SLEEP=0.5" "HERDR_SETTLE_READ_SEQUENCE=~"
    assert_success
    [ "$(_log_count '^sleep 0.5$')" -eq 25 ]
    assert_output --partial "never settled within 13s"
}

@test "avatar_issue_watcher: a leading-zero IW_SETTLE_SECONDS does not abort the tick" {
    # $(( )) reads a leading-zero numeral as octal; 08/09 is not valid octal
    # and used to abort the whole tick with "value too great for base"
    # (codex, PR #1611 review, second pass). 10# forces base 10.
    _run_tick "IW_SETTLE_SECONDS=08" "HERDR_SETTLE_READ_SEQUENCE=~"
    assert_success
    _assert_logged "agent prompt iw-dotfiles-issue-11"
    assert_output --partial "never settled within 08s"
}

@test "avatar_issue_watcher: a non-standard zero poll interval does not crash awk" {
    # 'case ... in 0 | 0.0 | 0.00)' missed .0/0.000 and fell through to a
    # fatal awk division-by-zero, leaving _max_polls empty and the loop's
    # `[ -lt ]` erroring on an empty operand (agy, PR #1611 review, second
    # pass). The zero check now lives inside awk itself, so the poll count
    # falls back to the unscaled seconds (13, same as the literal "0" case)
    # instead of crashing. `sleep .0` is still called between polls — the
    # shell-side `= "0"` skip guard only recognises that one literal
    # spelling, same as every sibling *_SLEEP override in this file — but a
    # real `sleep .0` returns immediately, so this is a cosmetic 12 extra
    # no-op forks, not the crash this test pins the absence of.
    _run_tick "IW_SETTLE_POLL_SLEEP=.0" "HERDR_SETTLE_READ_SEQUENCE=~"
    assert_success
    [ "$(_log_count '^sleep .0$')" -eq 12 ]
    assert_output --partial "never settled within 13s"
    _assert_logged "agent prompt iw-dotfiles-issue-11"
}

@test "avatar_issue_watcher: a poll gap at or above the cap still sleeps once" {
    # ceil(13/13)=1 alone gives one read and zero sleeps — an override asking
    # to check every 13s should still wait that one real gap before giving up
    # (agy, PR #1611 review, second pass).
    _run_tick "IW_SETTLE_POLL_SLEEP=13" "HERDR_SETTLE_READ_SEQUENCE=~"
    assert_success
    [ "$(_log_count '^sleep 13$')" -eq 1 ]
    assert_output --partial "never settled within 13s"
}

@test "avatar_issue_watcher: a pathologically small poll interval is still bounded" {
    # ceil(13/0.001)=13000 would otherwise spawn thousands of herdr round
    # trips for one dispatch — a fat-fingered override, not attacker input,
    # but a real self-inflicted resource risk (agy, PR #1611 review, 4th
    # pass). The poll count now ceilings at 1000 regardless of how small the
    # gap gets.
    _install_frozen_clock_stub # count-bound only: no 13s deadline under load
    _run_tick "IW_SETTLE_POLL_SLEEP=0.001" "HERDR_SETTLE_READ_SEQUENCE=~"
    assert_success
    [ "$(_log_count '^sleep 0.001$')" -eq 999 ]
    assert_output --partial "never settled within 13s"
}

# The same `0` escape _IW_IDLE_POLL_SLEEP has: the suite polls without paying
# for it, and the poll still runs its full budget and still prompts.
@test "avatar_issue_watcher: IW_SETTLE_POLL_SLEEP=0 polls without sleeping at all" {
    _run_tick "IW_SETTLE_POLL_SLEEP=0" "HERDR_SETTLE_READ_SEQUENCE=~"
    assert_success
    _refute_logged "sleep "
    assert_output --partial "never settled within 13s"
    _assert_logged "agent prompt iw-dotfiles-issue-11"
}

@test "avatar_issue_watcher: a dispatch that fails before agent start never settles" {
    # No pane was opened, so there is nothing to wait for — the budget must not
    # be spent on an attempt that cannot prompt anyway.
    _run_tick "HERDR_TAB_FAIL=1"
    assert_failure
    _refute_logged "sleep "
    _refute_logged "agent read"
}

@test "avatar_issue_watcher: a dispatch that never lands is not judged at all" {
    # Attempt 1 stalls, attempts 2-3 die at tab create. Since #1444 the gate no
    # longer classifies *why* a dispatch failed — no error code, from any
    # attempt, can book a strike. Only a prompt confirmed submitted is judged.
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle" "HERDR_TAB_FAIL_AFTER=1"
    assert_failure
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "avatar_issue_watcher: --dry-run does not take the tick lock" {
    _hold_lock
    _run_tick -- --dry-run
    assert_success
    assert_output --partial "acme/dotfiles#11"
    refute_output --partial "already running"
}

@test "avatar_issue_watcher: --dry-run leaves an expired gate file on disk" {
    _set_limit_state "0" "$(($(date +%s) - 60))"
    _run_tick -- --dry-run
    assert_success
    # Evaluating the gate clears an expired file — a state change in the mode
    # documented as changing nothing.
    [ -f "${_LIMIT_FILE}" ]
}

@test "avatar_issue_watcher: --dry-run reports even while the gate is closed" {
    _set_limit_state "0" "$(($(date +%s) + 900))"
    _run_tick -- --dry-run
    assert_success
    assert_output --partial "acme/dotfiles#11"
}

# ---------------------------------------------------------------------------
# The three signals (issue #1453)
# ---------------------------------------------------------------------------

@test "avatar_issue_watcher: only open issues assigned to me are ever searched" {
    # The "already closed" half of the handled signal is the search itself: a
    # closed issue never enters the candidate list to begin with.
    _run_tick
    assert_success
    _assert_logged "--assignee @me --state open"
}

@test "avatar_issue_watcher: an issue an open PR closes is skipped" {
    _set_open_prs '{"acme/dotfiles":[{"number":90,"headRefName":"feature/x","body":"Closes #11"}]}'
    _run_tick
    assert_success
    assert_output --partial "an open PR already closes it"
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: the closing keyword is matched case-insensitively" {
    _set_open_prs '{"acme/dotfiles":[{"number":90,"headRefName":"feature/x","body":"fixes #11"}]}'
    _run_tick
    assert_success
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: a PR on the issue branch counts even without the keyword" {
    # A PR opened by hand may carry no `Closes #<n>`, but gwt always branches
    # wt/issue-<n>/<index>, so the branch name is the second, independent mark.
    _set_open_prs '{"acme/dotfiles":[{"number":90,"headRefName":"wt/issue-11/1","body":"no keyword here"}]}'
    _run_tick
    assert_success
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: a PR closing a longer number does not retire this issue" {
    # Without the word boundary, `Closes #115` would read as closing #11 and
    # retire it for as long as that PR stayed open.
    _set_open_prs '{"acme/dotfiles":[{"number":90,"headRefName":"feature/x","body":"Closes #115"}]}'
    _run_tick
    assert_success
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
}

@test "avatar_issue_watcher: an open PR on another repo does not retire this issue" {
    _set_open_prs '{"other/elsewhere":[{"number":90,"headRefName":"wt/issue-11/1","body":"Closes #11"}]}'
    _run_tick
    assert_success
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
}

@test "avatar_issue_watcher: an issue whose session is live is not dispatched again" {
    _set_live_agents 11
    _run_tick
    assert_success
    assert_output --partial "already running"
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: a failing open-PR query skips the repo, not the tick" {
    # Fail-closed on purpose (D-6): guessing "unhandled" here opens a second PR
    # on an issue that already has one, and the next tick re-evaluates anyway.
    _run_tick "GH_PR_LIST_FAIL=1"
    assert_success
    assert_output --partial "Cannot list open PRs"
    _refute_logged "tab create"
}

# ---------------------------------------------------------------------------
# Concurrency limits (issue #1453 D-2)
# ---------------------------------------------------------------------------

@test "avatar_issue_watcher: the tick holds once the global limit is reached" {
    _set_running 21 22 23 24 25 26 27
    _run_tick
    assert_success
    assert_output --partial "7 issue session(s) already running"
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: one session short of the limit still dispatches" {
    _set_running 21 22 23 24 25 26
    _run_tick "IW_MAX_PER_REPO=9"
    assert_success
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
}

@test "avatar_issue_watcher: a repo at its own limit is skipped" {
    _set_running 21 22 23
    _run_tick
    assert_success
    assert_output --partial "3 of its issues are already running"
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: a repo at its limit does not stop another repo" {
    _two_repo_fixture
    _set_running 21 22 23
    _run_tick
    assert_success
    _assert_logged "--label iw-other-issue-41 --no-focus"
}

# ---------------------------------------------------------------------------
# Zombie tabs (issue #1596)
# ---------------------------------------------------------------------------

@test "avatar_issue_watcher: zombie panes on closed issues do not fill the cap" {
    # The bug: a tab gh:pr-post-merge-verify failed to close keeps its agent
    # pane, so the tab alone reads it as running forever and the repo's
    # slots are never freed — the watcher then refuses every new issue,
    # silently.
    #
    # Since the grace period (PR #1597) it takes two observations to say that:
    # the first tick only starts the clock, and the slot is freed on the tick
    # that finds the pane still stopped a grace window later.
    _set_running_with_status idle 21 22 23 24 25 26 27
    _run_tick "GH_CLOSED_ISSUES=21 22 23 24 25 26 27"
    assert_success
    _refute_logged "tab create"

    : >"${_LOG}"
    _age_zombie_candidates
    _run_tick "GH_CLOSED_ISSUES=21 22 23 24 25 26 27"
    assert_success
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
}

@test "avatar_issue_watcher: a pane that has only just gone quiet keeps its slot" {
    # The regression the grace period exists for (PR #1597 codex/agy review):
    # an agent waiting on a background subagent reports `idle` for minutes, and
    # one snapshot cannot tell that pause apart from a finished session. Freeing
    # the slot on that single sighting would dispatch a second session onto an
    # issue the first one is still working.
    _set_running_with_status idle 21 22 23
    _run_tick "GH_CLOSED_ISSUES=21 22 23"
    assert_success
    assert_output --partial "already running"
    _refute_logged "tab create"

    # Nothing was reclaimed — the tick only wrote down when it first looked.
    run wc -l <"${_ZOMBIE_FILE}"
    assert_output "3"
}

@test "avatar_issue_watcher: a pane that resumes work resets its grace clock" {
    # Self-healing: the delegation came back, so the clock the first tick
    # started must be thrown away rather than aged into a reclaim. Otherwise a
    # session that went quiet once would be reclaimed the instant it goes quiet
    # again, however long it worked in between.
    _set_running_with_status idle 21 22 23
    _run_tick "GH_CLOSED_ISSUES=21 22 23"
    assert_success
    _refute_logged "tab create"

    : >"${_LOG}"
    _set_agents_with_status working \
        21 22 23
    _run_tick "GH_CLOSED_ISSUES=21 22 23"
    assert_success
    assert_output --partial "already running"
    run cat "${_ZOMBIE_FILE}"
    assert_output ""

    # Quiet again — and back at the start of the window, not past its end.
    : >"${_LOG}"
    _set_agents_with_status idle \
        21 22 23
    _run_tick "GH_CLOSED_ISSUES=21 22 23"
    assert_success
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: two stopped panes age independently" {
    # The clock is per repo+issue, so one pane crossing the window says nothing
    # about its neighbour's.
    _set_running_with_status idle 21 22
    _seed_zombie_candidate 21 "$(($(date +%s) - 1200))"
    _run_tick "GH_CLOSED_ISSUES=21 22"
    assert_success

    # 21 is settled, so its row is gone; 22 is still counting.
    run cat "${_ZOMBIE_FILE}"
    refute_output --partial "	21	"
    assert_output --partial "	22	"
}

@test "avatar_issue_watcher: an idle pane on a still-open issue still counts as live" {
    # The guard that makes "AND the issue is closed" load-bearing: an agent
    # between two tool calls reports `idle` for a moment, and reclaiming its
    # slot then would dispatch the same issue twice.
    _set_agents_with_status idle 11
    _run_tick
    assert_success
    assert_output --partial "already running"
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: an unreadable issue state keeps an idle pane live" {
    # A failed state read must never be the reason a slot is reclaimed.
    _set_agents_with_status idle 11
    _run_tick "GH_ISSUE_VIEW_FAIL=1"
    assert_success
    assert_output --partial "already running"
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: an unrecognised agent_status counts as live" {
    # Only `idle` and `done` are known to mean "stopped"; anything else must
    # fail toward "still running".
    _set_agents_with_status starting 11
    _run_tick "GH_CLOSED_ISSUES=11"
    assert_success
    assert_output --partial "already running"
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: an unreachable herdr holds the tick instead of dispatching" {
    # "How many are running" has no safe default: guessing "none" would lift the
    # cap exactly when herdr is unhealthy.
    _run_tick "HERDR_AGENT_LIST_FAIL=1"
    assert_success
    assert_output --partial "holding this tick"
    _refute_logged "tab create"
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

@test "avatar_issue_watcher: consecutive ticks take turns between repos" {
    _two_repo_fixture
    _run_tick
    assert_success
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"

    : >"${_LOG}"
    _set_live_agents 11
    _run_tick
    assert_success
    _assert_logged "--label iw-other-issue-41 --no-focus"
}

@test "avatar_issue_watcher: the cursor is persisted for the next tick" {
    _two_repo_fixture
    _run_tick
    assert_success
    run cat "${_STATE_DIR}/select.json"
    assert_output --partial '"last_repo": "acme/dotfiles"'
}

@test "avatar_issue_watcher: a state dir with no cursor starts at the first repo" {
    _two_repo_fixture
    mkdir -p "${_STATE_DIR}"
    [ ! -f "${_STATE_DIR}/select.json" ]
    _run_tick
    assert_success
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
}

@test "avatar_issue_watcher: an unwritable state dir does not stop the dispatch" {
    _two_repo_fixture
    mkdir -p "${_STATE_DIR}"
    chmod 500 "${_STATE_DIR}"
    _run_tick
    assert_success
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
}

@test "avatar_issue_watcher: --dry-run does not advance the cursor" {
    _two_repo_fixture
    _run_tick -- --dry-run
    assert_success
    [ ! -f "${_STATE_DIR}/select.json" ]
}

# ---------------------------------------------------------------------------
# PR #1456 review regressions
# ---------------------------------------------------------------------------

@test "avatar_issue_watcher: a full open-PR window is treated as unknown, not as an answer" {
    # 100 open PRs means the window is full; the issue's own PR may sit outside
    # it, so answering "unhandled" would reinstate the duplicate-PR failure.
    _set_filler_prs "acme/dotfiles" 100
    _run_tick
    assert_success
    assert_output --partial "cannot rule out a duplicate"
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: a window with room to spare still answers" {
    _set_filler_prs "acme/dotfiles" 99
    _run_tick
    assert_success
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
}

@test "avatar_issue_watcher: 'Closes: #N' counts as an open PR closing the issue" {
    _set_open_prs '{"acme/dotfiles":[{"number":90,"headRefName":"feature/x","body":"Closes: #11"}]}'
    _run_tick
    assert_success
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: a cross-repo 'Closes owner/repo#N' counts too" {
    _set_open_prs '{"acme/dotfiles":[{"number":90,"headRefName":"feature/x","body":"Closes acme/dotfiles#11"}]}'
    _run_tick
    assert_success
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: a raised per-tick cap cannot exceed the per-repo cap" {
    # Two already running plus a per-tick allowance of three: only one slot is
    # left in this repo, so only one issue may start.
    _set_live_agents 21 22
    _set_issues '[
      {"number":11,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":13,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}
    ]'
    _run_tick "IW_DISPATCH_PER_TICK=3"
    assert_success
    [ "$(_log_count 'tab create')" -eq 1 ]
}

@test "avatar_issue_watcher: a raised per-tick cap cannot exceed the global cap" {
    _set_live_agents 21 22 23 24 25 26
    _set_issues '[
      {"number":11,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":13,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}
    ]'
    # Per-repo headroom is lifted so the global ceiling is the only thing left
    # to hold the line: six running, seven allowed, so exactly one may start.
    _run_tick "IW_DISPATCH_PER_TICK=3" "IW_MAX_PER_REPO=9"
    assert_success
    [ "$(_log_count 'tab create')" -eq 1 ]
}

@test "avatar_issue_watcher: a non-integer cap override falls back to the default" {
    _run_tick "IW_MAX_CONCURRENT=abc"
    assert_success
    assert_output --partial "not a positive integer"
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
}

@test "avatar_issue_watcher: an empty cap override is silently the default" {
    # Unset-vs-empty must not warn: `IW_MAX_CONCURRENT=` in a cron env is the
    # same intent as not setting it at all.
    _run_tick "IW_MAX_CONCURRENT="
    assert_success
    refute_output --partial "not a positive integer"
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
}

@test "avatar_issue_watcher: --help reports the effective cap, not the default" {
    run env "IW_MAX_CONCURRENT=5" bash "${SCRIPT}" --help
    assert_success
    assert_output --partial "5 running in total"
}

@test "avatar_issue_watcher: the global cap default stays above the per-repo cap default" {
    # A global cap at or below the per-repo cap can never fire while only one
    # repo is watched — it would be dead config. Both numbers are read back
    # from --help — the same readout that pins the literal defaults in
    # "--help documents the concurrency limits and the cursor" — so this holds
    # for whatever the shipped defaults become (#1579 raised them).
    local _per_repo _concurrent
    run bash "${SCRIPT}" --help
    assert_success
    _concurrent=$(printf '%s\n' "${output}" | sed -nE 's/.*[^0-9]([0-9]+) running in total.*/\1/p')
    _per_repo=$(printf '%s\n' "${output}" | sed -nE 's/.*[^0-9]([0-9]+) in one repo.*/\1/p')
    [ -n "${_per_repo}" ]
    [ -n "${_concurrent}" ]
    [ "${_concurrent}" -gt "${_per_repo}" ]
}

# ---------------------------------------------------------------------------
# Read-only on issues
# ---------------------------------------------------------------------------

@test "avatar_issue_watcher: the tick never writes to an issue" {
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

@test "avatar_issue_watcher: only the four read calls reach gh" {
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

@test "avatar_issue_watcher: a failed dispatch is retried up to three times" {
    _run_tick "HERDR_PROMPT_MODE=fail"
    assert_failure
    [ "$(_log_count 'tab create')" -eq 3 ]
    assert_output --partial "Giving up on acme/dotfiles#11 after 3 attempts"
}

@test "avatar_issue_watcher: each failed attempt closes its tab before retrying" {
    _run_tick "HERDR_PROMPT_MODE=fail"
    assert_failure
    # Nothing may survive: a leftover iw-<repo>-issue-<N> tab with an agent in it is
    # the running-now signal, so it would hold the issue without working it.
    [ "$(_log_count 'tab close ws-test-1:t9')" -eq 3 ]
}

@test "avatar_issue_watcher: a dispatch that succeeds on the second attempt keeps its tab" {
    _run_tick "HERDR_PROMPT_FAIL_TIMES=2" "HERDR_AGENT_STATUS=idle"
    assert_success
    # Every tab but the one that took the prompt is closed.
    [ "$(_log_count 'tab close')" -eq $(($(_log_count 'tab create') - 1)) ]
}

@test "avatar_issue_watcher: a tab-create failure is retried and then given up on" {
    _run_tick "HERDR_TAB_FAIL=1"
    assert_failure
    [ "$(_log_count 'tab create')" -eq 3 ]
    assert_output --partial "herdr tab create failed"
}

@test "avatar_issue_watcher: an agent-start failure closes the tab it opened" {
    _run_tick "HERDR_START_FAIL=1"
    assert_failure
    _assert_logged "tab close ws-test-1:t9"
}

# ---------------------------------------------------------------------------
# #1525 — the agent_pane_busy race on a pane that was just created
# ---------------------------------------------------------------------------
#
# A tab's shell is not interactive the instant `tab create` answers, so
# `agent start` on it is refused with `agent_pane_busy` and returns immediately.
# In cron that lost every single tick for 130 ticks running. It is a timing
# race, not a defect in the pane, so another attempt *on the same pane* is the
# fix — which is exactly what the outer _IW_MAX_ATTEMPTS loop cannot give: it
# throws the tab away and builds a new, equally cold pane.

@test "avatar_issue_watcher: a transient agent_pane_busy is retried and the issue still dispatches" {
    _run_tick "HERDR_START_PANE_BUSY=1"
    assert_success
    # The retry is *inner*: the same tab, a second start. A second `tab create`
    # here would mean the outer loop absorbed it, which is the defect.
    [ "$(_log_count 'agent start')" -eq 2 ]
    [ "$(_log_count 'tab create')" -eq 1 ]
    _assert_logged "agent prompt iw-dotfiles-issue-11 /gh-flow:wave 11"
}

# The retry has to be visible: 130 ticks of silent failure is what made this
# cost a day. The gap comes from IW_START_RETRY_SLEEP, so a hardcoded 2 would
# read "retrying in 2s" here and fail — the message is the proof the override
# reached the code, and with it that the bats suite pays no real wait.
@test "avatar_issue_watcher: a retried pane race names itself and its configured gap" {
    _run_tick "HERDR_START_PANE_BUSY=1"
    assert_success
    assert_output --partial "agent_pane_busy"
    assert_output --partial "retrying in 0s"
}

# The gap itself is 13s since #1571, not the 2s this shipped with: `tab create`
# answering before the pane's shell is interactive is the *same* class of race
# as the settle wait above, and 2s was shorter than the 5s already measured to
# fail. Unlike the settle wait it is still a flat sleep — #1570 turned only the
# settle into a poll, because only the settle has a pane to read. Asserted
# through the message rather than a `sleep` line, which is what tells the two
# waits apart in the call log.
@test "avatar_issue_watcher: the start retry gap defaults to 13s" {
    # An empty assignment beats _run_tick's own `IW_START_RETRY_SLEEP=0` and
    # still lets `${IW_START_RETRY_SLEEP:-13}` fall through to the default.
    _run_tick "HERDR_START_PANE_BUSY=1" "IW_START_RETRY_SLEEP="
    assert_success
    assert_output --partial "retrying in 13s"
}

@test "avatar_issue_watcher: the start retry gap stays env-overridable" {
    _run_tick "HERDR_START_PANE_BUSY=1" "IW_START_RETRY_SLEEP=4"
    assert_success
    assert_output --partial "retrying in 4s"
    refute_output --partial "retrying in 13s"
}

# The SSOT line itself, so a change that only moves the default out of the
# ${VAR:-13} form (and with it the `0` escape the suite depends on) is caught
# here rather than as a mysteriously slow suite.
@test "avatar_issue_watcher: both herdr wait constants are 13 and overridable" {
    run grep -qF -- '_IW_SETTLE_SECONDS="${IW_SETTLE_SECONDS:-13}"' "${SCRIPT}"
    assert_success
    run grep -qF -- '_IW_START_RETRY_SLEEP="${IW_START_RETRY_SLEEP:-13}"' "${SCRIPT}"
    assert_success
}

# #1530/#1549 and #1560/#1571 were both "two of the three dispatchers were
# fixed". The comment naming the other two is the guard against a third round.
@test "avatar_issue_watcher: the wait comments name the other two dispatchers" {
    run grep -qF -- '_PMT_SETTLE_SECONDS' "${SCRIPT}"
    assert_success
    run grep -qF -- 'PMV_SETTLE_SECONDS' "${SCRIPT}"
    assert_success
}

# The comment used to justify the flat sleep with "herdr exposes no signal for
# 'the input loop is up'" — false even when it was written, since the file was
# already reading pane text a few hundred lines below (#1570). Pinned as an
# absence rather than as a replacement sentence so the wording stays free.
@test "avatar_issue_watcher: the settle comment no longer claims herdr exposes no signal" {
    run grep -qF -- 'herdr exposes no signal' "${SCRIPT}"
    assert_failure
}

# The inner retrying is bounded, and the bound is the point: cron re-runs every
# few minutes anyway. Three inner *attempts* per outer attempt, three outer
# attempts — the two layers are independent and both still hold.
@test "avatar_issue_watcher: a permanent agent_pane_busy stops after the inner attempt budget" {
    _run_tick "HERDR_START_PANE_BUSY=99"
    assert_failure
    [ "$(_log_count 'agent start')" -eq 9 ]
    [ "$(_log_count 'tab create')" -eq 3 ]
    _refute_logged "agent prompt"
}

# Exhausting the inner budget must still fall through to _iw_cleanup_attempt —
# a retry loop that swallowed the failure would leak a tab per outer attempt,
# which is the litter the issue's log already shows.
@test "avatar_issue_watcher: a start that never succeeds closes its tab" {
    _run_tick "HERDR_START_PANE_BUSY=99"
    assert_failure
    [ "$(_log_count 'tab close ws-test-1:t9')" -eq 3 ]
}

# The #1445/#1458 regression guard. herdr names this race precisely, on stderr;
# `_hp_agent_start` (lib/herdr_pane.sh) used to throw that stream away, so 21 failures in the cron
# log said only "start failed". Restoring `2>&1 >/dev/null` must make this red.
@test "avatar_issue_watcher: a failed start reports the cause herdr gave on stderr" {
    _run_tick "HERDR_START_PANE_BUSY=99"
    assert_failure
    assert_output --partial "agent_pane_busy"
    assert_output --partial "is not an available shell"
}

# What herdr writes to stderr is a JSON document, so dumping it verbatim buries
# the sentence inside braces exactly where a cron log is read in a hurry.
@test "avatar_issue_watcher: the cause line carries the message, not the raw JSON" {
    _run_tick "HERDR_START_PANE_BUSY=99"
    assert_failure
    refute_output --partial '{"error"'
}

# Only the one known race is retried. `agent_name_taken` is a named failure,
# but it is not a race that a second attempt on the same pane can win, so it
# ends its outer attempt at once — one start per attempt, three in all.
@test "avatar_issue_watcher: a named failure that is not the pane race is never retried" {
    _run_tick "HERDR_START_NAME_TAKEN=1"
    assert_failure
    [ "$(_log_count 'agent start')" -eq 3 ]
    assert_output --partial "agent_name_taken"
}

# A failure that does not name itself is not a race we understand either — the
# same contract #1512 set on the merge-train side.
@test "avatar_issue_watcher: an unexplained start failure is not retried" {
    _run_tick "HERDR_START_FAIL=1"
    assert_failure
    [ "$(_log_count 'agent start')" -eq 3 ]
}

# PR #1528 review (codex, FOLLOW-UP). herdr picks the stream, not us — that is
# why _hp_herdr_error_code reads stdout first and stderr second. The *message*
# helper read only stderr, so a failure herdr answered on stdout arrived with
# its code but no sentence. `agent_name_taken` is exactly that shape.
#
# Both halves must survive: the code is what a human greps a cron log for
# (`grep -c agent_pane_busy` is how #1525 was measured), the sentence is what
# they read once they find it.
@test "avatar_issue_watcher: a stdout-only failure reports both its code and herdr's sentence" {
    _run_tick "HERDR_START_NAME_TAKEN=1"
    assert_failure
    assert_output --partial "agent_name_taken"
    assert_output --partial "agent name is already used"
}

# PR #1528 review (agy, BLOCKER). When `mktemp` fails there is no capture file,
# so no error code can be read and nothing is retryable — but the start itself
# is still worth one attempt, and losing the cause must not cost the dispatch.
@test "avatar_issue_watcher: a start still dispatches when the stderr capture file cannot be opened" {
    _install_failing_mktemp
    _run_tick
    assert_success
    _assert_logged "agent prompt iw-dotfiles-issue-11 /gh-flow:wave 11"
}

# Same fallback on the failing side: the tick reports the failure and cleans up
# rather than dying on the unreadable capture file, and it claims no cause it
# could not actually read.
@test "avatar_issue_watcher: a failed start without a capture file reports no invented cause" {
    _install_failing_mktemp
    _run_tick "HERDR_START_PANE_BUSY=99"
    assert_failure
    [ "$(_log_count 'agent start')" -eq 3 ]
    refute_output --partial "원인:"
    _assert_logged "tab close ws-test-1:t9"
}

@test "avatar_issue_watcher: a non-stall prompt failure is not retried within the attempt" {
    _run_tick "HERDR_PROMPT_MODE=fail"
    assert_failure
    # Three attempts, one prompt each — never two prompts inside one attempt.
    [ "$(_log_count 'agent prompt')" -eq 3 ]
}

# ---------------------------------------------------------------------------
# Stall recovery (issue #1443)
# ---------------------------------------------------------------------------

@test "avatar_issue_watcher: agent_prompt_stalled is recovered by pressing Enter, never retyped" {
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle" "HERDR_SENDKEYS_MODE=ok"
    assert_success
    # The stalled command is already sitting in the input box unsubmitted, so a
    # second `agent prompt` would type it on top of itself and Enter would still
    # never land. Exactly one prompt, ever.
    [ "$(_log_count 'agent prompt')" -eq 1 ]
    _assert_logged "agent send-keys iw-dotfiles-issue-11 Enter"
    [ "$(_log_count 'agent send-keys')" -eq 1 ]
}

@test "avatar_issue_watcher: the Enter recovery stops as soon as state_change_seq moves" {
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle" "HERDR_SENDKEYS_MODE=ok"
    assert_success
    assert_output --partial "state_change_seq"
    assert_output --partial "Dispatched to iw-dotfiles-issue-11"
}

@test "avatar_issue_watcher: an unresolved stall presses Enter three times and still reports the stall" {
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

@test "avatar_issue_watcher: a final unresolved stall is escalated visibly instead of cleaning up the last tab" {
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle"
    assert_failure
    _assert_logged "agent send-keys iw-dotfiles-issue-11 Enter"
    _assert_logged "tab rename ws-test-1:t9 issue-11-STUCK"
    _assert_logged "notification show issue watcher prompt stalled --body #11 dispatch stalled repeatedly — herdr agent attach iw-dotfiles-issue-11 --sound request"
    refute_output --partial "(unknown)"
}

# ---------------------------------------------------------------------------
# Unknown command (issue #2300)
# ---------------------------------------------------------------------------

@test "avatar_issue_watcher: a stall over an Unknown command pane fails as agent_unknown_command without Enter" {
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle" \
        "HERDR_READ_AFTER_PROMPT=● Unknown command: /gh-flow:wave"
    assert_failure
    assert_output --partial "herdr agent prompt failed for agent iw-dotfiles-issue-11 (agent_unknown_command)."
    assert_output --partial "answered '● Unknown command: /gh-flow:wave' to '/gh-flow:wave 11'"
    assert_output --partial "plugin is installed"
    _refute_logged "agent send-keys"
}

@test "avatar_issue_watcher: an Unknown command line 40 rows above the pane bottom is still detected" {
    # A real 66-row herdr pane stacks blank and status lines under the
    # rejection, pushing it out of the 15-line settle window (#2306).
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle" \
        "HERDR_READ_AFTER_PROMPT=● Unknown command: /gh-flow:wave" \
        "HERDR_READ_AFTER_PROMPT_PAD=39"
    assert_failure
    assert_output --partial "herdr agent prompt failed for agent iw-dotfiles-issue-11 (agent_unknown_command)."
    [ -s "${_STATE_DIR}/unknown-command/acme_dotfiles-11" ]
    _refute_logged "agent send-keys"
}

@test "avatar_issue_watcher: an Unknown command stops after attempt 1 with cleanup and no STUCK escalation" {
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle" \
        "HERDR_READ_AFTER_PROMPT=● Unknown command: /gh-flow:wave"
    assert_failure
    [ "$(_log_count 'agent prompt')" -eq 1 ]
    _assert_logged "tab close ws-test-1:t9"
    _refute_logged "tab rename"
    _refute_logged "notification show"
    assert_output --partial "after attempt 1"
}

@test "avatar_issue_watcher: an issue that hit Unknown command is held on the next tick" {
    # The tab is closed, so without the hold the next tick would see an idle
    # issue and rebuild a tab for the same answer (PR #2301 review).
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle" \
        "HERDR_READ_AFTER_PROMPT=● Unknown command: /gh-flow:wave"
    assert_failure
    [ -s "${_STATE_DIR}/unknown-command/acme_dotfiles-11" ]

    : >"${_LOG}"
    _run_tick
    assert_output --partial "Skipping acme/dotfiles#11 — its last dispatch answered Unknown command"
    _refute_logged "agent prompt"
}

@test "avatar_issue_watcher: an Unknown command hold expires" {
    mkdir -p "${_STATE_DIR}/unknown-command"
    printf '%s' "$(($(date +%s) - 21601))" >"${_STATE_DIR}/unknown-command/acme_dotfiles-11"
    _run_tick
    assert_success
    _assert_logged "agent prompt iw-dotfiles-issue-11 /gh-flow:wave 11"
}

@test "avatar_issue_watcher: a working agent wins over an Unknown command line in its pane" {
    # `working` is positive evidence the prompt landed; the pane read is never reached.
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=working" \
        "HERDR_READ_AFTER_PROMPT=● Unknown command: /gh-flow:wave"
    assert_success
    assert_output --partial "treating as delivered"
    refute_output --partial "agent_unknown_command"
}

@test "avatar_issue_watcher: a stall pane without Unknown command keeps the Enter recovery" {
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle" \
        "HERDR_READ_AFTER_PROMPT=> /gh-flow:wave 11"
    assert_failure
    [ "$(_log_count 'agent send-keys')" -eq 9 ]
    [ "$(_log_count 'agent prompt')" -eq 3 ]
    _assert_logged "tab rename ws-test-1:t9 issue-11-STUCK"
    refute_output --partial "agent_unknown_command"
}

@test "avatar_issue_watcher: agent_prompt_stalled recovery is skipped when the agent is already working" {
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=working"
    assert_success
    [ "$(_log_count 'agent prompt')" -eq 1 ]
    assert_output --partial "treating as delivered"
    # `working` is positive evidence the prompt landed — nothing to submit.
    _refute_logged "agent send-keys"
}

@test "avatar_issue_watcher: a blipped seq baseline falls back to the working status" {
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

@test "avatar_issue_watcher: a failing send-keys abandons recovery instead of burning attempts" {
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle" "HERDR_SENDKEYS_MODE=fail"
    assert_failure
    # One press per dispatch attempt, not three: retrying against a pane herdr
    # cannot reach at all is pure waste.
    [ "$(_log_count 'agent send-keys')" -eq 3 ]
    [ "$(_log_count 'agent prompt')" -eq 3 ]
    assert_output --partial "pane unreachable"
}

@test "avatar_issue_watcher: a broken pane is named as an outage, not booked as a strike" {
    # PR #1449 codex review, BLOCKER B: an unreachable pane must not read as a
    # spent quota. Since #1444 that follows from the dispatch failing at all —
    # the distinct code survives only so the cron log names the real fault.
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle" "HERDR_SENDKEYS_MODE=fail"
    assert_failure
    assert_output --partial "herdr_send_keys_failed"
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "avatar_issue_watcher: a broken pane leaves an existing strike count untouched" {
    _set_limit_state "1" "0"
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle" "HERDR_SENDKEYS_MODE=fail"
    assert_failure
    run cat "${_LIMIT_FILE}"
    assert_output --partial '"strikes": "1"'
    refute_output --partial '"strikes": "2"'
}

# ---------------------------------------------------------------------------
# The prompt error document arrives on stderr (issue #1559)
# ---------------------------------------------------------------------------
#
# `_iw_prompt_once` used to send stderr to /dev/null, and herdr answers a failed
# `agent prompt` on exactly that stream. So `.error.code` was empty on every
# failure, every branch keyed on it was unreachable, and every cron line read
# `(unknown)`. These pin the code back to the name herdr gave it — the whole
# suite above only ever passed because the stub answered on stdout.

@test "avatar_issue_watcher: a stall herdr reported on stderr is still named agent_prompt_stalled" {
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle"
    assert_failure
    assert_output --partial "herdr agent prompt failed for agent iw-dotfiles-issue-11 (agent_prompt_stalled)"
    refute_output --partial "(unknown)"
}

@test "avatar_issue_watcher: a stall on stderr still reaches the already-working short-circuit" {
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=working"
    assert_success
    assert_output --partial "treating as delivered"
    # The branch is reachable only when `.error.code` parses, so a silent
    # regression to `2>/dev/null` would press Enter into a busy pane instead.
    _refute_logged "agent send-keys"
}

@test "avatar_issue_watcher: a stall on stderr still triggers the Enter recovery" {
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle" "HERDR_SENDKEYS_MODE=ok"
    assert_success
    _assert_logged "agent send-keys iw-dotfiles-issue-11 Enter"
    assert_output --partial "Dispatched to iw-dotfiles-issue-11"
}

@test "avatar_issue_watcher: a failed send-keys outranks the stall code it recovered from" {
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle" "HERDR_SENDKEYS_MODE=fail"
    assert_failure
    assert_output --partial "herdr_send_keys_failed"
    refute_output --partial "(unknown)"
}

@test "avatar_issue_watcher: a non-stall failure on stderr is named, not reported as unknown" {
    _run_tick "HERDR_PROMPT_MODE=fail"
    assert_failure
    assert_output --partial "herdr agent prompt failed for agent iw-dotfiles-issue-11 (agent_not_found)"
    refute_output --partial "(unknown)"
}

# ---------------------------------------------------------------------------
# A working agent is never torn down (issue #1559 follow-up)
# ---------------------------------------------------------------------------
#
# The incident: a session that was dispatched and doing real work was torn down
# three times in one tick, because a failed attempt ran _iw_cleanup_attempt
# unconditionally. Independent of the error-code fix above on purpose — that
# parsing is what failed in production, so it is not trusted alone.

@test "avatar_issue_watcher: a working agent survives a prompt failure instead of being torn down" {
    _run_tick "HERDR_PROMPT_MODE=fail" "HERDR_AGENT_STATUS=working"
    assert_success
    # One attempt, and no teardown of the pane the agent is working in.
    [ "$(_log_count 'tab create')" -eq 1 ]
    _refute_logged "tab close"
    refute_output --partial "Giving up"
}

@test "avatar_issue_watcher: an idle agent is still torn down and retried after a prompt failure" {
    # The negative half: the guard above must not become a blanket skip.
    _run_tick "HERDR_PROMPT_MODE=fail" "HERDR_AGENT_STATUS=idle"
    assert_failure
    [ "$(_log_count 'tab create')" -eq 3 ]
    [ "$(_log_count 'tab close')" -eq 3 ]
    assert_output --partial "Giving up on acme/dotfiles#11 after 3 attempts"
}

@test "avatar_issue_watcher: an unreachable agent is torn down rather than assumed working" {
    # `agent get` errors once the agent has been prompted, so the guard has no
    # status at all — an unanswered query is not evidence of work in progress.
    _run_tick "HERDR_PROMPT_MODE=fail" "HERDR_GET_FAIL_AFTER_PROMPT=1"
    assert_failure
    [ "$(_log_count 'tab close')" -eq 3 ]
    assert_output --partial "Giving up on acme/dotfiles#11 after 3 attempts"
}

# ---------------------------------------------------------------------------
# --dry-run
# ---------------------------------------------------------------------------

@test "avatar_issue_watcher: --dry-run lists the candidates it would dispatch" {
    _run_tick -- --dry-run
    assert_success
    assert_output --partial "Dry run"
    assert_output --partial "acme/dotfiles#11"
}

@test "avatar_issue_watcher: --dry-run opens no tab and sends no prompt" {
    _run_tick -- --dry-run
    assert_success
    _refute_logged "tab create"
    _refute_logged "agent prompt"
}

@test "avatar_issue_watcher: --dry-run applies the same filters as a real tick" {
    _issues_with_labels 11 wontfix
    _run_tick -- --dry-run
    assert_success
    assert_output --partial "No dispatchable issue"
}

@test "avatar_issue_watcher: --dry-run works without herdr installed" {
    rm -f "${_BIN_DIR}/herdr"
    _run_tick "PATH=$(_path_without herdr)" -- --dry-run
    assert_success
    assert_output --partial "acme/dotfiles#11"
}

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------

@test "avatar_issue_watcher: missing herdr binary fails with a clear error" {
    rm -f "${_BIN_DIR}/herdr"
    _run_tick "PATH=$(_path_without herdr)"
    assert_failure
    assert_output --partial "herdr not found"
}

@test "avatar_issue_watcher: a missing watch list fails with a clear error" {
    _run_tick "IW_WATCHED_REPOS=${_WORK_DIR}/nope.json"
    assert_failure
    assert_output --partial "Watch list not found"
}

@test "avatar_issue_watcher: --cwd pointing nowhere fails" {
    _run_tick -- --cwd "${_WORK_DIR}/nope"
    assert_failure
    assert_output --partial "Cannot cd"
}

@test "avatar_issue_watcher: a relative watch-list path resolves against --cwd" {
    _write_watch_file '[{"repo":"acme/dotfiles","path":"dotfiles","host":"github.com"}]'
    _run_tick -- --cwd "${_WORK_DIR}"
    assert_success
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
}

# ---------------------------------------------------------------------------
# Locking
# ---------------------------------------------------------------------------

@test "avatar_issue_watcher: a tick is skipped while another instance holds the lock" {
    _hold_lock
    _run_tick
    assert_success
    assert_output --partial "already running"
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: the lock is released so the next tick runs" {
    _run_tick
    assert_success
    : >"${_LOG}"
    _set_issues '[{"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}]'
    _run_tick
    assert_success
    _assert_logged "--label iw-dotfiles-issue-12 --no-focus"
}

@test "avatar_issue_watcher: missing flock degrades to a warning, not a failure" {
    _run_tick "PATH=$(_path_without flock)"
    assert_success
    assert_output --partial "without single-instance protection"
    _assert_logged "agent prompt iw-dotfiles-issue-11"
}

# ---------------------------------------------------------------------------
# Candidate-selection runtime (issue #2157, rollback removed in #2173)
# ---------------------------------------------------------------------------

@test "avatar_issue_watcher: missing python3 is refused, not silently skipped" {
    _run_tick "PATH=$(_path_without python3)"
    assert_failure
    assert_output --partial "python3 (>= 3.10) not found"
    _refute_logged "agent prompt"
}

# ---------------------------------------------------------------------------
# CLAUDE_CONFIG_DIR routing (issue #1393)
# ---------------------------------------------------------------------------

@test "avatar_issue_watcher: dispatch routes CLAUDE_CONFIG_DIR to the default account" {
    _run_tick
    assert_success
    _assert_logged "--env CLAUDE_CONFIG_DIR=${HOME}/.claude-personal"
}

@test "avatar_issue_watcher: CLAUDE_DEFAULT_ACCOUNT selects the account dir" {
    _make_account "${HOME}/.claude-work"
    _run_tick "CLAUDE_ENABLED_ACCOUNTS=personal work" "CLAUDE_DEFAULT_ACCOUNT=work"
    assert_success
    _assert_logged "--env CLAUDE_CONFIG_DIR=${HOME}/.claude-work"
}

@test "avatar_issue_watcher: internal setup mode uses ~/.claude without account resolution" {
    printf 'internal\n' >"${HOME}/.dotfiles-setup-mode"
    _make_account "${HOME}/.claude"
    _run_tick "CLAUDE_ENABLED_ACCOUNTS="
    assert_success
    _assert_logged "--env CLAUDE_CONFIG_DIR=${HOME}/.claude"
}

@test "avatar_issue_watcher: missing account directory fails fast before opening a tab" {
    rm -rf "${HOME}/.claude-personal"
    _run_tick
    assert_failure
    assert_output --partial "Claude account directory missing"
    _refute_logged "tab create"
}

# Issue #1561. The directory check above is not enough: `claude-accounts setup`
# creates the directory, only a completed login fills it. A logged-out pane
# opens on `Not logged in`, drops every keystroke, and the tick reports
# `agent_prompt_stalled` — a symptom that names neither the account nor the
# cause. These pin the failure at the routing step, where the account is still
# in hand.
@test "avatar_issue_watcher: an account with no credentials fails fast before opening a tab" {
    rm -f "${HOME}/.claude-personal/.credentials.json"
    _run_tick
    assert_failure
    assert_output --partial "not logged in"
    _refute_logged "tab create"
    _refute_logged "agent start"
}

@test "avatar_issue_watcher: an empty credentials file fails fast the same way" {
    : >"${HOME}/.claude-personal/.credentials.json"
    _run_tick
    assert_failure
    assert_output --partial "not logged in"
    _refute_logged "tab create"
}

# PR #1566 codex review. Non-empty is not parseable: a login killed mid-write
# leaves a truncated file that clears `-s` and still opens the pane on
# `Not logged in` — the exact stall this check exists to name. `jq -e` is the
# whole of the extra test; no key of the credential format is read.
@test "avatar_issue_watcher: a truncated credentials file fails fast the same way" {
    printf '%s' '{"claudeAiOauth":{"accessToken":"te' \
        >"${HOME}/.claude-personal/.credentials.json"
    _run_tick
    assert_failure
    assert_output --partial "not logged in"
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: a credentials file that is not JSON at all fails fast" {
    printf 'not json\n' >"${HOME}/.claude-personal/.credentials.json"
    _run_tick
    assert_failure
    assert_output --partial "not logged in"
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: the credentials check names the file it looked at" {
    rm -f "${HOME}/.claude-personal/.credentials.json"
    _run_tick
    assert_failure
    assert_output --partial "${HOME}/.claude-personal/.credentials.json"
}

@test "avatar_issue_watcher: a logged-in account passes the credentials check" {
    # The mirror of the two above — the guard must not fire on the normal path.
    _run_tick
    assert_success
    _assert_logged "--env CLAUDE_CONFIG_DIR=${HOME}/.claude-personal"
}

@test "avatar_issue_watcher: unknown account name fails fast with the available list" {
    _run_tick "CLAUDE_DEFAULT_ACCOUNT=ghost"
    assert_failure
    assert_output --partial "Unknown claude account: ghost"
}

@test "avatar_issue_watcher: falls back to plain ~/.claude when no multi-account setup exists" {
    _make_account "${HOME}/.claude"
    _run_tick -u CLAUDE_ENABLED_ACCOUNTS -u CLAUDE_DEFAULT_ACCOUNT
    assert_success
    _assert_logged "--env CLAUDE_CONFIG_DIR=${HOME}/.claude"
}

@test "avatar_issue_watcher: the single-account fallback still fails fast without ~/.claude" {
    rm -rf "${HOME}/.claude" "${HOME}/.claude-personal"
    _run_tick -u CLAUDE_ENABLED_ACCOUNTS -u CLAUDE_DEFAULT_ACCOUNT
    assert_failure
}

@test "avatar_issue_watcher: the account dir is resolved once for the whole cycle" {
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

@test "avatar_issue_watcher: unset HOME and XDG_STATE_HOME does not trip set -u" {
    local _tmp="${_WORK_DIR}/nohome-tmp"
    mkdir -p "${_tmp}"
    # Open-coded rather than via _run_tick: this test needs XDG_STATE_HOME
    # *absent*, and the helper always assigns it — `env` applies assignments
    # after its own -u options, so -u could not win. Still routed through
    # _run_script so the #1473 fd fix applies here too, structurally rather
    # than by a restated redirect.
    run _run_script env -u HOME -u XDG_STATE_HOME \
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

@test "avatar_issue_watcher: a dispatch whose agent holds working leaves no gate state" {
    _run_tick "HERDR_STATUS_AFTER_PROMPT=working"
    assert_success
    assert_output --partial "held 'working' for 60s"
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "avatar_issue_watcher: a confirmed dispatch that never reaches working records a strike" {
    # The prompt landed — `agent prompt` succeeded — and a minute later the pane
    # is still idle. One /gh-flow:wave runs for minutes, so the work never
    # started.
    _run_tick
    assert_success
    assert_output --partial "No dispatched agent reached 'working' within 60s (1/2)"
    run cat "${_LIMIT_FILE}"
    assert_output --partial '"strikes": "1"'
    assert_output --partial '"backoff_until": "0"'
}

@test "avatar_issue_watcher: an agent that reaches working and falls back records a strike" {
    # Working for the first two polls of the window, idle for the remaining
    # four. `working` has to be *held*, not merely touched — and the log has to
    # say which of the two failures this was.
    _run_tick "HERDR_STATUS_AFTER_PROMPT=working" "HERDR_STATUS_AFTER_PROMPT_GETS=2"
    assert_success
    assert_output --partial "reached 'working' and fell back inside 60s (1/2)"
    run cat "${_LIMIT_FILE}"
    assert_output --partial '"strikes": "1"'
}

@test "avatar_issue_watcher: a dispatch that never lands leaves the strike count alone" {
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

@test "avatar_issue_watcher: two consecutive unproductive ticks close the gate" {
    _run_tick
    assert_success
    # A different issue next tick: strikes count consecutive *ticks*, and the
    # first one already left a tab behind for #11.
    _set_issues '[{"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}]'
    _run_tick
    assert_success
    assert_output --partial "Rate-limit gate closed for 30m"
    run cat "${_LIMIT_FILE}"
    assert_output --partial '"strikes": "0"'
    refute_output --partial '"backoff_until": "0"'
}

@test "avatar_issue_watcher: one healthy agent clears the slate for the whole tick" {
    # Issue #1444, 확정 3: one account, one quota. An agent holding `working`
    # proves the account is not spent, so the tick earns no strike even though
    # its other dispatches went nowhere — those are issue-specific failures, not
    # evidence about the quota.
    _set_issues '[
      {"number":11,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]},
      {"number":13,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}
    ]'
    _run_tick "IW_DISPATCH_PER_TICK=3" "HERDR_WORKING_AGENTS=iw-dotfiles-issue-12"
    assert_success
    assert_output --partial "Agent iw-dotfiles-issue-12 held 'working'"
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "avatar_issue_watcher: every dispatch in a tick is judged, not just the first" {
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

@test "avatar_issue_watcher: an unreadable agent status is not booked as idle" {
    # Regression (PR #1468 codex review, BLOCKER): `_hp_agent_status` reports a
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

@test "avatar_issue_watcher: an unreadable deciding poll leaves an existing strike alone" {
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

@test "avatar_issue_watcher: readable early polls do not rescue an unreadable deciding poll" {
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

@test "avatar_issue_watcher: a strike logs the pane tail as evidence" {
    _run_tick
    assert_success
    _assert_logged "agent read iw-dotfiles-issue-11 --lines 40 --format text"
    assert_output --partial "Pane tail for iw-dotfiles-issue-11 (evidence only"
    assert_output --partial "5-hour limit reached"
}

@test "avatar_issue_watcher: a healthy tick captures no pane evidence" {
    # The 40-line read is the evidence capture; the short one is the settle
    # poll (#1570) and runs on every fresh dispatch, healthy or not.
    _run_tick "HERDR_STATUS_AFTER_PROMPT=working"
    assert_success
    _refute_logged "agent read iw-dotfiles-issue-11 --lines 40"
}

@test "avatar_issue_watcher: an unreadable pane does not break the strike" {
    # `agent read` answers JSON-on-stdout with exit 0 when the target is gone.
    # Logging that as if it were pane content would be worse than saying
    # nothing, and it must not disturb the verdict either way.
    _run_tick "HERDR_READ_MODE=missing"
    assert_success
    assert_output --partial "No pane output captured for iw-dotfiles-issue-11"
    refute_output --partial '{"error"'
    run cat "${_LIMIT_FILE}"
    assert_output --partial '"strikes": "1"'
}

@test "avatar_issue_watcher: pane text cannot open the gate" {
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

@test "avatar_issue_watcher: a closed gate holds the tick without dispatching" {
    _set_limit_state "0" "$(($(date +%s) + 900))"
    _run_tick
    assert_success
    assert_output --partial "Rate-limit gate closed"
    _refute_logged "agent prompt"
}

@test "avatar_issue_watcher: a held tick opens no tab" {
    _set_limit_state "0" "$(($(date +%s) + 900))"
    _run_tick
    assert_success
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: a held tick leaves the gate deadline untouched" {
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

@test "avatar_issue_watcher: an expired backoff reopens the gate and dispatches" {
    _set_limit_state "0" "$(($(date +%s) - 60))"
    _run_tick "HERDR_STATUS_AFTER_PROMPT=working"
    assert_success
    assert_output --partial "Rate-limit gate reopened"
    _assert_logged "agent prompt iw-dotfiles-issue-11"
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "avatar_issue_watcher: an out-of-range future deadline is treated as expired" {
    _set_limit_state "0" "$(($(date +%s) + 999999))"
    _run_tick "HERDR_STATUS_AFTER_PROMPT=working"
    assert_success
    assert_output --partial "Rate-limit gate reopened"
}

@test "avatar_issue_watcher: a corrupt gate file fails open" {
    mkdir -p "${_STATE_DIR}"
    printf 'not json at all\n' >"${_LIMIT_FILE}"
    _run_tick "HERDR_STATUS_AFTER_PROMPT=working"
    assert_success
    _assert_logged "agent prompt iw-dotfiles-issue-11"
}

@test "avatar_issue_watcher: a non-numeric deadline fails open" {
    _set_limit_state "0" "soon"
    _run_tick "HERDR_STATUS_AFTER_PROMPT=working"
    assert_success
    assert_output --partial "dispatching anyway"
    _assert_logged "agent prompt iw-dotfiles-issue-11"
}

@test "avatar_issue_watcher: a productive tick clears accumulated strikes" {
    _set_limit_state "1" "0"
    _run_tick "HERDR_STATUS_AFTER_PROMPT=working"
    assert_success
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "avatar_issue_watcher: a stalled dispatch with the agent working earns no strike" {
    # herdr says `agent_prompt_stalled` but the agent is already working, so
    # _iw_prompt_issue treats it as delivered — and the same `working` carries
    # it through the observation window.
    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=working"
    assert_success
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "avatar_issue_watcher: a non-quota dispatch failure earns no strike" {
    _run_tick "HERDR_PROMPT_MODE=fail"
    assert_failure
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "avatar_issue_watcher: a non-quota failure leaves an existing strike untouched" {
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

@test "avatar_issue_watcher: repeated non-quota failures never close the gate" {
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

@test "avatar_issue_watcher: repeated non-quota failures never close a gate holding a strike" {
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

@test "avatar_issue_watcher: a state dir with no gate file ticks exactly as before" {
    mkdir -p "${_STATE_DIR}"
    _run_tick "HERDR_STATUS_AFTER_PROMPT=working"
    assert_success
    _assert_logged "agent prompt iw-dotfiles-issue-11"
    [ ! -f "${_LIMIT_FILE}" ]
}

@test "avatar_issue_watcher: an unwritable state dir warns but does not change the exit code" {
    mkdir -p "${_STATE_DIR}"
    chmod 500 "${_STATE_DIR}"
    _run_tick
    assert_success
    assert_output --partial "rate-limit gate will not survive this tick"
    chmod 700 "${_STATE_DIR}"
}

# ---------------------------------------------------------------------------
# Strike casualties and their retry (issue #1604)
# ---------------------------------------------------------------------------
#
# The gate knew a strike had happened but not *which* issue paid for it, so
# every reopen round-robined on to the next issue in the queue and the one the
# outage actually killed was never retried — an outage outliving one backoff
# window quietly ate a worktree slot per 30 minutes. These cover the three
# halves of the fix: booking the casualty, retrying it ahead of fresh work, and
# bounding those retries.

@test "avatar_issue_watcher: a strike books the issue it killed as a casualty" {
    _run_tick
    assert_success
    assert_output --partial "No dispatched agent reached 'working' within 60s (1/2)"
    assert_output --partial "Booked acme/dotfiles#11 as a rate-limit casualty"
    run cat "${_CASUALTY_FILE}"
    assert_output --partial "acme/dotfiles"
    assert_output --partial "11"
}

@test "avatar_issue_watcher: a dispatch that holds working is never booked as a casualty" {
    # The mirror of the test above, and the invariant that keeps the retry list
    # from filling up with issues that are perfectly healthy.
    _run_tick "HERDR_STATUS_AFTER_PROMPT=working"
    assert_success
    [ ! -s "${_CASUALTY_FILE}" ]
}

@test "avatar_issue_watcher: a reopened gate retries the casualty before a fresh issue" {
    # #11 was killed by the outage; #12 is what the round-robin would reach for
    # next. The casualty has to get the tick's attention first — that ordering
    # is the whole fix, since the selector never comes back to a skipped issue.
    _set_limit_state "0" "$(($(date +%s) - 60))"
    _seed_casualty 11 0
    _set_issues '[{"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}]'

    _run_tick "HERDR_STATUS_AFTER_PROMPT=working"
    assert_success
    assert_output --partial "Rate-limit gate reopened"
    assert_output --partial "Re-prompting acme/dotfiles#11 in its surviving pane"
    assert_output --partial "acme/dotfiles#11 is working again"

    local _first _second
    _first=$(grep -n -m1 -F 'agent prompt iw-dotfiles-issue-11' "${_LOG}" | cut -d: -f1)
    _second=$(grep -n -m1 -F 'agent prompt iw-dotfiles-issue-12' "${_LOG}" | cut -d: -f1)
    [ -n "${_first}" ] || fail "casualty #11 was never re-prompted"
    [ -n "${_second}" ] || fail "fresh candidate #12 was never dispatched"
    [ "${_first}" -lt "${_second}" ] ||
        fail "casualty #11 was re-prompted only after fresh candidate #12"

    # Recovered, so it stops being a casualty.
    [ ! -s "${_CASUALTY_FILE}" ]
}

@test "avatar_issue_watcher: an outage outliving the backoff does not burn the retry budget" {
    # The regression this whole mechanism exists for. The gate reopens, the
    # quota is still spent, and nothing retried holds `working` — so the row
    # keeps every attempt it had and waits for the next reopen. Burning an
    # attempt here would drop the issue after three windows of an outage that
    # routinely runs for five hours.
    _set_limit_state "0" "$(($(date +%s) - 60))"
    _seed_casualty 11 0
    _set_issues '[]'

    _run_tick
    assert_success
    assert_output --partial "the quota looks spent, so its retry budget is untouched"
    refute_output --partial "Giving up on acme/dotfiles#11"
    run cat "${_CASUALTY_FILE}"
    assert_output --partial "acme/dotfiles"
    # Still zero attempts spent — the fourth column never moved.
    assert_output --regexp 'acme/dotfiles	11	[0-9]+	0'
}

@test "avatar_issue_watcher: a casualty is given up on after _IW_MAX_ATTEMPTS with the quota recovered" {
    # #12 recovers, which is what proves the account has quota again; #11 still
    # will not run, so its failure is now something other than the outage and
    # the attempt budget is allowed to pay for it. Seeded at 2, so this pass is
    # the third and last.
    #
    # #12 sitting *after* #11 in the file is deliberate: the proof that clears
    # the budget arrives only once every casualty has been observed, so a build
    # that judged each row as it went would still read the quota as spent when
    # it reached #11.
    _set_limit_state "0" "$(($(date +%s) - 60))"
    _seed_casualty 11 2
    _seed_casualty 12 0
    _set_issues '[]'

    _run_tick "HERDR_WORKING_AGENTS=iw-dotfiles-issue-12"
    assert_success
    assert_output --partial "acme/dotfiles#12 is working again"
    assert_output --partial "Giving up on acme/dotfiles#11 after 3 attempts."
    # Both rows are gone: one recovered, one was given up on.
    [ ! -s "${_CASUALTY_FILE}" ]
}

@test "avatar_issue_watcher: a casualty whose pane is gone is redispatched from scratch" {
    # The outage took the tab with it, so there is no pane left to re-prompt.
    # Falling back to the ordinary dispatch path rebuilds workspace, tab and
    # agent — and reaching it also proves the account dir resolves this
    # early in the tick, ahead of the candidate loop that used to own it.
    _set_limit_state "0" "$(($(date +%s) - 60))"
    _seed_casualty 11 0
    _set_issues '[]'

    _run_tick "HERDR_AGENT_MISSING=iw-dotfiles-issue-11" \
        "HERDR_STATUS_AFTER_PROMPT=working"
    assert_success
    assert_output --partial "Pane for acme/dotfiles#11 is gone — redispatching from scratch"
    _assert_logged "tab create"
    _assert_logged "agent prompt iw-dotfiles-issue-11"
    assert_output --partial "acme/dotfiles#11 is working again"
    [ ! -s "${_CASUALTY_FILE}" ]
}

@test "avatar_issue_watcher: a casualty whose repo left the watch list is dropped" {
    # Nothing here can act on a repo with no local checkout, and a row that can
    # never be retried would sit in the file forever.
    _set_limit_state "0" "$(($(date +%s) - 60))"
    mkdir -p "${_STATE_DIR}"
    printf 'ghost/repo\t99\t%s\t0\n' "$(date +%s)" >"${_CASUALTY_FILE}"
    _set_issues '[]'

    _run_tick
    assert_success
    assert_output --partial "Dropping rate-limit casualty ghost/repo#99"
    [ ! -s "${_CASUALTY_FILE}" ]
}

@test "avatar_issue_watcher: a casualty whose re-prompt hits Unknown command is dropped" {
    # #2300: the surviving pane would give the same answer on every reopen.
    _set_limit_state "0" "$(($(date +%s) - 60))"
    _seed_casualty 11 0
    _set_issues '[]'

    _run_tick "HERDR_PROMPT_MODE=stall" "HERDR_AGENT_STATUS=idle" \
        "HERDR_READ_AFTER_PROMPT=● Unknown command: /gh-flow:wave"
    assert_output --partial "Re-prompting acme/dotfiles#11 in its surviving pane"
    assert_output --partial "Dropping rate-limit casualty acme/dotfiles#11"
    _refute_logged "agent send-keys"
    [ ! -s "${_CASUALTY_FILE}" ]
}

@test "avatar_issue_watcher: an open gate does not retry casualties every tick" {
    # The retry is a gate-*reopen* event. A tick that finds the gate merely open
    # — strikes on record, no backoff running — has already had its reopen, and
    # re-prompting the same panes every three minutes would be its own outage.
    _set_limit_state "1" "0"
    _seed_casualty 11 0
    _set_issues '[]'

    _run_tick
    assert_success
    refute_output --partial "Re-prompting acme/dotfiles#11"
    _refute_logged "agent prompt iw-dotfiles-issue-11"
    # Untouched, still waiting for the reopen that will act on it.
    run cat "${_CASUALTY_FILE}"
    assert_output --partial "acme/dotfiles"
}

@test "avatar_issue_watcher: a reopened gate retries its casualty even at the concurrency ceiling" {
    # The deadlock (PR #1622 codex review). The casualty's own pane is what
    # fills the last slot: its session died with the quota, but its issue is
    # still OPEN, so the zombie reclaim — which only collects panes on CLOSED
    # issues — never gives that slot back. A retry gated behind the ceiling
    # would therefore starve exactly the issue the ceiling is full *because
    # of*, on every tick, forever. Re-prompting that surviving pane opens no
    # session at all, so the ceiling has nothing to protect here.
    _set_limit_state "0" "$(($(date +%s) - 60))"
    _seed_casualty 11 0
    _set_running 11
    _set_issues '[{"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}]'

    _run_tick "IW_MAX_CONCURRENT=1" "HERDR_STATUS_AFTER_PROMPT=working"
    assert_success
    assert_output --partial "Re-prompting acme/dotfiles#11 in its surviving pane"
    _assert_logged "agent prompt iw-dotfiles-issue-11"
    assert_output --partial "acme/dotfiles#11 is working again"
    [ ! -s "${_CASUALTY_FILE}" ]

    # Exempt, not lifted: fresh work still waits for a real slot.
    assert_output --partial "1 issue session(s) already running"
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: a redispatched casualty is counted before fresh work is admitted" {
    # The stale-memo half of the same review. _iw_live_agents is memoized once
    # per tick, and the retry's missing-pane fallback opens a real tab the memo
    # cannot know about — so an uninvalidated tick would size the rest of its
    # dispatching against a count taken before the redispatch and run one over
    # _IW_MAX_CONCURRENT.
    #
    # The agent is in `agent list` from the start while its tab is not: the
    # `iw-dotfiles-issue-11` tab only appears in `tab list` once the redispatch below
    # creates it — precisely the mid-tick change the memo would otherwise miss.
    _set_limit_state "0" "$(($(date +%s) - 60))"
    _seed_casualty 11 0
    _set_live_agents 11
    mv "${_WORK_DIR}/tabs.json" "${_WORK_DIR}/tabs-after-create.json"
    _set_issues '[{"number":12,"repository":{"nameWithOwner":"acme/dotfiles"},"labels":[]}]'

    _run_tick "IW_MAX_CONCURRENT=1" \
        "HERDR_AGENT_MISSING=iw-dotfiles-issue-11" \
        "HERDR_STATUS_AFTER_PROMPT=working"
    assert_success
    assert_output --partial "Pane for acme/dotfiles#11 is gone — redispatching from scratch"
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"

    # The slot the redispatch just took is visible to the ceiling check, so #12
    # waits for the next tick instead of making two sessions out of one slot.
    assert_output --partial "1 issue session(s) already running"
    _refute_logged "--label iw-dotfiles-issue-12 --no-focus"
}

# ---------------------------------------------------------------------------
# Saturation alert (issue #1606)
# ---------------------------------------------------------------------------
#
# The alert is deliberately cause-blind: it fires on "every slot has been full
# for N ticks in a row", whatever emptied the watcher's queue. Both outages it
# exists for (#1596/#1597 stale tabs, #1604 quota retries that never resumed)
# looked identical from here, and both were found by a human asking the next
# morning rather than by the watcher saying anything.

@test "avatar_issue_watcher: consecutive saturated ticks notify exactly once at the threshold" {
    _set_running 21 22 23 24 25 26 27

    _run_tick "IW_SATURATION_ALERT_TICKS=2"
    assert_success
    # One short of the threshold: counted, not announced.
    _refute_logged "notification show"
    run cat "${_SATURATION_FILE}"
    assert_output --partial '"ticks": "1"'

    : >"${_LOG}"
    _run_tick "IW_SATURATION_ALERT_TICKS=2"
    assert_success
    [ "$(_log_count 'notification show')" -eq 1 ]
}

@test "avatar_issue_watcher: a saturated tick inside the cooldown window sends no second notification" {
    _set_running 21 22 23 24 25 26 27

    _run_tick "IW_SATURATION_ALERT_TICKS=1" "IW_SATURATION_COOLDOWN_SECONDS=10800"
    assert_success
    [ "$(_log_count 'notification show')" -eq 1 ]

    # Still saturated, still past the threshold — and still the same incident,
    # so the cooldown holds. The counter keeps climbing underneath it: the
    # cooldown gates the alert, never the record of how long this has run.
    : >"${_LOG}"
    _run_tick "IW_SATURATION_ALERT_TICKS=1" "IW_SATURATION_COOLDOWN_SECONDS=10800"
    assert_success
    _refute_logged "notification show"
    run cat "${_SATURATION_FILE}"
    assert_output --partial '"ticks": "2"'
}

@test "avatar_issue_watcher: a freed slot clears the counter and a fresh episode alerts again" {
    # The regression that matters most: without the clear, the 3h cooldown from
    # the first episode would swallow the alert for a *second, unrelated* outage
    # that started ten minutes later.
    _set_running 21 22 23 24 25 26 27
    _run_tick "IW_SATURATION_ALERT_TICKS=1" "IW_MAX_PER_REPO=9"
    assert_success
    [ "$(_log_count 'notification show')" -eq 1 ]

    # One pane gone: the tick dispatches again, so the episode is over.
    : >"${_LOG}"
    _set_panes_for 21 22 23 24 25 26
    _run_tick "IW_SATURATION_ALERT_TICKS=1" "IW_MAX_PER_REPO=9"
    assert_success
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
    [ ! -f "${_SATURATION_FILE}" ]

    # Full again, well inside the old cooldown — a new incident, and it says so.
    : >"${_LOG}"
    _set_panes_for 21 22 23 24 25 26 27
    _run_tick "IW_SATURATION_ALERT_TICKS=1" "IW_MAX_PER_REPO=9"
    assert_success
    [ "$(_log_count 'notification show')" -eq 1 ]
}

@test "avatar_issue_watcher: the saturation alert names every occupied issue and its agent status" {
    # F-2. The numbers alone would only restate the count the alert already
    # carries; the per-pane status is what separates "genuinely busy" from the
    # zombie tabs of #1596 without attaching to seven panes by hand.
    _set_running 21 22 23 24 25 26 27
    _run_tick "IW_SATURATION_ALERT_TICKS=1" "HERDR_AGENT_STATUS=done"
    assert_success
    _assert_logged "acme/dotfiles#21: done"
    _assert_logged "acme/dotfiles#24: done"
    _assert_logged "acme/dotfiles#27: done"
}

@test "avatar_issue_watcher: a tick where every offering repo sits at its own cap counts as saturated" {
    # The second way the slots fill up, and the one the total-concurrency hold
    # never sees: three of seven global slots used, but the only repo with
    # anything to dispatch is at its per-repo cap, so the tick starts nothing.
    _set_running 21 22 23
    _run_tick "IW_SATURATION_ALERT_TICKS=1"
    assert_success
    assert_output --partial "3 of its issues are already running"
    refute_output --partial "already running (max 7)"
    [ "$(_log_count 'notification show')" -eq 1 ]
}

@test "avatar_issue_watcher: an alert herdr refused does not start the cooldown" {
    # The cooldown exists to stop a *delivered* alert repeating. Stamping it on
    # a refused one would trade one noisy warning line for three silent hours,
    # which is the outcome this whole alert exists to prevent.
    _set_running 21 22 23 24 25 26 27
    _run_tick "IW_SATURATION_ALERT_TICKS=1" "HERDR_NOTIFY_FAIL=1"
    assert_success
    assert_output --partial "Could not post a herdr notification"
    run cat "${_SATURATION_FILE}"
    assert_output --partial '"last_notified": "0"'

    : >"${_LOG}"
    _run_tick "IW_SATURATION_ALERT_TICKS=1"
    assert_success
    [ "$(_log_count 'notification show')" -eq 1 ]
}

@test "avatar_issue_watcher: an empty backlog with no repo capped clears a running episode" {
    # PR #1624 review (agy FOLLOW-UP + codex Assumption): clearing keys off
    # "did a per-repo cap block anything this tick" (_select_rc == 2), not off
    # whether a candidate happened to exist. No candidates at all and no cap
    # hit is exactly the same "nothing is currently blocked" signal a real
    # dispatch gives — so it clears rather than leaving a resolved episode to
    # linger in `--status` for as long as the backlog stays empty.
    _set_saturation_state 5 0
    _set_issues '[]'
    _run_tick "IW_SATURATION_ALERT_TICKS=6"
    assert_success
    assert_output --partial "No dispatchable issue this tick."
    _refute_logged "notification show"
    [ ! -f "${_SATURATION_FILE}" ]
}

# ---------------------------------------------------------------------------
# --status (issue #1441, AC 11)
# ---------------------------------------------------------------------------

@test "avatar_issue_watcher: --status reports an open gate and runs no tick" {
    _run_tick -- --status
    assert_success
    assert_output --partial "Rate-limit gate open"
    _refute_logged "agent prompt"
    _refute_logged "search issues repo:"
}

@test "avatar_issue_watcher: --status reports gh search issues support" {
    _run_tick -- --status
    assert_success
    assert_output --partial "gh supports 'gh search issues --json'"
}

@test "avatar_issue_watcher: --status reports a gh without search (#1849)" {
    _run_tick "GH_NO_SEARCH=1" -- --status
    assert_success
    assert_output --partial "gh lacks 'gh search issues --json'"
}

@test "avatar_issue_watcher: --status tells a missing gh from an outdated one" {
    rm -f "${_BIN_DIR}/gh"
    _run_tick "PATH=$(_path_without gh)" -- --status
    assert_success
    assert_output --partial "gh not found on PATH"
}

@test "avatar_issue_watcher: --status names the state file it read" {
    _run_tick -- --status
    assert_success
    assert_output --partial "rate-limit.json"
}

@test "avatar_issue_watcher: --status reports a closed gate with the time left" {
    _set_limit_state "0" "$(($(date +%s) + 900))"
    _run_tick -- --status
    assert_success
    assert_output --partial "Rate-limit gate closed"
    assert_output --partial "15m"
    _refute_logged "agent prompt"
}

@test "avatar_issue_watcher: --status reports accumulated strikes while the gate is open" {
    _set_limit_state "1" "0"
    _run_tick -- --status
    assert_success
    assert_output --partial "1/2"
    assert_output --partial "Rate-limit gate open"
}

@test "avatar_issue_watcher: --status leaves an expired gate file on disk" {
    _set_limit_state "0" "$(($(date +%s) - 60))"
    _run_tick -- --status
    assert_success
    assert_output --partial "Rate-limit gate open"
    # Reporting is not deciding: only a real tick may clear an expired file,
    # the same reason --dry-run stays clear of the gate check.
    [ -f "${_LIMIT_FILE}" ]
}

@test "avatar_issue_watcher: --status treats an out-of-range deadline as expired" {
    _set_limit_state "0" "$(($(date +%s) + 999999))"
    _run_tick -- --status
    assert_success
    assert_output --partial "Rate-limit gate open"
}

@test "avatar_issue_watcher: --status fails open on a corrupt gate file" {
    mkdir -p "${_STATE_DIR}"
    printf 'not json at all\n' >"${_LIMIT_FILE}"
    _run_tick -- --status
    assert_success
    assert_output --partial "unreadable"
}

@test "avatar_issue_watcher: --status reports a saturation episode already in progress" {
    # The command a human runs after the alert wakes them: how long have the
    # slots been full, and has the alert already fired for this episode.
    _set_saturation_state 4 0
    _run_tick "IW_SATURATION_ALERT_TICKS=20" -- --status
    assert_success
    assert_output --partial "saturation.json"
    assert_output --partial "4/20"
    assert_output --partial "no alert sent yet"
}

@test "avatar_issue_watcher: --status reports the actual remaining cooldown, not the cooldown's fixed length" {
    # PR #1624 review (codex BLOCKER + agy FOLLOW-UP): the line used to print
    # IW_SATURATION_COOLDOWN_SECONDS verbatim regardless of elapsed time, so a
    # cooldown 1h into its 3h window still read as "next after 180m" — never
    # counting down. 3600s elapsed of a 10800s cooldown leaves 7200s = 120m.
    _set_saturation_state 20 "$(($(date +%s) - 3600))"
    _run_tick "IW_SATURATION_ALERT_TICKS=20" "IW_SATURATION_COOLDOWN_SECONDS=10800" -- --status
    assert_success
    assert_output --partial "120m"
    refute_output --partial "180m"
}

@test "avatar_issue_watcher: --status reports the cooldown as elapsed once it has passed" {
    _set_saturation_state 20 "$(($(date +%s) - 20000))"
    _run_tick "IW_SATURATION_ALERT_TICKS=20" "IW_SATURATION_COOLDOWN_SECONDS=10800" -- --status
    assert_success
    assert_output --partial "cooldown elapsed"
}

@test "avatar_issue_watcher: --status reports no saturation episode when there is no counter file" {
    _run_tick -- --status
    assert_success
    assert_output --partial "No saturation episode"
}

@test "avatar_issue_watcher: --status does not take the tick lock" {
    _hold_lock
    _run_tick -- --status
    assert_success
    refute_output --partial "already running"
}

@test "avatar_issue_watcher: --status answers even without herdr on PATH" {
    rm -f "${_BIN_DIR}/herdr"
    _run_tick "PATH=$(_path_without herdr)" -- --status
    assert_success
    assert_output --partial "Rate-limit gate open"
    refute_output --partial "herdr not found"
}

# ---------------------------------------------------------------------------
# The suite fails loudly (issue #1473)
# ---------------------------------------------------------------------------
#
# A red case in this file used to print no result line at all: the tick handed
# its stubs bats' own stdin, a stub drained it, and on a stdin that never sends
# EOF the drain blocked forever — one regression turned a red run into a stuck
# one, in CI and in the terminal alike. These cases run a deliberately red
# child suite under exactly that stdin and assert it comes back red *and*
# bounded, so the harness can never go back to swallowing its own failures.

@test "avatar_issue_watcher: a red assertion after a healthy tick reports not ok" {
    _run_child_suite <<'PROBE'
@test "probe: healthy tick then a red assertion" {
    _run_tick
    assert_output --partial "THIS-STRING-CANNOT-APPEAR"
}
PROBE
    _assert_not_hung "healthy tick"
    assert_equal "${status}" 1
    assert_output --partial "not ok 1 probe: healthy tick then a red assertion"
}

@test "avatar_issue_watcher: a red assertion after a failed dispatch reports not ok" {
    _run_child_suite <<'PROBE'
@test "probe: failed dispatch then a red assertion" {
    _run_tick "HERDR_PROMPT_MODE=fail"
    assert_output --partial "THIS-STRING-CANNOT-APPEAR"
}
PROBE
    _assert_not_hung "failed dispatch"
    assert_equal "${status}" 1
    assert_output --partial "not ok 1 probe: failed dispatch then a red assertion"
}

@test "avatar_issue_watcher: a red assertion without a tick still reports not ok" {
    # The control: this shape always reported red, and must keep doing so —
    # it is what proves the two cases above measure the tick, not bats.
    _run_child_suite <<'PROBE'
@test "probe: no tick, just a red assertion" {
    assert_equal "x" "y"
}
PROBE
    _assert_not_hung "no tick"
    assert_equal "${status}" 1
    assert_output --partial "not ok 1 probe: no tick, just a red assertion"
}

@test "avatar_issue_watcher: a green suite stays green on a never-EOF stdin" {
    # The other half of the guarantee: the fix must not have bought a bounded
    # red run by breaking the passing path. A full tick, same stdin, still 0.
    _run_child_suite <<'PROBE'
@test "probe: healthy tick, honest assertion" {
    _run_tick
    assert_success
    assert_output --partial "dispatched"
}
PROBE
    _assert_not_hung "green suite"
    assert_equal "${status}" 0
    assert_output --partial "ok 1 probe: healthy tick, honest assertion"
}

# ---------------------------------------------------------------------------
# Entry-point resolution (issue #2209)
# ---------------------------------------------------------------------------

# An Agent Factory copy: renamed `issue-af07`, description kept, with the
# folded block splitting `Use for` and `/gh-flow:wave` across two lines.
_AF_FRONTMATTER='name: issue-af07
description: >-
  Chain one GitHub issue to a reviewed PR. Use for
  /gh-flow:wave, "full flow on #42".
metadata:
  agent-factory:
    kind: item'

@test "avatar_issue_watcher: an installed, enabled gh-flow plugin dispatches /gh-flow:wave" {
    printf '{"enabledPlugins":{"gh-flow@test":true}}\n' >"${HOME}/.claude-personal/settings.json"
    _write_skill "${HOME}/.claude-personal" issue-af07 "${_AF_FRONTMATTER}"
    _run_tick
    assert_success
    # The plugin wins over a flat copy: upstream is the SSOT.
    _assert_logged "agent prompt iw-dotfiles-issue-11 /gh-flow:wave 11"
}

@test "avatar_issue_watcher: a disabled gh-flow plugin falls through to the flat copy" {
    printf '{"enabledPlugins":{"gh-flow@test":false}}\n' >"${HOME}/.claude-personal/settings.json"
    _write_skill "${HOME}/.claude-personal" issue-af07 "${_AF_FRONTMATTER}"
    _run_tick
    assert_success
    _assert_logged "agent prompt iw-dotfiles-issue-11 /issue-af07 11"
}

@test "avatar_issue_watcher: settings.local.json disabling the plugin falls through to the flat copy" {
    printf '{"enabledPlugins":{"gh-flow@test":true}}\n' >"${HOME}/.claude-personal/settings.json"
    printf '{"enabledPlugins":{"gh-flow@test":false}}\n' >"${HOME}/.claude-personal/settings.local.json"
    _write_skill "${HOME}/.claude-personal" issue-af07 "${_AF_FRONTMATTER}"
    _run_tick
    assert_success
    _assert_logged "agent prompt iw-dotfiles-issue-11 /issue-af07 11"
}

@test "avatar_issue_watcher: a disabled plugin with no flat copy dispatches nothing" {
    printf '{"enabledPlugins":{"gh-flow@test":false}}\n' >"${HOME}/.claude-personal/settings.json"
    _run_tick
    assert_failure
    assert_output --partial "has no /gh-flow:wave entry point"
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: a malformed settings.json leaves an installed plugin enabled" {
    printf '{not json\n' >"${HOME}/.claude-personal/settings.json"
    _run_tick
    assert_success
    _assert_logged "agent prompt iw-dotfiles-issue-11 /gh-flow:wave 11"
}

@test "avatar_issue_watcher: no plugin dispatches the Agent Factory copy by its anchor" {
    rm -rf "${HOME}/.claude-personal/plugins"
    _write_skill "${HOME}/.claude-personal" issue-af07 "${_AF_FRONTMATTER}"
    _run_tick
    assert_success
    _assert_logged "agent prompt iw-dotfiles-issue-11 /issue-af07 11"
    assert_output --partial "Dispatched to iw-dotfiles-issue-11: /issue-af07 11"
}

@test "avatar_issue_watcher: two anchored copies dispatch nothing and open no tab" {
    rm -rf "${HOME}/.claude-personal/plugins"
    _write_skill "${HOME}/.claude-personal" issue-af07 "${_AF_FRONTMATTER}"
    _write_skill "${HOME}/.claude-personal" issue-af08 "name: issue-af08
description: Use for /gh-flow:wave."
    _run_tick
    assert_failure
    assert_output --partial "several /gh-flow:wave entry points"
    _refute_logged "tab create"
    _refute_logged "agent prompt"
}

@test "avatar_issue_watcher: no anchored copy dispatches nothing and opens no tab" {
    rm -rf "${HOME}/.claude-personal/plugins"
    # Mentions the chain without the slash form — must not count as the anchor.
    _write_skill "${HOME}/.claude-personal" wave-af05 "name: wave-af05
description: Carry one issue through gh-flow:wave, then via gh-flow:wave again."
    _run_tick
    assert_failure
    assert_output --partial "has no /gh-flow:wave entry point"
    _refute_logged "tab create"
    _refute_logged "agent prompt"
    # Logged once for the tick, not once per attempt.
    [ "$(printf '%s\n' "${output}" | grep -c 'has no /gh-flow:wave entry point')" -eq 1 ]
}

@test "avatar_issue_watcher: a casualty re-prompt sends the resolved entry point" {
    rm -rf "${HOME}/.claude-personal/plugins"
    _write_skill "${HOME}/.claude-personal" issue-af07 "${_AF_FRONTMATTER}"
    _set_limit_state "0" "$(($(date +%s) - 60))"
    _seed_casualty 11 0
    _set_issues '[]'

    _run_tick "HERDR_STATUS_AFTER_PROMPT=working"
    assert_success
    assert_output --partial "Re-prompting acme/dotfiles#11 in its surviving pane"
    _assert_logged "agent prompt iw-dotfiles-issue-11 /issue-af07 11"
    _refute_logged "/gh-flow:wave 11"
}

@test "avatar_issue_watcher: a flat copy anchored on the retired /gh-flow:issue alias is not an entry point" {
    rm -rf "${HOME}/.claude-personal/plugins"
    _write_skill "${HOME}/.claude-personal" issue-af03 "name: issue-af03
description: Use for /gh-flow:issue."
    _run_tick
    assert_failure
    assert_output --partial "has no /gh-flow:wave entry point"
    _refute_logged "agent prompt"
}

# ---------------------------------------------------------------------------
# cwd mode (issue #2243)
# ---------------------------------------------------------------------------

# Give the fixture checkout an origin and run the next tick from inside it.
_cwd_repo() {
    git -C "${_REPO_DIR}" remote add origin "$1"
    _RUN_DIR="${_REPO_DIR}"
}

@test "avatar_issue_watcher: cwd mode dry-runs the current repo with no watch list" {
    _cwd_repo "https://github.com/acme/dotfiles.git"
    _run_tick "IW_WATCHED_REPOS=${_WORK_DIR}/nope.json" -- --dry-run
    assert_success
    refute_output --partial "Watch list not found"
    assert_output --partial "cwd mode"
    assert_output --partial "acme/dotfiles#11  (${_REPO_DIR}, github.com)"
}

@test "avatar_issue_watcher: cwd mode ignores the watch-list file's other repos" {
    _make_repo "${_WORK_DIR}/other"
    _write_watch_file '[{"repo":"acme/other","path":"'"${_WORK_DIR}/other"'"}]'
    _set_issues '[{"number":21,"repository":{"nameWithOwner":"acme/other"},"labels":[]}]'
    _cwd_repo "https://github.com/acme/dotfiles.git"
    _run_tick -- --dry-run
    assert_success
    assert_output --partial "No dispatchable issue"
}

@test "avatar_issue_watcher: cwd mode reads a GHES scp-style origin from a subdirectory" {
    _cwd_repo "git@ghes.example.com:acme/dotfiles.git"
    mkdir -p "${_REPO_DIR}/sub"
    _RUN_DIR="${_REPO_DIR}/sub"
    _run_tick "IW_WATCHED_REPOS=${_WORK_DIR}/nope.json" -- --dry-run
    assert_success
    assert_output --partial "acme/dotfiles#11  (${_REPO_DIR}, ghes.example.com)"
}

@test "avatar_issue_watcher: cwd mode reads an ssh:// origin with a port" {
    _cwd_repo "ssh://git@ghes.example.com:2222/acme/dotfiles"
    _run_tick "IW_WATCHED_REPOS=${_WORK_DIR}/nope.json" -- --dry-run
    assert_success
    assert_output --partial "acme/dotfiles#11  (${_REPO_DIR}, ghes.example.com)"
}

@test "avatar_issue_watcher: cwd mode with an unparsable origin fails without falling back" {
    _cwd_repo "/srv/git/dotfiles"
    _run_tick -- --dry-run
    assert_failure
    assert_output --partial "cannot read owner/repo from origin URL"
    refute_output --partial "Dry run"
}

@test "avatar_issue_watcher: --cwd keeps the watch-list mode even inside a repo" {
    _cwd_repo "https://github.com/acme/dotfiles.git"
    _run_tick "IW_WATCHED_REPOS=${_WORK_DIR}/nope.json" -- --cwd "${_REPO_DIR}" --dry-run
    assert_failure
    assert_output --partial "Watch list not found"
}

@test "avatar_issue_watcher: a repo without origin keeps the watch-list mode" {
    _RUN_DIR="${_REPO_DIR}"
    _run_tick "IW_WATCHED_REPOS=${_WORK_DIR}/nope.json" -- --dry-run
    assert_failure
    assert_output --partial "Watch list not found"
}

# ---------------------------------------------------------------------------
# watch list|add|remove (issue #2243)
# ---------------------------------------------------------------------------

_watch_json() {
    jq -c "$1" "${_WATCH_FILE}"
}

@test "avatar_issue_watcher: watch list reports a missing file" {
    rm -f "${_WATCH_FILE}"
    _run_tick -- watch list
    assert_success
    assert_output --partial "Watch list not found: ${_WATCH_FILE}"
}

@test "avatar_issue_watcher: watch list prints the entries and touches no gh/herdr" {
    _run_tick -- watch list
    assert_success
    assert_output --partial "${_WATCH_FILE}"
    assert_output --partial "acme/dotfiles  (${_REPO_DIR}, github.com)"
    [ ! -s "${_LOG}" ]
}

@test "avatar_issue_watcher: watch add creates a missing file as a bare array" {
    rm -f "${_WATCH_FILE}"
    _run_tick -- watch add acme/new --path "${_WORK_DIR}" --host ghes.example.com
    assert_success
    [ "$(_watch_json '.')" = '[{"repo":"acme/new","path":"'"${_WORK_DIR}"'","host":"ghes.example.com"}]' ]
}

@test "avatar_issue_watcher: watch add creates the default file and its parent dirs" {
    # Empty override = default path, inside the sandbox $HOME.
    local _default="${HOME}/.avatars/issue-watcher/watched-repos.json"
    [ ! -e "${HOME}/.avatars" ]
    _run_tick IW_WATCHED_REPOS= -- watch add acme/new --path "${_WORK_DIR}"
    assert_success
    assert_output --partial "in ${_default}"
    [ "$(jq -c '.[0].repo' "${_default}")" = '"acme/new"' ]
}

@test "avatar_issue_watcher: the old agent-factory watch list is never read" {
    local _old="${HOME}/.agent-factory/avatars/issue-watcher/watched-repos.json"
    mkdir -p "$(dirname "${_old}")"
    printf '%s' '[{"repo":"acme/legacy","path":"/x","host":"github.com"}]' >"${_old}"
    _run_tick IW_WATCHED_REPOS= -- watch list
    assert_success
    assert_output --partial "Watch list not found: ${HOME}/.avatars/issue-watcher/watched-repos.json"
    refute_output --partial "acme/legacy"
}

@test "avatar_issue_watcher: watch add with no argument adds the current checkout" {
    rm -f "${_WATCH_FILE}"
    _cwd_repo "git@github.com:acme/dotfiles.git"
    _run_tick -- watch add
    assert_success
    [ "$(_watch_json '.[0] | [.repo, .path, .host]')" = '["acme/dotfiles","'"${_REPO_DIR}"'","github.com"]' ]
}

@test "avatar_issue_watcher: watch add of a listed repo updates it without a duplicate" {
    _write_watch_file '{"repos":[{"repo":"acme/dotfiles","path":"/old","host":"github.com","post_merge_verify":true,"post_merge_verify_skill":"gh-verify:live"}],"note":1}'
    _run_tick -- watch add acme/dotfiles --path "${_WORK_DIR}" --host ghes.example.com
    assert_success
    assert_output --partial "Updated acme/dotfiles"
    [ "$(_watch_json '.repos | length')" = "1" ]
    [ "$(_watch_json '.repos[0]')" = '{"repo":"acme/dotfiles","path":"'"${_WORK_DIR}"'","host":"ghes.example.com","post_merge_verify":true,"post_merge_verify_skill":"gh-verify:live"}' ]
    [ "$(_watch_json '.note')" = "1" ]
}

@test "avatar_issue_watcher: watch add backs up the old file and leaves no temp file" {
    cp "${_WATCH_FILE}" "${_WORK_DIR}/before.json"
    _run_tick -- watch add acme/new --path "${_WORK_DIR}"
    assert_success
    cmp "${_WATCH_FILE}.bak-$(date +%Y%m%d)" "${_WORK_DIR}/before.json"
    [ "$(_watch_json 'length')" = "2" ]
    [ -z "$(find "${_WORK_DIR}" -maxdepth 1 -name 'watched-repos.json.tmp.*')" ]
}

@test "avatar_issue_watcher: watch add of a new repo needs a path outside its checkout" {
    _run_tick -- watch add acme/new
    assert_failure
    assert_output --partial "pass --path"
}

@test "avatar_issue_watcher: watch add with no argument outside a repo fails with usage" {
    _run_tick -- watch add
    assert_failure
    assert_output --partial "not a git checkout"
    assert_output --partial "Usage: avatar_issue_watcher.sh watch"
}

@test "avatar_issue_watcher: watch add and remove leave broken JSON untouched" {
    _write_watch_file '{not json'
    cp "${_WATCH_FILE}" "${_WORK_DIR}/before.json"
    _run_tick -- watch add acme/new --path "${_WORK_DIR}"
    assert_failure
    assert_output --partial "not valid JSON"
    _run_tick -- watch remove acme/dotfiles
    assert_failure
    _run_tick -- watch list
    assert_failure
    cmp "${_WATCH_FILE}" "${_WORK_DIR}/before.json"
    [ ! -e "${_WATCH_FILE}.bak-$(date +%Y%m%d)" ]
}

@test "avatar_issue_watcher: watch remove drops the repo and keeps the others' fields" {
    _write_watch_file '[{"repo":"acme/dotfiles","path":"/a"},{"repo":"acme/x","path":"/b","post_merge_verify":true,"post_merge_verify_skill":"gh-verify:live"}]'
    _run_tick -- watch remove acme/dotfiles
    assert_success
    [ "$(_watch_json '.')" = '[{"repo":"acme/x","path":"/b","post_merge_verify":true,"post_merge_verify_skill":"gh-verify:live"}]' ]
}

@test "avatar_issue_watcher: watch remove with no argument removes the current checkout" {
    _write_watch_file '{"repos":[{"repo":"acme/dotfiles","path":"/a"},{"repo":"acme/x","path":"/b"}]}'
    _cwd_repo "https://github.com/acme/dotfiles"
    _run_tick -- watch remove
    assert_success
    [ "$(_watch_json '.')" = '{"repos":[{"repo":"acme/x","path":"/b"}]}' ]
}

@test "avatar_issue_watcher: watch remove of an unlisted repo fails and changes nothing" {
    cp "${_WATCH_FILE}" "${_WORK_DIR}/before.json"
    _run_tick -- watch remove acme/nope
    assert_failure
    assert_output --partial "acme/nope is not in the watch list"
    cmp "${_WATCH_FILE}" "${_WORK_DIR}/before.json"
}

@test "avatar_issue_watcher: an unknown watch command fails with usage" {
    _run_tick -- watch frob
    assert_failure
    assert_output --partial "Unknown watch command: frob"
}

@test "avatar_issue_watcher: watch add edits a symlinked watch list at its target" {
    mv "${_WATCH_FILE}" "${_WORK_DIR}/real.json"
    ln -s "${_WORK_DIR}/real.json" "${_WATCH_FILE}"
    _run_tick -- watch add acme/new --path "${_WORK_DIR}"
    assert_success
    [ -L "${_WATCH_FILE}" ]
    [ "$(jq -c 'length' "${_WORK_DIR}/real.json")" = "2" ]
}

@test "avatar_issue_watcher: cwd mode resolves an ssh config alias to its real host" {
    _cwd_repo "git@gh-work:acme/dotfiles.git"
    _run_tick "IW_WATCHED_REPOS=${_WORK_DIR}/nope.json" -- --dry-run
    assert_success
    assert_output --partial "acme/dotfiles#11  (${_REPO_DIR}, github.com)"
}

@test "avatar_issue_watcher: cwd mode keeps github.com when ssh routes it via ssh.github.com" {
    _cwd_repo "git@github.com:acme/dotfiles.git"
    _run_tick "IW_WATCHED_REPOS=${_WORK_DIR}/nope.json" -- --dry-run
    assert_success
    assert_output --partial "acme/dotfiles#11  (${_REPO_DIR}, github.com)"
    refute_output --partial "ssh.github.com"
}

@test "avatar_issue_watcher: cwd mode maps an ssh:// origin naming ssh.github.com to github.com" {
    _cwd_repo "ssh://git@ssh.github.com:443/acme/dotfiles.git"
    _run_tick "IW_WATCHED_REPOS=${_WORK_DIR}/nope.json" -- --dry-run
    assert_success
    assert_output --partial "acme/dotfiles#11  (${_REPO_DIR}, github.com)"
    refute_output --partial "ssh.github.com"
}

@test "avatar_issue_watcher: an unparsable origin's error drops embedded credentials" {
    _cwd_repo "https://user:s3cret@ghes.example.com/a/b/c"
    _run_tick -- --dry-run
    assert_failure
    assert_output --partial "https://ghes.example.com/a/b/c"
    refute_output --partial "s3cret"
}

@test "avatar_issue_watcher: watch add from a worktree keeps a listed entry's path" {
    _cwd_repo "https://github.com/acme/dotfiles"
    _add_worktree 11
    _RUN_DIR="$(_worktree_path 11)"
    _run_tick -- watch add
    assert_success
    assert_output --partial "Updated acme/dotfiles"
    [ "$(_watch_json '.[0].path')" = "\"${_REPO_DIR}\"" ]
}

@test "avatar_issue_watcher: watch add --path of a worktree stores its main checkout" {
    rm -f "${_WATCH_FILE}"
    _add_worktree 11
    _run_tick -- watch add acme/dotfiles --path "$(_worktree_path 11)"
    assert_success
    [ "$(_watch_json '.[0].path')" = "\"${_REPO_DIR}\"" ]
}

@test "avatar_issue_watcher: watch add from a worktree of an unlisted repo stores the main checkout" {
    rm -f "${_WATCH_FILE}"
    _cwd_repo "https://github.com/acme/dotfiles"
    _add_worktree 11
    _RUN_DIR="$(_worktree_path 11)"
    _run_tick -- watch add
    assert_success
    [ "$(_watch_json '.[0].path')" = "\"${_REPO_DIR}\"" ]
}

# ---------------------------------------------------------------------------
# label list|add|remove — the excluded-labels file
# ---------------------------------------------------------------------------

_label_json() {
    jq -c "$1" "${_LABEL_FILE}"
}

@test "avatar_issue_watcher: label list reports the four default labels and its source" {
    _run_tick -- label list
    assert_success
    assert_output --partial "source: default (no file at ${_LABEL_FILE})"
    assert_output --partial "wontfix"
    assert_output --partial "not-implement"
    assert_output --partial "TODO"
    assert_output --partial "manual"
    refute_output --partial "보류"
    [ ! -e "${_LABEL_FILE}" ]
    [ ! -s "${_LOG}" ]
}

@test "avatar_issue_watcher: the label file defaults to the watch list's directory" {
    _run_tick IW_EXCLUDE_LABELS_FILE= -- label add 보류
    assert_success
    [ "$(jq -c '.[-1]' "${_WORK_DIR}/excluded-labels.json")" = '"보류"' ]
}

@test "avatar_issue_watcher: label add seeds an absent file from the default set" {
    _run_tick -- label add 보류
    assert_success
    assert_output --partial "Excluded 보류 in ${_LABEL_FILE}"
    [ "$(_label_json '.')" = '["wontfix","not-implement","TODO","manual","보류"]' ]
    _run_tick -- label list
    assert_success
    assert_output --partial "source: file (${_LABEL_FILE})"
    assert_output --partial "보류"
}

@test "avatar_issue_watcher: label add is idempotent" {
    printf '%s\n' '["wontfix"]' >"${_LABEL_FILE}"
    _run_tick -- label add wontfix "on hold" "on hold"
    assert_success
    assert_output --partial "Already excluded: wontfix"
    [ "$(_label_json '.')" = '["wontfix","on hold"]' ]
    cp "${_LABEL_FILE}" "${_WORK_DIR}/before.json"
    _run_tick -- label add wontfix
    assert_success
    cmp "${_LABEL_FILE}" "${_WORK_DIR}/before.json"
}

@test "avatar_issue_watcher: label add rejects empty, comma, TAB and US labels" {
    local _bad
    for _bad in "" "a,b" "$(printf 'a\tb')" "$(printf 'a\037b')"; do
        _run_tick -- label add ok "${_bad}"
        assert_failure
        assert_output --partial "Invalid label"
    done
    _run_tick -- label add
    assert_failure
    assert_output --partial "needs at least one label"
    [ ! -e "${_LABEL_FILE}" ]
}

@test "avatar_issue_watcher: label remove drops a label and warns on a missing one" {
    _run_tick -- label remove TODO nope
    assert_success
    assert_output --partial "Not in the exclude list: nope"
    assert_output --partial "Removed TODO"
    [ "$(_label_json '.')" = '["wontfix","not-implement","manual"]' ]
}

@test "avatar_issue_watcher: label remove of only missing labels is a no-op" {
    printf '%s\n' '["wontfix"]' >"${_LABEL_FILE}"
    cp "${_LABEL_FILE}" "${_WORK_DIR}/before.json"
    _run_tick -- label remove nope
    assert_success
    assert_output --partial "Not in the exclude list: nope"
    cmp "${_LABEL_FILE}" "${_WORK_DIR}/before.json"
    [ ! -e "${_LABEL_FILE}.bak-$(date +%Y%m%d)" ]
}

@test "avatar_issue_watcher: label writes back up the old file and leave no temp file" {
    printf '%s\n' '["wontfix"]' >"${_LABEL_FILE}"
    cp "${_LABEL_FILE}" "${_WORK_DIR}/before.json"
    _run_tick -- label add manual
    assert_success
    cmp "${_LABEL_FILE}.bak-$(date +%Y%m%d)" "${_WORK_DIR}/before.json"
    [ -z "$(find "${_WORK_DIR}" -maxdepth 1 -name 'excluded-labels.json.tmp.*')" ]
}

@test "avatar_issue_watcher: label add, remove and list leave broken JSON untouched" {
    printf '%s\n' '{not json' >"${_LABEL_FILE}"
    cp "${_LABEL_FILE}" "${_WORK_DIR}/before.json"
    _run_tick -- label add x
    assert_failure
    assert_output --partial "left untouched"
    _run_tick -- label remove wontfix
    assert_failure
    _run_tick -- label list
    assert_failure
    printf '%s\n' '{"labels":["x"]}' >"${_LABEL_FILE}"
    _run_tick -- label add x
    assert_failure
    printf '%s\n' '{not json' >"${_LABEL_FILE}"
    cmp "${_LABEL_FILE}" "${_WORK_DIR}/before.json"
    [ ! -e "${_LABEL_FILE}.bak-$(date +%Y%m%d)" ]
}

@test "avatar_issue_watcher: label add with \$IW_EXCLUDE_LABELS set writes the file and warns" {
    _run_tick IW_EXCLUDE_LABELS=x -- label add y
    assert_success
    assert_output --partial "overrides the file"
    [ "$(_label_json '.[-1]')" = '"y"' ]
    _run_tick IW_EXCLUDE_LABELS=x,z -- label list
    assert_success
    assert_output --partial "source: env"
    refute_output --partial "wontfix"
}

@test "avatar_issue_watcher: an unknown label command fails with usage" {
    _run_tick -- label frob
    assert_failure
    assert_output --partial "Unknown label command: frob"
    assert_output --partial "Usage: avatar_issue_watcher.sh label"
}

@test "avatar_issue_watcher: the label file replaces the default set at selection" {
    printf '%s\n' '["보류"]' >"${_LABEL_FILE}"
    _issues_with_labels 11 보류
    _run_tick
    assert_success
    assert_output --partial "excluded label"
    _refute_logged "tab create"
    # manual is a default label, but the file no longer lists it.
    _issues_with_labels 11 manual
    _run_tick
    assert_success
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
}

@test "avatar_issue_watcher: \$IW_EXCLUDE_LABELS beats the label file at selection" {
    printf '%s\n' '["manual"]' >"${_LABEL_FILE}"
    _issues_with_labels 11 manual
    _run_tick IW_EXCLUDE_LABELS=other
    assert_success
    _assert_logged "--label iw-dotfiles-issue-11 --no-focus"
}

@test "avatar_issue_watcher: a broken label file falls back to the default set at selection" {
    printf '%s\n' '{not json' >"${_LABEL_FILE}"
    _issues_with_labels 11 TODO
    _run_tick
    assert_success
    assert_output --partial "using the default set"
    _refute_logged "tab create"
}

# ---------------------------------------------------------------------------
# Targeted run: one issue reference instead of the search
# ---------------------------------------------------------------------------

# Run the pure parser alone, extracted from the script: sourcing the script
# would run main() (its entry guard compares BASH_SOURCE with $0).
_parse_ref() {
    run bash -c "$(sed -n '/^_iw_parse_issue_ref()/,/^}/p' "${SCRIPT}")
_iw_parse_issue_ref \"\$1\"" _ "$1"
}

@test "avatar_issue_watcher: issue-ref parser reads URL, owner/repo#N, #N and N" {
    _parse_ref "https://github.com/acme/dotfiles/issues/11"
    assert_success
    assert_output "$(printf 'github.com\tacme/dotfiles\t11')"
    _parse_ref "https://github.com/acme/dotfiles/issues/11/#issuecomment-9"
    assert_output "$(printf 'github.com\tacme/dotfiles\t11')"
    _parse_ref "https://ghes.example.com/acme/dotfiles/issues/7?x=1"
    assert_output "$(printf 'ghes.example.com\tacme/dotfiles\t7')"
    _parse_ref "acme/dotfiles#11"
    assert_output "$(printf '\tacme/dotfiles\t11')"
    _parse_ref "#11"
    assert_output "$(printf '\t\t11')"
    _parse_ref "11"
    assert_output "$(printf '\t\t11')"
}

@test "avatar_issue_watcher: issue-ref parser rejects garbage" {
    local _r
    for _r in "" abc 0 007 "a#5" "a/b/c#5" "acme/dotfiles#5x" \
        "https://github.com/acme/dotfiles/pull/5" "https://github.com/issues/5" \
        "https:///acme/dotfiles/issues/1"; do
        _parse_ref "${_r}"
        [ "${status}" -eq 1 ] || fail "accepted: ${_r}"
    done
}

@test "avatar_issue_watcher: a garbage issue ref fails before any gh call" {
    _run_tick -- --dry-run "not-an-issue"
    assert_failure
    assert_output --partial "Not an issue reference: not-an-issue"
    [ ! -s "${_LOG}" ]
}

@test "avatar_issue_watcher: --force without an issue ref is rejected" {
    _run_tick -- --force
    assert_failure
    assert_output --partial "--force only applies to a targeted run"
    [ ! -s "${_LOG}" ]
}

@test "avatar_issue_watcher: a targeted run skips the search and dispatches that issue" {
    _run_tick -- "https://github.com/acme/dotfiles/issues/12"
    assert_success
    _refute_logged "search issues"
    _assert_logged "gh issue view 12 --repo acme/dotfiles --json number,state,labels"
    _assert_logged "--label iw-dotfiles-issue-12 --no-focus"
    _assert_logged "/gh-flow:wave 12"
    _refute_logged "iw-dotfiles-issue-11"
}

@test "avatar_issue_watcher: targeted dry-run prints the dispatch and touches no state" {
    _run_tick -- --dry-run "acme/dotfiles#12"
    assert_success
    assert_output --partial "Dry run — would dispatch:"
    assert_output --partial "acme/dotfiles#12  (${_REPO_DIR}, github.com)"
    _refute_logged "search issues"
    _refute_logged "tab create"
    [ ! -f "${_STATE_DIR}/select.json" ]
    [ ! -f "${_SATURATION_FILE}" ]
}

@test "avatar_issue_watcher: a targeted run leaves the round-robin cursor alone" {
    mkdir -p "${_STATE_DIR}"
    printf '{ "last_repo": "acme/other" }\n' >"${_STATE_DIR}/select.json"
    _run_tick -- "acme/dotfiles#12"
    assert_success
    _assert_logged "--label iw-dotfiles-issue-12 --no-focus"
    [ "$(cat "${_STATE_DIR}/select.json")" = '{ "last_repo": "acme/other" }' ]
    [ ! -f "${_SATURATION_FILE}" ]
}

@test "avatar_issue_watcher: a bare #N resolves to the cwd checkout's origin" {
    _cwd_repo "git@ghes.example.com:acme/dotfiles.git"
    _run_tick "IW_WATCHED_REPOS=${_WORK_DIR}/nope.json" -- --dry-run "#12"
    assert_success
    assert_output --partial "acme/dotfiles#12  (${_REPO_DIR}, ghes.example.com)"
}

@test "avatar_issue_watcher: a GHES URL matches a GHES watch-list entry" {
    _write_watch_file '[{"repo":"acme/dotfiles","path":"'"${_REPO_DIR}"'","host":"ghes.example.com"}]'
    _run_tick -- --dry-run "https://ghes.example.com/acme/dotfiles/issues/12/"
    assert_success
    assert_output --partial "acme/dotfiles#12  (${_REPO_DIR}, ghes.example.com)"
    _assert_logged "gh issue view 12 --repo acme/dotfiles"
}

@test "avatar_issue_watcher: a URL host differing from the entry's host fails" {
    _run_tick -- --dry-run "https://ghes.example.com/acme/dotfiles/issues/12"
    assert_failure
    assert_output --partial "the URL names host ghes.example.com, but its entry uses github.com"
    _refute_logged "issue view"
}

@test "avatar_issue_watcher: a repo neither watched nor the cwd checkout fails" {
    _run_tick -- --dry-run "acme/unknown#3"
    assert_failure
    assert_output --partial "acme/unknown is neither on the watch list nor the current checkout"
    assert_output --partial "watch add acme/unknown --path P"
    _refute_logged "issue view"
}

@test "avatar_issue_watcher: a closed targeted issue fails" {
    _run_tick "GH_CLOSED_ISSUES=12" -- --dry-run "acme/dotfiles#12"
    assert_failure
    assert_output --partial "acme/dotfiles#12 is CLOSED"
}

@test "avatar_issue_watcher: an unreadable targeted issue fails" {
    _run_tick "GH_ISSUE_VIEW_FAIL=1" -- --dry-run "acme/dotfiles#12"
    assert_failure
    assert_output --partial "Cannot read acme/dotfiles#12 on github.com"
}

@test "avatar_issue_watcher: an excluded label refuses a targeted run, --force overrides" {
    _run_tick "GH_ISSUE_LABELS=bug manual" -- "acme/dotfiles#12"
    assert_failure
    assert_output --partial "carries an excluded label (manual)"
    _refute_logged "tab create"
    _run_tick "GH_ISSUE_LABELS=bug manual" -- "acme/dotfiles#12" --force
    assert_success
    assert_output --partial "dispatching anyway (--force)"
    _assert_logged "--label iw-dotfiles-issue-12 --no-focus"
}

@test "avatar_issue_watcher: a targeted issue already running is skipped with exit 0" {
    _set_running 12
    _run_tick -- "acme/dotfiles#12" --force
    assert_success
    assert_output --partial "Skipping acme/dotfiles#12 — already running."
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: a targeted issue an open PR closes is skipped with exit 0" {
    _set_open_prs '{"acme/dotfiles":[{"number":40,"headRefName":"feat/x","body":"Closes #12"}]}'
    _run_tick -- "acme/dotfiles#12"
    assert_success
    assert_output --partial "Skipping acme/dotfiles#12 — an open PR already closes it."
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: a targeted run with an unreadable PR list skips (fail-closed)" {
    _run_tick "GH_PR_LIST_FAIL=1" -- "acme/dotfiles#12"
    assert_success
    assert_output --partial "Cannot list open PRs for acme/dotfiles"
    _refute_logged "tab create"
}

@test "avatar_issue_watcher: a targeted run honours the closed rate-limit gate" {
    _set_limit_state 2 "$(($(date +%s) + 600))"
    _run_tick -- "acme/dotfiles#12"
    assert_success
    assert_output --partial "Rate-limit gate closed"
    _refute_logged "tab create"
}

# `agent_not_ready` is claude parked at its first-run trust dialog for a repo it
# has never opened. Retrying the start cannot pass it; confirming the dialog can.
@test "avatar_issue_watcher: a trust-folder dialog is accepted instead of failing the start" {
    _run_tick "HERDR_START_NOT_READY=1" "HERDR_PANE_TEXT=Quick safety check: Yes, I trust this folder"
    assert_success
    [ "$(_log_count 'agent start')" -eq 1 ]
    _assert_logged "pane send-keys ws-test-1:p9 Down Enter"
    _assert_logged "agent prompt iw-dotfiles-issue-11 /gh-flow:wave 11"
}

@test "avatar_issue_watcher: agent_not_ready without a trust dialog still fails the start" {
    _run_tick "HERDR_START_NOT_READY=1" "HERDR_PANE_TEXT=some other blocker"
    _refute_logged "pane send-keys"
    assert_output --partial "agent_not_ready"
}

# ---------------------------------------------------------------------------
# Detached targeted run (#2286): on a tty an issue-ref run re-runs itself in
# the background with its output in a per-run log. bats never gives the script
# a tty, so IW_ASSUME_TTY=1 is the test seam standing in for `[ -t 1 ]`.
# ---------------------------------------------------------------------------

_LOGS_DIR_REL="avatar-issue-watcher/logs"

# Wait (max ~10s) for the detached child to write its closing exit=<rc> line.
_wait_exit_line() {
    local _i=0
    while [ "${_i}" -lt 100 ]; do
        tail -n 1 "$1" 2>/dev/null | grep -q '^exit=' && return 0
        sleep 0.1
        _i=$((_i + 1))
    done
    fail "no exit= line in $1"
}

_only_run_log() {
    ls "${_STATE_HOME}/${_LOGS_DIR_REL}"/acme-dotfiles-12-*.log
}

@test "avatar_issue_watcher: a tty targeted run detaches and logs to a per-run file" {
    _run_tick "IW_ASSUME_TTY=1" "IW_DETACH_CHECK_SLEEP=0" -- "acme/dotfiles#12"
    assert_success
    assert_output --partial "PID"
    assert_output --partial "${_STATE_HOME}/${_LOGS_DIR_REL}/acme-dotfiles-12-"
    assert_output --partial "tail -f"
    refute_output --partial "issue-watcher tick"
    local _log
    _log=$(_only_run_log)
    _wait_exit_line "${_log}"
    grep -q "issue-watcher tick" "${_log}"
    [ "$(tail -n 1 "${_log}")" = "exit=0" ]
    _assert_logged "/gh-flow:wave 12"
}

@test "avatar_issue_watcher: a detached child that fails at once fails the parent" {
    # The suite's sleep stub returns at once; this check needs the real wait.
    printf '#!/bin/sh\nexec %s "$@"\n' "$(command -v sleep)" >"${_BIN_DIR}/sleep"
    _run_tick "IW_ASSUME_TTY=1" "IW_DETACH_CHECK_SLEEP=3" "GH_CLOSED_ISSUES=12" -- "acme/dotfiles#12"
    assert_failure
    assert_output --partial "ended at once (exit=1)"
    grep -q "acme/dotfiles#12 is CLOSED" "$(_only_run_log)"
    [ "$(tail -n 1 "$(_only_run_log)")" = "exit=1" ]
}

@test "avatar_issue_watcher: --fg keeps a tty targeted run in the foreground" {
    _run_tick "IW_ASSUME_TTY=1" -- "acme/dotfiles#12" --fg
    assert_success
    assert_output --partial "issue-watcher tick"
    _assert_logged "/gh-flow:wave 12"
    [ ! -d "${_STATE_HOME}/${_LOGS_DIR_REL}" ]
}

@test "avatar_issue_watcher: dry-run, plain tick and a non-tty run never detach" {
    _run_tick "IW_ASSUME_TTY=1" -- --dry-run "acme/dotfiles#12"
    assert_success
    assert_output --partial "Dry run — would dispatch:"
    _run_tick "IW_ASSUME_TTY=1" -- --dry-run
    assert_success
    _run_tick -- "acme/dotfiles#12"
    assert_success
    assert_output --partial "issue-watcher tick"
    [ ! -d "${_STATE_HOME}/${_LOGS_DIR_REL}" ]
}

@test "avatar_issue_watcher: the --_detached marker is internal and not in --help" {
    _run_tick -- --help
    assert_success
    assert_output --partial "--fg"
    refute_output --partial "_detached"
}

@test "avatar_issue_watcher: run logs keep only the newest 20" {
    local _d="${_STATE_HOME}/${_LOGS_DIR_REL}" _i
    mkdir -p "${_d}"
    for _i in $(seq 1 20); do
        : >"${_d}/acme-old-${_i}-20200101-0000$(printf '%02d' "${_i}").log"
        touch -d "2020-01-01 00:00:${_i}" "${_d}/acme-old-${_i}-20200101-0000$(printf '%02d' "${_i}").log"
    done
    _run_tick "IW_ASSUME_TTY=1" "IW_DETACH_CHECK_SLEEP=0" -- "acme/dotfiles#12"
    assert_success
    _wait_exit_line "$(_only_run_log)"
    [ "$(ls "${_d}" | wc -l)" -eq 20 ]
    [ ! -e "${_d}/acme-old-1-20200101-000001.log" ]
    [ -e "${_d}/acme-old-2-20200101-000002.log" ]
}

@test "avatar_issue_watcher: an unwritable log dir refuses to detach" {
    mkdir -p "${_STATE_DIR}"
    : >"${_STATE_DIR}/logs"
    _run_tick "IW_ASSUME_TTY=1" -- "acme/dotfiles#12"
    assert_failure
    assert_output --partial "Cannot write the run log"
    _refute_logged "issue view"
}

@test "avatar_issue_watcher: --fg without an issue ref is rejected" {
    _run_tick -- --fg
    assert_failure
    assert_output --partial "--fg only applies to a targeted run"
    [ ! -s "${_LOG}" ]
}

# The child is re-run as `bash <self> --_detached "$@"`: each argument must
# reach it as one word, a --cwd path with a space included (PR #2288 review).
@test "avatar_issue_watcher: a detached run keeps a --cwd path with a space intact" {
    mkdir -p "${_WORK_DIR}/with space"
    _run_tick "IW_ASSUME_TTY=1" "IW_DETACH_CHECK_SLEEP=0" -- --cwd "${_WORK_DIR}/with space" "acme/dotfiles#12"
    assert_success
    local _log
    _log=$(_only_run_log)
    _wait_exit_line "${_log}"
    [ "$(tail -n 1 "${_log}")" = "exit=0" ]
    _assert_logged "/gh-flow:wave 12"
}
