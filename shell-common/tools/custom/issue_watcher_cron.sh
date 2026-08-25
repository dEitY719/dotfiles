#!/bin/bash
# shell-common/tools/custom/issue_watcher_cron.sh
# issue-watcher 5분 주기 감시 사이클 — 1회 tick (issue #1389, #1440).
#
# cron 이 5분마다 이 스크립트를 호출하면 tick 1회를 수행한다. tick 은 감시부터
# 디스패치까지를 직접 수행한다 — 판단이 필요한 지점은 마지막 한 곳,
# 디스패치된 pane 안에서 도는 `/gh-issue-flow <N>` 뿐이다 (issue #1440):
#   1) `gh search issues` 로 할당된 open 이슈를 교차 저장소 한 번에 조회
#   2) 제외 라벨 필터
#   3) watched-repos.json 밖 저장소 제외 + 로컬 경로 매핑
#   4) 워크트리가 이미 있으면 처리 완료로 보고 스킵
#   5) `blockedBy` 가 OPEN 인 이슈 스킵 (조회 실패 시 fail-open)
#   6) 이슈당 워크트리 + herdr tab + claude agent 생성
#   7) `/gh-issue-flow <N>` 프롬프트 전달
# 토큰 한도 게이트가 닫혀 있으면 사이클 전체를 보류한다 (issue #1436).
#
# 이슈에 어떤 쓰기도 하지 않는다 — 댓글·라벨·assignee 변경 없음. 조회 전용이다.
#
# Usage: issue_watcher_cron.sh [--cwd <PATH>] [--dry-run] | [-h|--help|help]

set -u

# Initialize common tools environment (DOTFILES_ROOT/SHELL_COMMON + ux_lib)
. "$(dirname "$0")/init.sh" || exit 1

# init.sh returns early under DOTFILES_TEST_MODE=1 (and before it exports
# SHELL_COMMON), so resolve shell-common from this script's own location as a
# fallback. Both ux_lib and the claude integration below are loaded from here.
_IW_SHELL_COMMON="${SHELL_COMMON:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Same early return means ux_* can still be undefined here — every output path
# below depends on it.
if ! type ux_header >/dev/null 2>&1; then
    if [ -f "${_IW_SHELL_COMMON}/tools/ux_lib/ux_lib.sh" ]; then
        # shellcheck source=/dev/null
        . "${_IW_SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
    fi
fi

# ============================================================
# Constants (SSOT for the watch cycle)
# ============================================================

_IW_STATE_SUBDIR="issue-watcher"
_IW_LOCK_BASENAME=".lock"

# Watch list. Not a list of repos to *query* — `gh search issues` already spans
# every repo the account can see in one call. It is the result filter (an issue
# outside it is ignored) plus the repo -> local checkout map the worktree step
# needs. Overridable so the bats suite can point at a fixture.
_IW_REPOS_FILE_DEFAULT="${HOME:-/nonexistent}/.agent-factory/avatars/issue-watcher/watched-repos.json"

# Labels that park an issue. Exact matches, not substrings.
_IW_EXCLUDE_LABELS_DEFAULT="wontfix,보류,not-implement"

# Per-cycle dispatch cap. Each dispatch spawns a worktree and a claude session;
# three at once is what the pre-#1440 dispatcher profile allowed and the value
# is preserved verbatim (behavior preservation).
_IW_MAX_PER_CYCLE="3"
# Attempts per issue before giving up on it for this cycle. Every failed
# attempt cleans its own worktree up first, so a retry starts from scratch.
_IW_MAX_ATTEMPTS="3"
# Upper bound on the search result set. Only the first _IW_MAX_PER_CYCLE
# survivors are ever dispatched, but the filters run before the cap, so the
# window has to be wider than the cap.
_IW_SEARCH_LIMIT="50"

# herdr agent naming. `iw-<issue-number>`; the tick picks these itself now, so
# unlike pre-#1440 it can address the dispatched panes afterwards.
_IW_AGENT_PREFIX="iw-"
# 5분 주기보다 여유 있게 4분 — cron tick 이 겹치지 않게 한다.
_IW_TIMEOUT_MS="240000"

# Rate-limit gate (issue #1436). Rationale for each value sits with the gate
# functions below; the values themselves live here with the rest of the SSOT.
_IW_LIMIT_STATE_BASENAME="rate-limit.json"
_IW_LIMIT_STRIKES="2"
_IW_LIMIT_BACKOFF_SECONDS="1800"

# herdr's `.error.code` from the last failed dispatch attempt, published by
# _iw_prompt_issue so the rate-limit gate can tell a quota wall from an
# unrelated herdr failure. Empty whenever the dispatch succeeded.
_IW_DISPATCH_ERROR_CODE=""
# CLAUDE_CONFIG_DIR for every pane this tick opens. Resolved once per tick.
_IW_CONFIG_DIR=""
# Set by --dry-run: collect and report candidates, mutate nothing.
_IW_DRY_RUN=0

# ============================================================
# Helpers — state paths and JSON
# ============================================================

# Nested defaults on purpose: under `set -u`, `${XDG_STATE_HOME:-$HOME/...}`
# still aborts with "HOME: unbound variable" when HOME itself is unset (a cron
# environment can be that bare), so HOME is never referenced unguarded.
_iw_state_dir() {
    printf '%s/%s' \
        "${XDG_STATE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.local/state}" \
        "${_IW_STATE_SUBDIR}"
}

# Extract one string field from JSON on stdin.
#   $1 = jq filter, e.g. '.result.pane.pane_id' (used when jq is available).
#        The POSIX fallback derives the flat key from the filter's last
#        dot-segment (here: pane_id) and matches that key anywhere in the doc.
_iw_json_value() {
    local _json _key
    _json=$(cat)
    [ -n "${_json}" ] || return 0

    if command -v jq >/dev/null 2>&1; then
        printf '%s' "${_json}" | jq -r "${1} // empty" 2>/dev/null
        return 0
    fi

    _key="${1##*.}"

    # One JSON token per line first, so the greedy `.*` below cannot skip past
    # the wanted key into a later one on the same (single-line) document.
    printf '%s' "${_json}" |
        awk '{ gsub(/[,{}]/, "\n"); print }' |
        sed -n "s/.*\"${_key}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" |
        head -n 1
}

# First occurrence of a flat key anywhere in the document. `herdr tab create`
# and `herdr workspace create` both answer with a pane, but nest it under
# different parents (`.result.pane` vs `.result.root_pane`), and the CLI is
# free to add another. Keying on the leaf name rather than the path keeps this
# working across both shapes without a per-command filter table.
_iw_json_first() {
    local _json
    _json=$(cat)
    [ -n "${_json}" ] || return 0

    if command -v jq >/dev/null 2>&1; then
        printf '%s' "${_json}" |
            jq -r "[.. | objects | .$1? // empty] | map(select(type == \"string\")) | first // empty" 2>/dev/null
        return 0
    fi

    printf '%s' "${_json}" | _iw_json_value ".$1"
}

# Echo epoch seconds, or nothing when the clock is unreadable.
_iw_now() {
    local _now
    _now=$(date +%s 2>/dev/null) || return 0
    case "${_now}" in
    '' | *[!0-9]*) return 0 ;;
    esac
    printf '%s' "${_now}"
}

# ============================================================
# Helpers — the watch list
# ============================================================

_iw_repos_file() {
    printf '%s' "${IW_WATCHED_REPOS:-${_IW_REPOS_FILE_DEFAULT}}"
}

# Parsed watch list, cached for the tick. Every candidate consults it twice
# (path, host) and the parse is a jq process each time; the file cannot change
# mid-tick in any way this run should act on.
_IW_WATCH_LIST=""
_IW_WATCH_LIST_LOADED=0

# Emit `<owner/repo><TAB><local-path><TAB><host>` per watched entry.
#
# Two accepted shapes, because the file is a personal SSOT this repo does not
# own and cannot migrate: a bare array, or an object with a `repos` array.
# Entries are `{ "repo": "owner/name", "path": "/local/checkout",
# "host": "github.com" }`; `host` is optional and defaults to github.com.
# An entry with no usable repo or path is dropped — a repo the tick cannot
# place on disk has nowhere to put a worktree.
_iw_watch_list() {
    local _file

    if [ "${_IW_WATCH_LIST_LOADED}" -eq 1 ]; then
        [ -z "${_IW_WATCH_LIST}" ] || printf '%s\n' "${_IW_WATCH_LIST}"
        return 0
    fi

    _file=$(_iw_repos_file)
    _IW_WATCH_LIST_LOADED=1
    [ -f "${_file}" ] || return 0

    _IW_WATCH_LIST=$(jq -r '
        (if type == "array" then . else (.repos // []) end)
        | .[]?
        | select(type == "object")
        | select((.repo // "") != "" and (.path // "") != "")
        | [ .repo, .path, (.host // "github.com") ]
        | @tsv
    ' "${_file}" 2>/dev/null)

    [ -z "${_IW_WATCH_LIST}" ] || printf '%s\n' "${_IW_WATCH_LIST}"
}

# Echo the local checkout path for <owner/repo>, or nothing when the repo is
# not watched. "not watched" and "watched but pathless" are the same answer on
# purpose: both mean this tick must not act on the repo.
_iw_repo_path() {
    _iw_watch_list | awk -F '\t' -v r="$1" '$1 == r { print $2; exit }'
}

# Echo the host for <owner/repo>, defaulting to github.com.
_iw_repo_host() {
    local _host
    _host=$(_iw_watch_list | awk -F '\t' -v r="$1" '$1 == r { print $3; exit }')
    printf '%s' "${_host:-github.com}"
}

# Echo every distinct host in the watch list, one per line.
_iw_watch_hosts() {
    _iw_watch_list | awk -F '\t' '{ print $3 }' | sort -u
}

# ============================================================
# Helpers — claude account routing
# ============================================================

# Echo the CLAUDE_CONFIG_DIR the dispatched panes must run `claude` with — the
# same account routing `claude_yolo` applies (issue #1393). herdr's `--kind`
# enum has no `claude-yolo`, so the two effects of that wrapper are reproduced
# here instead: this env var, plus the `-- --dangerously-skip-permissions` tail
# on `herdr agent start`.
#
# Returns:
#   0  directory echoed on stdout
#   1  unknown account / missing directory (fail-fast, message already printed)
#   2  HOME unset — nothing to route against; caller degrades to no --env
#
# One narrow exception to the fail-fast (PR #1395 review): a user who never ran
# `claude-accounts setup` has no CLAUDE_ENABLED_ACCOUNTS whitelist at all and
# never named an account, so `_claude_resolve_account` rejects even the implicit
# `personal` default. Before #1393 the pane ran bare `claude` and worked for
# them; routing must not turn that into a hard failure, so ~/.claude is used
# when it exists. Every other resolution failure still fails fast — an explicit
# CLAUDE_DEFAULT_ACCOUNT whose dir is missing, or a non-empty whitelist that
# does not list the account, are real misconfigurations and silently switching
# accounts there would route the pane at the wrong credentials.
#
# claude.sh is sourced inside a subshell on purpose:
#   - its interactive guard (`case $- in *i*`) defines nothing at all in a
#     non-interactive cron run unless DOTFILES_FORCE_INIT is exported first;
#   - the subshell keeps its ~40 functions and aliases out of this script.
# ux_* diagnostics go to stderr (ux_error) or are suppressed, so only the
# resolved directory ever reaches stdout.
_iw_resolve_config_dir() {
    [ -n "${HOME:-}" ] || return 2

    (
        # Captured before claude.sh is sourced: the *caller's* environment is
        # what says whether the single-account fallback below applies.
        # set-but-empty CLAUDE_DEFAULT_ACCOUNT counts as explicitly set.
        _enabled="${CLAUDE_ENABLED_ACCOUNTS:-}"
        _default_set=0
        [ -z "${CLAUDE_DEFAULT_ACCOUNT+x}" ] || _default_set=1

        DOTFILES_FORCE_INIT=1
        export DOTFILES_FORCE_INIT

        # shellcheck source=/dev/null
        . "${_IW_SHELL_COMMON}/tools/integrations/claude.sh" >&2 || {
            ux_error "Cannot load ${_IW_SHELL_COMMON}/tools/integrations/claude.sh — CLAUDE_CONFIG_DIR unresolvable."
            exit 1
        }

        # Internal-PC single-account override (issue #571): the multi-account
        # layout is off there, so this branch must run before account
        # resolution — an empty CLAUDE_ENABLED_ACCOUNTS must not fail the tick.
        if [ "$(_dotfiles_setup_mode)" = "internal" ]; then
            _cfg_dir="$HOME/.claude"
        else
            _account="${CLAUDE_DEFAULT_ACCOUNT:-personal}"
            _cfg_dir=$(_claude_resolve_account "${_account}") || {
                # No multi-account opt-in at all *and* no account was asked
                # for — the pre-#1393 single-account user. ux_* writes to
                # stdout, which this subshell reserves for the resolved path.
                if [ -z "${_enabled}" ] && [ "${_default_set}" -eq 0 ] &&
                    [ -d "$HOME/.claude" ]; then
                    ux_warning "CLAUDE_ENABLED_ACCOUNTS not configured — falling back to \$HOME/.claude (single-account mode)." >&2
                    ux_info "Run 'claude-accounts setup' to opt into multi-account routing." >&2
                    printf '%s' "$HOME/.claude"
                    exit 0
                fi
                ux_error "Unknown claude account: ${_account} — cannot set CLAUDE_CONFIG_DIR for the watcher pane."
                ux_info "Available: $(_claude_resolve_account --list | tr '\n' ' ')"
                exit 1
            }
        fi

        if [ ! -d "${_cfg_dir}" ]; then
            ux_error "Claude account directory missing: ${_cfg_dir} — cannot bootstrap the watcher pane."
            ux_info "Run: claude-accounts setup"
            exit 1
        fi

        printf '%s' "${_cfg_dir}"
    )
}

# ============================================================
# Step 1-3 — find the issues this tick may act on
# ============================================================

# `gh search issues` spans every repo in one query, so the pre-#1440 loop over
# `gh issue list --repo <r>` (one round trip per watched repo) collapses to one
# call per *host*. Emits `<owner/repo><TAB><number><TAB><labels>` with labels
# joined by US (0x1f) — a label can contain a comma or a space, so neither is
# usable as the separator.
_iw_search_issues() {
    local _host _json

    for _host in $(_iw_watch_hosts); do
        _json=$(GH_HOST="${_host}" gh search issues \
            --assignee @me --state open \
            --json number,repository,labels \
            --limit "${_IW_SEARCH_LIMIT}" 2>/dev/null) || {
            ux_warning "gh search issues failed on ${_host} — skipping that host this tick." >&2
            continue
        }

        printf '%s' "${_json}" | jq -r '
            .[]?
            | [ .repository.nameWithOwner,
                (.number | tostring),
                ([ .labels[]?.name ] | join("")) ]
            | @tsv
        ' 2>/dev/null
    done
}

# 0 when any of the issue's labels ($1, US-joined) is on the exclude list.
# Exact matches only: a `wontfix-later` label must not be parked by `wontfix`.
_iw_excluded_by_label() {
    local _labels="$1" _excluded _label _us _oldifs

    _excluded="${IW_EXCLUDE_LABELS:-${_IW_EXCLUDE_LABELS_DEFAULT}}"
    _us=$(printf '\037')

    _oldifs="$IFS"
    IFS="${_us}"
    # Word splitting on US is the point: the label list is a list. US is the
    # separator precisely because a label may contain a comma or a space.
    # shellcheck disable=SC2086
    set -- ${_labels}
    IFS="$_oldifs"

    for _label in "$@"; do
        [ -n "${_label}" ] || continue
        case ",${_excluded}," in
        *",${_label},"*) return 0 ;;
        esac
    done

    return 1
}

# Echo the existing worktree path for issue <2> inside checkout <1>, or
# nothing. This is the dedup criterion, carried over verbatim from the profile
# it replaces: a worktree for the issue means the issue was already picked up.
# (Switching it to PR state is a behavior change and stays out of #1440 —
# AgentToolbox #2848 C5.)
#
# `gwt spawn --wt-name issue-<n>` always branches `wt/issue-<n>/<index>`, so
# the branch is what identifies the worktree; the directory name carries a
# project prefix this script would otherwise have to reconstruct.
_iw_worktree_for_issue() {
    git -C "$1" worktree list --porcelain 2>/dev/null |
        awk -v pat="^branch refs/heads/wt/issue-$2/" '
            /^worktree / { p = substr($0, 10) }
            $0 ~ pat     { print p; exit }
        '
}

# 0 when the issue has at least one OPEN blocker.
#
# Fail-open by design: a GraphQL error, an unparseable answer or a server that
# does not know the field all answer "not blocked". A watcher that stops
# dispatching because a dependency query broke is worse than one that starts an
# issue whose blocker is still open — the blocker is visible in the PR.
_iw_blocked_by_open() {
    local _repo="$1" _number="$2" _host="$3" _owner _name _json _open

    _owner="${_repo%%/*}"
    _name="${_repo##*/}"

    # The $owner/$name/$number here are GraphQL variables bound by -F below,
    # not shell parameters — single quotes are exactly right.
    # Variables: $owner String!, $name String!, $number Int!
    # `-F number=` is what makes the Int! bind an integer; `-f` would send the
    # string "1440" and the server would reject it (issue #395).
    # shellcheck disable=SC2016
    _json=$(GH_HOST="${_host}" gh api graphql \
        -f query='query($owner:String!,$name:String!,$number:Int!){
            repository(owner:$owner,name:$name){
                issue(number:$number){ blockedBy(first:20){ nodes{ number state } } }
            }
        }' \
        -F owner="${_owner}" -F name="${_name}" -F number="${_number}" 2>/dev/null) || {
        ux_info "blockedBy query failed for ${_repo}#${_number} — proceeding (fail-open)." >&2
        return 1
    }

    _open=$(printf '%s' "${_json}" | jq -r '
        [ .data.repository.issue.blockedBy.nodes[]?
          | select(.state == "OPEN") | .number ] | join(",")
    ' 2>/dev/null) || _open=""

    [ -n "${_open}" ] || return 1
    ux_info "Skipping ${_repo}#${_number} — blocked by open #${_open}." >&2
    return 0
}

# Emit up to _IW_MAX_PER_CYCLE `<repo><TAB><number><TAB><path><TAB><host>`
# lines on stdout. Filters run cheapest-first so the network-bound blockedBy
# check only ever sees issues that survived everything local.
#
# Every diagnostic here goes to stderr: stdout is the candidate list itself,
# and one ux_info line landing in it would be read back as an issue to
# dispatch.
_iw_collect_candidates() {
    local _repo _number _labels _path _host _found=0

    while IFS="$(printf '\t')" read -r _repo _number _labels; do
        if [ -z "${_repo}" ] || [ -z "${_number}" ]; then
            continue
        fi

        _path=$(_iw_repo_path "${_repo}")
        # Not on the watch list. Silent: `gh search issues` spans every repo
        # the account can see, so this is the common case, not an anomaly.
        [ -n "${_path}" ] || continue

        if [ ! -d "${_path}" ]; then
            ux_warning "Watched repo ${_repo} maps to a missing path (${_path}) — skipping." >&2
            continue
        fi

        if _iw_excluded_by_label "${_labels}"; then
            ux_info "Skipping ${_repo}#${_number} — excluded label." >&2
            continue
        fi

        if [ -n "$(_iw_worktree_for_issue "${_path}" "${_number}")" ]; then
            ux_info "Skipping ${_repo}#${_number} — worktree already exists." >&2
            continue
        fi

        _host=$(_iw_repo_host "${_repo}")

        if _iw_blocked_by_open "${_repo}" "${_number}" "${_host}"; then
            continue
        fi

        printf '%s\t%s\t%s\t%s\n' "${_repo}" "${_number}" "${_path}" "${_host}"

        _found=$((_found + 1))
        [ "${_found}" -lt "${_IW_MAX_PER_CYCLE}" ] || break
    done <<EOF
$(_iw_search_issues)
EOF
}

# ============================================================
# Step 4-6 — worktree, pane, dispatch
# ============================================================

# `gwt` is a shell function in shell-common, not a binary, so it cannot be
# reached the way `herdr` and `gh` are. A PATH-resolvable `gwt` wins when one
# exists (that is how the bats suite stubs it); otherwise the function file is
# sourced inside a subshell, which inherits ux_* from this script and keeps
# git_worktree.sh's own definitions out of it.
_iw_gwt() {
    if command -v gwt >/dev/null 2>&1; then
        gwt "$@"
        return
    fi

    (
        DOTFILES_FORCE_INIT=1
        export DOTFILES_FORCE_INIT
        # shellcheck source=/dev/null
        . "${_IW_SHELL_COMMON}/functions/git_worktree.sh" || exit 1
        gwt "$@"
    )
}

# Create the issue's worktree and echo its path. `gwt spawn` refuses to run
# from inside a worktree, so it runs from the checkout root; its own output
# goes to stderr because stdout here carries the resulting path.
_iw_spawn_worktree() {
    local _path="$1" _number="$2" _wt

    (cd "${_path}" && _iw_gwt spawn --wt-name "issue-${_number}") >&2 || return 1

    _wt=$(_iw_worktree_for_issue "${_path}" "${_number}")
    [ -n "${_wt}" ] || return 1
    printf '%s' "${_wt}"
}

# Best-effort teardown of a half-built dispatch, so the next attempt starts
# from nothing. A leftover worktree is not merely clutter: it is exactly what
# the dedup check keys on, so leaving one behind would retire the issue
# permanently without it ever having been worked.
_iw_cleanup_attempt() {
    local _path="$1" _wt="$2" _tab="$3"

    [ -z "${_tab}" ] || herdr tab close "${_tab}" >/dev/null 2>&1 || true
    [ -z "${_wt}" ] || (cd "${_path}" && _iw_gwt remove "${_wt}" --force) >/dev/null 2>&1 || true
}

# Echo the workspace id whose label is <1>, creating it against cwd <2> when no
# such workspace exists. Label-matched rather than persisted: the herdr server
# is the SSOT for what is open, and a state file would only drift from it.
_iw_workspace_for_label() {
    local _label="$1" _cwd="$2" _json _ws

    _json=$(herdr workspace list 2>/dev/null) || _json=""
    _ws=$(printf '%s' "${_json}" | jq -r --arg l "${_label}" '
        [ .result.workspaces[]? | select(.label == $l) | .workspace_id ] | first // empty
    ' 2>/dev/null) || _ws=""

    if [ -n "${_ws}" ]; then
        printf '%s' "${_ws}"
        return 0
    fi

    set -- --cwd "${_cwd}" --label "${_label}" --no-focus
    [ -z "${_IW_CONFIG_DIR}" ] || set -- "$@" --env "CLAUDE_CONFIG_DIR=${_IW_CONFIG_DIR}"

    _json=$(herdr workspace create "$@" 2>/dev/null) || _json=""
    _ws=$(printf '%s' "${_json}" | _iw_json_first workspace_id)
    [ -n "${_ws}" ] || return 1
    printf '%s' "${_ws}"
}

# Open the issue's tab and echo `<pane_id><TAB><tab_id>`.
_iw_tab_create() {
    local _ws="$1" _cwd="$2" _label="$3" _json _pane _tab

    set -- --workspace "${_ws}" --cwd "${_cwd}" --label "${_label}" --no-focus
    [ -z "${_IW_CONFIG_DIR}" ] || set -- "$@" --env "CLAUDE_CONFIG_DIR=${_IW_CONFIG_DIR}"

    _json=$(herdr tab create "$@" 2>/dev/null) || return 1

    _pane=$(printf '%s' "${_json}" | _iw_json_first pane_id)
    _tab=$(printf '%s' "${_json}" | _iw_json_first tab_id)
    [ -n "${_pane}" ] || return 1
    printf '%s\t%s' "${_pane}" "${_tab}"
}

# Echo the agent status (idle|working|blocked|done|unknown). Returns non-zero
# when herdr itself rejects the query (agent missing / pane closed).
_iw_agent_status() {
    local _json _rc=0
    _json=$(herdr agent get "$1" 2>/dev/null) || _rc=$?
    [ "${_rc}" -eq 0 ] || return 1
    printf '%s' "${_json}" | _iw_json_value '.result.agent.agent_status'
}

# `-- ARG...` is passed through to the pane's claude invocation. Unattended
# cron ticks must never stop on a permission-approval prompt (issue #1393).
_iw_agent_start() {
    herdr agent start "$1" --kind claude --pane "$2" \
        -- --dangerously-skip-permissions >/dev/null 2>&1
}

# Echo herdr's JSON response on stdout; the exit code is herdr's own.
_iw_prompt_once() {
    herdr agent prompt "$1" "$2" --wait --timeout "${_IW_TIMEOUT_MS}" 2>/dev/null
}

# Send `/gh-issue-flow <N>` to the issue's agent.
#
# The prompt is a slash command, not prose: pre-#1440 this channel carried an
# instruction to *run another agent*, and the receiving session had to work out
# which tool that meant (#1394). There is nothing left to interpret here, and
# the command runs top-level rather than inside a subagent, which is what took
# this path out of the `SubagentStop` guard gap (#1434).
_iw_prompt_issue() {
    local _agent="$1" _number="$2" _prompt _json _code _rc=0 _post_stall_status

    _prompt="/gh-issue-flow ${_number}"
    _IW_DISPATCH_ERROR_CODE=""
    _json=$(_iw_prompt_once "${_agent}" "${_prompt}") || _rc=$?

    # Only `agent_prompt_stalled` is retried: it means the keystroke was dropped
    # by a not-yet-ready input loop (issue #1399), which a second later is gone.
    # Every other error is a real failure and must not be re-sent — a duplicate
    # prompt would start a second flow on the same issue.
    if [ "${_rc}" -ne 0 ]; then
        _code=$(printf '%s' "${_json}" | _iw_json_value '.error.code')
        if [ "${_code}" = "agent_prompt_stalled" ]; then
            # `agent_prompt_stalled` only proves herdr saw no state change
            # within its fixed 5s window — it does NOT prove the prompt was
            # never submitted (PR #1400 codex review). `working` is positive
            # evidence the first call *did* land, so retrying would type the
            # same command into an already-busy pane; any other status gives no
            # such evidence, so the retry proceeds as before.
            _post_stall_status=$(_iw_agent_status "${_agent}") || _post_stall_status=""
            if [ "${_post_stall_status}" = "working" ]; then
                ux_warning "herdr reported agent_prompt_stalled but ${_agent} is already working — treating as delivered, not retrying."
                _rc=0
            else
                ux_warning "herdr reported agent_prompt_stalled — retrying once."
                sleep 1
                _rc=0
                _json=$(_iw_prompt_once "${_agent}" "${_prompt}") || _rc=$?
            fi
        fi
    fi

    if [ "${_rc}" -eq 0 ]; then
        ux_success "Dispatched to ${_agent}: ${_prompt}"
        return 0
    fi

    # Publish the *final* attempt's code — after a retry `$_json` holds the
    # second response, so `$_code` from the first is stale. The rate-limit gate
    # reads this to tell herdr's failure modes apart.
    _IW_DISPATCH_ERROR_CODE=$(printf '%s' "${_json}" | _iw_json_value '.error.code')
    ux_error "herdr agent prompt failed for agent ${_agent} (${_IW_DISPATCH_ERROR_CODE:-unknown})."
    return 1
}

# One issue, end to end: worktree, workspace, tab, agent, prompt. Retries the
# whole sequence up to _IW_MAX_ATTEMPTS times, cleaning up before each retry so
# no attempt inherits the previous one's half-built state.
_iw_process_issue() {
    local _repo="$1" _number="$2" _path="$3"
    local _attempt=1 _agent _label _wt="" _ws="" _pane_tab="" _pane="" _tab=""

    _agent="${_IW_AGENT_PREFIX}${_number}"
    _label=$(basename "${_path}")
    # Stale from the previous issue otherwise, and the rate-limit gate reads it
    # to decide whether this failure was quota-shaped.
    _IW_DISPATCH_ERROR_CODE=""

    while [ "${_attempt}" -le "${_IW_MAX_ATTEMPTS}" ]; do
        _wt=""
        _tab=""

        if ! _wt=$(_iw_spawn_worktree "${_path}" "${_number}"); then
            ux_warning "Worktree spawn failed for ${_repo}#${_number} (attempt ${_attempt}/${_IW_MAX_ATTEMPTS})."
            # A spawn can fail after `git worktree add` succeeded. Recover the
            # path so the cleanup below really removes it — a survivor would
            # satisfy the dedup check and retire the issue unworked.
            _wt=$(_iw_worktree_for_issue "${_path}" "${_number}")
        elif ! _ws=$(_iw_workspace_for_label "${_label}" "${_path}"); then
            ux_warning "No herdr workspace for ${_label} (attempt ${_attempt}/${_IW_MAX_ATTEMPTS})."
        elif ! _pane_tab=$(_iw_tab_create "${_ws}" "${_wt}" "#${_number}"); then
            ux_warning "herdr tab create failed for ${_repo}#${_number} (attempt ${_attempt}/${_IW_MAX_ATTEMPTS})."
        else
            IFS="$(printf '\t')" read -r _pane _tab <<EOF
${_pane_tab}
EOF
            if ! _iw_agent_start "${_agent}" "${_pane}"; then
                ux_warning "herdr agent start ${_agent} failed on pane ${_pane} (attempt ${_attempt}/${_IW_MAX_ATTEMPTS})."
            elif _iw_prompt_issue "${_agent}" "${_number}"; then
                ux_success "${_repo}#${_number} dispatched (worktree ${_wt}, pane ${_pane})."
                return 0
            fi
        fi

        _iw_cleanup_attempt "${_path}" "${_wt}" "${_tab}"
        _attempt=$((_attempt + 1))
    done

    ux_error "Giving up on ${_repo}#${_number} after ${_IW_MAX_ATTEMPTS} attempts."
    return 1
}

# ============================================================
# Rate-limit gate (issue #1436)
# ============================================================

# Token-limit exhaustion is invisible to this tick by default: `herdr agent
# prompt` hands the command over and returns, so a claude session that starts
# and then stops on a spent quota still reads as a delivered dispatch. Worse,
# by then the tick has created the `issue-<n>` worktree its own dedup check
# keys on, so that issue is never offered again — exhaustion becomes silent
# loss, not merely waste.
#
# The gate below holds dispatches after repeated unhealthy cycles and reopens
# itself on a timer. It is deliberately evidence-poor and fail-open (NF-1): a
# detector that can wedge the watcher is worse than the leak it guards.
#
# The signal: a spent quota stops the dispatched claude session before it can
# change state, so herdr's `--wait` draws no transition, answers
# `agent_prompt_stalled`, the retry stalls too and `_iw_prompt_issue` fails.
# `_iw_agent_status` then separates a real wall from an unrelated hiccup: an
# agent reporting `working`/`blocked` is alive and busy, so that failure earns
# no strike.
#
# Pre-#1440 this had to watch the resident `iw-watch` agent instead, because
# the per-issue panes were opened by a subagent inside that session and their
# names never came back (`herdr agent list` carries no agent-name field). The
# tick now chooses those names itself, so the gate watches the dispatch it
# actually cares about. What made the old indirection sound in the first place
# still holds and is now direct: `_iw_resolve_config_dir` picks a single
# CLAUDE_CONFIG_DIR for every pane this tick opens (#1393) — one account, one
# quota. If account routing ever splits per pane, this reasoning has to be
# revisited (PR #1439 agy review).

_iw_limit_state_file() {
    printf '%s/%s' "$(_iw_state_dir)" "${_IW_LIMIT_STATE_BASENAME}"
}

# Echo one field of the gate state file, or nothing. A missing file, an
# unreadable one and an absent field are all "nothing" on purpose — every
# caller reads that as "no gate" and proceeds (NF-1).
_iw_limit_read() {
    local _file
    _file=$(_iw_limit_state_file)
    [ -f "${_file}" ] || return 0
    _iw_json_value ".$1" <"${_file}" 2>/dev/null
}

# Persist strikes + backoff deadline. Both are written as JSON *strings*: the
# jq-less branch of _iw_json_value only matches quoted values, and a bare cron
# environment is exactly where jq is likely to be missing.
_iw_limit_write() {
    local _dir _file
    _dir=$(_iw_state_dir)
    _file="${_dir}/${_IW_LIMIT_STATE_BASENAME}"

    if ! mkdir -p "${_dir}" 2>/dev/null; then
        ux_warning "Cannot create state directory (${_dir}) — the rate-limit gate will not survive this tick."
        return 1
    fi

    if ! printf '{ "strikes": "%s", "backoff_until": "%s" }\n' "$1" "$2" >"${_file}" 2>/dev/null; then
        ux_warning "Cannot write ${_file} — the rate-limit gate will not survive this tick."
        return 1
    fi
}

_iw_limit_clear() {
    rm -f "$(_iw_limit_state_file)" 2>/dev/null || true
}

# The gate itself. Returns 0 when this tick may dispatch, non-zero when it must
# hold. Every unexpected input answers 0 — see NF-1.
_iw_limit_gate_check() {
    local _until _now _left

    [ -f "$(_iw_limit_state_file)" ] || return 0

    _until=$(_iw_limit_read backoff_until)
    case "${_until}" in
    *[!0-9]*)
        ux_warning "Rate-limit state is unreadable (backoff_until='${_until}') — dispatching anyway."
        return 0
        ;;
    '')
        # Present but fieldless: a truncated write or a hand edit. Strike
        # bookkeeping never produces this — _iw_limit_write always emits both
        # fields.
        ux_warning "Rate-limit state file has no backoff deadline — dispatching anyway."
        return 0
        ;;
    esac

    # 0 is the resting value written while strikes accumulate: evidence on
    # record, gate still open.
    [ "${_until}" -gt 0 ] || return 0

    _now=$(_iw_now)
    if [ -z "${_now}" ]; then
        ux_warning "Cannot read the clock — rate-limit gate ignored this tick."
        return 0
    fi

    # A deadline further out than twice its own length cannot have been written
    # by this script; a clock jump or a hand edit did it. Expiring beats
    # stalling forever (F-3).
    _left=$((_until - _now))
    if [ "${_left}" -le 0 ] || [ "${_left}" -gt $((_IW_LIMIT_BACKOFF_SECONDS * 2)) ]; then
        ux_info "Rate-limit gate reopened — backoff expired, resuming dispatch."
        _iw_limit_clear
        return 0
    fi

    ux_warning "Rate-limit gate closed — holding dispatch for ~$(((_left + 59) / 60))m (no worktree is created this tick)."
    return 1
}

# Record the outcome of the dispatch just attempted. $1 is _iw_process_issue's
# exit status, $2 the agent it dispatched to. Two consecutive stalled
# dispatches shut the gate; one delivered one wipes the slate, so
# `_IW_LIMIT_STRIKES` really does count consecutive stalls. 1 would hold the
# watcher over a single transient herdr blip; 2 buys that evidence for one
# extra tick (~5 min).
_iw_limit_record() {
    local _rc="$1" _agent="$2" _status _strikes _now

    if [ "${_rc}" -eq 0 ]; then
        # A prompt herdr accepted means the agent changed state, i.e. it is
        # processing — `--wait` would not have returned otherwise.
        _iw_limit_clear
        return 0
    fi

    # Only a stall is quota-shaped. herdr's other failures — `agent_not_found`,
    # an auth or transport error, a malformed response — say the pane or the
    # connection broke, not that the account ran dry. Counting them would hold
    # dispatch for 30 minutes over an outage this gate cannot fix, and would
    # file it under "token limit" in the cron log where nobody would look for a
    # broken socket (PR #1439 codex review). Such a failure leaves the strike
    # count where it is: it is evidence of neither exhaustion nor health.
    if [ "${_IW_DISPATCH_ERROR_CODE}" != "agent_prompt_stalled" ]; then
        ux_info "Dispatch failed with '${_IW_DISPATCH_ERROR_CODE:-unknown}' — not a token-limit signature, gate untouched."
        return 0
    fi

    _status=$(_iw_agent_status "${_agent}") || _status=""
    case "${_status}" in
    working | blocked)
        ux_info "Dispatch failed but agent ${_agent} is ${_status} — not a token-limit signal, gate untouched."
        _iw_limit_clear
        return 0
        ;;
    esac

    _strikes=$(_iw_limit_read strikes)
    case "${_strikes}" in
    '' | *[!0-9]*) _strikes=0 ;;
    esac
    _strikes=$((_strikes + 1))

    if [ "${_strikes}" -lt "${_IW_LIMIT_STRIKES}" ]; then
        ux_warning "Dispatch stalled with agent ${_agent} at '${_status:-none}' (${_strikes}/${_IW_LIMIT_STRIKES}) — possible token-limit exhaustion."
        _iw_limit_write "${_strikes}" "0" || true
        return 0
    fi

    _now=$(_iw_now)
    if [ -z "${_now}" ]; then
        ux_warning "Cannot read the clock — rate-limit gate left open despite ${_strikes} failed dispatches."
        return 0
    fi

    # Claude's quota windows run for hours, so a short backoff would only
    # re-dispatch into the same wall; 30 minutes keeps the recovery latency
    # (F-3) well inside one window while cutting the burn rate to zero.
    ux_warning "Rate-limit gate closed for $((_IW_LIMIT_BACKOFF_SECONDS / 60))m — ${_strikes} consecutive dispatches stalled with the agent idle (likely token limit)."
    _iw_limit_write "0" "$((_now + _IW_LIMIT_BACKOFF_SECONDS))" || true
}

# ============================================================
# Locking
# ============================================================

# Single-instance guard. A cron tick can fire while the previous one is still
# blocked in `herdr agent prompt --wait`; without a lock both would observe the
# same candidate set and both dispatch, breaking the one-cycle-at-a-time
# invariant. Since #1440 this is the *only* overlap guard — the resident
# watcher agent whose idle/working status used to double as one is gone.
# Deliberately non-blocking: a skipped tick just retries 5 minutes later.
# Returns non-zero only when another tick holds the lock; a missing flock or an
# unusable state dir soft-degrades to "no protection" rather than failing.
_iw_acquire_lock() {
    local _dir _lock
    _dir=$(_iw_state_dir)
    _lock="${_dir}/${_IW_LOCK_BASENAME}"

    if ! command -v flock >/dev/null 2>&1; then
        ux_warning "flock not found — running without single-instance protection"
        return 0
    fi

    if ! mkdir -p "${_dir}" 2>/dev/null; then
        ux_warning "Cannot create state directory (${_dir}) — running without single-instance protection"
        return 0
    fi

    # The 2>/dev/null must be scoped to the group, not attached to `exec`:
    # `exec 9>FILE 2>/dev/null` applies *both* redirections permanently, muting
    # the whole script's stderr — every later ux_error would vanish from the
    # cron log. The group restores fd 2 on exit while fd 9 persists.
    if ! { exec 9>"${_lock}"; } 2>/dev/null; then
        ux_warning "Cannot open lock file (${_lock}) — running without single-instance protection"
        return 0
    fi

    if ! flock -n 9; then
        ux_warning "another issue_watcher_cron tick is already running — skip"
        return 1
    fi
}

# ============================================================
# Usage
# ============================================================

_iw_usage() {
    ux_header "issue_watcher_cron"
    ux_info "Usage: issue_watcher_cron.sh [--cwd <PATH>] [--dry-run] | [-h|--help|help]"
    ux_info "Runs one issue-watcher tick: find assigned issues, dispatch /gh-issue-flow."
    ux_bullet "options"
    ux_bullet_sub "--cwd <PATH>   fallback checkout root for watched repos (default: git repo root)"
    ux_bullet_sub "--dry-run      print the issues this tick would dispatch, change nothing"
    ux_bullet_sub "-h, --help, help   show this help"
    ux_bullet "cycle"
    ux_bullet_sub "gh search issues --assignee @me --state open   (one query per watched host)"
    ux_bullet_sub "excluded labels: ${_IW_EXCLUDE_LABELS_DEFAULT}"
    ux_bullet_sub "an issue with an OPEN blockedBy is skipped (query failure fails open)"
    ux_bullet_sub "an issue that already has a wt/issue-<n>/* worktree is skipped"
    ux_bullet_sub "at most ${_IW_MAX_PER_CYCLE} issues per cycle, ${_IW_MAX_ATTEMPTS} attempts each"
    ux_bullet_sub "no issue is ever written to — no comment, label or assignee change"
    ux_bullet "watch list"
    ux_bullet_sub "${_IW_REPOS_FILE_DEFAULT}"
    ux_bullet_sub "override with \$IW_WATCHED_REPOS; entries are {repo, path, host}"
    ux_bullet "state"
    ux_bullet_sub "\${XDG_STATE_HOME:-\$HOME/.local/state}/${_IW_STATE_SUBDIR}/${_IW_LIMIT_STATE_BASENAME}   (rate-limit gate)"
    ux_bullet "rate-limit gate"
    ux_bullet_sub "${_IW_LIMIT_STRIKES} dispatches in a row that stall with the agent idle close the gate"
    ux_bullet_sub "other herdr failures (agent_not_found, auth, network) never close it"
    ux_bullet_sub "while closed the tick holds: no prompt, no worktree, exit 0"
    ux_bullet_sub "it reopens by itself after $((_IW_LIMIT_BACKOFF_SECONDS / 60))m — delete ${_IW_LIMIT_STATE_BASENAME} to reopen it now"
    ux_bullet "claude session (claude-yolo parity)"
    ux_bullet_sub "each pane runs claude --dangerously-skip-permissions (unattended cron)"
    ux_bullet_sub "internal setup mode  → CLAUDE_CONFIG_DIR=\$HOME/.claude"
    ux_bullet_sub "otherwise            → CLAUDE_CONFIG_DIR=\$HOME/.claude-\${CLAUDE_DEFAULT_ACCOUNT:-personal}"
    ux_bullet_sub "  (that account must be listed in \$CLAUDE_ENABLED_ACCOUNTS)"
    ux_bullet_sub "no \$CLAUDE_ENABLED_ACCOUNTS and no \$CLAUDE_DEFAULT_ACCOUNT → \$HOME/.claude if it exists"
    ux_bullet_sub "the resolved directory must already exist — the tick fails fast otherwise"
    ux_bullet "crontab"
    ux_bullet_sub "*/5 * * * * /path/to/issue_watcher_cron.sh >> ~/.local/state/issue-watcher/cron.log 2>&1"
}

# ============================================================
# Main
# ============================================================

main() {
    local _cwd="" _repo _number _path _host _rc _dispatched=0 _failed=0 _candidates

    while [ "$#" -gt 0 ]; do
        case "$1" in
        -h | --help | help)
            _iw_usage
            exit 0
            ;;
        --cwd)
            if [ "$#" -lt 2 ]; then
                ux_error "--cwd requires a PATH argument."
                exit 1
            fi
            _cwd="$2"
            shift 2
            ;;
        --dry-run)
            _IW_DRY_RUN=1
            shift
            ;;
        *)
            ux_error "Unknown option: $1"
            ux_info "Run 'issue_watcher_cron.sh --help' for usage."
            exit 1
            ;;
        esac
    done

    # --cwd is where the tick runs from, which is what a relative `path` in the
    # watch list resolves against. A cron tick starts in $HOME, so a watch list
    # written with relative paths needs this to mean anything.
    if [ -n "${_cwd}" ]; then
        if ! cd "${_cwd}"; then
            ux_error "Cannot cd to --cwd ${_cwd}."
            exit 1
        fi
    fi

    ux_header "issue-watcher tick"

    if ! command -v gh >/dev/null 2>&1; then
        ux_error "gh not found in PATH — cannot query assigned issues."
        exit 1
    fi

    # jq is not optional on this path. The watch list and the search result are
    # arrays of objects, and the flat-key fallback _iw_json_value uses for the
    # single-value herdr responses cannot walk those. Refusing loudly beats
    # dispatching against a half-parsed candidate set.
    if ! command -v jq >/dev/null 2>&1; then
        ux_error "jq not found in PATH — cannot parse the issue search or the watch list."
        ux_info "Install jq, or add it to the cron PATH."
        exit 1
    fi

    if [ ! -f "$(_iw_repos_file)" ]; then
        ux_error "Watch list not found: $(_iw_repos_file)"
        ux_info "Create it, or point \$IW_WATCHED_REPOS at one. Entries: {repo, path, host}."
        exit 1
    fi

    # A dry run reports what it would dispatch and touches nothing, so it must
    # stay usable on a machine with no herdr server.
    if [ "${_IW_DRY_RUN}" -eq 0 ] && ! command -v herdr >/dev/null 2>&1; then
        ux_error "herdr not found in PATH — cannot run the issue-watcher tick."
        ux_info "Install it via ./herdr/setup.sh, or add it to the cron PATH."
        exit 1
    fi

    _iw_acquire_lock || exit 0

    # Before any worktree is created: a closed gate must cost nothing.
    _iw_limit_gate_check || exit 0

    _candidates=$(_iw_collect_candidates)

    if [ -z "${_candidates}" ]; then
        ux_info "No dispatchable issue this tick."
        exit 0
    fi

    if [ "${_IW_DRY_RUN}" -eq 1 ]; then
        ux_success "Dry run — would dispatch:"
        while IFS="$(printf '\t')" read -r _repo _number _path _host; do
            [ -n "${_repo}" ] || continue
            ux_bullet "${_repo}#${_number}  (${_path}, ${_host})"
        done <<EOF
${_candidates}
EOF
        exit 0
    fi

    # Resolved once for the whole tick: every pane it opens shares one account,
    # which is also what lets the rate-limit gate read one pane's stall as
    # evidence about the quota behind all of them.
    _IW_CONFIG_DIR=$(_iw_resolve_config_dir)
    case "$?" in
    0) ;;
    2)
        _IW_CONFIG_DIR=""
        ux_warning "HOME is unset — starting claude without CLAUDE_CONFIG_DIR account routing."
        ;;
    *)
        exit 1
        ;;
    esac

    while IFS="$(printf '\t')" read -r _repo _number _path _host; do
        [ -n "${_repo}" ] || continue

        _rc=0
        _iw_process_issue "${_repo}" "${_number}" "${_path}" || _rc=$?
        _iw_limit_record "${_rc}" "${_IW_AGENT_PREFIX}${_number}"

        if [ "${_rc}" -eq 0 ]; then
            _dispatched=$((_dispatched + 1))
        else
            _failed=$((_failed + 1))
        fi

        # A gate that just shut must not be walked past for the rest of the
        # cycle — the remaining issues would burn their worktrees against the
        # same wall.
        _iw_limit_gate_check || break
    done <<EOF
${_candidates}
EOF

    if [ "${_dispatched}" -eq 0 ] && [ "${_failed}" -gt 0 ]; then
        ux_error "Tick complete — 0 dispatched, ${_failed} failed."
        exit 1
    fi

    ux_success "Tick complete — ${_dispatched} issue(s) dispatched, ${_failed} failed."
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
