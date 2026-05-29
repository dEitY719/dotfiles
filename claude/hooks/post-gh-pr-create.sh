#!/usr/bin/env bash
# claude/hooks/post-gh-pr-create.sh
# Claude Code PostToolUse hook for `gh pr create`.
#
# Reads the PostToolUse event JSON from stdin, filters to Bash invocations
# whose command starts with `gh pr create`, parses the PR URL from the
# tool output, and syncs project-board status:
#
#   * PR card  → "In review"  (unconditional — verify pair handles races)
#   * Linked issues (Closes #N) → "In progress" with --only-from guard so
#     a re-opened, already-Done issue is not dragged backwards.
#
# Why a hook instead of inlining in claude/skills/gh-pr/SKILL.md Step 7:
#   Three places try to sync after PR creation — the skill body, this hook,
#   and (in AgentToolbox-style repos) GitHub project builtins. Triple-syncing
#   wastes tokens and widens the race window. When this hook is installed the
#   skill detects it (claude/skills/gh-pr/references/project-board-sync.md
#   "Hook auto-skip") and bows out of inline sync — leaving exactly one
#   responsible writer per environment. Idempotence is still guaranteed by
#   the verify pair inside _gh_project_status_sync.
#
# Always exits 0 — board sync is best-effort, never blocks the user's flow.
#
# Reference: issue #390, design SSOT on parent issue #384 (good-point 9 +
# conflict C).

set -u

# Read the PostToolUse payload from stdin. Empty input → bow out.
input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

# Need jq to parse the JSON envelope. Without it the hook becomes a no-op
# (fallback inline sync in the skill takes over).
command -v jq >/dev/null 2>&1 || exit 0

tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
[ "$tool_name" = "Bash" ] || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
# Match `gh pr create` even when prefixed by env-vars (`FOO=bar gh pr create`)
# or `command gh pr create`. Plain prefix-match would miss those.
printf '%s' "$cmd" | grep -qE '(^|[[:space:]])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)' || exit 0

# `output` is the gh-cli stdout; tool_response shape varies between Claude
# Code versions, so fall back through a couple of plausible field names
# before giving up.
output=$(printf '%s' "$input" |
    jq -r '.tool_response.output // .tool_response.stdout // .tool_response // ""' \
        2>/dev/null) || exit 0

# `gh pr create` prints the new PR URL on success. Pull the trailing PR
# number out of the first such URL we see.
#
# Issue #703 — host must be derived from `_dotfiles_setup_mode` so the
# `internal` PC (where the real target is `github.samsungds.net`) is
# matched correctly. Source the SSOT helper; on failure fall back to
# matching either host so a stale install can still extract the PR
# number for the common `github.com` case.
# shellcheck disable=SC1091
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_host.sh" 2>/dev/null
if command -v _gh_resolve_host >/dev/null 2>&1; then
    _gh_resolved=$(_gh_resolve_host)
    # Build the URL-match regex from the host `gh` will actually use: when
    # the caller exported GH_HOST, `gh pr create` emits a URL on that host,
    # so the regex must honor the override. Matching the resolved default
    # instead would miss the URL and silently drop the sync. Native bash
    # parameter expansion escapes the dots (no printf|sed subshell).
    _gh_host="${GH_HOST:-$_gh_resolved}"
    _gh_host_regex="${_gh_host//./\\.}"
    # Export GH_HOST so the later `gh repo view` and `_gh_project_status_sync`
    # calls route to the same host (issue #804). The helper now self-heals
    # too, but exporting here keeps the hook correct on a stale install and
    # is defense-in-depth. Default to the resolved host only when unset.
    : "${GH_HOST:=$_gh_resolved}"
    export GH_HOST
    unset _gh_resolved _gh_host
else
    _gh_host_regex='(github\.com|github\.samsungds\.net)'
fi
pr_num=$(printf '%s' "$output" |
    grep -oE "https://${_gh_host_regex}/[^/]+/[^/]+/pull/[0-9]+" |
    head -1 |
    grep -oE '[0-9]+$')
unset _gh_host_regex
[ -n "$pr_num" ] || exit 0

# Source the shared board-sync helper. Failure to source → silent no-op.
_helper="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_project_status.sh"
[ -r "$_helper" ] || exit 0
# shellcheck disable=SC1090
. "$_helper" 2>/dev/null || exit 0

# Need owner/repo to look up linked issues. `_gh_project_status_sync` itself
# does not need GH_REPO (it discovers projects via the item's node id), but
# `_gh_pr_closing_issue_numbers` does.
GH_REPO="${GH_REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)}"
export GH_REPO

# Absorb the projectV2 "Auto-add to project" race: when this
# hook fires, GitHub's builtin auto-add workflow may not have placed the
# brand-new PR on the board yet. `_gh_project_status_sync` then finds zero
# project items and quietly no-ops (its empty-`_records` early return),
# while GitHub auto-adds the card moments later in the default "Backlog"
# column — leaving the PR stuck. (Issues never hit this: they are board
# members from creation, long before any sync.) The helper's verify pair
# only re-fights a builtin that *overwrites* our write, not one that adds
# the item *after* we looked. So poll: re-sync until the card exists and
# reaches "In review", bounded so boardless repos exit immediately.
#
# Tunables (env): POST_GH_PR_CREATE_SYNC_ATTEMPTS (default 6),
#                 POST_GH_PR_CREATE_SYNC_SLEEP    (default 2 seconds).

# True (rc 0) when GH_REPO has >=1 projectV2 board. Used once, up front, so a
# repo with no board skips the retry budget entirely (the sync would no-op
# forever otherwise).
_post_gh_pr_create_repo_has_board() {
    [ -n "$GH_REPO" ] || return 1
    local _o="${GH_REPO%/*}" _n="${GH_REPO#*/}" _cnt
    [ -n "$_o" ] && [ -n "$_n" ] || return 1
    # GraphQL variables ($o, $n) are bound via the -f flags below, so the
    # single-quoted query intentionally does not shell-expand.
    # shellcheck disable=SC2016
    _cnt=$(gh api graphql \
        -f query='query($o:String!,$n:String!){repository(owner:$o,name:$n){projectsV2(first:1){totalCount}}}' \
        -f o="$_o" -f n="$_n" --jq '.data.repository.projectsV2.totalCount' 2>/dev/null) || return 1
    [ "${_cnt:-0}" -gt 0 ] 2>/dev/null
}

printf '[post-gh-pr-create] PR #%s → "In review"\n' "$pr_num" >&2
if _post_gh_pr_create_repo_has_board; then
    _attempts="${POST_GH_PR_CREATE_SYNC_ATTEMPTS:-6}"
    _i=1
    while [ "$_i" -le "$_attempts" ]; do
        _gh_project_status_sync pr "$pr_num" "In review"
        if [ "$(_gh_project_status_query_current pr "$pr_num")" = "In review" ]; then
            break
        fi
        if [ "$_i" -lt "$_attempts" ]; then
            sleep "${POST_GH_PR_CREATE_SYNC_SLEEP:-2}"
        fi
        _i=$((_i + 1))
    done
    if [ "$_i" -gt "$_attempts" ]; then
        printf '[post-gh-pr-create] PR #%s still not "In review" after %s attempts — GitHub auto-add may have landed late; verify the board.\n' \
            "$pr_num" "$_attempts" >&2
    fi
else
    # No board attached → single call keeps the helper's silent no-op contract.
    _gh_project_status_sync pr "$pr_num" "In review"
fi

if [ -n "$GH_REPO" ]; then
    for _issue in $(_gh_pr_closing_issue_numbers "$pr_num" "$GH_REPO" 2>/dev/null); do
        _gh_project_status_sync issue "$_issue" "In progress" \
            --only-from "Backlog,Ready,In review"
    done
fi

exit 0
