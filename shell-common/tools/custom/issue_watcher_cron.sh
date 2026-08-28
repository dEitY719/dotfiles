#!/bin/bash
# shell-common/tools/custom/issue_watcher_cron.sh
# issue-watcher 주기 감시 사이클 — 1회 tick (issue #1389, #1440, #1453).
#
# cron 이 주기마다 이 스크립트를 호출하면 tick 1회를 수행한다. tick 은 감시부터
# 디스패치까지를 직접 수행한다 — 판단이 필요한 지점은 마지막 한 곳,
# 디스패치된 pane 안에서 도는 `/gh-issue-flow <N>` 뿐이다 (issue #1440):
#   1) 끝난 이슈의 워크트리 회수 (closed + agent 없음 + 미커밋 변경 없음)
#   2) 살아있는 per-issue agent 수가 상한이면 이번 tick 보류
#   3) `gh search issues` 로 할당된 open 이슈를 교차 저장소 한 번에 조회
#   4) 제외 라벨 필터 + watched-repos.json 밖 저장소 제외 + 로컬 경로 매핑
#   5) repo 라운드로빈 · 이슈 번호 오름차순으로 후보 정렬
#   6) 이미 실행 중 / 이미 처리됨(이슈를 닫는 open PR) / blockedBy OPEN 스킵
#   7) tick 당 최대 _IW_DISPATCH_PER_TICK 건만 워크트리 + herdr tab + agent 생성
#   8) `/gh-issue-flow <N>` 프롬프트 전달
# 토큰 한도 게이트가 닫혀 있으면 사이클 전체를 보류한다 (issue #1436, #1444).
#
# 워크트리 존재 여부는 어떤 판정에도 쓰이지 않는다 (issue #1453 NF-1) — 순수
# 작업 공간이라 언제 지워도 다음 tick 의 결정이 달라지지 않는다.
#
# 이슈에 어떤 쓰기도 하지 않는다 — 댓글·라벨·assignee 변경 없음. 조회 전용이다.
#
# Usage: issue_watcher_cron.sh [--cwd <PATH>] [--dry-run] | --status | [-h|--help|help]

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

# The herdr agent-name SSOT (#1530). Sourced at file scope rather than lazily
# because _iw_agent_name is called from both the dispatch loop and the tick's
# summary, and a tick that discovers the helper missing halfway through would
# have already opened panes it can no longer address.
if [ ! -f "${_IW_SHELL_COMMON}/functions/herdr_agent_name.sh" ]; then
    ux_error "herdr_agent_name.sh not found under ${_IW_SHELL_COMMON}/functions — cannot derive agent names."
    exit 1
fi
# shellcheck source=/dev/null
. "${_IW_SHELL_COMMON}/functions/herdr_agent_name.sh" || exit 1

# ============================================================
# Constants (SSOT for the watch cycle)
# ============================================================

_IW_STATE_SUBDIR="issue-watcher"
_IW_LOCK_BASENAME=".lock"

# Field separators, resolved once. `IFS="$(printf '\t')"` written into a
# `while` header is re-evaluated — and so re-forks `printf` — on every
# iteration, and the candidate loop runs once per search result (up to
# _IW_SEARCH_LIMIT per host). US (0x1f) joins label lists for the same reason
# a tab joins the columns: a label may contain a comma or a space.
_IW_TAB=$(printf '\t')
_IW_US=$(printf '\037')

# Watch list. Not a list of repos to *query* — `gh search issues` already spans
# every repo the account can see in one call. It is the result filter (an issue
# outside it is ignored) plus the repo -> local checkout map the worktree step
# needs. Overridable so the bats suite can point at a fixture.
_IW_REPOS_FILE_DEFAULT="${HOME:-/nonexistent}/.agent-factory/avatars/issue-watcher/watched-repos.json"

# Labels that park an issue. Exact matches, not substrings.
_IW_EXCLUDE_LABELS_DEFAULT="wontfix,보류,not-implement"

# Concurrency limits (issue #1453 D-2). Three constants, because they bound
# three different things and no one of them implies the others:
#
#   _IW_MAX_PER_REPO      fairness — one busy repo must not consume the whole
#                         budget and starve the rest
#   _IW_MAX_CONCURRENT    total load — the ceiling that stops the *accumulated*
#                         number of live sessions growing with the repo count
#   _IW_DISPATCH_PER_TICK intake rate — a burst of ready issues must not all
#                         enter their token-heavy implement phase together
#
# The pre-#1453 cap ("3 per cycle") only ever bounded intake. Dispatch is
# fire-and-forget, so with work taking T minutes and a period of P the steady
# state was roughly `T/P × intake` sessions at once — i.e. the slower the work,
# the more of it ran in parallel. The only thing holding that down was a bug
# (worktrees were never collected, and their presence blocked re-dispatch), so
# collecting them and capping concurrency had to land together.
#
# The defaults are the policy; the `IW_*` overrides exist so the bats suite can
# exercise the multi-dispatch paths without waiting out a real cycle, and so a
# machine with a different budget can say so — the same shape as
# IW_WATCHED_REPOS / IW_EXCLUDE_LABELS / IW_IDLE_POLL_SLEEP above.
#
# Defined here rather than with the other helpers because the three constants
# below are its only callers and they must be final before anything reads them.
# A cap that silently became "" or "abc" is worse than no override at all: every
# later `[ "$n" -ge "$cap" ]` would error out and the guard would read as passed
# (PR #1456 agy review).
_iw_cap() {
    case "${1-}" in
    '' | *[!0-9]*) ;;
    *) if [ "$1" -gt 0 ]; then
        printf '%s' "$1"
        return 0
    fi ;;
    esac
    [ -z "${1-}" ] || printf '[issue-watcher] %s=%s is not a positive integer — using %s.\n' "$3" "$1" "$2" >&2
    printf '%s' "$2"
}

_IW_MAX_PER_REPO=$(_iw_cap "${IW_MAX_PER_REPO-}" 7 IW_MAX_PER_REPO)
_IW_MAX_CONCURRENT=$(_iw_cap "${IW_MAX_CONCURRENT-}" 17 IW_MAX_CONCURRENT)
_IW_DISPATCH_PER_TICK=$(_iw_cap "${IW_DISPATCH_PER_TICK-}" 1 IW_DISPATCH_PER_TICK)
# Attempts per issue before giving up on it for this cycle. Every failed
# attempt cleans its own worktree up first, so a retry starts from scratch.
_IW_MAX_ATTEMPTS="3"
# Upper bound on the search result set. Only _IW_DISPATCH_PER_TICK survivors
# are ever dispatched, but the filters run before the cap, so the window has to
# be wider than the cap.
_IW_SEARCH_LIMIT="50"
# Upper bound on the open-PR window used to answer "is this issue already
# handled". Wide enough that a repo's whole open-PR set fits: an issue whose PR
# sits outside the window would read as unhandled and earn a second PR.
_IW_PR_LIMIT="100"

# herdr agent naming. The tick picks these itself now, so unlike pre-#1440 it
# can address the dispatched panes afterwards — which is also why the name must
# be unique across every watched repo: `iw-<number>` alone collides the moment
# two repos both have an issue #11, and herdr would route the second dispatch's
# prompt at the first one's pane (PR #1447 agy review). See _iw_agent_name.
#
# No trailing dash since #1530: `herdr_agent_name` joins the parts. Pre-#1530
# this folded the owner in verbatim (`iw-<owner>-<repo>-<N>`), which herdr's
# `^[a-z][a-z0-9_-]{0,31}$` rejects for any owner carrying uppercase — so the
# watcher dispatched nothing at all in 21 attempts.
_IW_AGENT_PREFIX="iw"
# `herdr agent prompt --wait` 한 번의 상한 — 4분. tick 이 겹치지 않게 막는 것은
# flock 이므로 이 값은 cron 주기와 무관하다. 무응답 pane 하나가 tick 을 무한정
# 붙들지 않게 하는 것이 목적이다.
_IW_TIMEOUT_MS="240000"
# Post-start idle checks (see _iw_wait_for_idle): at most 10 checks, this far
# apart. The gap is overridable so the bats suite does not pay real sleep on
# every cold-agent path. Neither value is the time a healthy launch waits —
# `herdr agent start` already answers `"agent_status":"idle"`, so the loop
# returns on its *first* poll and the elapsed time is ~0s. These two only bound
# the unhealthy case, where the agent never reports idle at all.
_IW_IDLE_POLL_MAX="10"
_IW_IDLE_POLL_SLEEP="${IW_IDLE_POLL_SLEEP:-0.5}"

# Unconditional settle wait between `agent start` and the first prompt
# (issue #1560). Not a poll interval and not replaceable by one: `idle` means
# "not working", not "accepting keystrokes", and a freshly drawn claude TUI is
# idle while its key-input loop is still unattached. herdr exposes no signal
# for "the input loop is up", and its own stall window (5000ms) is a fixed
# internal — so the only knob the dispatcher owns is how long it lets the pane
# sit before typing into it. Measured on herdr 0.7.5: prompting ~5s after start
# returns `agent_prompt_stalled` every time, ~13s lands. Raising
# _IW_IDLE_POLL_MAX instead is a no-op, for the reason above it.
#
# Applied on the fresh-launch path only — a warm session takes a prompt at
# once and must not pay this. Overridable (to 0) for the same reason
# _IW_IDLE_POLL_SLEEP is: the bats suite must not sleep 13 real seconds per
# dispatch test.
#
# 13 is the repo-wide constant for "herdr just brought something up, wait
# before touching it" (#1571). Its four twins are _IW_START_RETRY_SLEEP below,
# _PMT_SETTLE_SECONDS / _PMT_START_RETRY_SLEEP in pr_merge_train_cron.sh, and
# PMV_SETTLE_SECONDS in
# claude/skills/gh-pr-post-merge-verify/references/dispatch.sh.md. Change one,
# change all five — #1530/#1549 and #1560/#1571 are both the same defect
# recurring because only two of the three dispatchers were fixed.
_IW_SETTLE_SECONDS="${IW_SETTLE_SECONDS:-13}"

# Round-robin cursor (issue #1453 D-3). Its own file, so `rate-limit.json` and
# every pre-#1453 state directory stay untouched; a missing file simply means
# "start at the first watched repo".
_IW_SELECT_STATE_BASENAME="select.json"

# Stall recovery (issue #1443). A stalled prompt means the text is already
# sitting in the pane's input box unsubmitted, so the recovery is a bare Enter,
# never a second `agent prompt` — see _iw_stall_recover_via_enter. Bounded at 3
# presses 2s apart: a key-input loop that is not listening after ~6s is not
# going to start, and the whole budget stays far inside the 5-minute tick.
# The interval is overridable for the same reason _IW_IDLE_POLL_SLEEP is.
_IW_STALL_RECOVER_ATTEMPTS="3"
_IW_STALL_RECOVER_SLEEP="${IW_STALL_RECOVER_SLEEP:-2}"

# Start retrying (issue #1525, the same defect #1512 fixed on the merge-train
# side). `herdr tab create` answers before the pane's shell is interactive, so
# `agent start` on it is refused with `agent_pane_busy` — a timing race against
# a pane that is perfectly good a moment later. herdr rejects it immediately
# rather than waiting, so `agent start --timeout` (which only extends the
# readiness wait) cannot help; another attempt on the *same* pane can.
#
# This is a different layer from _IW_MAX_ATTEMPTS, which cleans the attempt up
# and builds a new worktree and a new, equally cold tab — three tries at the
# same race. That is what left 130 consecutive ticks with 0 dispatches. The two
# bounds are independent and both still hold.
#
# Bounded in *attempts*, not retries, so the `start N/MAX` warning reads exactly
# true. The gap is overridable for the same reason _IW_STALL_RECOVER_SLEEP is —
# the bats suite must not pay a real wait per retry test.
#
# The gap is 13s, not the 2s it shipped with (#1571): this is the *same* class
# of wait as _IW_SETTLE_SECONDS above — herdr answered before the thing it
# brought up was usable — and 2s was shorter than the 5s already measured to
# fail. Its twins are _IW_SETTLE_SECONDS above, _PMT_SETTLE_SECONDS /
# _PMT_START_RETRY_SLEEP in pr_merge_train_cron.sh, and PMV_SETTLE_SECONDS in
# claude/skills/gh-pr-post-merge-verify/references/dispatch.sh.md; all five
# move together. The wait and this retry are complements, not substitutes — 13s
# shrinks the race, the retry survives what is left of it.
_IW_START_ATTEMPT_MAX="3"
_IW_START_RETRY_SLEEP="${IW_START_RETRY_SLEEP:-13}"

# Rate-limit gate (issue #1436; judgment input rebuilt in #1444). Rationale for
# each value sits with the gate functions below; the values themselves live here
# with the rest of the SSOT.
#
# Both values were re-examined and confirmed as constants in #1441, which had
# proposed a one-strike close and an exponential 1800->3600->7200->14400 ramp:
#   - strikes stays 2. One strike would hold the watcher for 30 minutes over a
#     single transient herdr blip, and it contradicts the neighbouring
#     requirement that one stall among several delivered dispatches must NOT
#     close the gate.
#   - the backoff stays a single fixed value. Claude's quota windows run for
#     hours, so the real cost of retrying after 30 minutes is small, while a
#     ramp needs a third field in `rate-limit.json` (with back-compat for files
#     already on disk) and would invalidate the "twice its own length" outlier
#     guard in _iw_limit_gate_state, which both gate readers go through and
#     which assumes this value is fixed-length.
_IW_LIMIT_STATE_BASENAME="rate-limit.json"
_IW_LIMIT_STRIKES="2"
_IW_LIMIT_BACKOFF_SECONDS="1800"
# How long a *confirmed* dispatch has to hold `working` before the tick accepts
# it as proof the quota is intact (issue #1444). One `/gh-issue-flow` runs for
# minutes — review gate included — so a prompt that provably reached the pane
# and is idle again a minute later did not finish early, it never started.
_IW_LIMIT_OBSERVE_SEC="60"
# A fixed divisor of the window above, not a policy cap like the _IW_MAX_*
# knobs, so it stays a bare constant the way _IW_STALL_RECOVER_ATTEMPTS does.
_IW_LIMIT_OBSERVE_POLLS="6"
# Gap between those polls, derived so the two values above stay the SSOT.
# Overridable (to 0) for the same reason _IW_IDLE_POLL_SLEEP is: the bats suite
# must not pay a real minute per gate test.
_IW_LIMIT_OBSERVE_SLEEP="${IW_LIMIT_OBSERVE_SLEEP:-$((_IW_LIMIT_OBSERVE_SEC / _IW_LIMIT_OBSERVE_POLLS))}"
# Pane lines captured as evidence when a strike is booked (issue #1444). They
# go to the cron log for a human to read later; nothing parses them and nothing
# gates on them.
_IW_LIMIT_EVIDENCE_LINES="40"

# Set by _iw_stall_recover_via_enter when `herdr agent send-keys` itself fails —
# the pane is gone, not merely slow. Kept distinct from the prompt response's
# own `.error.code` so the dispatch log names the outage rather than the stall
# it is disguised as (issue #1443, PR #1449 codex review). Since #1444 it is a
# log input only — the gate no longer classifies error codes at all. Empty
# otherwise.
_IW_STALL_RECOVER_ERROR=""
# Set by _iw_start_agent_retrying to the herdr error code and the human sentence
# behind the start it gave up on — empty when herdr named neither on either
# stream (issue #1525). Log inputs only; nothing branches on them.
_IW_START_CODE=""
_IW_START_MESSAGE=""
# The file herdr's stderr is captured to. Global, not local, so the signal trap
# that removes it can still name it — a `local` would be unset by the time the
# trap fires and `set -u` would turn the cleanup into its own error (the same
# point agy raised on PR #1517).
_IW_ERRF=""
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
#   $1 = jq filter, e.g. '.result.pane.pane_id'.
#
# jq-only, and deliberately so: main() refuses to run without jq (the watch
# list and the search result are arrays of objects, which no flat-key text
# scanner can walk), so every caller here is downstream of that check. A
# hand-rolled awk/sed fallback would be unreachable code pretending to be a
# safety net. Always returns 0 — a malformed document reads as "no such field",
# which is what every caller already treats it as.
_iw_json_value() {
    jq -r "${1} // empty" 2>/dev/null || return 0
}

# First string value of a flat key anywhere in the document. `herdr tab create`
# and `herdr workspace create` both answer with a pane, but nest it under
# different parents (`.result.pane` vs `.result.root_pane`), and the CLI is
# free to add another. Keying on the leaf name rather than the path keeps this
# working across both shapes without a per-command filter table.
# The key travels as a jq *argument*, never as interpolated program text: a
# caller-supplied string spliced into the filter would be a jq syntax error at
# best and arbitrary jq at worst (PR #1447 agy review).
_iw_json_first() {
    jq -r --arg k "$1" \
        '[.. | objects | .[$k]? // empty] | map(select(type == "string")) | first // empty' \
        2>/dev/null || return 0
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
# Helpers — the three signals (issue #1453)
# ============================================================

# Until #1453 one signal — "does a wt/issue-<n> worktree exist" — answered
# three questions whose answers expire at different moments:
#
#   what is running right now   true from start to finish
#   what has already been done  true forever after
#   what may be collected       true once the work is over
#
# A worktree only ever reports that a dispatch *started*, so all three answers
# were wrong in a different direction: collecting one re-dispatched an issue
# whose PR was still open, keeping one retired an issue whose session had died
# unnoticed, and neither bounded how many sessions ran at once. The three
# questions now get three signals:
#
#   running now  -> a live herdr agent pane sitting in the issue's worktree
#   handled      -> GitHub: an open PR that closes the issue
#   collectable  -> the issue is closed and no agent pane is in its worktree
#
# The worktree is demoted to a plain workspace. Nothing keys on its existence
# (NF-1), so it can be removed at any moment without changing what the next
# tick decides — which is what makes collecting them safe at all.

# Parsed once per tick, like the watch list: both the running-now signal and
# the collection step walk it, and a `git worktree list` per watched checkout
# is the most expensive local call in the tick. Nothing re-reads it after
# _iw_cleanup_worktrees removes entries — the spawn path asks
# _iw_worktree_for_issue directly — so the cache cannot go stale within a tick.
_IW_ISSUE_WORKTREES=""
_IW_ISSUE_WORKTREES_LOADED=0

# Echo $1 with every symlink resolved, or $1 unchanged when it cannot be
# entered. Path comparisons in this file are between two sources that need not
# agree spelling-wise — herdr reports a pane's cwd, git reports a worktree root,
# and either can have arrived through a symlink.
_iw_physical_path() {
    (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"
}

# Emit `<worktree-path><TAB><owner/repo><TAB><number>` for every issue worktree
# across every watched checkout.
#
# The branch, not the directory name, identifies an issue worktree:
# `gwt spawn --wt-name issue-<n>` always branches `wt/issue-<n>/<index>`, while
# the directory carries a project prefix. Reading the number off the path would
# also hard-code a naming convention `gwt` owns and this script does not.
_iw_issue_worktrees() {
    local _repo _path _host

    if [ "${_IW_ISSUE_WORKTREES_LOADED}" -eq 1 ]; then
        [ -z "${_IW_ISSUE_WORKTREES}" ] || printf '%s\n' "${_IW_ISSUE_WORKTREES}"
        return 0
    fi

    _IW_ISSUE_WORKTREES=$(_iw_watch_list | while IFS="${_IW_TAB}" read -r _repo _path _host; do
        [ -n "${_path}" ] || continue
        [ -d "${_path}" ] || continue
        git -C "${_path}" worktree list --porcelain 2>/dev/null |
            awk -v repo="${_repo}" '
                /^worktree / { p = substr($0, 10) }
                /^branch refs\/heads\/wt\/issue-/ {
                    n = $0
                    sub(/^branch refs\/heads\/wt\/issue-/, "", n)
                    sub(/\/.*$/, "", n)
                    if (n ~ /^[0-9]+$/ && p != "") print p "\t" repo "\t" n
                }
            '
    done)

    _IW_ISSUE_WORKTREES_LOADED=1
    [ -z "${_IW_ISSUE_WORKTREES}" ] || printf '%s\n' "${_IW_ISSUE_WORKTREES}"
}

# Parsed once per tick, like the watch list: every cap check consults it and
# the herdr round trip must not be paid per candidate. main() primes it in its
# own shell so the subshells below inherit a warm cache.
_IW_LIVE_AGENTS=""
_IW_LIVE_AGENTS_LOADED=0

# Emit `<owner/repo><TAB><number>` for every issue whose worktree currently has
# a live herdr agent pane. Non-zero when herdr could not be asked at all.
#
# `herdr agent list` carries no agent-name field, so the `iw-<repo>-issue-<n>` names
# this tick chooses cannot be matched back by name. What it does carry is each
# pane's `cwd`, and every dispatched pane is opened on the issue's worktree
# (`_iw_tab_create` passes it as --cwd) — so joining that column against
# _iw_issue_worktrees recovers the issue number exactly, without depending on
# how the worktree directory happens to be named.
#
# Volatility is fine here, unlike for "already handled": the question is what
# is running *now*, and after a reboot nothing is. The signal and the truth go
# stale together.
_iw_live_agents() {
    local _json _cwds

    if [ "${_IW_LIVE_AGENTS_LOADED}" -eq 1 ]; then
        [ -z "${_IW_LIVE_AGENTS}" ] || printf '%s\n' "${_IW_LIVE_AGENTS}"
        return 0
    fi

    _json=$(herdr agent list 2>/dev/null) || return 1
    # A herdr that answers nothing at all must not read as "nothing running":
    # that is the one mistake this signal cannot afford, since it would lift
    # the concurrency cap exactly when herdr is unhealthy.
    [ -n "${_json}" ] || return 1

    # Both columns, because they answer at different moments: `cwd` is where the
    # pane was opened (stable for the session's whole life) and `foreground_cwd`
    # is where its shell is standing now. Taking only one loses the session that
    # `cd`-ed away, and losing it means the collection step reads a live
    # worktree as idle (PR #1456 agy/codex review).
    _cwds=$(printf '%s' "${_json}" | jq -r '
        if (.result.agents | type) == "array"
        then .result.agents[]? | (.cwd // empty), (.foreground_cwd // empty)
        else error("no agent list")
        end
    ' 2>/dev/null) || return 1

    # Prefix match on the physical path, not string equality: an agent sitting in
    # a subdirectory of its worktree is still working that issue, and one side of
    # the comparison may have arrived through a symlink.
    _IW_LIVE_AGENTS=$(_iw_issue_worktrees |
        while IFS="${_IW_TAB}" read -r _wt _repo _number; do
            printf '%s\t%s\t%s\n' "$(_iw_physical_path "${_wt}")" "${_repo}" "${_number}"
        done |
        awk -F "${_IW_TAB}" -v cwds="${_cwds}" '
            BEGIN {
                n = split(cwds, a, "\n")
                for (i = 1; i <= n; i++) if (a[i] != "") live[++m] = a[i]
            }
            {
                for (i = 1; i <= m; i++) {
                    if (live[i] == $1 || index(live[i], $1 "/") == 1) {
                        print $2 "\t" $3
                        break
                    }
                }
            }
        ')

    _IW_LIVE_AGENTS_LOADED=1
    [ -z "${_IW_LIVE_AGENTS}" ] || printf '%s\n' "${_IW_LIVE_AGENTS}"
}

# Prime the memo with "nothing is running" after a failed lookup. Only
# --dry-run may use this: it is a report, so it must stay usable where a real
# tick cannot run at all, and the worst a wrong count can do there is overstate
# what the next real tick would pick. A real tick must never assume this — the
# concurrency cap would lift exactly when herdr is unhealthy. Named rather than
# written out at the call site so the memo's two-variable invariant stays here.
_iw_live_agents_assume_none() {
    _IW_LIVE_AGENTS=""
    _IW_LIVE_AGENTS_LOADED=1
}

# How many per-issue sessions are live, in total and per repo.
_iw_live_count() {
    _iw_live_agents | awk 'END { print NR + 0 }'
}

_iw_live_count_repo() {
    _iw_live_agents | awk -F "${_IW_TAB}" -v r="$1" '$1 == r { n++ } END { print n + 0 }'
}

# 0 when <owner/repo> issue <number> already has a live session.
_iw_live_has() {
    _iw_live_agents |
        awk -F "${_IW_TAB}" -v r="$1" -v n="$2" \
            '$1 == r && $2 == n { f = 1 } END { exit f ? 0 : 1 }'
}

# Single-entry open-PR cache. One entry is enough because the selector walks
# one repo at a time and never comes back to a repo within a tick.
_IW_PR_CACHE_REPO=""
_IW_PR_CACHE_DATA=""

# Load <repo>'s open PRs. Non-zero when GitHub could not be asked.
#
# `gh pr list` rather than a `closedByPullRequestsReferences` GraphQL query on
# each issue: one round trip per repo instead of one per candidate, and it
# answers on every GHES version in the watch list rather than only on servers
# new enough to know the field.
_iw_load_open_prs() {
    local _repo="$1" _host="$2" _json _count

    [ "${_IW_PR_CACHE_REPO}" != "${_repo}" ] || return 0

    _json=$(GH_HOST="${_host}" gh pr list --repo "${_repo}" \
        --state open --limit "${_IW_PR_LIMIT}" \
        --json number,headRefName,body 2>/dev/null) || return 1
    [ -n "${_json}" ] || return 1

    # A full window is indistinguishable from a truncated one, and a truncated
    # one silently reinstates the exact failure this file exists to remove: the
    # issue's PR sits outside the window, reads as "unhandled", and earns a
    # second PR. Treat it as "cannot tell" rather than as an answer
    # (PR #1456 agy/codex review).
    _count=$(printf '%s' "${_json}" | jq -r 'length' 2>/dev/null) || _count=""
    case "${_count}" in
    '' | *[!0-9]*) return 1 ;;
    esac
    if [ "${_count}" -ge "${_IW_PR_LIMIT}" ]; then
        ux_warning "${_repo} has ${_count}+ open PRs — cannot rule out a duplicate within the ${_IW_PR_LIMIT}-PR window." >&2
        return 1
    fi

    _IW_PR_CACHE_REPO="${_repo}"
    _IW_PR_CACHE_DATA="${_json}"
}

# Is issue <1> already handled by an open PR in the cached repo?
#   0  handled
#   1  not handled
#   2  cannot tell — the caller drops the issue for this tick (D-6)
#
# Two independent marks, because each alone has a hole: `gh:pr` writes
# `Closes #<n>` into the body, which a hand-opened PR may lack, while
# `gwt spawn --wt-name issue-<n>` always branches `wt/issue-<n>/<index>`, which
# a PR raised from a differently-named branch would not have.
#
# The `\b` after the number is load-bearing: without it `#14` would match a
# body that closes `#145`, retiring issue 14 for as long as that PR is open.
#
# The optional `:` and the optional non-space run before `#` cover the two other
# spellings GitHub honours — `Closes: #11` and the cross-repo `Closes
# owner/repo#11` — which the first cut missed, so a hand-written PR using either
# read as "unhandled" and the issue was dispatched again (PR #1456 codex review).
_iw_handled_by_pr() {
    local _number="$1" _hits

    _hits=$(printf '%s' "${_IW_PR_CACHE_DATA}" | jq -r --arg n "${_number}" '
        [ .[]?
          | select(
              ((.headRefName // "") | test("^wt/issue-" + $n + "/"))
              or ((.body // "")
                  | test("\\b(close[sd]?|fix(e[sd])?|resolve[sd]?):?\\s+(\\S+)?#" + $n + "\\b"; "i"))
            )
        ] | length
    ' 2>/dev/null) || _hits=""

    case "${_hits}" in
    '' | *[!0-9]*) return 2 ;;
    0) return 1 ;;
    *) return 0 ;;
    esac
}

# ============================================================
# Helpers — the round-robin cursor (issue #1453 D-3)
# ============================================================

_iw_select_state_file() {
    printf '%s/%s' "$(_iw_state_dir)" "${_IW_SELECT_STATE_BASENAME}"
}

# Echo the repo the previous tick dispatched from, or nothing. A missing or
# unreadable file — which is every state directory written before #1453 — means
# "start at the first watched repo", never an error.
_iw_last_repo() {
    local _file
    _file=$(_iw_select_state_file)
    [ -f "${_file}" ] || return 0
    _iw_json_value '.last_repo' <"${_file}"
}

# Persist the cursor. Failure costs round-robin fairness for one tick and
# nothing else, so it warns and returns success — the dispatch it follows has
# already happened.
_iw_write_last_repo() {
    local _dir _file

    # --dry-run runs the whole selection to report what it would pick, and
    # advancing the cursor there would make merely *asking* change which repo
    # the next real tick serves.
    [ "${_IW_DRY_RUN}" -eq 0 ] || return 0

    _dir=$(_iw_state_dir)
    _file=$(_iw_select_state_file)

    if ! mkdir -p "${_dir}" 2>/dev/null ||
        ! printf '{ "last_repo": "%s" }\n' "$1" >"${_file}" 2>/dev/null; then
        ux_warning "Cannot persist the round-robin cursor (${_file}) — the next tick starts at the first repo." >&2
    fi
}

# Echo every watched repo once, starting at the one *after* $1.
#
# Without the rotation, a repo that always has candidates would starve every
# repo after it: the selector stops at the first dispatchable issue it finds,
# and at one dispatch per tick that first repo would be the only one ever
# reached.
_iw_repo_order() {
    _iw_watch_list | awk -F "${_IW_TAB}" -v last="$1" '
        { r[NR] = $1 }
        END {
            if (NR == 0) exit
            start = 1
            if (last != "") {
                for (i = 1; i <= NR; i++) if (r[i] == last) { start = i + 1; break }
            }
            for (k = 0; k < NR; k++) print r[((start - 1 + k) % NR) + 1]
        }
    '
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

        # A directory that exists is not an account that is logged in
        # (issue #1561) — a logged-out pane opens on `Not logged in · Run
        # /login` and drops every keystroke, which the dispatcher then reports
        # as `agent_prompt_stalled`, a symptom that names neither the account
        # nor the cause. Fail here instead, where the account is still in hand.
        # The rule for what counts as "logged in" lives in claude.sh, sourced
        # above; only the wording of the failure is this script's business.
        if ! _claude_account_logged_in "${_cfg_dir}"; then
            ux_error "Claude account not logged in: ${_cfg_dir}/.credentials.json is missing, empty, or not valid JSON — the pane would open on 'Not logged in' and every prompt would stall."
            ux_info "Run: claude-accounts status   (then log that account in)" >&2
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
    local _host _json _qualifiers

    for _host in $(_iw_watch_hosts); do
        # `repo:` qualifiers, so the result window covers the watched repos and
        # nothing else. Without them `--limit` truncates *every* assigned issue
        # on the account, and under gh's default best-match ordering a watched
        # repo can sit outside the window indefinitely — starvation with no
        # symptom (PR #1447 codex/agy review). `--sort updated` then makes the
        # truncation deterministic instead of relevance-ranked.
        _qualifiers=$(_iw_watch_list |
            awk -F "${_IW_TAB}" -v h="${_host}" '$3 == h { printf "repo:%s ", $1 }')
        [ -n "${_qualifiers}" ] || continue

        # Word splitting is the point: each qualifier is its own argument.
        # shellcheck disable=SC2086
        _json=$(GH_HOST="${_host}" gh search issues ${_qualifiers} \
            --assignee @me --state open \
            --sort updated --order desc \
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
    local _labels="$1" _excluded _label _oldifs

    _excluded="${IW_EXCLUDE_LABELS:-${_IW_EXCLUDE_LABELS_DEFAULT}}"

    _oldifs="$IFS"
    IFS="${_IW_US}"
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
# nothing.
#
# Since #1453 this locates a workspace, it does not judge anything: the spawn
# step reads back the path `gwt` just created, and the cleanup step needs the
# path to remove. Whether the issue may be dispatched is decided entirely by
# the three signals above (NF-1).
#
# `gwt spawn --wt-name issue-<n>` always branches `wt/issue-<n>/<index>`, so
# the branch is what identifies the worktree; the directory name carries a
# project prefix this script would otherwise have to reconstruct.
#
# The *highest* index wins, not the first listed. A cleanup that failed to
# remove `wt/issue-<n>/1` leaves the next spawn creating `/2`, and handing the
# tab the stale `/1` path would open the pane on the wrong worktree. The house
# helper `_gh_pr_approve_locate_own_worktree` picks the highest index for this
# same reason.
_iw_worktree_for_issue() {
    git -C "$1" worktree list --porcelain 2>/dev/null |
        awk -v pat="^branch refs/heads/wt/issue-$2/" '
            /^worktree / { p = substr($0, 10) }
            $0 ~ pat {
                n = $0
                sub(pat, "", n)
                if (n ~ /^[0-9]+$/ && n + 0 >= best) { best = n + 0; bestp = p }
                else if (bestp == "") { bestp = p }
            }
            END { if (bestp != "") print bestp }
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

# Emit `<repo><TAB><number>` for every searched issue that survives the *local*
# filters — watch-list membership, a checkout that exists, and the exclude
# labels. Just the two identifying columns: the checkout path and the host are
# per-repo facts, and _iw_select_candidates resolves them once per repo it
# serves rather than once per candidate it discards. No cap and no network
# here either: which of these
# actually gets dispatched is _iw_select_candidates' decision, and paying for a
# GitHub round trip per candidate when at most _IW_DISPATCH_PER_TICK of them
# can be dispatched would be wasted on all the rest.
#
# Every diagnostic here goes to stderr: stdout is the candidate list itself,
# and one ux_info line landing in it would be read back as an issue to
# dispatch.
_iw_collect_candidates() {
    local _repo _number _labels _path

    # fd 3, not stdin: a loop body that reads stdin would consume the rest of
    # the search results and truncate the candidate set with no error
    # (PR #1447 agy review). Nothing in the body reads stdin today; keeping the
    # read on fd 3 is what stops the next thing added here from regressing it.
    while IFS="${_IW_TAB}" read -r _repo _number _labels <&3; do
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

        printf '%s\t%s\n' "${_repo}" "${_number}"
    done 3<<EOF
$(_iw_search_issues)
EOF
}

# Pick which of $1's `<repo><TAB><number>` lines this tick dispatches, at most
# _IW_DISPATCH_PER_TICK of them, and echo each as
# `<repo><TAB><number><TAB><path><TAB><host>` — the shape the dispatch loop and
# the dry-run printer consume.
#
# Order is repo round-robin (D-3) then ascending issue number, so the oldest
# issue of the repo whose turn it is goes first and the choice is deterministic
# enough to test. The expensive checks run last and lazily — the open-PR list
# costs one call per repo and blockedBy one per issue, and both are paid only
# for issues that are about to be dispatched.
#
# Diagnostics go to stderr, for the same reason as in _iw_collect_candidates.
# How many issues this tick may still start: the per-tick intake rate, further
# clipped by the free slots under the global ceiling.
#
# Both halves are needed. main() already refuses a tick that is *at* the global
# ceiling, but that check answers one question ("may this tick start anything?")
# and cannot answer the other ("how many?"): with _IW_DISPATCH_PER_TICK raised
# above 1, a tick starting at max-1 would pass that gate and then dispatch its
# whole per-tick allowance, overshooting _IW_MAX_CONCURRENT (PR #1456 codex
# review).
_iw_dispatch_budget() {
    local _slots
    _slots=$(( _IW_MAX_CONCURRENT - $(_iw_live_count) ))
    if [ "${_slots}" -lt "${_IW_DISPATCH_PER_TICK}" ]; then
        [ "${_slots}" -gt 0 ] || _slots=0
        printf '%s' "${_slots}"
    else
        printf '%s' "${_IW_DISPATCH_PER_TICK}"
    fi
}

_iw_select_candidates() {
    local _candidates="$1"
    local _repo _number _numbers _path _host _live _rc _selected=""
    local _budget _repo_budget

    _budget=$(_iw_dispatch_budget)
    [ "${_budget}" -gt 0 ] || return 0

    for _repo in $(_iw_repo_order "$(_iw_last_repo)"); do
        _numbers=$(printf '%s\n' "${_candidates}" |
            awk -F "${_IW_TAB}" -v r="${_repo}" '$1 == r { print $2 }' | sort -n)
        # Before the cap check, so a repo with nothing to offer stays silent
        # rather than reporting that it is busy.
        [ -n "${_numbers}" ] || continue

        _live=$(_iw_live_count_repo "${_repo}")
        _repo_budget=$(( _IW_MAX_PER_REPO - _live ))
        if [ "${_repo_budget}" -le 0 ]; then
            ux_info "Skipping ${_repo} — ${_live} of its issues are already running (max ${_IW_MAX_PER_REPO})." >&2
            continue
        fi
        # The repo's own headroom, never more than what is left for this tick.
        [ "${_repo_budget}" -le "${_budget}" ] || _repo_budget="${_budget}"

        _path=$(_iw_repo_path "${_repo}")
        _host=$(_iw_repo_host "${_repo}")

        # Fail-closed, unlike the blockedBy query below, because the risks are
        # not symmetric (D-6): mistaking "blocked" for "ready" starts an issue
        # a little early, but mistaking "handled" for "ready" opens a second PR
        # on an issue that already has one. Nothing is lost by waiting — the
        # next tick re-evaluates this repo from scratch.
        if ! _iw_load_open_prs "${_repo}" "${_host}"; then
            ux_warning "Cannot list open PRs for ${_repo} — skipping its issues this tick." >&2
            continue
        fi

        for _number in ${_numbers}; do
            if _iw_live_has "${_repo}" "${_number}"; then
                ux_info "Skipping ${_repo}#${_number} — already running." >&2
                continue
            fi

            _iw_handled_by_pr "${_number}"
            _rc=$?
            if [ "${_rc}" -eq 0 ]; then
                ux_info "Skipping ${_repo}#${_number} — an open PR already closes it." >&2
                continue
            elif [ "${_rc}" -ne 1 ]; then
                ux_warning "Cannot tell whether ${_repo}#${_number} is already handled — skipping it this tick." >&2
                continue
            fi

            if _iw_blocked_by_open "${_repo}" "${_number}" "${_host}"; then
                continue
            fi

            printf '%s\t%s\t%s\t%s\n' "${_repo}" "${_number}" "${_path}" "${_host}"
            _selected="${_repo}"
            # Both budgets are spent per selection, so a repo cannot exceed its
            # own headroom and the tick cannot exceed the global one.
            _repo_budget=$((_repo_budget - 1))
            _budget=$((_budget - 1))
            [ "${_repo_budget}" -gt 0 ] || break
            [ "${_budget}" -gt 0 ] || break
        done

        [ "${_budget}" -gt 0 ] || break
    done

    # Advance the cursor only when this tick actually served a repo. A tick
    # that found nothing has not taken anyone's turn.
    [ -z "${_selected}" ] || _iw_write_last_repo "${_selected}"
}

# Remove the worktrees of issues that are finished with: the issue is closed
# and no agent pane is sitting in it (D-1's third signal).
#
# Runs *before* dispatch (D-4) for two reasons — the space it frees is usable
# in the same tick, and a failure here cannot hold up a dispatch. Cleanup is
# hygiene, not correctness: since NF-1 nothing keys on a worktree's existence,
# so a worktree that outlives its issue costs disk and nothing else.
_iw_cleanup_worktrees() {
    local _wt _repo _number _host _state _root _here _wt_real

    _here=$(pwd -P)

    # fd 3: the loop body runs `gh`, which reads stdin (PR #1447 agy review).
    while IFS="${_IW_TAB}" read -r _wt _repo _number <&3; do
        [ -n "${_wt}" ] || continue
        [ -n "${_number}" ] || continue
        # Never collect the worktree this tick is standing in — or any worktree
        # it is standing *inside*. Comparing the two raw strings missed both a
        # subdirectory cwd and a path that arrived through a symlink, either of
        # which let the tick pull the ground out from under itself
        # (PR #1456 agy/codex review).
        _wt_real=$(_iw_physical_path "${_wt}")
        [ "${_here}" = "${_wt_real}" ] && continue
        case "${_here}/" in "${_wt_real}/"*) continue ;; esac
        ! _iw_live_has "${_repo}" "${_number}" || continue

        _host=$(_iw_repo_host "${_repo}")
        _state=$(GH_HOST="${_host}" gh issue view "${_number}" --repo "${_repo}" \
            --json state -q .state 2>/dev/null) || {
            ux_info "Cannot read ${_repo}#${_number} state — leaving its worktree in place."
            continue
        }
        [ "${_state}" = "CLOSED" ] || continue

        # Deliberately no `--force`. `git worktree remove` refuses a working
        # tree with modified or untracked files, and that refusal is the whole
        # safety property here: an issue can be closed by hand while its session
        # still holds uncommitted work, and forcing would delete that work with
        # no warning and no recovery — routine hygiene must not be a data-loss
        # path (PR #1456 agy/codex review). A worktree left behind costs disk
        # and nothing else, since NF-1 means its existence decides nothing.
        _root=$(_iw_repo_path "${_repo}")
        if git -C "${_root}" worktree remove "${_wt}" >/dev/null 2>&1; then
            ux_info "Collected worktree ${_wt} — ${_repo}#${_number} is closed."
        else
            ux_warning "Leaving worktree ${_wt} in place — it has uncommitted or untracked changes (or git refused)."
        fi
    done 3<<EOF
$(_iw_issue_worktrees)
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
# from nothing. Since NF-1 a survivor no longer retires the issue — nothing
# keys on a worktree's existence — but it still costs: `gwt spawn` skips any
# index whose branch is still there, so the next attempt builds `issue-<n>/2`
# and the abandoned `/1` stays on disk until a later tick collects it.
_iw_cleanup_attempt() {
    local _path="$1" _wt="$2" _tab="$3"

    [ -z "${_tab}" ] || herdr tab close "${_tab}" >/dev/null 2>&1 || true
    [ -z "${_wt}" ] || (cd "${_path}" && _iw_gwt remove "${_wt}" --force) >/dev/null 2>&1 || true
}

# Run a herdr *create* command with the flags every such call shares:
#   _iw_herdr_create <cwd> <label> <herdr-subcommand-word>...
# e.g. `_iw_herdr_create "$_cwd" "$_label" tab create --workspace ws-1`.
#
# One owner on purpose. The `--env CLAUDE_CONFIG_DIR=` tail is the invariant
# the rate-limit gate's soundness rests on — one account, one quota (see the
# gate's header comment) — so a new creation call site must not be able to
# quietly omit it. herdr's own JSON goes to stdout; the exit code is herdr's.
_iw_herdr_create() {
    local _cwd="$1" _label="$2"
    shift 2

    set -- "$@" --cwd "${_cwd}" --label "${_label}" --no-focus
    [ -z "${_IW_CONFIG_DIR}" ] || set -- "$@" --env "CLAUDE_CONFIG_DIR=${_IW_CONFIG_DIR}"

    herdr "$@" 2>/dev/null
}

# Echo the herdr workspace label for <repo> at <path>.
#
# The directory basename is the label users already see (`dotfiles`,
# `agent-toolbox`), so it stays the default — but only while it identifies one
# repo. Two watched checkouts whose leaf directory names collide would
# otherwise be merged onto a single workspace, and the second repo's tabs would
# open inside the first repo's (PR #1447 codex/agy review). When the watch list
# contains such a collision, both sides fall back to the unambiguous slug.
_iw_workspace_label() {
    local _repo="$1" _path="$2" _base _count

    _base=$(basename "${_path}")
    _count=$(_iw_watch_list |
        awk -F "${_IW_TAB}" -v b="${_base}" '
            { n = split($2, parts, "/"); if (parts[n] == b) c++ }
            END { print c + 0 }
        ')

    if [ "${_count}" -le 1 ]; then
        printf '%s' "${_base}"
    else
        printf '%s' "${_repo}"
    fi
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

    _json=$(_iw_herdr_create "${_cwd}" "${_label}" workspace create) || _json=""
    _ws=$(printf '%s' "${_json}" | _iw_json_first workspace_id)
    [ -n "${_ws}" ] || return 1
    printf '%s' "${_ws}"
}

# Open the issue's tab and echo `<pane_id><TAB><tab_id>`.
_iw_tab_create() {
    local _ws="$1" _cwd="$2" _label="$3" _json _pane _tab

    _json=$(_iw_herdr_create "${_cwd}" "${_label}" tab create --workspace "${_ws}") || return 1

    _pane=$(printf '%s' "${_json}" | _iw_json_first pane_id)
    _tab=$(printf '%s' "${_json}" | _iw_json_first tab_id)
    [ -n "${_pane}" ] || return 1
    printf '%s\t%s' "${_pane}" "${_tab}"
}

# Echo the herdr agent name for <owner/repo> issue <number>:
# `iw-<repo>-issue-<number>`. Composition and the character rules behind it are
# the SSOT this file shares with pr_merge_train_cron.sh and
# gh:pr-post-merge-verify — shell-common/functions/herdr_agent_name.sh (#1530).
# Returns non-zero (and echoes nothing) when the repo cannot be normalized;
# every caller here treats an empty name as a failed dispatch rather than
# starting an agent with a malformed one.
_iw_agent_name() {
    herdr_agent_name "${_IW_AGENT_PREFIX}" "$1" "issue-$2"
}

# Echo the agent status (idle|working|blocked|done|unknown). Returns non-zero
# when herdr itself rejects the query (agent missing / pane closed).
_iw_agent_status() {
    local _json _rc=0
    _json=$(herdr agent get "$1" 2>/dev/null) || _rc=$?
    [ "${_rc}" -eq 0 ] || return 1
    printf '%s' "${_json}" | _iw_json_value '.result.agent.agent_status'
}

# Echo the agent's `state_change_seq` — a counter herdr bumps on every
# observable state change, a submitted prompt included. Returns non-zero when
# herdr rejects the query; echoes nothing when the field is absent (an older
# herdr, or a response this script cannot parse), which every caller reads as
# "no usable baseline" rather than as a value.
#
# This is the signal `agent_status` cannot give: `idle` covers both "waiting for
# input" and "drew the input box but the key loop is not wired up yet", and that
# ambiguity is the whole of issue #1443. The counter moving is positive proof
# the keystroke landed.
_iw_agent_seq() {
    local _json _rc=0
    _json=$(herdr agent get "$1" 2>/dev/null) || _rc=$?
    [ "${_rc}" -eq 0 ] || return 1
    printf '%s' "${_json}" | _iw_json_value '.result.agent.state_change_seq'
}

# `-- ARG...` is passed through to the pane's claude invocation. Unattended
# cron ticks must never stop on a permission-approval prompt (issue #1393).
#
# stderr goes to the file named by $3 rather than /dev/null (#1525, the same
# defect class as #1445/#1458): herdr is free to answer on either stream and in
# cron it answers on stderr, so discarding it threw away the one sentence that
# named the failure — `agent_pane_busy`. stdout stays on the pipe because the
# caller reads `.error.code` off it, which is why this is a file and not `2>&1`.
_iw_agent_start() {
    herdr agent start "$1" --kind claude --pane "$2" \
        -- --dangerously-skip-permissions 2>"$3"
}

# Echo the herdr error code behind a failed call: <1> is herdr's stdout, <2> the
# file its stderr was captured to. stdout first, stderr as the fallback. Both
# are consulted because the stream herdr picks is not ours to choose — and in
# production it picked the one nobody was reading. Echoes nothing when neither
# stream carried a parsable error document.
_iw_herdr_error_code() {
    local _json="$1" _errfile="$2" _code

    _code=$(printf '%s' "${_json}" | _iw_json_value '.error.code')
    if [ -z "${_code}" ] && [ -s "${_errfile}" ]; then
        _code=$(_iw_json_value '.error.code' <"${_errfile}")
    fi
    printf '%s' "${_code}"
}

# The human half of the same document: herdr's own sentence about the failure.
# Same two inputs and the same stdout-first order as _iw_herdr_error_code —
# herdr picks the stream, not us, so a helper that read only one of them would
# hand back a code with no sentence for every failure answered on the other.
# `agent_name_taken` is exactly that shape (PR #1528 review, codex).
#
# `.error.message` before any raw text, because what herdr writes is a JSON
# document and dumping it verbatim buries the sentence inside braces exactly
# where a cron log is read in a hurry. The first raw stderr line is the last
# resort: it is what a non-JSON stream (a crash, a shell error) carries, and
# what keeps this working if herdr ever changes its JSON shape.
_iw_herdr_error_message() {
    local _json="$1" _errfile="$2" _msg

    _msg=$(printf '%s' "${_json}" | _iw_json_value '.error.message')
    if [ -z "${_msg}" ] && [ -s "${_errfile}" ]; then
        _msg=$(_iw_json_value '.error.message' <"${_errfile}")
        [ -n "${_msg}" ] || _msg=$(head -n 1 "${_errfile}" 2>/dev/null)
    fi
    printf '%s' "${_msg}"
}

# Start agent <1> on pane <2>, retrying only the #1525 `agent_pane_busy` race.
# 0 = an agent is running on the pane, 1 = gave up, with _IW_START_CODE naming
# the last failure and _IW_START_MESSAGE carrying herdr's sentence about it.
#
# Each attempt truncates the capture file, so a retry that fails differently can
# never be reported with the previous attempt's cause.
_iw_start_agent_retrying() {
    local _agent="$1" _pane="$2" _json _attempt=1 _rc=1

    _IW_START_CODE=""
    _IW_START_MESSAGE=""
    # A capture file we cannot open costs the *cause*, not the start: herdr
    # names nothing we can read, so nothing is retryable, but the one attempt
    # is still worth making. /dev/null keeps every reader below correct — it is
    # never `-s`, so both parsers simply answer "no such field".
    #
    # The trap is armed only on the branch that has a file to remove. Arming it
    # unconditionally put `/dev/null` in reach of the trap's own `rm -f`, which
    # — unlike the guarded removal at the end — would have run on any signal
    # landing in this window (PR #1528 review, agy).
    if _IW_ERRF=$(mktemp); then
        trap 'rm -f "${_IW_ERRF}"' EXIT INT TERM
    else
        _IW_ERRF="/dev/null"
    fi

    while :; do
        if _json=$(_iw_agent_start "${_agent}" "${_pane}" "${_IW_ERRF}"); then
            _rc=0
            break
        fi
        _IW_START_CODE=$(_iw_herdr_error_code "${_json}" "${_IW_ERRF}")

        # The one failure worth another attempt (#1525): the pane was created
        # moments ago and its shell is not interactive yet. Only this code — a
        # failure that does not name itself is not a race we understand, and
        # ending the attempt immediately keeps that contract intact.
        if [ "${_IW_START_CODE}" != "agent_pane_busy" ] ||
            [ "${_attempt}" -ge "${_IW_START_ATTEMPT_MAX}" ]; then
            break
        fi

        ux_warning "herdr agent start ${_agent} hit agent_pane_busy on pane ${_pane} (start ${_attempt}/${_IW_START_ATTEMPT_MAX}) — retrying in ${_IW_START_RETRY_SLEEP}s."
        [ "${_IW_START_RETRY_SLEEP}" = "0" ] || sleep "${_IW_START_RETRY_SLEEP}"
        _attempt=$((_attempt + 1))
    done

    # Only the give-up path is ever read, and the capture file still holds the
    # last attempt's stderr right here — so a retry that goes on to win pays
    # nothing for the sentence describing the failure it recovered from.
    [ "${_rc}" -eq 0 ] || _IW_START_MESSAGE=$(_iw_herdr_error_message "${_json}" "${_IW_ERRF}")

    # Mirrors the arming above: no file, no trap to clear and nothing to remove.
    if [ "${_IW_ERRF}" != "/dev/null" ]; then
        trap - EXIT INT TERM
        rm -f "${_IW_ERRF}"
    fi
    return "${_rc}"
}

# Wait for a freshly started agent to report idle before prompting it.
# `herdr agent start` only confirms the pane looks interactive — a claude
# process can have drawn its prompt box before its key-input loop accepts
# Enter, so the command is typed but never submitted and herdr's fixed 5s stall
# check fires `agent_prompt_stalled` (issue #1399). Pre-#1440 the resident
# watcher pane got this grace; every dispatched pane needs it now, because each
# one is cold (PR #1447 codex review).
#
# This is a *health* check, not the settle wait. A live agent answers `idle` on
# the first poll, so the normal path leaves here in ~0s — the poll budget only
# bounds how long a missing agent or a closed pane can hold the tick, and
# hitting that budget still dispatches because the stall recovery in
# _iw_prompt_issue is the second line of defence. The wait that actually makes
# the prompt land is _iw_settle, which runs after this (issue #1560).
_iw_wait_for_idle() {
    local _agent="$1" _i=0 _status _get_failed=0 _detail=""

    while [ "${_i}" -lt "${_IW_IDLE_POLL_MAX}" ]; do
        if _status=$(_iw_agent_status "${_agent}"); then
            [ "${_status}" != "idle" ] || return 0
        else
            _get_failed=$((_get_failed + 1))
        fi
        _i=$((_i + 1))
        [ "${_i}" -lt "${_IW_IDLE_POLL_MAX}" ] || break
        [ "${_IW_IDLE_POLL_SLEEP}" = "0" ] || sleep "${_IW_IDLE_POLL_SLEEP}"
    done

    # Health-check failures (agent missing / pane closed) and a merely slow
    # `starting` pane both land here — surface the failure count so a genuinely
    # gone agent does not read as "just slow" (PR #1400 codex review).
    # Counted in checks, not seconds: the gap between them is overridable, so a
    # wall-clock figure here would be wrong in exactly the runs that read it.
    [ "${_get_failed}" -eq 0 ] ||
        _detail=" (${_get_failed}/${_IW_IDLE_POLL_MAX} health-check failures)"
    ux_warning "Agent ${_agent} never reported idle in ${_IW_IDLE_POLL_MAX} checks${_detail} — dispatching anyway."
}

# Let a freshly launched pane settle before typing into it (issue #1560).
# Separate from _iw_wait_for_idle on purpose: that one asks herdr a question
# and can answer "the agent is gone", this one asks nothing and can only wait.
# Always succeeds — a settle that could fail would skip the prompt it exists to
# protect, which is a worse outcome than a prompt sent slightly too early.
_iw_settle() {
    [ "${_IW_SETTLE_SECONDS}" = "0" ] || sleep "${_IW_SETTLE_SECONDS}"
    return 0
}

# Echo herdr's JSON response on stdout; the exit code is herdr's own.
#
# herdr writes its error JSON to stderr and its success payload to stdout, so
# the two must be merged here — dropping stderr leaves `.error.code` unreadable
# and every recovery branch below unreachable (#1559, the same defect class as
# #1445/#1458/#1525). Merged rather than split into a capture file the way
# _iw_agent_start does: the only reader is `_iw_json_value '.error.code'`, which
# already fails silently on non-JSON noise, and the success path never reaches
# it — rc 0 short-circuits ahead of the parse.
_iw_prompt_once() {
    herdr agent prompt "$1" "$2" --wait --timeout "${_IW_TIMEOUT_MS}" 2>&1
}

# Recover a stalled prompt by *submitting* what is already typed (issue #1443).
#   $1 = agent name
#   $2 = state_change_seq read before the prompt was sent, or "" when that read
#        did not produce one
#
# `agent_prompt_stalled` means herdr typed the command into the pane and saw no
# state change: the text is sitting in the input box, unsent, because the key
# loop was not accepting Enter yet. Re-sending the *prompt* — which is what this
# used to do — types the whole command a second time on top of the first, so the
# box ends up holding a doubled, corrupt line and Enter still never lands. The
# only correct recovery is the missing keystroke.
#
# Presses Enter up to _IW_STALL_RECOVER_ATTEMPTS times and returns 0 as soon as
# the pane shows evidence the submission landed:
#   - with a baseline seq: the counter moved (any move — a herdr restart could
#     reset it downwards and that is still an observable change);
#   - without one: `agent_status` reached `working`. A baseline read can fail on
#     a transient local herdr blip, and a sequence comparison against an empty
#     baseline can never succeed — that would escalate a one-off blip into a
#     permanent hard failure (PR #1449 codex review). `working` is the same
#     positive evidence the caller's pre-flight short-circuit already trusts.
#
# A `send-keys` that *itself* fails is a different animal from "no change yet":
# the agent is gone or herdr is unreachable, so the remaining attempts would
# only burn against a dead target. Bail immediately and publish a distinct error
# via _IW_STALL_RECOVER_ERROR so the rate-limit gate does not read a broken pane
# as a spent quota.
_iw_stall_recover_via_enter() {
    local _agent="$1" _seq0="$2" _i=1 _seq _status

    _IW_STALL_RECOVER_ERROR=""

    while [ "${_i}" -le "${_IW_STALL_RECOVER_ATTEMPTS}" ]; do
        if ! herdr agent send-keys "${_agent}" Enter >/dev/null 2>&1; then
            ux_error "herdr agent send-keys ${_agent} Enter failed — pane unreachable, abandoning stall recovery."
            _IW_STALL_RECOVER_ERROR="herdr_send_keys_failed"
            return 1
        fi

        [ "${_IW_STALL_RECOVER_SLEEP}" = "0" ] || sleep "${_IW_STALL_RECOVER_SLEEP}"

        if [ -n "${_seq0}" ]; then
            _seq=$(_iw_agent_seq "${_agent}") || _seq=""
            if [ -n "${_seq}" ] && [ "${_seq}" != "${_seq0}" ]; then
                ux_warning "Stalled prompt submitted by Enter on attempt ${_i}/${_IW_STALL_RECOVER_ATTEMPTS} (${_agent} state_change_seq ${_seq0} -> ${_seq})."
                return 0
            fi
        else
            _status=$(_iw_agent_status "${_agent}") || _status=""
            if [ "${_status}" = "working" ]; then
                ux_warning "Stalled prompt submitted by Enter on attempt ${_i}/${_IW_STALL_RECOVER_ATTEMPTS} (${_agent} is working; no seq baseline)."
                return 0
            fi
        fi

        _i=$((_i + 1))
    done

    ux_warning "Enter pressed ${_IW_STALL_RECOVER_ATTEMPTS}x on ${_agent} with no observable state change — prompt still unsubmitted."
    return 1
}

# Send `/gh-issue-flow <N>` to the issue's agent.
#
# The prompt is a slash command, not prose: pre-#1440 this channel carried an
# instruction to *run another agent*, and the receiving session had to work out
# which tool that meant (#1394). There is nothing left to interpret here, and
# the command runs top-level rather than inside a subagent, which is what took
# this path out of the `SubagentStop` guard gap (#1434).
_iw_prompt_issue() {
    local _agent="$1" _number="$2" _prompt _json _code _rc=0 _seq0 _post_stall_status _fail_code

    _prompt="/gh-issue-flow ${_number}"
    _IW_STALL_RECOVER_ERROR=""

    # Baseline taken *before* the prompt is sent, not after a stall is detected:
    # by then the counter may already have moved for the very submission this
    # comparison is supposed to detect, and a baseline read after the fact could
    # never tell the two apart (issue #1443).
    _seq0=$(_iw_agent_seq "${_agent}") || _seq0=""

    _json=$(_iw_prompt_once "${_agent}" "${_prompt}") || _rc=$?

    # Only `agent_prompt_stalled` gets a recovery pass: it means the command was
    # typed into a not-yet-ready input loop (issue #1399) and never submitted.
    # Every other error is a real failure — and note nothing here ever re-sends
    # the prompt, so a duplicate flow on the same issue is not reachable.
    if [ "${_rc}" -ne 0 ]; then
        _code=$(printf '%s' "${_json}" | _iw_json_value '.error.code')
        if [ "${_code}" = "agent_prompt_stalled" ]; then
            # `agent_prompt_stalled` only proves herdr saw no state change
            # within its fixed 5s window — it does NOT prove the prompt was
            # never submitted (PR #1400 codex review). `working` is positive
            # evidence the call *did* land, so there is nothing to recover.
            _post_stall_status=$(_iw_agent_status "${_agent}") || _post_stall_status=""
            if [ "${_post_stall_status}" = "working" ]; then
                ux_warning "herdr reported agent_prompt_stalled but ${_agent} is already working — treating as delivered, not retrying."
                _rc=0
            elif _iw_stall_recover_via_enter "${_agent}" "${_seq0}"; then
                _rc=0
            fi
        fi
    fi

    if [ "${_rc}" -eq 0 ]; then
        ux_success "Dispatched to ${_agent}: ${_prompt}"
        return 0
    fi

    # Naming the failure only. A failed `send-keys` wins over the prompt
    # response's own code because it is the more specific fact: the response
    # says `agent_prompt_stalled`, but the pane being unreachable is what a
    # human needs to read in the cron log (PR #1449 codex review). No caller
    # branches on this string — since #1444 the gate reads whether the dispatch
    # succeeded, never why it failed. `_code` is already parsed above: reaching
    # here means the dispatch failed, which is exactly the branch that set it.
    _fail_code="${_IW_STALL_RECOVER_ERROR:-${_code}}"
    ux_error "herdr agent prompt failed for agent ${_agent} (${_fail_code:-unknown})."
    return 1
}

# One issue, end to end: worktree, workspace, tab, agent, prompt. Retries the
# whole sequence up to _IW_MAX_ATTEMPTS times, cleaning up before each retry so
# no attempt inherits the previous one's half-built state.
_iw_process_issue() {
    local _repo="$1" _number="$2" _path="$3"
    local _attempt=1 _agent _label _wt="" _ws="" _pane_tab="" _pane="" _tab=""
    local _cause="" _msg=""

    # A repo whose name normalizes to nothing has no addressable agent, so the
    # dispatch fails here rather than starting a session under a name no later
    # tick can look up (#1530).
    _agent=$(_iw_agent_name "${_repo}" "${_number}") || {
        ux_warning "Cannot derive a herdr agent name for ${_repo}#${_number} — skipping."
        return 1
    }
    _label=$(_iw_workspace_label "${_repo}" "${_path}")

    while [ "${_attempt}" -le "${_IW_MAX_ATTEMPTS}" ]; do
        _wt=""
        _tab=""

        if ! _wt=$(_iw_spawn_worktree "${_path}" "${_number}"); then
            ux_warning "Worktree spawn failed for ${_repo}#${_number} (attempt ${_attempt}/${_IW_MAX_ATTEMPTS})."
            # A spawn can fail after `git worktree add` succeeded. Recover the
            # path so the cleanup below really removes it — a survivor would
            # push the next attempt onto a fresh index and leak this one.
            _wt=$(_iw_worktree_for_issue "${_path}" "${_number}")
        elif ! _ws=$(_iw_workspace_for_label "${_label}" "${_path}"); then
            ux_warning "No herdr workspace for ${_label} (attempt ${_attempt}/${_IW_MAX_ATTEMPTS})."
        elif ! _pane_tab=$(_iw_tab_create "${_ws}" "${_wt}" "#${_number}"); then
            ux_warning "herdr tab create failed for ${_repo}#${_number} (attempt ${_attempt}/${_IW_MAX_ATTEMPTS})."
        else
            IFS="${_IW_TAB}" read -r _pane _tab <<EOF
${_pane_tab}
EOF
            if ! _iw_start_agent_retrying "${_agent}" "${_pane}"; then
                # One line, plus the sentence herdr actually gave, indented
                # under it (#1445's idiom). Without it every cause — a busy
                # pane, a dead server, a rejected account — converged on the
                # same unhelpful sentence, which is precisely why #1525 sat
                # unnoticed through 21 failed starts.
                # The code goes on the main line and the sentence under it —
                # the code is the token a human greps a cron log for
                # (`grep -c agent_pane_busy` is how #1525 was measured), the
                # sentence is what they read once they have found it. Folding
                # the two into one field would cost whichever half lost.
                _cause="${_IW_START_MESSAGE}"
                _msg="herdr agent start ${_agent} failed on pane ${_pane} (${_IW_START_CODE:-unknown}, attempt ${_attempt}/${_IW_MAX_ATTEMPTS})."
                [ -z "${_cause}" ] || _msg="${_msg}
    원인: ${_cause}"
                ux_warning "${_msg}"
            elif _iw_wait_for_idle "${_agent}" && _iw_settle; then
                if _iw_prompt_issue "${_agent}" "${_number}"; then
                    ux_success "${_repo}#${_number} dispatched (worktree ${_wt}, pane ${_pane})."
                    return 0
                elif [ "$(_iw_agent_status "${_agent}")" = "working" ]; then
                    # A `working` agent is never torn down, whatever the dispatch
                    # reported (#1559). One tick killed a session that was doing
                    # real work three times over, because a failed attempt ran
                    # _iw_cleanup_attempt unconditionally — the prompt call had
                    # failed, the agent had not. Deliberately independent of the
                    # `.error.code` fix in _iw_prompt_once: that parsing is what
                    # silently broke in production, so it is not the only thing
                    # standing between a live session and `gwt remove`.
                    # Only `working` counts — an empty answer is an unreachable
                    # agent, not evidence of work, and still cleans up below.
                    #
                    # Scoped to *after* _iw_prompt_issue actually ran (agy/codex
                    # PR #1578 review): this branch used to sit alongside
                    # _iw_wait_for_idle in the same `&&` chain, so a plain idle
                    # timeout — the prompt for THIS issue never even sent — could
                    # also match "working" (the agent busy with unrelated, stale
                    # state) and get reported as delivered. Nesting it here means
                    # the guard only ever fires once a prompt attempt for this
                    # issue was actually made.
                    ux_warning "${_agent} reports working despite the failed prompt — keeping worktree ${_wt} and pane ${_pane}, not retrying."
                    return 0
                fi
            fi
        fi

        _iw_cleanup_attempt "${_path}" "${_wt}" "${_tab}"
        _attempt=$((_attempt + 1))
    done

    ux_error "Giving up on ${_repo}#${_number} after ${_IW_MAX_ATTEMPTS} attempts."
    return 1
}

# ============================================================
# Rate-limit gate (issue #1436, #1444)
# ============================================================

# Token-limit exhaustion is invisible to this tick by default: `herdr agent
# prompt` hands the command over and returns, so a claude session that starts
# and then stops on a spent quota still reads as a delivered dispatch — the
# tick books a success, the retry never fires, and the issue waits for a whole
# cycle before the next tick can offer it again. Since NF-1 the worktree left
# behind no longer retires the issue permanently (that was the pre-#1453
# failure this gate was written against), so exhaustion now costs a wasted
# dispatch slot rather than a lost issue — still worth holding the cycle for.
#
# The gate below holds dispatches after repeated unhealthy cycles and reopens
# itself on a timer. It is deliberately evidence-poor and fail-open (NF-1): a
# detector that can wedge the watcher is worse than the leak it guards.
#
# The signal, rebuilt in issue #1444. It used to be `agent_prompt_stalled` plus
# a non-`working` status, on the premise that a spent quota stops the session
# before it can change state. #1443 measured that same pair coming out of a
# *cold start*: claude draws its input box — herdr reads `idle` and
# `interactive_ready` — before its key-input loop accepts Enter, so the command
# is typed but never submitted. Both causes produce byte-identical
# observations, so no classifier over that pair can separate them. Worse, once
# #1443's Enter recovery repairs the stall the dispatch succeeds, and a gate
# keyed on the failure would never fire again for any reason.
#
# What replaces it is behavioural and reads in two steps:
#
#   1. Was the prompt actually submitted? `_iw_prompt_issue` returning 0 is
#      that proof — either herdr's `--wait` observed the transition, or the
#      Enter recovery watched `state_change_seq` move (#1443). A dispatch that
#      failed proves nothing about the quota: it is an input-loop or transport
#      problem, so the gate is left exactly as it was.
#   2. Did the submitted work hold? A confirmed dispatch is polled for
#      `_IW_LIMIT_OBSERVE_SEC`. One `/gh-issue-flow` runs for minutes, so an
#      agent that never reaches `working`, or falls back to `idle`/`done`
#      inside that window, did not do the work it was handed. That is the
#      shape quota exhaustion takes, and it earns the strike.
#
# `blocked` counts as alive alongside `working`: an agent waiting on a human is
# positive evidence the account still has quota, and booking it as exhaustion
# would be a new false positive of exactly the kind this rewrite removes.
#
# Deliberately *not* part of the judgment: the pane's own text. Claude's
# rate-limit banner wording is version-bound, so a string match would rot into
# a no-op that is neither fail-open nor fail-closed — an undetectable
# malfunction. The pane tail is captured when a strike is booked so a human can
# confirm the call after the fact, and that is all it is for.
#
# Pre-#1440 this had to watch the resident `iw-watch` agent instead, because
# the per-issue panes were opened by a subagent inside that session and their
# names never came back (`herdr agent list` carries no agent-name field). The
# tick now chooses those names itself, so the gate watches the panes doing the
# work rather than the one that spawned them. What made the old indirection
# sound in the first place still holds and is now direct:
# `_iw_resolve_config_dir` picks a single CLAUDE_CONFIG_DIR for every pane this
# tick opens (#1393) — one account, one quota. If account routing ever splits
# per pane, this reasoning has to be revisited (PR #1439 agy review).
#
# One account, one quota is also why the verdict is per *tick* rather than per
# dispatch: any single agent holding `working` proves the quota is intact for
# all of them, so one healthy pane clears the slate even when its neighbours
# died of their own issue-specific problems (issue #1444).

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

# Persist strikes + backoff deadline. Both are written as JSON *strings*. The
# readers coerce either encoding, so this is a schema choice, not a constraint;
# it stays quoted because a file already on disk from an earlier tick must keep
# parsing across the upgrade.
_iw_limit_write() {
    local _dir _file
    _dir=$(_iw_state_dir)
    _file=$(_iw_limit_state_file)

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

# Classify the gate file. Pure: reads, never writes, never prints (PR #1469
# codex review). Both readers route their expiry arithmetic through here — the
# tick's deciding _iw_limit_gate_check below and the read-only
# _iw_status_report — so a future change to what "expired" means cannot let
# `--status` disagree with the tick it reports on. The side effect that must
# NOT be shared (clearing an expired file) stays with the caller that is
# allowed to have it.
#
# Echoes "<state> <seconds-left>"; the second field is meaningful only for
# `closed`.
#
#   none        no state file at all — nothing to hold
#   fieldless   file present, `backoff_until` absent: a truncated write or a
#               hand edit. Strike bookkeeping never produces this —
#               _iw_limit_write always emits both fields
#   unreadable  `backoff_until` present but not a number
#   open        deadline is 0, the resting value written while strikes
#               accumulate: evidence on record, gate still open
#   no-clock    _iw_now failed
#   expired     deadline passed, or sits further out than twice its own length
#               — the latter cannot have been written by this script, so a
#               clock jump or a hand edit did it, and expiring beats stalling
#               forever (F-3)
#   closed      deadline still ahead; field 2 carries the seconds remaining
#
# Every unexpected input lands on a state its callers answer by dispatching —
# see NF-1.
_iw_limit_gate_state() {
    local _until _now _left

    [ -f "$(_iw_limit_state_file)" ] || {
        printf 'none 0\n'
        return 0
    }

    _until=$(_iw_limit_read backoff_until)
    case "${_until}" in
    '')
        printf 'fieldless 0\n'
        return 0
        ;;
    *[!0-9]*)
        printf 'unreadable 0\n'
        return 0
        ;;
    esac

    if [ "${_until}" -le 0 ]; then
        printf 'open 0\n'
        return 0
    fi

    _now=$(_iw_now)
    if [ -z "${_now}" ]; then
        printf 'no-clock 0\n'
        return 0
    fi

    _left=$((_until - _now))
    if [ "${_left}" -le 0 ] || [ "${_left}" -gt $((_IW_LIMIT_BACKOFF_SECONDS * 2)) ]; then
        printf 'expired 0\n'
        return 0
    fi

    printf 'closed %s\n' "${_left}"
}

# The gate itself. Returns 0 when this tick may dispatch, non-zero when it must
# hold. Every unexpected input answers 0 — see NF-1. This is the reader that
# owns the write: an expired file is cleared here, and only here.
_iw_limit_gate_check() {
    local _state _left

    read -r _state _left <<EOF
$(_iw_limit_gate_state)
EOF

    case "${_state}" in
    none | open)
        return 0
        ;;
    fieldless)
        ux_warning "Rate-limit state file has no backoff deadline — dispatching anyway."
        return 0
        ;;
    unreadable)
        ux_warning "Rate-limit state is unreadable (backoff_until='$(_iw_limit_read backoff_until)') — dispatching anyway."
        return 0
        ;;
    no-clock)
        ux_warning "Cannot read the clock — rate-limit gate ignored this tick."
        return 0
        ;;
    expired)
        ux_info "Rate-limit gate reopened — backoff expired, resuming dispatch."
        _iw_limit_clear
        return 0
        ;;
    esac

    ux_warning "Rate-limit gate closed — holding dispatch for ~$(((_left + 59) / 60))m (no worktree is created this tick)."
    return 1
}

# Poll the tick's confirmed dispatches for `_IW_LIMIT_OBSERVE_SEC`.
#
# Three verdicts, because "the agent is idle" and "herdr would not tell us what
# the agent is" are different facts and collapsing them is exactly the bug this
# whole rewrite exists to remove (PR #1468 codex review):
#
#   rc 0  one of them is alive at the end of the window — quota intact.
#         Echoes that agent.
#   rc 1  the window ended with a readable, non-alive status — the strike
#         verdict. Echoes an agent that *did* reach `working` earlier in the
#         window if there was one, so the caller can say "fell back" rather
#         than "never started"; echoes nothing when none of them ever moved.
#   rc 2  the deciding poll produced no readable status at all (every
#         `herdr agent get` errored, or answered without the field). No
#         evidence either way — the caller leaves the gate untouched.
#
# `_iw_agent_status` reports both of its failure modes as an empty string, so
# emptiness is the absence of evidence, never evidence of idleness. A strike
# needs a status we actually read.
#
# The last poll is the one that decides: `working` has to be *held*, not merely
# touched. The earlier polls exist only to tell those two failures apart in the
# log.
_iw_limit_observe() {
    local _agents="$1" _i=0 _agent _status _alive="" _seen="" _readable=0

    while [ "${_i}" -lt "${_IW_LIMIT_OBSERVE_POLLS}" ]; do
        [ "${_IW_LIMIT_OBSERVE_SLEEP}" = "0" ] || sleep "${_IW_LIMIT_OBSERVE_SLEEP}"
        _i=$((_i + 1))
        _alive=""
        # Per-poll, like `_alive`: only the deciding poll's readability counts.
        # A pane readable 50 seconds ago says nothing about now.
        _readable=0

        # fd 3, not stdin: the loop body runs `herdr`, which would otherwise
        # swallow the rest of the agent list and silently shorten the
        # observation to its first entry (PR #1447 agy review).
        while IFS= read -r _agent <&3; do
            [ -n "${_agent}" ] || continue
            _status=$(_iw_agent_status "${_agent}") || _status=""
            [ -z "${_status}" ] || _readable=1
            case "${_status}" in
            working | blocked)
                _alive="${_agent}"
                break
                ;;
            esac
        done 3<<EOF
${_agents}
EOF
        # `_alive` is this poll's answer and is cleared above every round;
        # `_seen` latches so the caller can tell "fell back" from "never
        # started".
        [ -z "${_alive}" ] || _seen="${_alive}"
    done

    if [ -n "${_alive}" ]; then
        printf '%s' "${_alive}"
        return 0
    fi

    [ "${_readable}" -eq 1 ] || return 2

    printf '%s' "${_seen}"
    return 1
}

# Copy the tail of each dispatched pane into the cron log when a strike is
# booked (issue #1444). Evidence for a human reading the log afterwards — the
# gate has already decided by the time this runs, and nothing here can change
# that decision. `--format text` gives the pane as plain lines; an error
# response comes back as JSON on stdout, which is skipped rather than logged as
# if it were pane content. That skip is decided by `_iw_json_value`, not by a
# byte-prefix match on the envelope: pane text is not JSON, so the filter reads
# as "no such field" for real output and names the code for a real error.
_iw_limit_evidence() {
    local _agents="$1" _agent _text _line

    # fd 3, not stdin: the loop body runs `herdr` (PR #1447 agy review).
    while IFS= read -r _agent <&3; do
        [ -n "${_agent}" ] || continue
        _text=$(herdr agent read "${_agent}" --lines "${_IW_LIMIT_EVIDENCE_LINES}" \
            --format text 2>/dev/null) || _text=""
        if [ -z "${_text}" ] || [ -n "$(printf '%s' "${_text}" | _iw_json_value '.error.code')" ]; then
            ux_info "No pane output captured for ${_agent}."
            continue
        fi
        ux_info "Pane tail for ${_agent} (evidence only — not a gate input):"
        printf '%s\n' "${_text}" | while IFS= read -r _line; do
            ux_bullet_sub "${_line}"
        done
    done 3<<EOF
${_agents}
EOF
}

# Record this tick's outcome. $1 is the newline-separated list of agents whose
# prompt was confirmed submitted — every other dispatch is excluded upstream
# because an unsubmitted prompt says nothing about the quota (issue #1444).
#
# Two consecutive unproductive ticks shut the gate; one productive tick wipes
# the slate, so `_IW_LIMIT_STRIKES` really does count consecutive failures. 1
# would hold the watcher over a single transient herdr blip; 2 buys that
# evidence for one extra tick (~5 min).
_iw_limit_record() {
    local _agents="$1" _alive="" _strikes _now _rc=0

    # Nothing reached a pane this tick: no evidence either way, so the strike
    # count stays exactly where it was. Said out loud rather than returned
    # silently — a gate that leaves no trace here is indistinguishable from a
    # gate that never ran, which is the class of blind assertion issue #1442
    # went through this suite to remove.
    if [ -z "${_agents}" ]; then
        ux_info "No dispatch reached its pane this tick — nothing to judge, gate untouched."
        return 0
    fi

    # Three-way, not a boolean: `rc 2` is "herdr never answered", which must not
    # be booked as idleness. On `rc 1` `_alive` carries the agent that reached
    # `working` earlier in the window, if any — see _iw_limit_observe.
    _alive=$(_iw_limit_observe "${_agents}") || _rc=$?
    if [ "${_rc}" -eq 0 ]; then
        ux_info "Agent ${_alive} held 'working' for ${_IW_LIMIT_OBSERVE_SEC}s — quota is not exhausted, gate cleared."
        _iw_limit_clear
        return 0
    fi
    if [ "${_rc}" -eq 2 ]; then
        ux_warning "No dispatched agent's status could be read after ${_IW_LIMIT_OBSERVE_SEC}s — herdr unreachable, gate untouched."
        return 0
    fi

    _strikes=$(_iw_limit_read strikes)
    case "${_strikes}" in
    '' | *[!0-9]*) _strikes=0 ;;
    esac
    _strikes=$((_strikes + 1))

    if [ -n "${_alive}" ]; then
        ux_warning "Agent ${_alive} reached 'working' and fell back inside ${_IW_LIMIT_OBSERVE_SEC}s (${_strikes}/${_IW_LIMIT_STRIKES}) — possible token-limit exhaustion."
    else
        ux_warning "No dispatched agent reached 'working' within ${_IW_LIMIT_OBSERVE_SEC}s (${_strikes}/${_IW_LIMIT_STRIKES}) — possible token-limit exhaustion."
    fi
    _iw_limit_evidence "${_agents}"

    if [ "${_strikes}" -lt "${_IW_LIMIT_STRIKES}" ]; then
        _iw_limit_write "${_strikes}" "0" || true
        return 0
    fi

    _now=$(_iw_now)
    if [ -z "${_now}" ]; then
        ux_warning "Cannot read the clock — rate-limit gate left open despite ${_strikes} unproductive ticks."
        return 0
    fi

    # Claude's quota windows run for hours, so a short backoff would only
    # re-dispatch into the same wall; 30 minutes keeps the recovery latency
    # (F-3) well inside one window while cutting the burn rate to zero.
    ux_warning "Rate-limit gate closed for $((_IW_LIMIT_BACKOFF_SECONDS / 60))m — ${_strikes} consecutive ticks whose dispatches never held 'working' (likely token limit)."
    _iw_limit_write "0" "$((_now + _IW_LIMIT_BACKOFF_SECONDS))" || true
}

# ============================================================
# Status report (--status)
# ============================================================

# A read-only window on the rate-limit gate (issue #1441, AC 11): it answers
# "is the watcher holding, and for how long" without running a tick.
#
# Deliberately does *not* call _iw_limit_gate_check. That helper clears an
# expired `rate-limit.json` as part of deciding, so reusing it would make an
# inspection command mutate state — the same reason --dry-run stays clear of it
# (PR #1447 codex/agy review). What the two share instead is
# _iw_limit_gate_state, which is pure: the arithmetic is stated once, the side
# effect stays with the tick (PR #1469 codex review).
#
# Always exits 0, including on an unreadable file. A closed gate is a normal
# operating state, not an error, and `set -e` cron wrappers that call this to
# log the gate must not die on it; the state is carried by the text, which is
# what a human reading cron.log reads anyway.
_iw_status_report() {
    local _file _state _left _strikes

    _file=$(_iw_limit_state_file)

    ux_header "issue-watcher status"
    ux_bullet "state file"
    ux_bullet_sub "${_file}"

    read -r _state _left <<EOF
$(_iw_limit_gate_state)
EOF

    if [ "${_state}" = "none" ]; then
        ux_success "Rate-limit gate open — no state file, the next tick dispatches."
        return 0
    fi

    # The deadline is classified before anything is asserted about the record:
    # reporting `?/2 ... on record` and then "the state is unreadable" one line
    # later is a contradiction, and the strike line is the one that looks like
    # data to whoever is reading cron.log.
    case "${_state}" in
    fieldless | unreadable)
        ux_warning "Rate-limit state is unreadable (backoff_until='$(_iw_limit_read backoff_until)') — the next tick dispatches anyway."
        return 0
        ;;
    esac

    # A file whose deadline parsed but whose strike count did not was hand
    # edited; "?" says so rather than inventing a 0.
    _strikes=$(_iw_limit_read strikes)
    case "${_strikes}" in
    '' | *[!0-9]*) _strikes="?" ;;
    esac
    ux_bullet "strikes"
    ux_bullet_sub "${_strikes}/${_IW_LIMIT_STRIKES} consecutive stalled dispatches on record"

    case "${_state}" in
    open)
        ux_success "Rate-limit gate open — the next tick dispatches."
        return 0
        ;;
    no-clock)
        ux_warning "Cannot read the clock — cannot tell whether the backoff has expired."
        return 0
        ;;
    expired)
        ux_success "Rate-limit gate open — the backoff expired, the next tick reopens it."
        return 0
        ;;
    esac

    ux_warning "Rate-limit gate closed — holding dispatch for ~$(((_left + 59) / 60))m."
    ux_bullet_sub "delete ${_file} to reopen it now"
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
    ux_info "Usage: issue_watcher_cron.sh [--cwd <PATH>] [--dry-run] | --status | [-h|--help|help]"
    ux_info "Runs one issue-watcher tick: find assigned issues, dispatch /gh-issue-flow."
    ux_bullet "options"
    ux_bullet_sub "--cwd <PATH>   run the tick from PATH; relative watch-list paths resolve against it"
    ux_bullet_sub "--dry-run      print the issues this tick would dispatch, change nothing"
    ux_bullet_sub "               (takes no lock and does not evaluate the rate-limit gate)"
    ux_bullet_sub "--status       print the rate-limit gate state and exit; runs no tick"
    ux_bullet_sub "               (takes no lock, changes nothing, always exits 0)"
    ux_bullet_sub "               --status and --help are terminal: the first of the two"
    ux_bullet_sub "               on the line answers and exits, ignoring the rest"
    ux_bullet_sub "-h, --help, help   show this help"
    ux_bullet "cycle"
    ux_bullet_sub "gh search issues --assignee @me --state open   (one query per watched host)"
    ux_bullet_sub "excluded labels: ${_IW_EXCLUDE_LABELS_DEFAULT}"
    ux_bullet_sub "an issue with an OPEN blockedBy is skipped (query failure fails open)"
    ux_bullet_sub "an issue an open PR already closes is skipped (query failure skips the repo)"
    ux_bullet_sub "a worktree's existence decides nothing — it is a workspace, not a marker"
    ux_bullet_sub "at most ${_IW_DISPATCH_PER_TICK} issue(s) per tick, ${_IW_MAX_ATTEMPTS} attempts each"
    ux_bullet_sub "no issue is ever written to — no comment, label or assignee change"
    ux_bullet "concurrency"
    ux_bullet_sub "a live agent pane in an issue's worktree means that issue is running"
    ux_bullet_sub "${_IW_MAX_CONCURRENT} running in total holds the tick (exit 0); ${_IW_MAX_PER_REPO} in one repo skips that repo"
    ux_bullet_sub "repos take turns (round-robin); within a repo the lowest issue number goes first"
    ux_bullet_sub "a worktree is collected once its issue is closed and no agent sits in it"
    ux_bullet "watch list"
    ux_bullet_sub "${_IW_REPOS_FILE_DEFAULT}"
    ux_bullet_sub "override with \$IW_WATCHED_REPOS; entries are {repo, path, host}"
    ux_bullet "state"
    ux_bullet_sub "\${XDG_STATE_HOME:-\$HOME/.local/state}/${_IW_STATE_SUBDIR}/${_IW_LIMIT_STATE_BASENAME}   (rate-limit gate)"
    ux_bullet_sub "\${XDG_STATE_HOME:-\$HOME/.local/state}/${_IW_STATE_SUBDIR}/${_IW_SELECT_STATE_BASENAME}       (round-robin cursor; absent = start at the first repo)"
    ux_bullet "rate-limit gate"
    ux_bullet_sub "a dispatch is judged only once its prompt is confirmed submitted"
    ux_bullet_sub "healthy means its agent still holds 'working' ${_IW_LIMIT_OBSERVE_SEC}s later"
    ux_bullet_sub "${_IW_LIMIT_STRIKES} ticks in a row where no dispatched agent does close the gate"
    ux_bullet_sub "a prompt that never reached the pane leaves the gate exactly as it was"
    ux_bullet_sub "a strike logs the pane tail as evidence — pane text never opens or closes the gate"
    ux_bullet_sub "while closed the tick holds: no prompt, no worktree, exit 0"
    ux_bullet_sub "it reopens by itself after $((_IW_LIMIT_BACKOFF_SECONDS / 60))m — delete ${_IW_LIMIT_STATE_BASENAME} to reopen it now"
    ux_bullet "claude session (claude-yolo parity)"
    ux_bullet_sub "each pane runs claude --dangerously-skip-permissions (unattended cron)"
    ux_bullet_sub "internal setup mode  → CLAUDE_CONFIG_DIR=\$HOME/.claude"
    ux_bullet_sub "otherwise            → CLAUDE_CONFIG_DIR=\$HOME/.claude-\${CLAUDE_DEFAULT_ACCOUNT:-personal}"
    ux_bullet_sub "  (that account must be listed in \$CLAUDE_ENABLED_ACCOUNTS)"
    ux_bullet_sub "no \$CLAUDE_ENABLED_ACCOUNTS and no \$CLAUDE_DEFAULT_ACCOUNT → \$HOME/.claude if it exists"
    ux_bullet_sub "the resolved directory must already exist — the tick fails fast otherwise"
    ux_bullet_sub "it must also hold a parseable .credentials.json — a logged-out account stalls every prompt"
    ux_bullet "crontab"
    ux_bullet_sub "*/5 * * * * /path/to/issue_watcher_cron.sh >> ~/.local/state/issue-watcher/cron.log 2>&1"
}

# ============================================================
# Main
# ============================================================

main() {
    local _cwd="" _repo _number _path _host _rc _dispatched=0 _failed=0 _candidates _live
    local _confirmed=""

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
        --status)
            # Terminal, like --help, and deliberately answered from inside the
            # parse loop: --status must reach the gate ahead of the gh/herdr
            # presence checks, because the gate is a local state file and the
            # box where a real tick cannot run is exactly where someone asks.
            # Handling it here also keeps --cwd off the read path, which the
            # report does not use — _iw_state_dir resolves through
            # XDG_STATE_HOME/HOME, never the working directory — so a bad
            # --cwd cannot make a documented always-0 command exit 1.
            _iw_status_report
            exit 0
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

    # Parse the watch list here, in the tick's own shell. Every later consult
    # sits inside a `$( )` — `_iw_repo_path` runs once per search result — and
    # a memo written there would be discarded with the subshell, leaving the
    # cache in _iw_watch_list permanently cold. Priming it once makes the file
    # read and the jq parse happen exactly once per tick, as intended.
    _iw_watch_list >/dev/null

    # Same reasoning, one signal down: the worktree scan feeds both the
    # running-now join (inside a pipeline) and the collection loop (inside a
    # heredoc), so neither call site can warm the memo for the other. Priming
    # it here holds `git worktree list` to one run per watched checkout.
    _iw_issue_worktrees >/dev/null

    # A dry run reports what it would dispatch and touches nothing, so it must
    # stay usable on a machine with no herdr server.
    if [ "${_IW_DRY_RUN}" -eq 0 ] && ! command -v herdr >/dev/null 2>&1; then
        ux_error "herdr not found in PATH — cannot run the issue-watcher tick."
        ux_info "Install it via ./herdr/setup.sh, or add it to the cron PATH."
        exit 1
    fi

    # The dry run answers ahead of both guards, and deliberately so. Taking the
    # lock would make a dry run silently no-op while a real tick is mid-cycle —
    # exactly when a human is most likely to be asking what the watcher sees —
    # and evaluating the gate would *clear* an expired `rate-limit.json`, which
    # is a state change in a mode documented as changing nothing
    # (PR #1447 codex/agy review).
    if [ "${_IW_DRY_RUN}" -eq 1 ]; then
        # A dry run must stay usable where a real tick cannot run at all, so an
        # unreachable herdr degrades to "nothing is running" here instead of
        # holding the tick.
        if ! _iw_live_agents >/dev/null; then
            _iw_live_agents_assume_none
            ux_warning "Cannot list herdr agents — reporting as if nothing were running."
        fi

        _candidates=$(_iw_select_candidates "$(_iw_collect_candidates)")
        if [ -z "${_candidates}" ]; then
            ux_info "No dispatchable issue this tick."
            exit 0
        fi
        ux_success "Dry run — would dispatch:"
        while IFS="${_IW_TAB}" read -r _repo _number _path _host <&3; do
            [ -n "${_repo}" ] || continue
            ux_bullet "${_repo}#${_number}  (${_path}, ${_host})"
        done 3<<EOF
${_candidates}
EOF
        exit 0
    fi

    _iw_acquire_lock || exit 0

    # Before any worktree is created: a closed gate must cost nothing.
    _iw_limit_gate_check || exit 0

    # Primed here, in the tick's own shell, so the subshells below inherit a
    # warm cache — the same reason the watch list is primed above. Failure is
    # terminal for the tick: "how many are running" has no safe default, and
    # guessing "none" would lift the concurrency cap exactly when herdr is
    # unhealthy (issue #1453, Error Cases).
    if ! _iw_live_agents >/dev/null; then
        ux_warning "Cannot list herdr agents — holding this tick rather than dispatching blind."
        exit 0
    fi

    # Before the concurrency check, not after: collecting finished worktrees is
    # what keeps the disk bounded, and a tick that is at its limit is exactly
    # the tick that most needs it done (D-4).
    _iw_cleanup_worktrees

    _live=$(_iw_live_count)
    if [ "${_live}" -ge "${_IW_MAX_CONCURRENT}" ]; then
        ux_info "Holding this tick — ${_live} issue session(s) already running (max ${_IW_MAX_CONCURRENT})."
        exit 0
    fi

    _candidates=$(_iw_select_candidates "$(_iw_collect_candidates)")

    if [ -z "${_candidates}" ]; then
        ux_info "No dispatchable issue this tick."
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

    # fd 3, not stdin: the loop body runs `gh`, `herdr` and `gwt`, any of which
    # may read stdin and would otherwise swallow the rest of the candidate list,
    # silently shortening the cycle (PR #1447 agy review).
    while IFS="${_IW_TAB}" read -r _repo _number _path _host <&3; do
        [ -n "${_repo}" ] || continue

        _rc=0
        _iw_process_issue "${_repo}" "${_number}" "${_path}" || _rc=$?

        if [ "${_rc}" -eq 0 ]; then
            _dispatched=$((_dispatched + 1))
            # Confirmed submitted, so this pane is a valid witness for the
            # quota — collected here, judged after the loop.
            _confirmed="${_confirmed}$(_iw_agent_name "${_repo}" "${_number}")
"
        else
            _failed=$((_failed + 1))
        fi
    done 3<<EOF
${_candidates}
EOF

    # After the cycle, not inside it: one pane holding `working` clears the
    # slate for every dispatch this tick made (issue #1444), so the verdict
    # needs all of them. Nothing inside the loop can shut the gate any more,
    # which is why the in-loop re-check that used to break out of it is gone.
    _iw_limit_record "${_confirmed}"

    if [ "${_dispatched}" -eq 0 ] && [ "${_failed}" -gt 0 ]; then
        ux_error "Tick complete — 0 dispatched, ${_failed} failed."
        exit 1
    fi

    ux_success "Tick complete — ${_dispatched} issue(s) dispatched, ${_failed} failed."
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
