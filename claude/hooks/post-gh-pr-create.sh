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
# "Never blocks" is literal since issue #1258: only ONE sync call is made in
# the foreground; the #813 retry-poll (which sleeps between GraphQL round
# trips) and the linked-issue sync are detached into a background subprocess,
# so the hook process returns in ~one round trip instead of the measured
# median 7.8s / max 48.7s.
#
# Reference: issue #390, design SSOT on parent issue #384 (good-point 9 +
# conflict C). Latency fix: issue #1258.

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

# Rollout-skew warning, emitted HERE in the foreground on purpose (PR #1420
# review). The consumer of this check is _post_gh_pr_create_repo_has_board
# below, which runs inside the detached tail whose stderr goes to /dev/null
# (#1258) — a warning printed there would never reach a human, so the guard
# would restore the retry-poll but tell nobody the deploy is skewed. Printing
# it at the top costs one builtin lookup, no fork and no wait, and it fires
# only in the window where the sourced helper predates #1405.
if ! command -v _gh_project_status_normalize_repo >/dev/null 2>&1; then
    printf '[post-gh-pr-create] %s sourced but _gh_project_status_normalize_repo undefined — splitting GH_REPO inline (#724).\n' \
        "$_helper" >&2
fi

# Need owner/repo to look up linked issues (`_gh_pr_closing_issue_numbers`
# takes it as an argument).
#
# Since #1405 the board helpers honor this exported GH_REPO explicitly: their
# resolution order is `--repo` arg > $GH_REPO > $TARGET_REPO > `gh repo view`
# auto-detect. Exporting it here IS the hook's repo pin, so the calls below
# deliberately do not repeat it as `--repo "$GH_REPO"` — the env level
# already carries the same value, and one binding is one place to keep
# right. (An empty `--repo` would not have broken anything either: the
# helper treats it as "not supplied" and falls through.)
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
# Issue #1258: that poll used to run inline, so the PostToolUse hook sat on
# up to (attempts-1) x sleep seconds plus 2 GraphQL round trips per attempt
# while the user's turn waited. Only the first sync stays in the foreground
# now; the rest is detached (see _post_gh_pr_create_deferred below).
#
# Tunables (env): POST_GH_PR_CREATE_SYNC_ATTEMPTS (default 6),
#                 POST_GH_PR_CREATE_SYNC_SLEEP    (default 2 seconds),
#                 POST_GH_PR_CREATE_ASYNC         (default 1; 0 = run the
#                 deferred tail in the foreground — deterministic tests, and
#                 manual runs where you want to watch the whole sync).

# True (rc 0) when GH_REPO has >=1 projectV2 board. Called once at the top of
# the deferred tail, so a repo with no board does not burn the retry budget in
# the background (the sync would no-op forever otherwise).
_post_gh_pr_create_repo_has_board() {
    [ -n "$GH_REPO" ] || return 1
    # Split via the board helper's own normalizer rather than by hand: it
    # also accepts gh's `HOST/OWNER/REPO` form of GH_REPO (#1405), which a
    # bare `${GH_REPO%/*}` / `${GH_REPO#*/}` pair would mis-split into
    # "host/owner" + "owner/repo" and query a repo that does not exist.
    #
    # Defense-in-depth (#724): the helper sourced above may predate #1405 and
    # not define that normalizer. Hook and helper deploy independently — a
    # worktree run resolves SHELL_COMMON to the *main* checkout — so a
    # rollout-skew window is real, and it was observed on this very helper
    # (`unknown option: --repo`). Calling the normalizer bare sent its rc 127
    # straight into `|| return 1`: has_board went false and the entire #813
    # retry-poll vanished without a word, reviving the stuck-in-Backlog
    # symptom #813 exists to prevent (#1414). Split inline instead — one
    # missing helper function is no reason to drop the poll.
    local _slug _o _n _cnt
    if command -v _gh_project_status_normalize_repo >/dev/null 2>&1; then
        _slug=$(_gh_project_status_normalize_repo "$GH_REPO") || return 1
    else
        # The warning for this branch was already printed in the foreground
        # at source time — see the block above the GH_REPO binding.
        #
        # Mirrors the normalizer's host-stripping and its "must contain a
        # slash" rejection, then ends in its "<owner> <repo>" output
        # contract, so both branches feed the one split below instead of
        # carrying two split idioms that must stay in sync. A slashless value
        # would otherwise leave _o == _n == the whole string, pass the
        # non-empty gate, and spend a GraphQL round trip to learn what the
        # normalizer answers for free (PR #1420 review).
        _slug="$GH_REPO"
        case "$_slug" in */*/*) _slug="${_slug#*/}" ;; esac
        case "$_slug" in */*) ;; *) return 1 ;; esac
        _slug="${_slug%%/*} ${_slug#*/}"
    fi
    _o="${_slug%% *}"
    _n="${_slug#* }"
    [ -n "$_o" ] && [ -n "$_n" ] || return 1
    # GraphQL variables ($o, $n) are bound via the -f flags below, so the
    # single-quoted query intentionally does not shell-expand. Both are
    # String! → -f (raw string) is the correct flag, never -F (issue #395).
    # Variables: $o String!, $n String!
    # shellcheck disable=SC2016
    _cnt=$(gh api graphql \
        -f query='query($o:String!,$n:String!){repository(owner:$o,name:$n){projectsV2(first:1){totalCount}}}' \
        -f o="$_o" -f n="$_n" --jq '.data.repository.projectsV2.totalCount' 2>/dev/null) || return 1
    [ "${_cnt:-0}" -gt 0 ] 2>/dev/null
}

# Everything that may have to WAIT. Runs detached in production; the tests
# force it inline via POST_GH_PR_CREATE_ASYNC=0 so call counts are observable.
#
#   1. has-board probe + attempts 2..N of the #813 retry-poll. Attempt 1's
#      sync already happened in the foreground below, so the loop opens with
#      the verify query — the call sequence per attempt is unchanged.
#   2. Linked-issue ("Closes #N") sync. Two more GraphQL round trips with no
#      user-visible urgency, so it rides along here.
_post_gh_pr_create_deferred() {
    local _attempts _i _issue
    if _post_gh_pr_create_repo_has_board; then
        _attempts="${POST_GH_PR_CREATE_SYNC_ATTEMPTS:-6}"
        _i=1
        while [ "$_i" -le "$_attempts" ]; do
            if [ "$(_gh_project_status_query_current pr "$pr_num")" = "In review" ]; then
                break
            fi
            if [ "$_i" -lt "$_attempts" ]; then
                sleep "${POST_GH_PR_CREATE_SYNC_SLEEP:-2}"
                _gh_project_status_sync pr "$pr_num" "In review"
            fi
            _i=$((_i + 1))
        done
        if [ "$_i" -gt "$_attempts" ]; then
            # Reaches a human only under POST_GH_PR_CREATE_ASYNC=0; the
            # detached branch sends stderr to /dev/null, which is the price
            # of not holding the turn open for the retry budget.
            printf '[post-gh-pr-create] PR #%s still not "In review" after %s attempts — GitHub auto-add may have landed late; verify the board.\n' \
                "$pr_num" "$_attempts" >&2
        fi
    fi

    if [ -n "$GH_REPO" ]; then
        for _issue in $(_gh_pr_closing_issue_numbers "$pr_num" "$GH_REPO" 2>/dev/null); do
            _gh_project_status_sync issue "$_issue" "In progress" \
                --only-from "Backlog,Ready,In review"
        done
    fi
}

printf '[post-gh-pr-create] PR #%s → "In review"\n' "$pr_num" >&2
# The one synchronous write. Boardless repos keep the helper's silent no-op
# contract, and a board that already carries the card is done right here.
_gh_project_status_sync pr "$pr_num" "In review"

if [ "${POST_GH_PR_CREATE_ASYNC:-1}" = "0" ]; then
    _post_gh_pr_create_deferred
else
    # Detach. The stdio redirections are load-bearing, not cosmetic: a child
    # holding the hook's stdout/stderr open keeps Claude Code waiting on the
    # pipe even after this process exits, which would undo the whole fix.
    # `disown` then drops the job so the exiting shell cannot SIGHUP it.
    (_post_gh_pr_create_deferred) </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
fi

exit 0
