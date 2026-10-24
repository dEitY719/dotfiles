#!/bin/bash
# shell-common/tools/custom/avatar_issue_watcher.sh
# issue-watcher 주기 감시 사이클 — 1회 tick (issue #1389, #1440, #1453).
#
# cron 이 주기마다 이 스크립트를 호출하면 tick 1회를 수행한다. tick 은 감시부터
# 디스패치까지를 직접 수행한다 — 판단이 필요한 지점은 마지막 한 곳,
# 디스패치된 pane 안에서 도는 `/gh-flow:wave <N>` 뿐이다 (issue #1440).
# 사용자의 수동 절차를 그대로 자동화한다:
#   1) 살아있는 per-issue 세션 수가 상한이면 이번 tick 보류
#   2) `gh search issues` 로 할당된 open 이슈를 교차 저장소 한 번에 조회
#   3) 제외 라벨 필터 + watched-repos.json 밖 저장소 제외 + 로컬 경로 매핑
#   4) repo 라운드로빈 · 이슈 번호 오름차순으로 후보 정렬
#   5) 이미 실행 중 / 이미 처리됨(이슈를 닫는 open PR) / blockedBy OPEN 스킵
#   6) tick 당 최대 _IW_DISPATCH_PER_TICK 건만, 탭을 열기 전에 이슈 worktree
#      (wt/issue-<N>/<idx>) 를 확보한다 — 있으면 재사용, 없으면 main 체크아웃에서
#      `gwt spawn --wt-name issue-<N>` (#2281). 그 worktree 를 cwd 로 herdr
#      tab(`iw-<repo>-issue-<N>`, agent 이름과 동일) + claude agent 생성
#   7) `/gh-flow:wave <N>` 프롬프트 전달 — wave 는 그 worktree 를 재사용 모드로 채택한다
# 토큰 한도 게이트가 닫혀 있으면 사이클 전체를 보류한다 (issue #1436, #1444).
#
# "실행 중" = repo 의 herdr workspace 안에 label 이 정확히 `issue-<N>`(사용자가
# 직접 연 탭) 또는 그 repo 의 `iw-<repo>-issue-<N>`(watcher 가 연 탭) 인 tab 이
# 있고 그 tab 에 agent 가 있음. 수동 탭도 인정하므로 사용자가 이미 작업 중인
# 이슈는 다시 디스패치하지 않는다. 수동 탭은 repo 를 모르므로 같은 workspace 를
# 공유하는 모든 repo 의 #N 을 막고, watcher 탭은 label 의 repo 에만 귀속된다.
#
# 정리(검토 후 /exit, `gwt teardown`, 탭 종료)는 사용자가 수동으로 한다 — tick 은
# 워크트리도 탭도 회수하지 않는다(실패한 디스패치 시도의 탭만 닫는다).
#
# repo 경로는 언제나 main 체크아웃이다 (#2281): worktree 안에서 실행하거나
# watch list 에 worktree 경로가 있어도 `--git-common-dir` 의 부모로 정규화한다.
#
# 이슈에 어떤 쓰기도 하지 않는다 — 댓글·라벨·assignee 변경 없음. 조회 전용이다.
#
# cwd 모드 (issue #2243): `--cwd` 없이 origin remote 가 있는 git 저장소 안에서
# 실행하면 watch list 파일을 읽지 않고 그 저장소 하나만 대상으로 삼는다.
# cron 은 `--cwd` 를 주거나 $HOME 에서 시작하므로 기존 watch list 동작 그대로다.
#
# 대상 지정 실행: 이슈 URL / owner/repo#N / #N / N 하나를 주면 검색 없이 그 이슈만
# 같은 가드(실행 중 탭, 열린 PR, blocker, 상한, gate, lock)를 거쳐 dispatch 한다.
#
# Usage: avatar_issue_watcher.sh [--cwd <PATH>] [--dry-run] [<issue-ref> [--force]]
#        | --status | watch list|add|remove ... | label ... | [-h|--help|help]

set -u

# Initialize common tools environment (DOTFILES_ROOT/SHELL_COMMON + ux_lib,
# under DOTFILES_TEST_MODE=1 too) and the shared cron lock (#2144).
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")/lib/cron_common.sh" && cron_bootstrap || exit 1
_IW_SHELL_COMMON="${SHELL_COMMON}"

# The herdr agent-name SSOT (#1530). Sourced at file scope rather than lazily
# because _iw_agent_name is called from both the dispatch loop and the tick's
# summary, and a tick that discovers the helper missing halfway through would
# have already opened panes it can no longer address.
if [ ! -f "${_IW_SHELL_COMMON}/lib/herdr_agent_name.sh" ]; then
    ux_error "herdr_agent_name.sh not found under ${_IW_SHELL_COMMON}/lib — cannot derive agent names."
    exit 1
fi
# shellcheck source=/dev/null
. "${_IW_SHELL_COMMON}/lib/herdr_agent_name.sh" || exit 1

# The herdr agent-lookup SSOT (#1569). This tick uses only its `agent list`
# fetcher (herdr_agent_list_json), which owns the "an empty answer is unknown,
# not nothing" rule. The running-now signal depends on it, so a tick that
# discovered it missing halfway through would have already decided what to
# dispatch on a signal it can no longer read.
if [ ! -f "${_IW_SHELL_COMMON}/lib/herdr_agent_lookup.sh" ]; then
    ux_error "herdr_agent_lookup.sh not found under ${_IW_SHELL_COMMON}/lib — cannot tell which issue sessions are live."
    exit 1
fi
# shellcheck source=/dev/null
. "${_IW_SHELL_COMMON}/lib/herdr_agent_lookup.sh" || exit 1

# herdr pane helpers shared with pr_merge_train_cron.sh (lock, settle, idle
# wait, workspace, account routing). Hard failure: without them there is no
# lock and no way to open a dispatch pane.
if [ ! -f "${_IW_SHELL_COMMON}/tools/custom/lib/herdr_pane.sh" ]; then
    ux_error "herdr_pane.sh not found under ${_IW_SHELL_COMMON}/tools/custom/lib — cannot open dispatch panes."
    exit 1
fi
# shellcheck source=/dev/null
. "${_IW_SHELL_COMMON}/tools/custom/lib/herdr_pane.sh" || exit 1

# Candidate-selection ops (#2157): dotfiles_tools.issue_watcher.select via cron_py.
# The legacy jq/awk rollback path was removed after one release (#2173).
_iw_sel() { cron_py dotfiles_tools.issue_watcher.select "$@"; }

# ============================================================
# Constants (SSOT for the watch cycle)
# ============================================================

_IW_STATE_SUBDIR="avatar-issue-watcher"
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
# outside it is ignored) plus the repo -> local checkout map the tab step
# needs (the tab opens on that path). Overridable so the bats suite can point at a fixture.
_IW_REPOS_FILE_DEFAULT="${HOME:-/nonexistent}/.avatars/issue-watcher/watched-repos.json"

# Labels that park an issue. Exact matches, not substrings. The default set;
# $IW_EXCLUDE_LABELS (comma-separated) and then the excluded-labels.json file
# next to the watch list replace it — see _iw_exclude_labels_resolve.
_IW_EXCLUDE_LABELS_DEFAULT="wontfix,not-implement,TODO,manual"

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
# (a leftover per-issue marker blocked re-dispatch), so dropping that marker
# and capping concurrency had to land together.
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

_IW_MAX_PER_REPO=$(_iw_cap "${IW_MAX_PER_REPO-}" 3 IW_MAX_PER_REPO)
_IW_MAX_CONCURRENT=$(_iw_cap "${IW_MAX_CONCURRENT-}" 5 IW_MAX_CONCURRENT)
_IW_DISPATCH_PER_TICK=$(_iw_cap "${IW_DISPATCH_PER_TICK-}" 1 IW_DISPATCH_PER_TICK)
# How long a pane has to keep looking stopped before the tick believes it.
# A single tick sees one snapshot, and in that snapshot a finished session and
# one that merely delegated to a background subagent are indistinguishable —
# both report `idle`/`done` (PR #1597 codex/agy review). Ten minutes covers a
# couple of ticks (cron runs every ~3 minutes) plus a typical delegation, which
# runs for minutes rather than the milliseconds between two tool calls.
_IW_ZOMBIE_GRACE_SECONDS=$(_iw_cap "${IW_ZOMBIE_GRACE_SECONDS-}" 600 IW_ZOMBIE_GRACE_SECONDS)
# Saturation alert (issue #1606). How many consecutive ticks may skip dispatch
# purely because the caps above are full before the watcher says so out loud,
# and how long it then stays quiet about a state that has not changed.
#
# The slots have stood full overnight twice, for two unrelated reasons
# (#1596/#1597 zombie tabs nobody closed, #1604 a quota backoff nobody resumed),
# and both times the only alarm was a human asking the next morning. So the
# alert is deliberately cause-blind: it counts ticks and nothing else. Working
# out *why* would need the pane-text matching #1444 rejected for the rate-limit
# gate, and a cause the watcher has not been taught is exactly the one that will
# cost the next night.
#
# 20 ticks is roughly an hour at the shipped */3 cron period — long enough that
# a healthy burst (every slot busy, dispatches landing again a few ticks later)
# never trips it, short enough that a night is not lost. The 3h cooldown is the
# same trade one level up: a saturation nobody has cleared is worth repeating,
# but not once an hour.
_IW_SATURATION_ALERT_TICKS=$(_iw_cap "${IW_SATURATION_ALERT_TICKS-}" 20 IW_SATURATION_ALERT_TICKS)
_IW_SATURATION_COOLDOWN_SECONDS=$(_iw_cap "${IW_SATURATION_COOLDOWN_SECONDS-}" 10800 IW_SATURATION_COOLDOWN_SECONDS)
# Attempts per issue before giving up on it for this cycle. Every failed
# attempt closes its own tab first, so a retry starts from scratch.
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

# Upper bound on the settle wait between `agent start` and the first prompt
# (issue #1560; a poll rather than a flat sleep since #1570). `agent_status`
# cannot end this wait: `idle` means "not working", not "accepting keystrokes",
# and a freshly drawn claude TUI is idle while its key-input loop is still
# unattached — which is also why raising _IW_IDLE_POLL_MAX is a no-op.
#
# What the pane *does* expose is its own text. `herdr agent read` shows a blank
# or half-drawn frame — or `Not logged in` — while claude is coming up, and
# settles on a steady frame once it is listening, so the dispatcher polls that
# instead of guessing (see _iw_settle). This value is the poll's cap, not its
# duration: a healthy pane leaves in ~1-2s and only one that never stabilises
# spends the whole budget, after which it is warned about and prompted anyway.
# Measured on herdr 0.7.5: prompting ~5s after start returns
# `agent_prompt_stalled` every time, ~13s lands — so 13 stays the cap.
#
# Applied on the fresh-launch path only — a warm session takes a prompt at
# once and must not pay this. Overridable (to 0) for the same reason
# _IW_IDLE_POLL_SLEEP is: the bats suite must not sleep 13 real seconds per
# dispatch test.
#
# 13 is the repo-wide constant for "herdr just brought something up, wait
# before touching it" (#1571). Its four twins are _IW_START_RETRY_SLEEP below,
# _PMT_SETTLE_SECONDS / _PMT_START_RETRY_SLEEP in pr_merge_train_cron.sh, and
# PMV_SETTLE_SECONDS in dEitY719/gh-verify-skills
# skills/post-merge-verify/references/dispatch.sh.md (#1659 moved it out of
# this repo; the old claude/skills/ path is gone). Change one,
# change all five — #1530/#1549 and #1560/#1571 are both the same defect
# recurring because only two of the three dispatchers were fixed. The *number*
# is what those five share; since #1570 the two settle constants spend it as a
# poll cap while the three start-retry gaps are still flat sleeps, because only
# a settle has a pane to read.
_IW_SETTLE_SECONDS="${IW_SETTLE_SECONDS:-13}"
# Gap between settle polls, and how many pane lines each poll reads. The gap is
# overridable (to 0) for the same reason _IW_IDLE_POLL_SLEEP is.
#
# 15, not 3 (PR #1611 review, live herdr 0.7.5 test): a real claude TUI's
# bottom `--lines N` window is `[status/banner line] [divider] [input line]
# [divider] [footer status bar]` — 3 lines captures only the footer, which
# renders and stabilises immediately and never contains the banner or input
# row at all. `_IW_SETTLE_NOT_READY_MARK` below could never actually match a
# real "Not logged in" pane with a 3-line window; it was checking a footer
# that looks the same whether the pane is broken or fine. 15 comfortably
# covers that whole block plus a wrapped multi-line status bar. The 40-line
# read is still _iw_limit_evidence's own, larger, different-purpose call —
# reading that wide here would make two frames differ over scrolling
# conversation history that has nothing to do with readiness.
_IW_SETTLE_POLL_SLEEP="${IW_SETTLE_POLL_SLEEP:-1}"
_IW_SETTLE_READ_LINES="15"
# The pane text herdr shows while claude is up but unusable (#1561). Stable
# across reads, so the "frames agree" test alone would take it for ready —
# and a bare state_change_seq comparison could not tell it apart at all.
_IW_SETTLE_NOT_READY_MARK="Not logged in"

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
# and builds a new, equally cold tab — three tries at the
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
# dEitY719/gh-verify-skills skills/post-merge-verify/references/dispatch.sh.md;
# all five move together. The wait and this retry are complements, not
# substitutes — 13s shrinks the race, the retry survives what is left of it.
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
# The zombie grace clock's backing file, alongside the gate state above. TSV
# rather than JSON because its records are per-item (<repo> <number> <epoch>)
# and every tick mutates one row of many — the shape the awk joins already
# speak, and one this script can rewrite atomically
# without a JSON primitive it does not have.
_IW_ZOMBIE_CANDIDATES_BASENAME="zombie-candidates.tsv"
# The issues a rate-limit strike killed, alongside the gate state above
# (issue #1604). Same TSV-and-atomic-rewrite discipline as the zombie clock, for
# the same reasons — per-item records, one row mutated per tick, and no JSON
# primitive this script owns.
#
# One column wider than its neighbour: `<repo> <number> <booked-epoch>
# <attempts>`. The retry budget is an attribute of the casualty, not a record of
# its own, so a second file keyed by the same pair would buy nothing and cost
# two rewrites per retry plus a whole new class of "row here, missing there"
# states — in a mechanism whose entire job is to stop losing issues. A fourth
# awk column is the cheaper half of that trade. A row missing the field reads as
# zero attempts, so a state directory written before it existed still parses.
_IW_LIMIT_CASUALTIES_BASENAME="rate-limit-casualties.tsv"
# The saturation counter's backing file (issue #1606). JSON like the gate's, not
# TSV like the zombie clock's: it holds two scalars for the watcher as a whole,
# not one row per item, and a human resetting an episode by hand reads it the
# same way they already read rate-limit.json.
_IW_SATURATION_STATE_BASENAME="saturation.json"
_IW_LIMIT_STRIKES="2"
_IW_LIMIT_BACKOFF_SECONDS="1800"
# How long a *confirmed* dispatch has to hold `working` before the tick accepts
# it as proof the quota is intact (issue #1444). One `/gh-flow:wave` runs for
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
_IW_PROMPT_KEEP_ATTEMPT=0
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
# Set by an issue-reference run: one named issue, so it has taken no repo's
# round-robin turn and the cursor stays where the last real tick left it.
_IW_TARGETED=0
# Set by _iw_limit_gate_check when it clears an expired backoff, and read once
# by main() (issue #1604). The casualty retry is a gate-reopen event, not a
# per-tick one: a tick that finds the gate simply `open` has already done its
# retrying on the reopen that preceded it.
_IW_LIMIT_GATE_REOPENED=0
# 1 once _iw_ensure_config_dir has run. Distinct from _IW_CONFIG_DIR being
# non-empty, because "HOME is unset" resolves to a legitimately empty value.
_IW_CONFIG_DIR_RESOLVED=0
# The slash command a pane runs for one issue — `/gh-flow:wave` or an Agent
# Factory flat copy such as `/issue-af01` (issue #2209). Resolved once per tick
# by _iw_ensure_flow_command: 0 = not yet asked, 1 = resolved, 2 = failed.
_IW_FLOW_COMMAND=""
_IW_FLOW_RESOLVED=0

# ============================================================
# Helpers — state paths and JSON
# ============================================================

# State dir for this dispatcher (lib/herdr_pane.sh _hp_state_dir).
_iw_state_dir() {
    _hp_state_dir "${_IW_STATE_SUBDIR}"
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
# cwd mode (#2243): the one `<owner/repo>\t<path>\t<host>` line main() derived
# from the current checkout. Non-empty replaces the watch-list file entirely.
_IW_CWD_ENTRY=""

# Emit `<owner/repo><TAB><local-path><TAB><host>` per watched entry.
#
# Two accepted shapes, because the file is a personal SSOT this repo does not
# own and cannot migrate: a bare array, or an object with a `repos` array.
# Entries are `{ "repo": "owner/name", "path": "/local/checkout",
# "host": "github.com" }`; `host` is optional and defaults to github.com.
# An entry with no usable repo or path is dropped — a repo the tick cannot
# place on disk has nowhere to open a tab.
_iw_watch_list() {
    local _file

    if [ "${_IW_WATCH_LIST_LOADED}" -eq 1 ]; then
        [ -z "${_IW_WATCH_LIST}" ] || printf '%s\n' "${_IW_WATCH_LIST}"
        return 0
    fi

    _IW_WATCH_LIST_LOADED=1
    if [ -n "${_IW_CWD_ENTRY}" ]; then
        _IW_WATCH_LIST="${_IW_CWD_ENTRY}"
        printf '%s\n' "${_IW_WATCH_LIST}"
        return 0
    fi

    _file=$(_iw_repos_file)
    [ -f "${_file}" ] || return 0

    _IW_WATCH_LIST=$(jq -r '
        (if type == "array" then . else (.repos // []) end)
        | .[]?
        | select(type == "object")
        | select((.repo // "") != "" and (.path // "") != "")
        | [ .repo, .path, (.host // "github.com") ]
        | @tsv
    ' "${_file}" 2>/dev/null | while IFS="${_IW_TAB}" read -r _repo _path _host; do
        # A list written before #2281 may name a worktree: every tick consumer
        # (workspace label, dispatch) works from its main checkout instead.
        _main=$(_iw_main_checkout "${_path}") && _path="${_main}"
        printf '%s\t%s\t%s\n' "${_repo}" "${_path}" "${_host}"
    done)

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

# Print `<owner/repo>\t<host>` for a git remote URL (#2243). Accepts the https
# form (`https://[user@]host[:port]/owner/repo[.git]`), `ssh://[user@]host[:port]/
# owner/repo[.git]` and scp-like `user@host:owner/repo[.git]` — GHES hosts
# included. Exit 1 on anything else (a local path, a nested group path).
_iw_parse_remote_url() {
    local _u="$1" _rest _host _slug
    case "${_u}" in
    *://*)
        _rest="${_u#*://}"
        _host="${_rest%%/*}"
        _host="${_host#*@}"
        _slug="${_rest#*/}"
        [ "${_slug}" != "${_rest}" ] || return 1
        ;;
    *@*:*)
        _rest="${_u#*@}"
        _host="${_rest%%:*}"
        _slug="${_rest#*:}"
        ;;
    *) return 1 ;;
    esac
    _host="${_host%%:*}"
    # An ssh host may be a ~/.ssh/config alias (`git@gh-work:acme/repo`, the
    # multi-account setup); `ssh -G` resolves it offline to the real HostName.
    case "${_u}" in
    http://* | https://*) ;;
    *)
        # A leading `-` would be parsed by ssh as an option, not a host.
        if [ -n "${_host}" ] && [ "${_host#-}" = "${_host}" ] && command -v ssh >/dev/null 2>&1; then
            _rest=$(ssh -G "${_host}" 2>/dev/null | awk '$1 == "hostname" { print $2; exit }')
            [ -z "${_rest}" ] || _host="${_rest}"
        fi
        # GitHub's port-443 ssh endpoint; gh's API host stays github.com (#2247).
        # shortcut: only this one GitHub endpoint is mapped; a GHES / GHE.com
        # port-443 ssh host still needs `watch add --host`, generalize if one appears.
        [ "${_host}" != "ssh.github.com" ] || _host="github.com"
        ;;
    esac
    _slug="${_slug%/}"
    _slug="${_slug%.git}"
    case "${_slug}" in
    */*/* | /* | */ | .*) return 1 ;;
    ?*/?*) ;;
    *) return 1 ;;
    esac
    [ -n "${_host}" ] || return 1
    printf '%s\t%s' "${_slug}" "${_host}"
}

# Echo the main checkout of the git checkout at <path> (#2281): a linked
# worktree resolves to the checkout that owns it, so a watcher started inside
# a worktree still records and dispatches from the main checkout (otherwise
# the session starts in the wrong worktree and wave stops on `not on <base>`).
# Exit 1 when <path> is not inside a git checkout.
_iw_main_checkout() {
    local _common
    # cd + `pwd -P`, not `rev-parse --path-format=absolute` (git >= 2.31 only).
    _common=$(cd "$1" 2>/dev/null && _c=$(git rev-parse --git-common-dir 2>/dev/null) &&
        cd "${_c}" && pwd -P) || return 1
    case "${_common}" in
    */.git) dirname "${_common}" ;;
    # A submodule's common dir is not `<checkout>/.git`; keep its toplevel.
    *) git -C "$1" rev-parse --show-toplevel 2>/dev/null ;;
    esac
}

# Print `<owner/repo>\t<main checkout>\t<host>` for the git checkout at the
# current directory (#2243, #2281). Exit 1 when it is not a git repo or has no
# `origin` (cwd mode does not apply), 2 when `origin` exists but cannot be parsed.
_iw_cwd_entry() {
    local _top _url _parsed
    _top=$(_iw_main_checkout .) || return 1
    [ -n "${_top}" ] || return 1
    _url=$(git remote get-url origin 2>/dev/null) || return 1
    [ -n "${_url}" ] || return 1
    _parsed=$(_iw_parse_remote_url "${_url}") || {
        # Echoed in an error message: drop any `user:token@` credentials.
        printf '%s' "${_url}" | sed 's#://[^/@]*@#://#'
        return 2
    }
    printf '%s\t%s\t%s' "${_parsed%%"${_IW_TAB}"*}" "${_top}" "${_parsed#*"${_IW_TAB}"}"
}

# Print `<host>\t<owner/repo>\t<number>` for an issue reference — the full
# `https://<host>/<owner>/<repo>/issues/<N>` URL (trailing slash, ?query and
# #fragment ignored), `<owner>/<repo>#<N>`, `#<N>` or a bare `<N>`. Host and
# repo are empty when the reference does not name them. Exit 1 on anything else.
_iw_parse_issue_ref() {
    local _r="$1" _host="" _repo="" _num _rest
    case "${_r}" in
    http://* | https://*)
        _rest="${_r#*://}"
        _rest="${_rest%%\#*}"
        _rest="${_rest%%\?*}"
        _rest="${_rest%/}"
        _host="${_rest%%/*}"
        _host="${_host##*@}"
        _host="${_host%%:*}"
        [ -n "${_host}" ] || return 1
        _rest="${_rest#*/}"
        _num="${_rest##*/}"
        _rest="${_rest%/*}"
        [ "${_rest##*/}" = "issues" ] || return 1
        _repo="${_rest%/issues}"
        [ -n "${_repo}" ] || return 1
        ;;
    */*\#*)
        _repo="${_r%%\#*}"
        _num="${_r#*\#}"
        ;;
    \#*) _num="${_r#\#}" ;;
    *) _num="${_r}" ;;
    esac
    case "${_num}" in
    '' | 0* | *[!0-9]*) return 1 ;;
    esac
    if [ -n "${_repo}" ]; then
        case "${_repo}" in
        */*/* | .* | */.* | *[!A-Za-z0-9._/-]*) return 1 ;;
        ?*/?*) ;;
        *) return 1 ;;
        esac
    fi
    case "${_host}" in
    *[!A-Za-z0-9.-]*) return 1 ;;
    esac
    printf '%s\t%s\t%s' "${_host}" "${_repo}" "${_num}"
}

# ============================================================
# `watch` subcommand — manage the watch-list file (#2243)
# ============================================================

_iw_watch_usage() {
    ux_info "Usage: avatar_issue_watcher.sh watch list"
    ux_info "       avatar_issue_watcher.sh watch add [owner/repo] [--path P] [--host H]"
    ux_info "       avatar_issue_watcher.sh watch remove [owner/repo]"
    ux_bullet_sub "owner/repo omitted: the current checkout's origin"
    ux_bullet_sub "file: $(_iw_repos_file)"
}

# Exit 1 unless <file> holds a bare array or an object whose `repos` is an
# array (or absent) — the two shapes _iw_watch_list reads.
_iw_watch_validate() {
    jq -e 'type == "array" or (type == "object" and ((.repos // []) | type) == "array")' \
        "$1" >/dev/null 2>&1
}

# Apply jq filter <2> (with the remaining jq args) to <1> and replace it:
# backup first, then a temp file swapped in with mv so a failed write never
# leaves a half-written watch list.
_iw_watch_write() {
    local _file="$1" _filter="$2" _tmp _dir _bak
    shift 2
    # A symlinked watch list (e.g. into a dotfiles repo) is edited at its
    # target: the mv below would otherwise replace the link with a plain file.
    if [ -L "${_file}" ]; then
        _file=$(readlink -f "${_file}") || return 1
    fi
    _dir=$(dirname "${_file}")
    mkdir -p "${_dir}" || return 1
    # No-clobber: a second edit the same day must not overwrite the pre-edit copy.
    _bak="${_file}.bak-$(date +%Y%m%d)"
    if [ -f "${_file}" ] && [ ! -e "${_bak}" ]; then
        cp -p "${_file}" "${_bak}" || return 1
    fi
    _tmp=$(mktemp "${_file}.tmp.XXXXXX") || return 1
    if [ -f "${_file}" ]; then
        jq "$@" "${_filter}" "${_file}" >"${_tmp}"
    else
        printf '[]' | jq "$@" "${_filter}" >"${_tmp}"
    fi || {
        rm -f "${_tmp}"
        return 1
    }
    mv "${_tmp}" "${_file}"
}

# The repo list of either shape, as a bare array.
_IW_WATCH_JQ_DEFS='def entries: if type == "array" then . else (.repos // []) end;
def put(f): if type == "array" then f else .repos = ((.repos // []) | f) end;'

_iw_watch_list_cmd() {
    local _file _rows _line
    _file=$(_iw_repos_file)
    if [ ! -f "${_file}" ]; then
        ux_info "Watch list not found: ${_file}"
        ux_bullet_sub "create it with: avatar-issue-watcher watch add"
        return 0
    fi
    if ! _iw_watch_validate "${_file}"; then
        ux_error "Watch list is not valid JSON (array or {\"repos\": [...]}): ${_file}"
        return 1
    fi
    ux_header "watch list"
    ux_info "${_file}"
    # Formatted by jq: splitting a tab row with `read` collapses an empty path.
    _rows=$(jq -r "${_IW_WATCH_JQ_DEFS}"'
        entries | .[]? | select(type == "object")
        | (if (.path // "") == "" then "no path" else .path end) as $p
        | "\(.repo // "")  (\($p), \(.host // "github.com"))"' "${_file}")
    if [ -z "${_rows}" ]; then
        ux_info "(no entries)"
        return 0
    fi
    while IFS= read -r _line; do
        ux_bullet "${_line}"
    done <<EOF
${_rows}
EOF
}

# watch add/remove: resolve the target repo — the argument, or the current
# checkout's origin. Sets _IW_W_REPO, and _IW_W_PATH/_IW_W_HOST when the current
# checkout is that repo (empty otherwise).
_iw_watch_target() {
    local _arg="$1" _entry _rc=0
    _IW_W_REPO="${_arg}"
    _IW_W_PATH=""
    _IW_W_HOST=""
    _entry=$(_iw_cwd_entry) || _rc=$?
    if [ "${_rc}" -eq 0 ]; then
        if [ -z "${_arg}" ] || [ "${_arg}" = "${_entry%%"${_IW_TAB}"*}" ]; then
            _IW_W_REPO="${_entry%%"${_IW_TAB}"*}"
            _entry="${_entry#*"${_IW_TAB}"}"
            _IW_W_PATH="${_entry%%"${_IW_TAB}"*}"
            _IW_W_HOST="${_entry#*"${_IW_TAB}"}"
        fi
    fi
    if [ -z "${_IW_W_REPO}" ]; then
        if [ "${_rc}" -eq 2 ]; then
            ux_error "Cannot read owner/repo from origin URL: ${_entry}"
        else
            ux_error "No owner/repo given and the current directory is not a git checkout with an origin remote."
        fi
        _iw_watch_usage
        return 1
    fi
    case "${_IW_W_REPO}" in
    */*/* | /* | */) ;;
    ?*/?*) return 0 ;;
    esac
    ux_error "Not an owner/repo: ${_IW_W_REPO}"
    return 1
}

_iw_watch_add_cmd() {
    local _file _arg="" _path="" _host="" _old _old_path _old_host _verb _main
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --path | --host)
            if [ "$#" -lt 2 ]; then
                ux_error "$1 requires a value."
                return 1
            fi
            case "$1" in
            --path) _path="$2" ;;
            *) _host="$2" ;;
            esac
            shift 2
            ;;
        -*)
            ux_error "Unknown option: $1"
            _iw_watch_usage
            return 1
            ;;
        *)
            if [ -n "${_arg}" ]; then
                ux_error "Unexpected argument: $1"
                return 1
            fi
            _arg="$1"
            shift
            ;;
        esac
    done
    _iw_watch_target "${_arg}" || return 1

    _file=$(_iw_repos_file)
    if [ -f "${_file}" ] && ! _iw_watch_validate "${_file}"; then
        ux_error "Watch list is not valid JSON — left untouched: ${_file}"
        return 1
    fi
    # One read of the listed entry as `<path>\t<host>`; empty when not listed.
    _old=""
    if [ -f "${_file}" ]; then
        _old=$(jq -r --arg r "${_IW_W_REPO}" "${_IW_WATCH_JQ_DEFS}"'
            [entries | .[]? | select(type == "object" and .repo == $r)] | first // empty
            | "\(.path // "")\t\(.host // "")"' "${_file}")
    fi
    _old_path=""
    _old_host=""
    _verb="Added"
    if [ -n "${_old}" ]; then
        _old_path="${_old%%"${_IW_TAB}"*}"
        _old_host="${_old#*"${_IW_TAB}"}"
        _verb="Updated"
    fi

    # An existing directory is stored absolute: the tick may run from anywhere.
    # A worktree path is stored as its main checkout (#2281).
    if [ -n "${_path}" ] && [ -d "${_path}" ]; then
        _path=$(cd "${_path}" && pwd -P)
        _main=$(_iw_main_checkout "${_path}") && _path="${_main}"
    fi
    # Explicit flags win; a listed entry keeps its values over the cwd-derived
    # ones, so `watch add` from a temporary worktree cannot repoint it there.
    _path="${_path:-${_old_path:-${_IW_W_PATH}}}"
    _host="${_host:-${_old_host:-${_IW_W_HOST:-github.com}}}"
    if [ -z "${_path}" ]; then
        ux_error "No local path for ${_IW_W_REPO} — pass --path, or run from its checkout."
        return 1
    fi

    # shellcheck disable=SC2016 # jq variables, not shell ones
    if ! _iw_watch_write "${_file}" "${_IW_WATCH_JQ_DEFS}"'
        put(if any(.[]?; type == "object" and .repo == $r)
            then map(if type == "object" and .repo == $r then .path = $p | .host = $h else . end)
            else . + [{repo: $r, path: $p, host: $h}] end)' \
        --arg r "${_IW_W_REPO}" --arg p "${_path}" --arg h "${_host}"; then
        ux_error "Could not write ${_file}."
        return 1
    fi
    ux_success "${_verb} ${_IW_W_REPO} (${_path}, ${_host}) in ${_file}"
}

_iw_watch_remove_cmd() {
    local _file
    if [ "$#" -gt 1 ]; then
        ux_error "Unexpected argument: $2"
        _iw_watch_usage
        return 1
    fi
    _iw_watch_target "${1-}" || return 1
    _file=$(_iw_repos_file)
    if [ ! -f "${_file}" ]; then
        ux_error "Watch list not found: ${_file}"
        return 1
    fi
    if ! _iw_watch_validate "${_file}"; then
        ux_error "Watch list is not valid JSON — left untouched: ${_file}"
        return 1
    fi
    if ! jq -e --arg r "${_IW_W_REPO}" "${_IW_WATCH_JQ_DEFS}"'
        any(entries | .[]?; type == "object" and .repo == $r)' "${_file}" >/dev/null; then
        ux_error "${_IW_W_REPO} is not in the watch list: ${_file}"
        return 1
    fi
    # shellcheck disable=SC2016 # jq variables, not shell ones
    if ! _iw_watch_write "${_file}" "${_IW_WATCH_JQ_DEFS}"'
        put(map(select((type == "object" and .repo == $r) | not)))' --arg r "${_IW_W_REPO}"; then
        ux_error "Could not write ${_file}."
        return 1
    fi
    ux_success "Removed ${_IW_W_REPO} from ${_file}"
}

# Entry point for `watch ...`. Runs ahead of the gh/herdr checks: it only edits
# a local file, so it must work where a tick cannot.
_iw_watch_cmd() {
    if ! command -v jq >/dev/null 2>&1; then
        ux_error "jq not found in PATH — cannot read or write the watch list."
        return 1
    fi
    case "${1-}" in
    list)
        _iw_watch_list_cmd
        ;;
    add)
        shift
        _iw_watch_add_cmd "$@"
        ;;
    remove)
        shift
        _iw_watch_remove_cmd "$@"
        ;;
    -h | --help | help)
        _iw_watch_usage
        ;;
    *)
        ux_error "Unknown watch command: ${1-}"
        _iw_watch_usage
        return 1
        ;;
    esac
}

# ============================================================
# `label` subcommand — manage the excluded-labels file
# ============================================================

# A bare JSON array of label strings, next to the watch list by default.
_iw_exclude_labels_file() {
    if [ -n "${IW_EXCLUDE_LABELS_FILE:-}" ]; then
        printf '%s' "${IW_EXCLUDE_LABELS_FILE}"
        return 0
    fi
    printf '%s/excluded-labels.json' "$(dirname "$(_iw_repos_file)")"
}

# Print <file>'s labels US-joined; exit 1 unless it holds a JSON array of strings.
_iw_exclude_labels_read() {
    jq -er 'if type == "array" and all(.[]; type == "string") then join("\u001f") else error end' "$1" 2>/dev/null
}

# A comma-separated label list ($IW_EXCLUDE_LABELS, the default), US-joined.
_iw_csv_to_us() {
    printf '%s' "$1" | tr ',' '\037'
}

# Resolve the effective exclude set once per process: $IW_EXCLUDE_LABELS >
# the file > the default. Sets _IW_EXCL_SET (US-joined — US because a label
# may hold a space) and _IW_EXCL_SOURCE (env|file|default). Diagnostics go to
# stderr: the tick calls this while its stdout is the candidate list.
_IW_EXCL_SET=""
_IW_EXCL_SOURCE=""
_iw_exclude_labels_resolve() {
    local _file
    [ -z "${_IW_EXCL_SOURCE}" ] || return 0
    if [ -n "${IW_EXCLUDE_LABELS:-}" ]; then
        _IW_EXCL_SOURCE="env"
        _IW_EXCL_SET=$(_iw_csv_to_us "${IW_EXCLUDE_LABELS}")
        return 0
    fi
    _file=$(_iw_exclude_labels_file)
    if [ -f "${_file}" ]; then
        if _IW_EXCL_SET=$(_iw_exclude_labels_read "${_file}"); then
            _IW_EXCL_SOURCE="file"
            return 0
        fi
        # The default set still parks the usual labels; holding every tick
        # over a typo in a convenience file would be the bigger loss.
        ux_warning "Excluded-labels file is not a JSON array of strings — using the default set: ${_file}" >&2
    fi
    _IW_EXCL_SOURCE="default"
    _IW_EXCL_SET=$(_iw_csv_to_us "${_IW_EXCLUDE_LABELS_DEFAULT}")
}

_iw_label_usage() {
    ux_info "Usage: avatar_issue_watcher.sh label list"
    ux_info "       avatar_issue_watcher.sh label add <label>..."
    ux_info "       avatar_issue_watcher.sh label remove <label>..."
    ux_bullet_sub "precedence: \$IW_EXCLUDE_LABELS > file > default (${_IW_EXCLUDE_LABELS_DEFAULT})"
    ux_bullet_sub "file: $(_iw_exclude_labels_file)"
}

_iw_label_list_cmd() {
    local _label _oldifs _file
    _file=$(_iw_exclude_labels_file)
    # Its own warning is replaced by the error below.
    _iw_exclude_labels_resolve 2>/dev/null
    # A default source with a file present means the file did not parse.
    if [ "${_IW_EXCL_SOURCE}" = "default" ] && [ -f "${_file}" ]; then
        ux_error "Excluded-labels file is not a JSON array of strings (the tick falls back to the default): ${_file}"
        return 1
    fi
    ux_header "excluded labels"
    case "${_IW_EXCL_SOURCE}" in
    env) ux_info "source: env (\$IW_EXCLUDE_LABELS)" ;;
    file) ux_info "source: file (${_file})" ;;
    *) ux_info "source: default (no file at ${_file})" ;;
    esac
    if [ -z "${_IW_EXCL_SET}" ]; then
        ux_info "(none)"
        return 0
    fi
    _oldifs="$IFS"
    IFS="${_IW_US}"
    set -f # a label such as '*' must not glob against the cwd
    # shellcheck disable=SC2086 # split on US: the set is a list
    set -- ${_IW_EXCL_SET}
    set +f
    IFS="$_oldifs"
    for _label in "$@"; do
        [ -z "${_label}" ] || ux_bullet "${_label}"
    done
}

# label add/remove: validate the arguments and the file, then set _IW_L_FILE
# and _IW_L_CUR (the current list US-joined — the file, or the default seed
# when the file is absent).
_iw_label_prepare() {
    local _verb="$1" _label
    shift
    if [ "$#" -eq 0 ]; then
        ux_error "label ${_verb} needs at least one label."
        _iw_label_usage
        return 1
    fi
    for _label in "$@"; do
        case "${_label}" in
        "" | *,* | *"${_IW_TAB}"* | *"${_IW_US}"* | *"
"*)
            ux_error "Invalid label (empty, or holds a comma, TAB, newline or US): '${_label}'"
            return 1
            ;;
        esac
    done
    _IW_L_FILE=$(_iw_exclude_labels_file)
    if [ -f "${_IW_L_FILE}" ]; then
        if ! _IW_L_CUR=$(_iw_exclude_labels_read "${_IW_L_FILE}"); then
            ux_error "Excluded-labels file is not a JSON array of strings — left untouched: ${_IW_L_FILE}"
            return 1
        fi
    else
        _IW_L_CUR=$(_iw_csv_to_us "${_IW_EXCLUDE_LABELS_DEFAULT}")
    fi
    if [ -n "${IW_EXCLUDE_LABELS:-}" ]; then
        ux_warning "\$IW_EXCLUDE_LABELS is set and overrides the file until it is unset."
    fi
}

# Write jq filter <1> as the label file via _iw_watch_write (backup, atomic
# swap), with _IW_L_CUR bound as $cur and the labels as $l.
_iw_label_write() {
    local _filter="$1" _cur _new
    shift
    _cur=$(printf '%s' "${_IW_L_CUR}" | jq -Rsc 'split("\u001f")') || return 1
    _new=$(printf '%s\n' "$@" | jq -Rsc 'split("\n") | map(select(. != ""))') || return 1
    _iw_watch_write "${_IW_L_FILE}" "${_filter}" --argjson cur "${_cur}" --argjson l "${_new}"
}

_iw_label_add_cmd() {
    local _label _added="" _sep=""
    _iw_label_prepare add "$@" || return 1
    for _label in "$@"; do
        case "${_IW_US}${_IW_L_CUR}${_IW_US}" in
        *"${_IW_US}${_label}${_IW_US}"*)
            ux_info "Already excluded: ${_label}"
            continue
            ;;
        esac
        _IW_L_CUR="${_IW_L_CUR:+${_IW_L_CUR}${_IW_US}}${_label}"
        _added="${_added}${_sep}${_label}"
        _sep=", "
    done
    [ -n "${_added}" ] || return 0
    # shellcheck disable=SC2016 # a jq variable, bound by _iw_label_write
    if ! _iw_label_write '$cur' "$@"; then
        ux_error "Could not write ${_IW_L_FILE}."
        return 1
    fi
    ux_success "Excluded ${_added} in ${_IW_L_FILE}"
}

_iw_label_remove_cmd() {
    local _label _removed="" _sep=""
    _iw_label_prepare remove "$@" || return 1
    for _label in "$@"; do
        case "${_IW_US}${_IW_L_CUR}${_IW_US}" in
        *"${_IW_US}${_label}${_IW_US}"*)
            _removed="${_removed}${_sep}${_label}"
            _sep=", "
            ;;
        *) ux_warning "Not in the exclude list: ${_label}" ;;
        esac
    done
    [ -n "${_removed}" ] || return 0
    # shellcheck disable=SC2016 # jq variables, bound by _iw_label_write
    if ! _iw_label_write '$cur - $l' "$@"; then
        ux_error "Could not write ${_IW_L_FILE}."
        return 1
    fi
    ux_success "Removed ${_removed} from ${_IW_L_FILE}"
}

# Entry point for `label ...`. Like `watch`, a local-file edit that runs ahead
# of the gh/herdr checks.
_iw_label_cmd() {
    if ! command -v jq >/dev/null 2>&1; then
        ux_error "jq not found in PATH — cannot read or write the excluded-labels file."
        return 1
    fi
    case "${1-}" in
    list)
        _iw_label_list_cmd
        ;;
    add)
        shift
        _iw_label_add_cmd "$@"
        ;;
    remove)
        shift
        _iw_label_remove_cmd "$@"
        ;;
    -h | --help | help)
        _iw_label_usage
        ;;
    *)
        ux_error "Unknown label command: ${1-}"
        _iw_label_usage
        return 1
        ;;
    esac
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
# The questions now get separate signals, and the tick keys on no worktree at
# all — the tick prepares (or reuses) `wt/issue-<n>/<idx>` before the tab
# opens (#2281), and the user removes it after reviewing the result:
#
#   running now  -> an `issue-<N>` or `iw-<repo>-issue-<N>` herdr tab with an
#                   agent in it, inside the repo's workspace
#   handled      -> GitHub: an open PR that closes the issue
#   collectable  -> nothing; closing tabs and removing worktrees is manual
#
# Why not join agent cwd against the issue worktree: a hand-opened
# `issue-<N>` tab may stand anywhere, and the tab label already names the
# issue, so the label stays the one signal.

# Parsed once per tick, like the watch list: every cap check consults it and
# the herdr round trips must not be paid per candidate. main() primes it in its
# own shell so the subshells below inherit a warm cache.
_IW_LIVE_AGENTS=""
_IW_LIVE_AGENTS_LOADED=0

# Emit `<owner/repo><TAB><number>` for every issue with a live session.
# Non-zero when herdr could not be asked at all.
#
# A session is a tab inside the repo's workspace (_iw_workspace_label), with at
# least one agent whose `tab_id` is that tab, labelled exactly either
#
#   iw-<repo>-issue-<N>  opened by this tick — the label is the agent name
#                        (_iw_agent_name), so it belongs to that one repo even
#                        when several watched repos share the workspace
#   issue-<N>            opened by hand — names no repo, so it belongs to #N of
#                        every repo sharing the workspace
#
# Both count, so an issue the user is already working by hand is never
# dispatched a second time.
#
# Each row carries the tab id(s) behind it (`<repo>\t<number>\t<tab_ids>`), so
# the global count is of distinct tabs, not of rows.
#
# shortcut: a hand-made `issue-<N>` tab in a workspace several watched repos
# share (same path) cannot be told apart — it yields a row for #N of *every*
# such repo: #N of each is skipped as "already running", the tab counts once
# against each one's per-repo cap, and a stopped tab on a closed issue costs one
# `gh issue view` per sharing repo (the global count stays right: distinct tab
# ids). Name the tab after the agent (`iw-<repo>-issue-<N>`) when that bites.
#
# Volatility is fine here, unlike for "already handled": the question is what
# is running *now*, and after a reboot nothing is. The signal and the truth go
# stale together.
#
# A tab alone answers "a session was opened here", not "it is still working"
# (issue #1596). When a tab that should have been closed after a merge
# survives, every later tick reads it as running and the repo loses a
# concurrency slot permanently. So a session is dropped from the live set
# once *both* of its stop conditions hold — every agent in the tab reports a
# stopped `agent_status`, and the issue is closed on GitHub. Either alone is a
# normal mid-flight state: an agent is `idle` between two tool calls, and an
# issue is closed while its session still verifies the merge.
#
# Both together are still not enough on a single tick, though (PR #1597
# codex/agy review). An agent that delegated to a background subagent — this
# repo's own standard workflow — reports `idle` for the *minutes* it waits for
# that subagent, and one snapshot cannot tell that pause apart from a finished
# session. So the pair has to hold across two observations at least
# _IW_ZOMBIE_GRACE_SECONDS apart before the session is believed dead; the
# first sighting only starts the clock. A delegation ends and the agent goes
# back to `working`, which clears the clock, while a real zombie never moves.
_iw_live_agents() {
    local _agents _tabs _wss _map _repo _path _host _number _stopped _tids _ts _now _pfx

    if [ "${_IW_LIVE_AGENTS_LOADED}" -eq 1 ]; then
        [ -z "${_IW_LIVE_AGENTS}" ] || printf '%s\n' "${_IW_LIVE_AGENTS}"
        return 0
    fi

    # One round trip each for the whole watch list. Any of them failing or
    # answering nothing must not read as "nothing running": that would lift
    # the concurrency cap exactly when herdr is unhealthy. `agent list` goes
    # through the shared SSOT fetcher (#1569).
    _agents=$(herdr_agent_list_json) || return 1
    _tabs=$(herdr tab list 2>/dev/null) || return 1
    _wss=$(herdr workspace list 2>/dev/null) || return 1
    [ -n "${_tabs}" ] && [ -n "${_wss}" ] || return 1

    # repo -> workspace label, resolved here because the label rule needs the
    # whole watch list (_iw_workspace_label) and jq cannot call a shell function.
    # The third column is the repo's watcher-tab label minus the number: the
    # agent name for issue 0 with the 0 cut off, so the slug is the SSOT's. An
    # unnameable repo gets an empty prefix and only its hand-made tabs match.
    _map=$(_iw_watch_list | while IFS="${_IW_TAB}" read -r _repo _path _host; do
        [ -n "${_path}" ] || continue
        _pfx=$(_iw_agent_name "${_repo}" 0) && _pfx="${_pfx%0}" || _pfx=""
        printf '%s\t%s\t%s\n' "${_repo}" "$(_iw_workspace_label "${_repo}" "${_path}")" "${_pfx}"
    done)

    # Rows: `<repo>\t<number>\t<stopped>\t<tab_ids>`, one per repo+issue.
    # stopped is 1 only when every agent in every matching tab reports a status
    # known to mean "not working". An unknown status is never a stop signal —
    # the set of herdr statuses is not this script's to enumerate. tab_ids is
    # the sorted, comma-joined set of tabs behind the row.
    _IW_LIVE_AGENTS=$(printf '%s\n%s\n%s\n' "${_wss}" "${_tabs}" "${_agents}" |
        jq -rs --arg map "${_map}" '
            .[0].result.workspaces as $ws | .[1].result.tabs as $tabs
            | .[2].result.agents as $agents
            | if ([$ws, $tabs, $agents] | all(type == "array")) | not
              then error("no herdr list") else . end
            | [ $map | split("\n")[] | select(length > 0) | split("\t")
                | .[0] as $repo | .[1] as $label | (.[2] // "") as $pfx
                | [ $ws[] | select(.label == $label) | .workspace_id ] as $ids
                | $tabs[]
                | select(.workspace_id | IN($ids[]))
                | (.label // "") as $l
                # Legacy `iw-issue-<N>` (pre-repo-label tabs) is read like a
                # hand-made one, so an upgrade never double-dispatches a live tab.
                | ( if ($l | test("^(iw-)?issue-[0-9]+$")) then ($l | sub("^(iw-)?issue-"; ""))
                    elif $pfx != "" and ($l | startswith($pfx))
                         and ($l[($pfx | length):] | test("^[0-9]+$"))
                    then $l[($pfx | length):]
                    else empty end ) as $n
                | .tab_id as $tid
                | [ $agents[] | select(.tab_id == $tid) | (.agent_status // "") ] as $st
                | select($st | length > 0)
                | { repo: $repo, n: $n, tid: $tid,
                    stopped: ($st | all(. == "idle" or . == "done")) } ]
            | group_by([.repo, .n])[]
            | [ .[0].repo, .[0].n, (if all(.[]; .stopped) then "1" else "0" end),
                ([ .[].tid ] | unique | join(",")) ]
            | @tsv
        ' 2>/dev/null) || return 1

    # Schema guard: issue tabs exist in a watched workspace, agents exist, yet
    # no agent's tab_id names any listed tab. That reads as "nothing running"
    # and lifts the cap, so say so — behavior unchanged, only louder. stderr:
    # this runs inside the substitution that builds the live set.
    if printf '%s\n%s\n%s\n' "${_wss}" "${_tabs}" "${_agents}" |
        jq -es --arg map "${_map}" '
            .[0].result.workspaces as $ws | .[1].result.tabs as $tabs
            | .[2].result.agents as $agents
            | [ $map | split("\n")[] | select(length > 0) | split("\t")[1] ] as $labels
            | [ $ws[] | select(.label | IN($labels[])) | .workspace_id ] as $ids
            | ($agents | length > 0)
              and any($tabs[]; (.workspace_id | IN($ids[]))
                  and ((.label // "") | test("^(iw-([a-z0-9_-]+-)?)?issue-[0-9]+$")))
              and ([ $tabs[].tab_id ] as $tids
                  | all($agents[]; (.tab_id | IN($tids[])) | not))
        ' >/dev/null 2>&1; then
        ux_warning "herdr lists issue tabs, but no agent's tab_id names any listed tab: each issue tab matches no agent and reads as idle, lifting the concurrency cap (herdr schema change?)." >&2
    fi

    _IW_LIVE_AGENTS=$(printf '%s\n' "${_IW_LIVE_AGENTS}" |
        while IFS="${_IW_TAB}" read -r _repo _number _stopped _tids; do
            [ -n "${_repo}" ] || continue
            # The GitHub round trip is paid only for a stopped session: a
            # working one is live whatever its issue says.
            if [ "${_stopped}" = "1" ] && _iw_issue_closed "${_repo}" "${_number}"; then
                _ts=$(_iw_zombie_candidate_ts "${_repo}" "${_number}")
                _now=$(date +%s)
                if [ -n "${_ts}" ] && [ $((_now - _ts)) -ge "${_IW_ZOMBIE_GRACE_SECONDS}" ]; then
                    # Stopped on two observations a grace window apart — the
                    # one shape a mid-delegation pause cannot take.
                    _iw_zombie_candidate_clear "${_repo}" "${_number}"
                    continue
                fi
                [ -n "${_ts}" ] || _iw_zombie_candidate_mark "${_repo}" "${_number}" "${_now}"
                printf '%s\t%s\t%s\n' "${_repo}" "${_number}" "${_tids}"
                continue
            fi
            _iw_zombie_candidate_clear "${_repo}" "${_number}"
            printf '%s\t%s\t%s\n' "${_repo}" "${_number}" "${_tids}"
        done)

    _IW_LIVE_AGENTS_LOADED=1
    [ -z "${_IW_LIVE_AGENTS}" ] || printf '%s\n' "${_IW_LIVE_AGENTS}"
}

# 0 only when GitHub says <owner/repo> issue <number> is CLOSED. A failed or
# unparsable read answers "no" on purpose: the caller reclaims a concurrency
# slot on a yes, and an unanswered question must never be the reason anything
# is reclaimed.
#
# stdin is closed because `gh` reads stdin, and this runs inside a `while
# read` loop fed by a pipe, which it would otherwise swallow (PR #1447 agy
# review).
_iw_issue_closed() {
    local _state

    _state=$(GH_HOST="$(_iw_repo_host "$1")" gh issue view "$2" --repo "$1" \
        --json state -q .state </dev/null 2>/dev/null) || return 1
    [ "${_state}" = "CLOSED" ]
}

# ------------------------------------------------------------
# Zombie grace clock (PR #1597 codex/agy review)
# ------------------------------------------------------------
#
# One `<repo>\t<number>\t<first-observed-stopped-epoch>` line per pane that has
# been seen stopped-and-closed but not yet believed. Kept on disk for the same
# reason the rate-limit gate is: the question spans ticks, and a tick is a
# process that remembers nothing of the last one.
#
# Every warning below goes to stderr rather than through ux_warning's default
# stdout, because these run inside the command substitution that builds
# _IW_LIVE_AGENTS — a warning on stdout would be read back as a live agent.

_iw_zombie_candidates_file() {
    printf '%s/%s' "$(_iw_state_dir)" "${_IW_ZOMBIE_CANDIDATES_BASENAME}"
}

# Echo the epoch this repo+issue was first seen stopped, or nothing. A missing
# file, an unreadable one and an absent row are all "nothing" (NF-1) — the
# caller reads that as "first sighting" and starts the clock.
_iw_zombie_candidate_ts() {
    local _file
    _file=$(_iw_zombie_candidates_file)
    [ -f "${_file}" ] || return 0
    awk -F "${_IW_TAB}" -v r="$1" -v n="$2" \
        '$1 == r && $2 == n { print $3; exit }' "${_file}" 2>/dev/null
}

# Start the clock for <repo> <number> at <epoch> — but only if it is not
# already running. Overwriting would reset the grace window on every tick and
# no pane would ever age out, which is exactly the bug this file prevents.
#
# The rewrite also drops rows older than six grace windows: an issue collected
# through some other path leaves a row nobody will ever look up again, and a
# state file that only grows is a slow leak.
_iw_zombie_candidate_mark() {
    local _dir _file _tmp _cutoff

    [ -z "$(_iw_zombie_candidate_ts "$1" "$2")" ] || return 0

    _dir=$(_iw_state_dir)
    _file=$(_iw_zombie_candidates_file)
    if ! mkdir -p "${_dir}" 2>/dev/null; then
        ux_warning "Cannot create state directory (${_dir}) — the zombie grace clock will not survive this tick." >&2
        return 1
    fi

    # Same directory as the target on purpose: `mv` is only atomic within one
    # filesystem, so a temp file under /tmp would trade the guarantee away.
    _tmp="${_file}.$$"
    _cutoff=$(($3 - 6 * _IW_ZOMBIE_GRACE_SECONDS))
    if {
        [ ! -f "${_file}" ] ||
            awk -F "${_IW_TAB}" -v r="$1" -v n="$2" -v c="${_cutoff}" \
                'NF == 3 && !($1 == r && $2 == n) && $3 + 0 >= c' "${_file}"
        printf '%s\t%s\t%s\n' "$1" "$2" "$3"
    } >"${_tmp}" 2>/dev/null && mv -f "${_tmp}" "${_file}" 2>/dev/null; then
        return 0
    fi

    rm -f "${_tmp}" 2>/dev/null || true
    ux_warning "Cannot write ${_file} — the zombie grace clock will not survive this tick." >&2
    return 1
}

# Drop the row keyed by <repo> <number> from a TSV <file> whose first two
# columns are that pair — shared by every "this issue is no longer tracked"
# clear across the zombie clock and the rate-limit casualty list, which both
# key their rows the same way. Silent about failure everywhere it is used: a
# row that could not be removed only ever costs one redundant re-check later,
# never a wrong dispatch.
_iw_tsv_drop_row() {
    local _file="$1" _tmp

    [ -f "${_file}" ] || return 0

    _tmp="${_file}.$$"
    if awk -F "${_IW_TAB}" -v r="$2" -v n="$3" \
        '!($1 == r && $2 == n)' "${_file}" >"${_tmp}" 2>/dev/null; then
        mv -f "${_tmp}" "${_file}" 2>/dev/null || rm -f "${_tmp}" 2>/dev/null || true
    else
        rm -f "${_tmp}" 2>/dev/null || true
    fi
    return 0
}

# Stop the clock for <repo> <number>. Called whenever the pane is observed
# working, or its issue is not closed, so a session that resumed mid-grace
# starts from zero the next time it goes quiet instead of being reclaimed the
# instant it does.
_iw_zombie_candidate_clear() {
    _iw_tsv_drop_row "$(_iw_zombie_candidates_file)" "$1" "$2"
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

# How many per-issue sessions are live, in total and per repo. The total counts
# distinct tab sets, not rows: repos sharing a workspace each get a row for the
# same tab (see the shortcut on _iw_live_agents).
_iw_live_count() {
    _iw_live_agents | awk -F "${_IW_TAB}" '!seen[$3]++ { n++ } END { print n + 0 }'
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
    _count=$(printf '%s' "${_json}" | _iw_sel pr-count) || _count=""
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
# /gh-flow:wave's own worktree always branches `wt/issue-<n>/<index>`, which
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
    local _hits

    # Decided from the printed count, never from the exit status: a python3
    # that cannot import the module exits 1 too, and 1 must not mean "not
    # handled" — that would open a second PR on the issue.
    _hits=$(printf '%s' "${_IW_PR_CACHE_DATA}" | _iw_sel handled-by-pr "$1") || _hits=""

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
    _hp_json_value '.last_repo' <"${_file}"
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
    [ "${_IW_TARGETED}" -eq 0 ] || return 0

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
    _iw_watch_list | _iw_sel repo-order "$1"
}

# ============================================================
# Helpers — claude account routing
# ============================================================

# CLAUDE_CONFIG_DIR for this dispatcher's panes — account routing, exit codes
# and rationale live in lib/herdr_pane.sh _hp_resolve_config_dir.
_iw_resolve_config_dir() {
    _hp_resolve_config_dir "${_IW_SHELL_COMMON}" watcher stdout
}

# Resolve _IW_CONFIG_DIR once per tick, wherever the tick first needs it.
#
# Two callers since #1604 — the candidate dispatch loop and the casualty retry
# that runs ahead of it — and both must see the same account, because "one
# account, one quota" is what makes the rate-limit gate's whole verdict sound.
# Memoized on its own flag rather than on the value: `HOME` unset resolves to a
# legitimately empty CLAUDE_CONFIG_DIR, so emptiness cannot mean "not yet asked".
# An unresolvable account is still terminal for the tick, exactly as it was when
# this lived inline in main().
_iw_ensure_config_dir() {
    [ "${_IW_CONFIG_DIR_RESOLVED}" -eq 0 ] || return 0
    _IW_CONFIG_DIR_RESOLVED=1

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
}

# Print the slash command that runs the gh-flow issue chain in account dir <1>
# (issue #2209). A slash command only runs on an exact name match, and the
# Agent Factory app installs skills as flat `<name>-afNN` copies with an
# unpredictable NN, so the name is looked up rather than hardcoded:
#   1) gh-flow plugin installed and not disabled -> /gh-flow:wave
#   2) exactly one skills/*/SKILL.md whose frontmatter says
#      `Use for /gh-flow:wave` (upstream's alias, which the app keeps)
#      -> /<that skill's name>
# Exit 1 when nothing matches, 2 (matching dirs on stdout) when several do —
# guessing would dispatch the wrong skill.
_iw_resolve_flow_command() {
    local _cfg="$1" _key _on _f _name _hits="" _count=0

    for _key in $(jq -r '(.plugins // {}) | keys[] | select(startswith("gh-flow@"))' \
        "${_cfg}/plugins/installed_plugins.json" 2>/dev/null); do
        # Only an explicit `false` disables: a missing settings.json or entry
        # leaves an installed plugin enabled, which is claude's own default.
        # settings.local.json overrides settings.json (claude merges them, local
        # wins), so the last file that mentions the plugin decides.
        _on=$(cat "${_cfg}/settings.json" "${_cfg}/settings.local.json" 2>/dev/null |
            jq -rs --arg k "${_key}" 'map(select((.enabledPlugins // {}) | has($k)) | .enabledPlugins[$k]) | last' 2>/dev/null)
        if [ "${_on}" != "false" ]; then
            printf '/gh-flow:wave'
            return 0
        fi
    done

    for _f in "${_cfg}"/skills/*/SKILL.md; do
        [ -f "${_f}" ] || continue
        # Frontmatter joined onto one line: a folded `description: >-` can put
        # `Use for` and `/gh-flow:wave` on different lines.
        awk 'NR==1 && /^---[[:space:]]*$/ {fm=1; next} fm && /^---[[:space:]]*$/ {exit} fm' "${_f}" |
            tr -s ' \t\n' '   ' | grep -Eq 'Use for /gh-flow:wave([^[:alnum:]:_-]|$)' || continue
        _hits="${_hits}${_f%/SKILL.md}
"
        _count=$((_count + 1))
    done

    case "${_count}" in
    0) return 1 ;;
    1) ;;
    *)
        printf '%s' "${_hits}"
        return 2
        ;;
    esac

    _f="${_hits%
}/SKILL.md"
    _name=$(awk 'NR==1 && /^---[[:space:]]*$/ {fm=1; next} fm && /^---[[:space:]]*$/ {exit} fm && /^name:/ {sub(/^name:[[:space:]]*/, ""); gsub(/["\047[:space:]]/, ""); print; exit}' "${_f}")
    [ -n "${_name}" ] || _name=$(basename "${_f%/SKILL.md}")
    printf '/%s' "${_name}"
}

# Resolve _IW_FLOW_COMMAND once per tick for the pane account. Shared by the
# first dispatch and the casualty retry, so both send the same command. A
# failure is logged once and is terminal for every dispatch this tick — it is
# deterministic, so retrying it would only rebuild tabs and panes.
_iw_ensure_flow_command() {
    local _cfg _out _rc=0
    case "${_IW_FLOW_RESOLVED}" in
    1) return 0 ;;
    2) return 1 ;;
    esac

    _iw_ensure_config_dir
    _cfg="${_IW_CONFIG_DIR:-${HOME-}/.claude}"
    _out=$(_iw_resolve_flow_command "${_cfg}") || _rc=$?
    if [ "${_rc}" -eq 0 ]; then
        _IW_FLOW_COMMAND="${_out}"
        _IW_FLOW_RESOLVED=1
        return 0
    fi

    _IW_FLOW_RESOLVED=2
    if [ "${_rc}" -eq 2 ]; then
        ux_error "Pane account (${_cfg}) has several /gh-flow:wave entry points — keep one of: $(printf '%s' "${_out}" | tr '\n' ' ')"
    else
        ux_error "Pane account (${_cfg}) has no /gh-flow:wave entry point — install the gh-flow plugin or its Agent Factory copy."
    fi
    return 1
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
    local _host _json _qualifiers _errf _cause

    # gh's stderr is kept, not discarded (#1849): on a gh too old to have
    # `search` the only symptom was the bare warning below, every tick, with
    # exit 0. Scratch beside the state file, named by pid, for the same reason
    # the casualty scratch is — no second mktemp in the tick.
    # An unwritable state dir must cost the cause, not the search: a failed
    # `2>FILE` redirection would skip gh entirely.
    _errf=$(_iw_state_dir)
    mkdir -p "${_errf}" 2>/dev/null || true
    _errf="${_errf}/search.err.$$"
    { : >"${_errf}"; } 2>/dev/null || _errf="/dev/null"

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
            --limit "${_IW_SEARCH_LIMIT}" 2>"${_errf}") || {
            _cause=$(head -n 1 "${_errf}" 2>/dev/null)
            ux_warning "gh search issues failed on ${_host}${_cause:+: ${_cause}} — skipping that host this tick." >&2
            continue
        }

        printf '%s' "${_json}" | _iw_sel search-rows
    done
    [ "${_errf}" = "/dev/null" ] || rm -f "${_errf}"
}

# 0 when any of the issue's labels ($1, US-joined) is on the exclude list.
# Exact matches only: a `wontfix-later` label must not be parked by `wontfix`.
_iw_excluded_by_label() {
    local _labels="$1" _excluded _label _oldifs

    _iw_exclude_labels_resolve
    _excluded="${_IW_EXCL_SET}"

    _oldifs="$IFS"
    IFS="${_IW_US}"
    # Word splitting on US is the point: the label list is a list. US is the
    # separator precisely because a label may contain a comma or a space.
    set -f # a label such as '*' must not glob against the cwd
    # shellcheck disable=SC2086
    set -- ${_labels}
    set +f
    IFS="$_oldifs"

    for _label in "$@"; do
        [ -n "${_label}" ] || continue
        case "${_IW_US}${_excluded}${_IW_US}" in
        *"${_IW_US}${_label}${_IW_US}"*) return 0 ;;
        esac
    done

    return 1
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

    _open=$(printf '%s' "${_json}" | _iw_sel open-blockers) || _open=""

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

# Echoes the `<repo>\t<number>\t<path>\t<host>` lines this tick may dispatch.
#
# The exit status carries a second answer the stdout cannot (issue #1606): 2
# means at least one repo that had work was skipped *because it sat at its
# per-repo cap*, 0 that no cap was in the way. main() pairs that with "did
# anything come back" to decide whether this tick counts as saturated, and the
# two cases it has to keep apart — capped versus an empty backlog — are
# indistinguishable from the candidate list alone.
#
# An exit status rather than a global, because every caller runs this inside a
# `$( )`: a variable assigned in that subshell dies with it, and the flag would
# always read as 0 back in main().
_iw_select_candidates() {
    local _candidates="$1"
    local _repo _number _numbers _path _host _live _rc _selected=""
    local _budget _repo_budget _capped=0

    # Unreachable from a real tick (main() holds on the total cap before this
    # runs). The dry run can still reach it, but that caller never reads $? —
    # so this stays a plain empty return rather than a status nobody consumes.
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
            # This repo had work and its cap is the only thing that stopped it —
            # the tick-level saturation signal this function reports on exit.
            _capped=1
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

    # Explicit, because the cursor write above must not become this function's
    # answer: a failed `_iw_write_last_repo` would otherwise read as "capped".
    [ "${_capped}" -eq 0 ] || return 2
    return 0
}

# ============================================================
# Step 4-6 — tab, agent, dispatch
# ============================================================

# Best-effort teardown of a half-built dispatch, so the next attempt starts
# from nothing. Only the tab: a surviving `iw-<repo>-issue-<N>` tab with an
# agent in it would read as a running session and hold the issue. The issue
# worktree stays (#2281) — it may hold work, the next attempt reuses it, and
# removing it is `gwt teardown`'s job.
_iw_cleanup_attempt() {
    [ -z "$1" ] || herdr tab close "$1" >/dev/null 2>&1 || true
}

# Echo the worktree of main checkout <1> on `wt/issue-<2>/<index>` with the
# highest index, or nothing. The trailing `/` keeps issue 11 off issue 110.
_iw_find_issue_worktree() {
    git -C "$1" worktree list --porcelain 2>/dev/null | awk -v p="refs/heads/wt/issue-$2/" '
        /^worktree / { wt = substr($0, 10) }
        /^branch / {
            b = substr($0, 8)
            if (index(b, p) != 1) next
            k = substr(b, length(p) + 1)
            if (k ~ /^[0-9]+$/ && (best == "" || k + 0 > best + 0)) { best = k; path = wt }
        }
        END { if (path != "") print path }'
}

# `gwt spawn --wt-name <2>` from main checkout <1>, cron-safe (#2281). gwt is a
# shell function behind the interactive guard, so it is sourced here with
# DOTFILES_FORCE_INIT=1, inside a subshell that keeps the watcher's cwd and
# namespace. No --ai/--user/--launch: the herdr pane starts the agent and
# picks the account. git-crypt handling is git_worktree_add's.
_iw_gwt_spawn() {
    local _f
    for _f in functions/git_worktree.sh functions/git_worktree_spawn.sh; do
        if [ ! -f "${_IW_SHELL_COMMON}/${_f}" ]; then
            ux_error "${_f} not found under ${_IW_SHELL_COMMON} — cannot spawn a worktree."
            return 1
        fi
    done
    (
        set +u # the gwt files are written for interactive shells, not nounset
        export DOTFILES_FORCE_INIT=1
        cd "$1" || exit 1
        # shellcheck source=/dev/null
        . "${_IW_SHELL_COMMON}/functions/git_worktree.sh" || exit 1
        # shellcheck source=/dev/null
        . "${_IW_SHELL_COMMON}/functions/git_worktree_spawn.sh" || exit 1
        git_worktree_spawn --wt-name "$2"
    )
}

# Echo the worktree issue <2> is dispatched into, under main checkout <1>: the
# existing `wt/issue-<2>/*` one (highest index) when there is one, else a fresh
# `gwt spawn` (<parent>/<project>-issue-<2>-<k>, branch wt/issue-<2>/<k>).
# gwt's own output goes to stderr (the cron log); stdout is the path alone.
# Non-zero, echoing nothing, when no worktree could be had.
_iw_issue_worktree() {
    local _main="$1" _n="$2" _wt
    _wt=$(_iw_find_issue_worktree "${_main}" "${_n}")
    # An empty index means a half-built worktree (spawn failed after `worktree
    # add --no-checkout`): do not dispatch into it, spawn a fresh one.
    if [ -z "${_wt}" ] || [ ! -d "${_wt}" ] || [ -z "$(git -C "${_wt}" ls-files 2>/dev/null | head -n 1)" ]; then
        _iw_gwt_spawn "${_main}" "issue-${_n}" >&2 || return 1
        _wt=$(_iw_find_issue_worktree "${_main}" "${_n}")
    fi
    [ -n "${_wt}" ] && [ -d "${_wt}" ] || return 1
    printf '%s' "${_wt}"
}

# herdr *create* with the shared flags, routed at this tick's account
# (lib/herdr_pane.sh _hp_herdr_create). Read at call time: _IW_CONFIG_DIR is
# resolved after the file is sourced.
_iw_herdr_create() {
    _hp_herdr_create "${_IW_CONFIG_DIR}" "$@"
}

# Echo the herdr workspace label for <repo> at <path>.
#
# The directory basename is the label users already see (`dotfiles`,
# `agent-toolbox`), so it stays the default — but only while it identifies one
# project directory. Several repos may share one path (gh-verify-skills,
# gh-flow-skills ... all under ~/para/project/skills): that is one directory,
# so one workspace, not a collision. Two *different* paths whose leaf names
# collide would otherwise be merged onto a single workspace, and the second
# repo's tabs would open inside the first repo's (PR #1447 codex/agy review);
# then both sides fall back to the unambiguous slug.
_iw_workspace_label() {
    local _repo="$1" _path="$2" _base _count

    _base=$(basename "${_path}")
    _count=$(_iw_watch_list |
        awk -F "${_IW_TAB}" -v b="${_base}" '
            { n = split($2, parts, "/"); if (parts[n] == b && !seen[$2]++) c++ }
            END { print c + 0 }
        ')

    if [ "${_count}" -le 1 ]; then
        printf '%s' "${_base}"
    else
        printf '%s' "${_repo}"
    fi
}

# Workspace id for label <1>, created against cwd <2> when missing
# (lib/herdr_pane.sh _hp_workspace_for_label).
_iw_workspace_for_label() {
    _hp_workspace_for_label "${_IW_CONFIG_DIR}" "$@"
}

# Open the issue's tab and echo `<pane_id><TAB><tab_id>`.
_iw_tab_create() {
    local _ws="$1" _cwd="$2" _label="$3" _json _pane _tab

    _json=$(_iw_herdr_create "${_cwd}" "${_label}" tab create --workspace "${_ws}") || return 1

    _pane=$(printf '%s' "${_json}" | _hp_json_first pane_id)
    _tab=$(printf '%s' "${_json}" | _hp_json_first tab_id)
    [ -n "${_pane}" ] || return 1
    printf '%s\t%s' "${_pane}" "${_tab}"
}

# Echo the herdr agent name for <owner/repo> issue <number>:
# `iw-<repo>-issue-<number>`. Composition and the character rules behind it are
# the SSOT this file shares with pr_merge_train_cron.sh and
# gh:pr-post-merge-verify — shell-common/lib/herdr_agent_name.sh (#1530).
# Returns non-zero (and echoes nothing) when the repo cannot be normalized;
# every caller here treats an empty name as a failed dispatch rather than
# starting an agent with a malformed one.
_iw_agent_name() {
    herdr_agent_name "${_IW_AGENT_PREFIX}" "$1" "issue-$2"
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
    printf '%s' "${_json}" | _hp_json_value '.result.agent.state_change_seq'
}

# The human half of the same document: herdr's own sentence about the failure.
# Same two inputs and the same stdout-first order as _hp_herdr_error_code —
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

    _msg=$(printf '%s' "${_json}" | _hp_json_value '.error.message')
    if [ -z "${_msg}" ] && [ -s "${_errfile}" ]; then
        _msg=$(_hp_json_value '.error.message' <"${_errfile}")
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
        if _json=$(_hp_agent_start "${_agent}" "${_pane}" "${_IW_ERRF}"); then
            _rc=0
            break
        fi
        _IW_START_CODE=$(_hp_herdr_error_code "${_json}" "${_IW_ERRF}")

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

# Post-start health check (lib/herdr_pane.sh _hp_wait_for_idle).
_iw_wait_for_idle() {
    _hp_wait_for_idle "$1" "${_IW_IDLE_POLL_MAX}" "${_IW_IDLE_POLL_SLEEP}" dispatching
}

# Pane-readiness poll before the prompt (lib/herdr_pane.sh _hp_settle).
_iw_settle() {
    _hp_settle "$1" "${_IW_SETTLE_SECONDS}" "${_IW_SETTLE_POLL_SLEEP}" \
        "${_IW_SETTLE_READ_LINES}" "${_IW_SETTLE_NOT_READY_MARK}"
}

# Echo herdr's JSON response on stdout; the exit code is herdr's own.
#
# herdr writes its error JSON to stderr and its success payload to stdout, so
# the two must be merged here — dropping stderr leaves `.error.code` unreadable
# and every recovery branch below unreachable (#1559, the same defect class as
# #1445/#1458/#1525). Merged rather than split into a capture file the way
# _hp_agent_start does: the only reader is `_hp_json_value '.error.code'`, which
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
            _status=$(_hp_agent_status "${_agent}") || _status=""
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

_iw_prompt_retryable() {
    case "$1" in
    timeout | agent_prompt_stalled | herdr_send_keys_failed) return 0 ;;
    esac
    return 1
}

# The one place a desktop alert is raised: `<title>`, `<body>`, and `<subject>`
# — the phrase both log lines end in. Two callers now (a stalled prompt and, in
# #1606, saturated slots), one CLI shape and one success/failure log pair, so a
# change to how the tick shouts lands in both instead of in whichever copy was
# remembered. `--sound request` because both are things a human has to act on.
# Returns non-zero when herdr refused; no caller has anything to do about that
# beyond the line already logged here.
_iw_herdr_notify() {
    if herdr notification show "$1" --body "$2" --sound request >/dev/null 2>&1; then
        ux_warning "Posted a herdr notification for $3."
        return 0
    fi
    ux_warning "Could not post a herdr notification for $3."
    return 1
}

_iw_escalate_prompt_stall() {
    local _tab="$1" _agent="$2" _number="$3" _code="$4"
    local _label="issue-${_number}-STUCK"
    local _body="#${_number} dispatch stalled repeatedly — herdr agent attach ${_agent}"

    if [ -n "${_tab}" ]; then
        if herdr tab rename "${_tab}" "${_label}" >/dev/null 2>&1; then
            ux_warning "Renamed tab ${_tab} to ${_label} after repeated prompt failure (${_code:-unknown})."
        else
            ux_warning "Could not rename tab ${_tab} after repeated prompt failure (${_code:-unknown})."
        fi
    fi

    _iw_herdr_notify "issue watcher prompt stalled" "${_body}" \
        "issue #${_number} prompt failure" || true
}

# Send `<flow command> <N>` to the issue's agent — `/gh-flow:wave <N>`, or the
# Agent Factory copy's name _iw_ensure_flow_command resolved (issue #2209).
#
# The prompt is a slash command, not prose: pre-#1440 this channel carried an
# instruction to *run another agent*, and the receiving session had to work out
# which tool that meant (#1394). There is nothing left to interpret here, and
# the command runs top-level rather than inside a subagent, which is what took
# this path out of the `SubagentStop` guard gap (#1434).
_iw_prompt_issue() {
    local _agent="$1" _number="$2" _tab="${3-}" _attempt="${4-}" _prompt _json _code _rc=0 _seq0 _post_stall_status _fail_code

    _IW_STALL_RECOVER_ERROR=""
    _IW_PROMPT_KEEP_ATTEMPT=0
    # After the resets: a caller reading them on this failure must not see a
    # previous issue's values.
    _iw_ensure_flow_command || return 1
    _prompt="${_IW_FLOW_COMMAND} ${_number}"

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
        _code=$(printf '%s' "${_json}" | _hp_json_value '.error.code')
        if [ "${_code}" = "agent_prompt_stalled" ]; then
            # `agent_prompt_stalled` only proves herdr saw no state change
            # within its fixed 5s window — it does NOT prove the prompt was
            # never submitted (PR #1400 codex review). `working` is positive
            # evidence the call *did* land, so there is nothing to recover.
            _post_stall_status=$(_hp_agent_status "${_agent}") || _post_stall_status=""
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
    if _iw_prompt_retryable "${_fail_code}" &&
        [ -n "${_attempt}" ] && [ "${_attempt}" -ge "${_IW_MAX_ATTEMPTS}" ]; then
        _iw_escalate_prompt_stall "${_tab}" "${_agent}" "${_number}" "${_fail_code}"
        _IW_PROMPT_KEEP_ATTEMPT=1
    fi
    ux_error "herdr agent prompt failed for agent ${_agent} (${_fail_code:-unknown})."
    return 1
}

# One issue, end to end: workspace, tab, agent, prompt. Retries the
# whole sequence up to _IW_MAX_ATTEMPTS times, cleaning up before each retry so
# no attempt inherits the previous one's half-built state.
_iw_process_issue() {
    local _repo="$1" _number="$2" _path="$3"
    local _attempt=1 _agent _label _ws="" _pane_tab="" _pane="" _tab=""
    local _cause="" _msg="" _wt

    # A repo whose name normalizes to nothing has no addressable agent, so the
    # dispatch fails here rather than starting a session under a name no later
    # tick can look up (#1530).
    _agent=$(_iw_agent_name "${_repo}" "${_number}") || {
        ux_warning "Cannot derive a herdr agent name for ${_repo}#${_number} — the composed name is invalid or exceeds herdr's 32-char limit. This issue will be skipped on every tick until the naming scheme changes (see herdr_agent_name.sh, #1553)."
        return 2
    }
    _label=$(_iw_workspace_label "${_repo}" "${_path}")

    # Before any tab or pane exists: no entry point is a deterministic
    # failure, and the retry loop below would only rebuild them (#2209).
    if ! _iw_ensure_flow_command; then
        ux_warning "Not dispatching ${_repo}#${_number} — no /gh-flow:wave entry point to run."
        return 1
    fi

    # The worktree comes before any tab, once per issue and outside the retry
    # loop: a retry or a later tick reuses it instead of spawning
    # issue-<N>-2 (#2281). No worktree, no dispatch — starting the session on
    # the main checkout instead is exactly what this guards against.
    if ! _wt=$(_iw_issue_worktree "${_path}" "${_number}"); then
        ux_error "Not dispatching ${_repo}#${_number} — could not acquire a wt/issue-${_number} worktree from ${_path}."
        return 1
    fi

    while [ "${_attempt}" -le "${_IW_MAX_ATTEMPTS}" ]; do
        _tab=""

        # The tab opens on the issue worktree and is labelled with the agent
        # name (`iw-<repo>-issue-<N>`) — the repo slug ties it to this repo
        # alone in a shared workspace, and the `iw-` keeps it apart from an
        # `issue-<N>` tab the user opened by hand; _iw_live_agents counts both.
        # /gh-flow:wave adopts that worktree in its reuse mode.
        if ! _ws=$(_iw_workspace_for_label "${_label}" "${_path}"); then
            ux_warning "No herdr workspace for ${_label} (attempt ${_attempt}/${_IW_MAX_ATTEMPTS})."
        elif ! _pane_tab=$(_iw_tab_create "${_ws}" "${_wt}" "${_agent}"); then
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
            elif _iw_wait_for_idle "${_agent}" && _iw_settle "${_agent}"; then
                if _iw_prompt_issue "${_agent}" "${_number}" "${_tab}" "${_attempt}"; then
                    ux_success "${_repo}#${_number} dispatched (tab ${_tab}, pane ${_pane})."
                    return 0
                elif [ "$(_hp_agent_status "${_agent}")" = "working" ]; then
                    # A `working` agent is never torn down, whatever the dispatch
                    # reported (#1559). One tick killed a session that was doing
                    # real work three times over, because a failed attempt ran
                    # _iw_cleanup_attempt unconditionally — the prompt call had
                    # failed, the agent had not. Deliberately independent of the
                    # `.error.code` fix in _iw_prompt_once: that parsing is what
                    # silently broke in production, so it is not the only thing
                    # standing between a live session and `tab close`.
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
                    ux_warning "${_agent} reports working despite the failed prompt — keeping tab ${_tab} and pane ${_pane}, not retrying."
                    return 0
                elif [ "${_IW_PROMPT_KEEP_ATTEMPT}" -eq 1 ]; then
                    ux_error "Giving up on ${_repo}#${_number} after ${_IW_MAX_ATTEMPTS} attempts."
                    return 1
                fi
            fi
        fi

        _iw_cleanup_attempt "${_tab}"
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
# cycle before the next tick can offer it again. Since NF-1 nothing left
# behind retires the issue permanently (that was the pre-#1453 failure this
# gate was written against), so exhaustion now costs a wasted
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
#      `_IW_LIMIT_OBSERVE_SEC`. One `/gh-flow:wave` runs for minutes, so an
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
    _hp_json_value ".$1" <"${_file}" 2>/dev/null
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
#   no-clock    _hp_now failed
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

    _now=$(_hp_now)
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
        # The one moment the casualty list is acted on. Flagged rather than
        # retried here: this function is the gate's decision and runs before the
        # tick has primed `herdr agent list` or resolved an account dir, and the
        # retry needs both. main() reads the flag once, ahead of both the
        # concurrency ceiling and _iw_select_candidates, so the issues the
        # outage killed are offered their pane back before a fresh issue is
        # allowed to take a slot — and before a slot count they may themselves
        # be occupying can turn the tick away (issue #1604, PR #1622 review).
        _IW_LIMIT_GATE_REOPENED=1
        return 0
        ;;
    esac

    ux_warning "Rate-limit gate closed — holding dispatch for ~$(((_left + 59) / 60))m (no tab is opened this tick)."
    return 1
}

# Poll the tick's confirmed dispatches for `_IW_LIMIT_OBSERVE_SEC`.
#
# $1 is the dispatch list: one `<agent>[<TAB><repo><TAB><number>]` row each. The
# trailing pair is what lets a strike name the issues it killed (issue #1604);
# a bare agent name still parses, and simply books no casualty.
#
# $2 is optional — a file the deciding poll's *readably failed* dispatches are
# written to, as `<repo><TAB><number>` rows. "Readably" is the whole point:
# `_hp_agent_status` reports both of its failure modes as an empty string, so a
# dispatch herdr would not talk about has no evidence against it and must not be
# booked as a casualty, even on a tick that earns a strike for its neighbours.
# The file is rewritten from scratch every poll and only ever read after this
# returns, so what survives is the verdict of the poll that decided.
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
# `_hp_agent_status` reports both of its failure modes as an empty string, so
# emptiness is the absence of evidence, never evidence of idleness. A strike
# needs a status we actually read.
#
# The last poll is the one that decides: `working` has to be *held*, not merely
# touched. The earlier polls exist only to tell those two failures apart in the
# log.
_iw_limit_observe() {
    local _agents="$1" _failed_file="${2-}" _i=0 _agent _repo _number _status
    local _alive="" _seen="" _readable=0

    while [ "${_i}" -lt "${_IW_LIMIT_OBSERVE_POLLS}" ]; do
        [ "${_IW_LIMIT_OBSERVE_SLEEP}" = "0" ] || sleep "${_IW_LIMIT_OBSERVE_SLEEP}"
        _i=$((_i + 1))
        _alive=""
        # Per-poll, like `_alive`: only the deciding poll's readability counts.
        # A pane readable 50 seconds ago says nothing about now.
        _readable=0
        # Same per-poll rule for the casualty list, and the reason it is
        # truncated here rather than appended to across the window.
        [ -z "${_failed_file}" ] || : >"${_failed_file}" 2>/dev/null || true

        # fd 3, not stdin: the loop body runs `herdr`, which would otherwise
        # swallow the rest of the agent list and silently shorten the
        # observation to its first entry (PR #1447 agy review).
        while IFS="${_IW_TAB}" read -r _agent _repo _number <&3; do
            [ -n "${_agent}" ] || continue
            _status=$(_hp_agent_status "${_agent}") || _status=""
            [ -z "${_status}" ] || _readable=1
            case "${_status}" in
            working | blocked)
                _alive="${_agent}"
                break
                ;;
            esac
            # Read, and not alive: this dispatch failed to hold `working`. Rows
            # without the issue pair are the bare-agent-name callers, which have
            # nothing to book.
            if [ -n "${_status}" ] && [ -n "${_failed_file}" ] &&
                [ -n "${_repo}" ] && [ -n "${_number}" ]; then
                printf '%s\t%s\n' "${_repo}" "${_number}" \
                    >>"${_failed_file}" 2>/dev/null || true
            fi
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
# that decision. The read-and-filter itself is _hp_pane_text's (#1570) — this
# just asks for 40 lines instead of the settle poll's 3.
_iw_limit_evidence() {
    local _agents="$1" _agent _rest _text _line

    # fd 3, not stdin: the loop body runs `herdr` (PR #1447 agy review). The
    # dispatch rows carry `<repo> <number>` after the agent name since #1604;
    # only the name addresses a pane, so the rest is read off and dropped.
    while IFS="${_IW_TAB}" read -r _agent _rest <&3; do
        [ -n "${_agent}" ] || continue
        _text=$(_hp_pane_text "${_agent}" "${_IW_LIMIT_EVIDENCE_LINES}")
        if [ -z "${_text}" ]; then
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

# ------------------------------------------------------------
# Strike casualties (issue #1604)
# ------------------------------------------------------------
#
# A strike closes the gate for _IW_LIMIT_BACKOFF_SECONDS, but until #1604 it
# forgot *which* issues the outage killed. On reopen the tick simply asked
# `_iw_select_candidates` again, which round-robins on to the next issue — so an
# outage lasting longer than one backoff window sacrificed a fresh issue every
# 30 minutes, each one holding a tab and a concurrency slot forever and
# none of them ever retried. A human had to re-prompt every dead pane by hand.
#
# The rows below are that missing memory. They are written where the strike is
# booked and read exactly once, when the gate reopens.

_iw_limit_casualties_file() {
    printf '%s/%s' "$(_iw_state_dir)" "${_IW_LIMIT_CASUALTIES_BASENAME}"
}

# Echo the attempts already spent on <repo> <number>, or nothing when the pair
# is not on file. Same NF-1 posture as _iw_zombie_candidate_ts: a missing file,
# an unreadable one and an absent row are one answer, and the caller reads it as
# "not a casualty".
_iw_limit_casualty_attempts() {
    local _file
    _file=$(_iw_limit_casualties_file)
    [ -f "${_file}" ] || return 0
    awk -F "${_IW_TAB}" -v r="$1" -v n="$2" \
        '$1 == r && $2 == n { print ($4 == "" ? 0 : $4 + 0); exit }' \
        "${_file}" 2>/dev/null
}

# Book <repo> <number> at <epoch> with <attempts> spent, replacing any row the
# pair already has.
#
# Overwriting on purpose — the one place this parts company with
# _iw_zombie_candidate_mark, which must never reset its clock. Here the row
# carries a retry budget that has to be able to move, and the epoch is read by
# nothing but the prune below.
#
# That prune drops rows older than a full day rather than the zombie file's six
# grace windows. Rows normally leave through the retry path, which is bounded by
# _IW_MAX_ATTEMPTS; this horizon only catches the ones orphaned another way — a
# repo dropped from the watch list, an issue closed by hand — and it has to sit
# well clear of a real quota outage, which runs for hours and during which a
# casualty must survive untouched.
_iw_limit_casualty_mark() {
    local _dir _file _tmp _cutoff

    _dir=$(_iw_state_dir)
    _file=$(_iw_limit_casualties_file)
    if ! mkdir -p "${_dir}" 2>/dev/null; then
        ux_warning "Cannot create state directory (${_dir}) — rate-limit casualties will not survive this tick."
        return 1
    fi

    # Same directory as the target on purpose: `mv` is only atomic within one
    # filesystem, so a temp file under /tmp would trade the guarantee away.
    _tmp="${_file}.$$"
    _cutoff=$(($3 - 86400))
    if {
        [ ! -f "${_file}" ] ||
            awk -F "${_IW_TAB}" -v r="$1" -v n="$2" -v c="${_cutoff}" \
                'NF >= 3 && !($1 == r && $2 == n) && $3 + 0 >= c' "${_file}"
        printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"
    } >"${_tmp}" 2>/dev/null && mv -f "${_tmp}" "${_file}" 2>/dev/null; then
        return 0
    fi

    rm -f "${_tmp}" 2>/dev/null || true
    ux_warning "Cannot write ${_file} — rate-limit casualties will not survive this tick."
    return 1
}

# Drop <repo> <number> from the file — the issue was retried successfully, or
# its budget ran out. Uses _iw_tsv_drop_row, so failure is silent for the same
# reason _iw_zombie_candidate_clear's is: a row that could not be removed
# costs one redundant re-prompt on the next reopen, never a lost issue.
_iw_limit_casualty_clear() {
    _iw_tsv_drop_row "$(_iw_limit_casualties_file)" "$1" "$2"
}

# Book every dispatch in <file> (`<repo><TAB><number>` rows, as written by
# _iw_limit_observe) as a casualty of the strike just recorded. A pair already
# on file keeps the attempts it has spent — a second outage must not hand it a
# fresh budget, or a genuinely broken issue would be retried forever.
_iw_limit_casualty_book() {
    local _file="$1" _now _repo _number _attempts

    [ -s "${_file}" ] || return 0
    _now=$(_hp_now)
    [ -n "${_now}" ] || return 0

    while IFS="${_IW_TAB}" read -r _repo _number; do
        [ -n "${_repo}" ] || continue
        [ -n "${_number}" ] || continue
        _attempts=$(_iw_limit_casualty_attempts "${_repo}" "${_number}")
        case "${_attempts}" in
        '' | *[!0-9]*) _attempts=0 ;;
        esac
        _iw_limit_casualty_mark "${_repo}" "${_number}" "${_now}" "${_attempts}" || return 0
        ux_info "Booked ${_repo}#${_number} as a rate-limit casualty — it will be retried when the gate reopens."
    done <"${_file}"
}

# Warn and drop <repo> <number> from the casualty file for <reason> — shared
# by _iw_limit_retry_casualties's two guard clauses that find a casualty they
# cannot act on at all (repo gone, agent name invalid).
_iw_limit_casualty_drop() {
    ux_warning "Dropping rate-limit casualty $1#$2 — $3"
    _iw_limit_casualty_clear "$1" "$2"
}

# Re-offer every casualty its pane, once, at gate-reopen time.
#
# Two ways back in, and the cheap one is tried first. If herdr still knows the
# issue's agent the pane and its session survived the outage, so all the issue
# needs is the prompt it never got to run — the same `herdr agent prompt`
# _iw_prompt_issue sends on a first dispatch. Only when the agent is gone does
# this fall back to the full _iw_process_issue path, which rebuilds workspace,
# tab and agent from scratch; rebuilding it unconditionally would
# throw away a perfectly good session and its branch.
#
# Success is verified exactly the way the gate verifies quota recovery, because
# it is the same question: _iw_limit_observe over _IW_LIMIT_OBSERVE_SEC. Per
# casualty rather than as one batch — the batch call names a single alive agent
# and would leave the other rows' verdicts unknown, and here every row needs its
# own answer. Run right after that row's own dispatch rather than in a
# separate pass over every row: nothing about *watching* one casualty depends
# on every other casualty having been dispatched first, only judging them
# does — see the apply pass below, which is what actually needs every verdict
# in hand before it acts on any of them.
#
# The retry budget only pays for failures the quota cannot explain. If nothing
# retried this pass held `working`, the account is still spent: the rows keep
# their attempts and wait for the next reopen, which is the whole point of
# remembering them. Attempts are burned only once some sibling has proved the
# quota came back and this issue still will not run — the "reason other than
# quota" _IW_MAX_ATTEMPTS is meant to bound.
_iw_limit_retry_casualties() {
    local _file _casualties="" _rows="" _quota_ok=0
    local _repo _number _epoch _attempts _agent _path _rc _line

    _file=$(_iw_limit_casualties_file)
    [ -s "${_file}" ] || return 0

    ux_info "Rate-limit casualties on file — retrying them before any new issue."

    # Read the whole file up front: the loop below rewrites it row by row, and
    # a `while read` on a file being rewritten under it reads whatever the
    # rewrite left behind.
    _casualties=$(cat "${_file}" 2>/dev/null) || return 0

    # Pass 1 — hand each casualty its prompt back, then watch it for the
    # window right away, collecting an rc-tagged verdict row per casualty.
    while IFS="${_IW_TAB}" read -r _repo _number _epoch _attempts <&3; do
        [ -n "${_repo}" ] || continue
        [ -n "${_number}" ] || continue

        _path=$(_iw_repo_path "${_repo}")
        if [ -z "${_path}" ]; then
            # The repo left the watch list while the gate was shut. Nothing
            # here can act on it, and keeping the row would retry it forever.
            _iw_limit_casualty_drop "${_repo}" "${_number}" "the repo is no longer watched."
            continue
        fi

        # Emptiness is checked alongside the exit status because everything
        # below addresses herdr *by* this name: an empty one would silently ask
        # about agent "" — a lookup that answers "gone" — and send the retry
        # down the redispatch path for a pane that is in fact alive.
        if ! _agent=$(_iw_agent_name "${_repo}" "${_number}") || [ -z "${_agent}" ]; then
            _iw_limit_casualty_drop "${_repo}" "${_number}" "no valid herdr agent name (see #1530)."
            continue
        fi

        if [ -n "$(_hp_agent_status "${_agent}")" ]; then
            ux_info "Re-prompting ${_repo}#${_number} in its surviving pane (${_agent})."
            if ! _iw_prompt_issue "${_agent}" "${_number}"; then
                # A prompt that never landed is a transport or input-loop
                # failure, not evidence about anything this function judges —
                # the same reading _iw_limit_record gives it. The row waits.
                ux_warning "Retry prompt for ${_repo}#${_number} did not land — keeping it on file."
                continue
            fi
        else
            ux_info "Pane for ${_repo}#${_number} is gone — redispatching from scratch."
            _iw_ensure_config_dir
            if ! _iw_process_issue "${_repo}" "${_number}" "${_path}"; then
                ux_warning "Redispatch of ${_repo}#${_number} failed — keeping it on file."
                continue
            fi
        fi

        _rc=0
        _iw_limit_observe "${_agent}${_IW_TAB}${_repo}${_IW_TAB}${_number}" >/dev/null || _rc=$?
        [ "${_rc}" -ne 0 ] || _quota_ok=1
        _rows="${_rows}${_rc}${_IW_TAB}${_repo}${_IW_TAB}${_number}${_IW_TAB}${_attempts:-0}
"
    done 3<<EOF
${_casualties}
EOF

    [ -n "${_rows}" ] || return 0

    # Pass 2 — apply. Kept separate from the dispatch-and-observe pass above
    # so a casualty that recovers late in the list still counts as the proof
    # that clears its earlier siblings' budget.
    while IFS="${_IW_TAB}" read -r _rc _repo _number _attempts; do
        [ -n "${_repo}" ] || continue
        [ -n "${_number}" ] || continue
        case "${_attempts}" in
        '' | *[!0-9]*) _attempts=0 ;;
        esac

        if [ "${_rc}" = "0" ]; then
            ux_success "Rate-limit casualty ${_repo}#${_number} is working again — dropping it from the retry list."
            _iw_limit_casualty_clear "${_repo}" "${_number}"
            continue
        fi

        if [ "${_quota_ok}" -eq 0 ]; then
            ux_warning "${_repo}#${_number} still did not hold 'working' and no sibling did either — the quota looks spent, so its retry budget is untouched."
            continue
        fi

        _attempts=$((_attempts + 1))
        if [ "${_attempts}" -ge "${_IW_MAX_ATTEMPTS}" ]; then
            _iw_limit_casualty_clear "${_repo}" "${_number}"
            ux_error "Giving up on ${_repo}#${_number} after ${_IW_MAX_ATTEMPTS} attempts."
            continue
        fi

        ux_warning "${_repo}#${_number} failed to hold 'working' with the quota recovered (${_attempts}/${_IW_MAX_ATTEMPTS}) — retrying on the next reopen."
        _line=$(_hp_now)
        [ -z "${_line}" ] ||
            _iw_limit_casualty_mark "${_repo}" "${_number}" "${_line}" "${_attempts}" || true
    done <<EOF
${_rows}
EOF
}

# Record this tick's outcome. $1 is the newline-separated list of dispatches
# whose prompt was confirmed submitted, one `<agent><TAB><repo><TAB><number>`
# row each — every other dispatch is excluded upstream because an unsubmitted
# prompt says nothing about the quota (issue #1444).
#
# Two consecutive unproductive ticks shut the gate; one productive tick wipes
# the slate, so `_IW_LIMIT_STRIKES` really does count consecutive failures. 1
# would hold the watcher over a single transient herdr blip; 2 buys that
# evidence for one extra tick (~5 min).
_iw_limit_record() {
    local _agents="$1" _alive="" _strikes _now _rc=0 _failed_file

    # Nothing reached a pane this tick: no evidence either way, so the strike
    # count stays exactly where it was. Said out loud rather than returned
    # silently — a gate that leaves no trace here is indistinguishable from a
    # gate that never ran, which is the class of blind assertion issue #1442
    # went through this suite to remove.
    if [ -z "${_agents}" ]; then
        ux_info "No dispatch reached its pane this tick — nothing to judge, gate untouched."
        return 0
    fi

    # Scratch beside the state file rather than under /tmp, and named by pid the
    # way the atomic rewrites are: the tick has exactly one `mktemp` call and
    # this must not become its second, since a state dir that cannot be written
    # is a documented degradation (no casualties booked) while a missing mktemp
    # would be an error.
    _failed_file="$(_iw_limit_casualties_file).failed.$$"
    mkdir -p "$(_iw_state_dir)" 2>/dev/null || true

    # Three-way, not a boolean: `rc 2` is "herdr never answered", which must not
    # be booked as idleness. On `rc 1` `_alive` carries the agent that reached
    # `working` earlier in the window, if any — see _iw_limit_observe.
    _alive=$(_iw_limit_observe "${_agents}" "${_failed_file}") || _rc=$?
    if [ "${_rc}" -eq 0 ]; then
        rm -f "${_failed_file}" 2>/dev/null || true
        ux_info "Agent ${_alive} held 'working' for ${_IW_LIMIT_OBSERVE_SEC}s — quota is not exhausted, gate cleared."
        _iw_limit_clear
        return 0
    fi
    if [ "${_rc}" -eq 2 ]; then
        rm -f "${_failed_file}" 2>/dev/null || true
        ux_warning "No dispatched agent's status could be read after ${_IW_LIMIT_OBSERVE_SEC}s — herdr unreachable, gate untouched."
        return 0
    fi

    # The strike is the tick's verdict; the casualties are which issues paid for
    # it. Booked before the strike arithmetic below because a reopen has to find
    # them whether this strike merely accumulates or actually shuts the gate —
    # the first of two unproductive ticks killed an issue just as thoroughly as
    # the second (issue #1604).
    _iw_limit_casualty_book "${_failed_file}"
    rm -f "${_failed_file}" 2>/dev/null || true

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

    _now=$(_hp_now)
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

# ============================================================
# Saturation alert (issue #1606)
# ============================================================
#
# One question, asked once per tick: did this tick dispatch nothing *purely*
# because the concurrency caps were full? The answer is a boolean, not a count
# of capped repos — two capped repos in one tick are still one tick of
# saturation, and the thing being measured is how long the watcher has been
# unable to start anything.
#
# Two call sites answer it per tick:
#   - main()'s total-concurrency hold — always saturated;
#   - after candidate selection — saturated only when `_select_rc == 2`
#     (some repo that had something to offer sat at its own per-repo cap),
#     never saturated otherwise. A tick with candidates but no cap hit clears
#     the same as one with nothing queued at all: "did a cap block anything"
#     is the fact that matters, not whether a candidate happened to exist —
#     keying the clear on candidate-emptiness instead let a resolved episode
#     linger in `--status` for as long as the backlog stayed empty (PR #1624
#     review, agy FOLLOW-UP + codex Assumption).
#
# The zombie-grace reclaim deliberately has no call site of its own: the live
# count is recomputed from scratch every tick, so a tick that reclaimed a pane
# already shows the extra headroom and routes itself through one of the branches
# above (PR #1608 design note).
#
# Nothing here inspects *why* the slots are full — same posture as the
# rate-limit gate since #1444, where pane text decides nothing.

_iw_saturation_state_file() {
    printf '%s/%s' "$(_iw_state_dir)" "${_IW_SATURATION_STATE_BASENAME}"
}

# Echo one field of the saturation state file, or nothing. A missing file, an
# unreadable one and an absent field are all "nothing" on purpose — every caller
# reads that as "no episode on record" and starts a fresh one (NF-1).
_iw_saturation_read() {
    local _file
    _file=$(_iw_saturation_state_file)
    [ -f "${_file}" ] || return 0
    _hp_json_value ".$1" <"${_file}" 2>/dev/null
}

# Persist the consecutive-tick count plus the epoch of the last alert. Both are
# written as JSON *strings* for the same reason _iw_limit_write writes its two
# that way: the readers coerce either encoding, and a file left by an earlier
# tick has to keep parsing across the upgrade.
_iw_saturation_write() {
    local _dir _file
    _dir=$(_iw_state_dir)
    _file=$(_iw_saturation_state_file)

    if ! mkdir -p "${_dir}" 2>/dev/null; then
        ux_warning "Cannot create state directory (${_dir}) — the saturation counter will not survive this tick."
        return 1
    fi

    if ! printf '{ "ticks": "%s", "last_notified": "%s" }\n' "$1" "$2" >"${_file}" 2>/dev/null; then
        ux_warning "Cannot write ${_file} — the saturation counter will not survive this tick."
        return 1
    fi
}

_iw_saturation_clear() {
    rm -f "$(_iw_saturation_state_file)" 2>/dev/null || true
}

# The alert body: one `<repo>#<number>: <status>` line per occupied slot (F-2).
#
# The status is asked per pane rather than reused from the `agent list` snapshot
# the live count was built on, because that snapshot is exactly what a human
# reading this alert has to second-guess: it is what makes the slot count as
# occupied, and a `done`/`idle` line beside an issue number is the difference
# between "everything is genuinely busy" and "a tab nobody closed". Without it
# the answer costs seven `herdr agent attach` calls by hand.
_iw_saturation_notify() {
    local _repo _number _rest _agent _status _body=""

    # fd 3, not stdin: `_hp_agent_status` shells out to herdr, which reads stdin
    # and would otherwise swallow the rest of the occupied list — the same
    # hazard main()'s dispatch loop documents.
    while IFS="${_IW_TAB}" read -r _repo _number _rest <&3; do
        [ -n "${_repo}" ] || continue
        _status=""
        if _agent=$(_iw_agent_name "${_repo}" "${_number}") && [ -n "${_agent}" ]; then
            _status=$(_hp_agent_status "${_agent}") || _status=""
        fi
        _body="${_body}${_repo}#${_number}: ${_status:-unknown}
"
    done 3<<EOF
$(_iw_live_agents)
EOF

    # The status is relayed, not swallowed: the caller starts the cooldown only
    # once an alert actually went out.
    _iw_herdr_notify "issue watcher slots saturated" \
        "No dispatch for ${_IW_SATURATION_ALERT_TICKS}+ consecutive ticks — every slot occupied:
${_body}" \
        "saturated concurrency slots"
}

# The single per-tick hook. $1 is 1 when this tick dispatched nothing purely
# because the caps were full, 0 when the slots had room.
#
# Fail-open throughout (NF-1): a field that reads back unusable is treated as
# "no episode on record", and a write that fails warns once and returns. An
# alert this script cannot persist must never be the reason a tick stops.
_iw_saturation_tick() {
    local _ticks _last _now _since

    if [ "$1" -eq 0 ]; then
        # F-4. The episode is over, so the cooldown goes with it: the next
        # saturation is a new incident and must not be silenced by the alert
        # that closed the last one.
        _iw_saturation_clear
        return 0
    fi

    _ticks=$(_iw_saturation_read ticks)
    case "${_ticks}" in
    '' | *[!0-9]*) _ticks=0 ;;
    esac
    _ticks=$((_ticks + 1))

    _last=$(_iw_saturation_read last_notified)
    case "${_last}" in
    '' | *[!0-9]*) _last=0 ;;
    esac

    if [ "${_ticks}" -ge "${_IW_SATURATION_ALERT_TICKS}" ]; then
        _now=$(_hp_now)
        if [ -z "${_now}" ]; then
            # No clock, no cooldown arithmetic — and an alert that cannot record
            # when it fired would re-fire every tick from here on. The count
            # still goes to disk below, so the episode is not lost, only
            # unannounced.
            ux_warning "Cannot read the clock — saturation alert skipped (${_ticks} consecutive full ticks)."
        else
            # Past the threshold only the clock decides (F-3). The counter keeps
            # climbing rather than resetting: re-arming on "ticks grew again"
            # would fire every tick forever, and zeroing it would throw away how
            # long this episode has actually run — which is the one number a
            # human waking up to this wants.
            #
            # A negative gap means `last_notified` sits in the future: a clock
            # jump or a hand edit, never something this script wrote. Alerting
            # beats staying quiet until the clock catches up, the same call
            # _iw_limit_gate_state makes for an out-of-range deadline.
            _since=$((_now - _last))
            if [ "${_last}" -eq 0 ] || [ "${_since}" -ge "${_IW_SATURATION_COOLDOWN_SECONDS}" ] ||
                [ "${_since}" -lt 0 ]; then
                ux_warning "Concurrency slots have been full for ${_ticks} consecutive tick(s) — nothing dispatched."
                # Only a delivered alert starts the clock. Stamping a refused
                # one would trade the warning line _iw_herdr_notify just logged
                # for three silent hours — exactly the outcome this alert
                # exists to prevent — so a refusal simply leaves the next tick
                # to try again.
                _iw_saturation_notify && _last="${_now}"
            fi
        fi
    fi

    _iw_saturation_write "${_ticks}" "${_last}" || true
}

# The read-only half of the alert, for the human it just woke up: how many ticks
# this episode has run, and whether the alert has already fired for it. Pure,
# like _iw_limit_gate_state — reporting an episode must never advance or clear
# one, the same reason --dry-run stays off the gate's write path.
_iw_saturation_status_report() {
    local _file _ticks _last _now _since _remaining

    _file=$(_iw_saturation_state_file)
    ux_bullet "saturation state file"
    ux_bullet_sub "${_file}"

    if [ ! -f "${_file}" ]; then
        ux_success "No saturation episode on record — the last tick that looked had room."
        return 0
    fi

    # A hand-edited or truncated field reads as "?" rather than as an invented
    # 0, the same call the strike line makes above.
    _ticks=$(_iw_saturation_read ticks)
    case "${_ticks}" in
    '' | *[!0-9]*) _ticks="?" ;;
    esac
    _last=$(_iw_saturation_read last_notified)
    case "${_last}" in
    '' | *[!0-9]*) _last=0 ;;
    esac

    ux_bullet "saturation"
    ux_bullet_sub "${_ticks}/${_IW_SATURATION_ALERT_TICKS} consecutive ticks that dispatched nothing with the slots full"

    if [ "${_last}" -eq 0 ]; then
        ux_warning "Slots saturated — no alert sent yet for this episode."
        return 0
    fi

    _now=$(_hp_now)
    if [ -z "${_now}" ]; then
        ux_warning "Slots saturated — an alert was sent for this episode; cannot read the clock to say when."
        return 0
    fi

    _since=$((_now - _last))
    if [ "${_since}" -lt 0 ]; then
        # Only a clock jump or a hand edit writes a future timestamp; the tick
        # alerts through it rather than waiting for the clock to catch up, so
        # the report says the same thing.
        ux_warning "Slots saturated — the last alert is stamped in the future; the next tick alerts anyway."
        return 0
    fi

    # The claim (`--help`, the changelog) is a *remaining* cooldown, not the
    # cooldown's own fixed length — printing `_IW_SATURATION_COOLDOWN_SECONDS`
    # verbatim here repeated that length forever regardless of how much of it
    # had already elapsed (PR #1624 review, codex BLOCKER + agy FOLLOW-UP).
    _remaining=$((_IW_SATURATION_COOLDOWN_SECONDS - _since))
    if [ "${_remaining}" -le 0 ]; then
        ux_warning "Slots saturated — last alert ~$(((_since + 59) / 60))m ago, cooldown elapsed — the next saturated tick alerts again."
    else
        ux_warning "Slots saturated — last alert ~$(((_since + 59) / 60))m ago, next alert possible in ~$(((_remaining + 59) / 60))m."
    fi
}

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
# Split from _iw_status_report when the saturation counter earned a section of
# its own (#1606): every branch below answers with `return 0`, so a second topic
# appended after them would be unreachable on all but one path. Two reporters,
# one caller, and neither can silence the other.
_iw_status_report() {
    ux_header "issue-watcher status"
    _iw_limit_status_report
    _iw_saturation_status_report
    _iw_gh_search_status_report
}

# The tick's whole intake is `gh search issues --json` (#1440). A gh without it
# — Ubuntu 22.04's apt gh 2.4.0 has no `search` at all — turns every tick into
# a silent no-op (#1849). Probed by feature, not version: `--help` is local and
# free, and lists `--json` only where the flag exists.
_iw_gh_search_status_report() {
    ux_bullet "gh search issues"
    if ! command -v gh >/dev/null 2>&1; then
        ux_warning "gh not found on PATH — every tick will find no issue. Install gh."
    elif gh search issues --help 2>&1 | grep -q -- '--json'; then
        ux_success "gh supports 'gh search issues --json'."
    else
        ux_warning "gh lacks 'gh search issues --json' — every tick will find no issue. Upgrade gh."
    fi
}

_iw_limit_status_report() {
    local _file _state _left _strikes

    _file=$(_iw_limit_state_file)

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
    _hp_acquire_lock "$(_iw_state_dir)" "${_IW_LOCK_BASENAME}" avatar_issue_watcher
}

# ============================================================
# Usage
# ============================================================

_iw_usage() {
    ux_header "avatar_issue_watcher"
    ux_info "Usage: avatar_issue_watcher.sh [--cwd <PATH>] [--dry-run] [<issue-ref> [--force]] | --status | watch ... | label ... | [-h|--help|help]"
    ux_info "Runs one issue-watcher tick: find assigned issues, dispatch /gh-flow:wave (or its Agent Factory copy)."
    ux_bullet "options"
    ux_bullet_sub "<issue-ref>    targeted run: dispatch this one issue instead of searching (see below)"
    ux_bullet_sub "--force        with <issue-ref> only: dispatch despite an excluded label"
    ux_bullet_sub "--cwd <PATH>   run the tick from PATH; relative watch-list paths resolve against it"
    ux_bullet_sub "--dry-run      print the issues this tick would dispatch, change nothing"
    ux_bullet_sub "               (takes no lock and does not evaluate the rate-limit gate)"
    ux_bullet_sub "--status       print the rate-limit gate state and exit; runs no tick"
    ux_bullet_sub "               (takes no lock, changes nothing, always exits 0)"
    ux_bullet_sub "               --status and --help are terminal: the first of the two"
    ux_bullet_sub "               on the line answers and exits, ignoring the rest"
    ux_bullet_sub "watch list                       print the watch list file and its entries"
    ux_bullet_sub "watch add [owner/repo] [--path P] [--host H]"
    ux_bullet_sub "                                 add or update an entry (default: current checkout)"
    ux_bullet_sub "watch remove [owner/repo]        drop an entry (default: current checkout)"
    ux_bullet_sub "label list                       print the excluded labels and their source"
    ux_bullet_sub "label add <label>...             exclude labels (absent file: seeded from the default)"
    ux_bullet_sub "label remove <label>...          stop excluding labels (an unlisted one only warns)"
    ux_bullet_sub "               writes keep a .bak-YYYYMMDD copy and unknown fields; broken JSON is left untouched"
    ux_bullet_sub "-h, --help, help   show this help"
    ux_bullet "cycle"
    ux_bullet_sub "gh search issues --assignee @me --state open   (one query per watched host)"
    ux_bullet_sub "excluded labels (exact match): \$IW_EXCLUDE_LABELS (comma-separated) > file > default"
    ux_bullet_sub "  file: \$IW_EXCLUDE_LABELS_FILE or excluded-labels.json next to the watch list (JSON array)"
    ux_bullet_sub "  default: ${_IW_EXCLUDE_LABELS_DEFAULT}"
    ux_bullet_sub "an issue with an OPEN blockedBy is skipped (query failure fails open)"
    ux_bullet_sub "an issue an open PR already closes is skipped (query failure skips the repo)"
    ux_bullet_sub "dispatch first reuses the wt/issue-<N>/* worktree, else runs gwt spawn --wt-name issue-<N>"
    ux_bullet_sub "  from the main checkout (no worktree -> no dispatch), then opens an"
    ux_bullet_sub "  iw-<repo>-issue-<N> tab (= the agent name) on it and runs /gh-flow:wave <N>"
    ux_bullet_sub "at most ${_IW_DISPATCH_PER_TICK} issue(s) per tick, ${_IW_MAX_ATTEMPTS} attempts each"
    ux_bullet_sub "no issue is ever written to — no comment, label or assignee change"
    ux_bullet "targeted run (<issue-ref>)"
    ux_bullet_sub "https://<host>/<owner>/<repo>/issues/<N>, <owner>/<repo>#<N>, #<N> or <N>"
    ux_bullet_sub "  (#<N> and <N>: the current checkout's origin repo)"
    ux_bullet_sub "repo: its watch-list entry, else the current checkout; neither -> watch add first"
    ux_bullet_sub "no search: reads that issue with gh issue view; not OPEN or unreadable -> exit 1"
    ux_bullet_sub "an excluded label refuses (exit 1) unless --force"
    ux_bullet_sub "running tab, open PR, open blocker, caps, gate and lock apply as in a tick (skip: exit 0)"
    ux_bullet_sub "the round-robin cursor and the saturation counter are left untouched"
    ux_bullet "concurrency"
    ux_bullet_sub "an issue-<N> (by hand) or iw-<repo>-issue-<N> (by the tick) tab with a live agent"
    ux_bullet_sub "  in the repo's workspace means that issue is running"
    ux_bullet_sub "  repos sharing a path: iw-<repo>-issue-<N> holds only its repo, issue-<N> holds all"
    ux_bullet_sub "${_IW_MAX_CONCURRENT} running in total holds the tick (exit 0); ${_IW_MAX_PER_REPO} in one repo skips that repo"
    ux_bullet_sub "repos take turns (round-robin); within a repo the lowest issue number goes first"
    ux_bullet_sub "cleanup is manual: after review, /exit, gwt teardown, close the tab"
    ux_bullet "watch list"
    ux_bullet_sub "${_IW_REPOS_FILE_DEFAULT}"
    ux_bullet_sub "override with \$IW_WATCHED_REPOS; entries are {repo, path, host}"
    ux_bullet_sub "cwd mode: no --cwd, run inside a checkout with an origin remote"
    ux_bullet_sub "  -> that repo only, the file is not read (cron passes --cwd or starts in \$HOME)"
    ux_bullet "state"
    ux_bullet_sub "\${XDG_STATE_HOME:-\$HOME/.local/state}/${_IW_STATE_SUBDIR}/${_IW_LIMIT_STATE_BASENAME}   (rate-limit gate)"
    ux_bullet_sub "\${XDG_STATE_HOME:-\$HOME/.local/state}/${_IW_STATE_SUBDIR}/${_IW_SELECT_STATE_BASENAME}       (round-robin cursor; absent = start at the first repo)"
    ux_bullet_sub "\${XDG_STATE_HOME:-\$HOME/.local/state}/${_IW_STATE_SUBDIR}/${_IW_SATURATION_STATE_BASENAME}   (saturation counter; absent = no episode)"
    ux_bullet "rate-limit gate"
    ux_bullet_sub "a dispatch is judged only once its prompt is confirmed submitted"
    ux_bullet_sub "healthy means its agent still holds 'working' ${_IW_LIMIT_OBSERVE_SEC}s later"
    ux_bullet_sub "${_IW_LIMIT_STRIKES} ticks in a row where no dispatched agent does close the gate"
    ux_bullet_sub "a prompt that never reached the pane leaves the gate exactly as it was"
    ux_bullet_sub "a strike logs the pane tail as evidence — pane text never opens or closes the gate"
    ux_bullet_sub "while closed the tick holds: no prompt, no tab, exit 0"
    ux_bullet_sub "it reopens by itself after $((_IW_LIMIT_BACKOFF_SECONDS / 60))m — delete ${_IW_LIMIT_STATE_BASENAME} to reopen it now"
    ux_bullet "saturation alert"
    ux_bullet_sub "${_IW_SATURATION_ALERT_TICKS} consecutive ticks that dispatch nothing because the caps are full raise one herdr notification"
    ux_bullet_sub "the body lists every occupied issue and its agent status — read it before reaching for a cause"
    ux_bullet_sub "it stays quiet for $((_IW_SATURATION_COOLDOWN_SECONDS / 3600))h afterwards while the state persists"
    ux_bullet_sub "a tick that dispatches clears the counter; a tick with no candidates leaves it alone"
    ux_bullet_sub "cause-blind by design — it fires on the symptom, whatever caused it"
    ux_bullet "claude session (claude-yolo parity)"
    ux_bullet_sub "each pane runs claude --dangerously-skip-permissions (unattended cron)"
    ux_bullet_sub "internal setup mode  → CLAUDE_CONFIG_DIR=\$HOME/.claude"
    ux_bullet_sub "otherwise            → CLAUDE_CONFIG_DIR=\$HOME/.claude-\${CLAUDE_DEFAULT_ACCOUNT:-personal}"
    ux_bullet_sub "  (that account must be listed in \$CLAUDE_ENABLED_ACCOUNTS)"
    ux_bullet_sub "no \$CLAUDE_ENABLED_ACCOUNTS and no \$CLAUDE_DEFAULT_ACCOUNT → \$HOME/.claude if it exists"
    ux_bullet_sub "the resolved directory must already exist — the tick fails fast otherwise"
    ux_bullet_sub "it must also hold a parseable .credentials.json — a logged-out account stalls every prompt"
    ux_bullet "crontab"
    ux_bullet_sub "*/4 * * * * /path/to/avatar_issue_watcher.sh >> ~/.local/state/avatar-issue-watcher/cron.log 2>&1"
}

# The guards a tick and a targeted run both pass before they select: 0 to go
# on, 1 to hold (the caller then exits or returns 0, as nothing was wrong).
#
# The dry run answers ahead of the lock and the gate, and deliberately so.
# Taking the lock would make a dry run silently no-op while a real tick is
# mid-cycle — exactly when a human is most likely to be asking what the watcher
# sees — and evaluating the gate would *clear* an expired `rate-limit.json`,
# which is a state change in a mode documented as changing nothing
# (PR #1447 codex/agy review).
_iw_tick_guards() {
    if [ "${_IW_DRY_RUN}" -eq 1 ]; then
        # A dry run must stay usable where a real tick cannot run at all, so an
        # unreachable herdr degrades to "nothing is running" here instead of
        # holding the tick.
        if ! _iw_live_agents >/dev/null; then
            _iw_live_agents_assume_none
            ux_warning "Cannot list herdr agents — reporting as if nothing were running."
        fi
        return 0
    fi

    _iw_acquire_lock || return 1

    # Before any tab is opened: a closed gate must cost nothing.
    _iw_limit_gate_check || return 1

    # Primed here, in the tick's own shell, so the subshells below inherit a
    # warm cache — the same reason the watch list is primed above. Failure is
    # terminal for the tick: "how many are running" has no safe default, and
    # guessing "none" would lift the concurrency cap exactly when herdr is
    # unhealthy (issue #1453, Error Cases).
    if ! _iw_live_agents >/dev/null; then
        ux_warning "Cannot list herdr agents — holding this tick rather than dispatching blind."
        return 1
    fi

    # Before the concurrency ceiling, not just before _iw_select_candidates
    # (PR #1622 codex review), and only on the tick that reopened the gate
    # (issue #1604).
    #
    # A casualty's own pane is routinely what fills the last slot: its session
    # died with the quota but its issue is still OPEN, and the zombie reclaim
    # above only collects panes whose issue is CLOSED — so that slot is never
    # given back. Leaving the retry behind the ceiling therefore starves
    # precisely the issue the ceiling is full *because of*, on every tick,
    # forever. And the cheap path the retry takes in that very case is a
    # re-prompt into the surviving pane, which opens no session and consumes no
    # slot at all, so the ceiling has no claim on it to begin with.
    #
    # It still has to run before the selector, which round-robins: asking that
    # first would hand this tick's slot to whichever issue is next in the queue
    # and leave the one the outage killed waiting for a turn that never comes.
    if [ "${_IW_LIMIT_GATE_REOPENED}" -eq 1 ]; then
        _iw_limit_retry_casualties

        # The retry's missing-pane fallback goes through _iw_process_issue,
        # which opens a real tab and a real pane — neither of which the memo
        # primed above can know about. Everything downstream that
        # spends a slot — the ceiling check below, _iw_dispatch_budget inside
        # the selector — would otherwise admit fresh work against a count taken
        # before the retry and overshoot _IW_MAX_CONCURRENT.
        _IW_LIVE_AGENTS=""
        _IW_LIVE_AGENTS_LOADED=0

        # Re-primed here in the tick's own shell for both reasons the first
        # priming gives: the subshells below must inherit a warm cache instead
        # of paying a herdr round trip apiece, and a lookup that fails now is
        # as terminal as one that failed then — an unknown count must never be
        # read as "nothing running".
        if ! _iw_live_agents >/dev/null; then
            ux_warning "Cannot list herdr agents after the casualty retry — holding this tick rather than dispatching blind."
            return 1
        fi
    fi
}

# ============================================================
# Targeted run — one named issue instead of the search
# ============================================================

# Dispatch <host> <owner/repo> <number> (host/repo may be empty, see
# _iw_parse_issue_ref) through the same guards and _iw_process_issue path a tick
# uses. $4 is --force (1/0), $5 the current checkout's `_iw_cwd_entry` line or
# empty. Exit 1 only for a hard error (repo unresolvable, issue unreadable or not
# OPEN, excluded label without --force, a failed dispatch); a guard that skips
# the issue answers 0, as a tick that dispatches nothing does.
#
# Never advances the round-robin cursor (_IW_TARGETED) and never touches the
# saturation counter: one named issue says nothing about whose turn it is or
# whether the caps are starving the backlog.
_iw_targeted_run() {
    local _url_host="$1" _repo="$2" _number="$3" _force="$4" _cwd_entry="$5"
    local _path _host _errf _json _cause _state _hit _candidates _live _rc _confirmed=""

    # The watch list wins; the current checkout is the fallback. Appended to the
    # cached list (never replacing it) so the casualty retry below still sees
    # every watched repo instead of dropping their rows as "no longer watched".
    _iw_watch_list >/dev/null
    if [ -n "${_cwd_entry}" ] && [ -z "$(_iw_repo_path "${_cwd_entry%%"${_IW_TAB}"*}")" ]; then
        _IW_WATCH_LIST="${_IW_WATCH_LIST:+${_IW_WATCH_LIST}
}${_cwd_entry}"
    fi

    if [ -z "${_repo}" ]; then
        if [ -z "${_cwd_entry}" ]; then
            ux_error "#${_number} names no repo and the current directory is no checkout with a usable origin."
            ux_info "Run it inside the checkout, or pass <owner>/<repo>#${_number}."
            return 1
        fi
        _repo="${_cwd_entry%%"${_IW_TAB}"*}"
    fi

    _path=$(_iw_repo_path "${_repo}")
    if [ -z "${_path}" ]; then
        ux_error "${_repo} is neither on the watch list nor the current checkout."
        ux_info "Run: avatar-issue-watcher watch add ${_repo} --path P"
        return 1
    fi
    _host=$(_iw_repo_host "${_repo}")
    if [ -n "${_url_host}" ] && [ "${_url_host}" != "${_host}" ]; then
        ux_error "${_repo}: the URL names host ${_url_host}, but its entry uses ${_host}."
        return 1
    fi
    if [ ! -d "${_path}" ]; then
        ux_error "${_repo} maps to a missing path (${_path})."
        return 1
    fi

    # gh's stderr kept for the error line, beside the state file as in
    # _iw_search_issues (no mktemp in the tick).
    _errf=$(_iw_state_dir)
    mkdir -p "${_errf}" 2>/dev/null || true
    _errf="${_errf}/issue-view.err.$$"
    { : >"${_errf}"; } 2>/dev/null || _errf="/dev/null"
    _rc=0
    _json=$(GH_HOST="${_host}" gh issue view "${_number}" --repo "${_repo}" \
        --json number,state,labels </dev/null 2>"${_errf}") || _rc=$?
    _cause=$(head -n 1 "${_errf}" 2>/dev/null)
    [ "${_errf}" = "/dev/null" ] || rm -f "${_errf}"
    _state=""
    [ "${_rc}" -ne 0 ] || _state=$(printf '%s' "${_json}" | jq -r '.state // empty' 2>/dev/null)
    if [ -z "${_state}" ]; then
        ux_error "Cannot read ${_repo}#${_number} on ${_host}${_cause:+: ${_cause}}"
        return 1
    fi
    if [ "${_state}" != "OPEN" ]; then
        ux_error "${_repo}#${_number} is ${_state} — only an OPEN issue is dispatched."
        return 1
    fi

    # The excluded labels it carries, by name, so the error can list them.
    _iw_exclude_labels_resolve
    _hit=$(printf '%s' "${_json}" | jq -r --arg ex "${_IW_EXCL_SET}" \
        '($ex | split("\u001f")) as $x | [.labels[]?.name | select(. as $n | any($x[]; . == $n))] | join(", ")' 2>/dev/null)
    if [ -n "${_hit}" ]; then
        if [ "${_force}" -ne 1 ]; then
            ux_error "${_repo}#${_number} carries an excluded label (${_hit}) — not dispatching."
            ux_info "Pass --force to dispatch it anyway."
            return 1
        fi
        ux_warning "${_repo}#${_number} carries an excluded label (${_hit}) — dispatching anyway (--force)."
    fi

    _iw_tick_guards || return 0

    _live=$(_iw_live_count)
    if [ "${_live}" -ge "${_IW_MAX_CONCURRENT}" ]; then
        ux_info "Holding ${_repo}#${_number} — ${_live} issue session(s) already running (max ${_IW_MAX_CONCURRENT})."
        return 0
    fi

    # The selector with a one-line candidate list: per-repo cap, open-PR
    # (fail-closed), running tab and blockedBy, each with its own Skipping line.
    _candidates=$(_iw_select_candidates "${_repo}${_IW_TAB}${_number}")
    if [ -z "${_candidates}" ]; then
        ux_info "Not dispatching ${_repo}#${_number}."
        return 0
    fi

    if [ "${_IW_DRY_RUN}" -eq 1 ]; then
        ux_success "Dry run — would dispatch:"
        ux_bullet "${_repo}#${_number}  (${_path}, ${_host})"
        return 0
    fi

    _iw_ensure_config_dir
    _rc=0
    _iw_process_issue "${_repo}" "${_number}" "${_path}" || _rc=$?
    [ "${_rc}" -ne 0 ] ||
        _confirmed="$(_iw_agent_name "${_repo}" "${_number}")${_IW_TAB}${_repo}${_IW_TAB}${_number}
"
    _iw_limit_record "${_confirmed}"
    # Any failed dispatch (rc 1 or 2) is a non-zero exit: the user asked for this one.
    [ "${_rc}" -eq 0 ] || return 1
    return 0
}

# ============================================================
# Main
# ============================================================

main() {
    local _cwd="" _repo _number _path _host _rc _dispatched=0 _skipped=0 _failed=0 _candidates _live _select_rc
    local _confirmed="" _ref="" _parsed="" _force=0 _ref_host _cwd_entry

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
        watch)
            # Terminal like --status, and ahead of the gh/herdr checks for the
            # same reason: it only edits a local file (#2243).
            shift
            if [ -n "${_cwd}" ] && ! cd "${_cwd}"; then
                ux_error "Cannot cd to --cwd ${_cwd}."
                exit 1
            fi
            _rc=0
            _iw_watch_cmd "$@" || _rc=$?
            exit "${_rc}"
            ;;
        label)
            # Terminal like `watch`: a local-file edit, ahead of gh/herdr.
            shift
            _rc=0
            _iw_label_cmd "$@" || _rc=$?
            exit "${_rc}"
            ;;
        --force)
            _force=1
            shift
            ;;
        -*)
            ux_error "Unknown option: $1"
            ux_info "Run 'avatar_issue_watcher.sh --help' for usage."
            exit 1
            ;;
        *)
            if [ -z "$1" ]; then
                ux_error "Not an issue reference: (empty)"
                exit 1
            fi
            if [ -n "${_ref}" ]; then
                ux_error "One issue reference per run — got ${_ref} and $1."
                exit 1
            fi
            _ref="$1"
            shift
            ;;
        esac
    done

    # Parsed ahead of every gh/herdr check: a typo needs no network to report.
    if [ -n "${_ref}" ]; then
        if ! _parsed=$(_iw_parse_issue_ref "${_ref}"); then
            ux_error "Not an issue reference: ${_ref}"
            ux_info "Use https://<host>/<owner>/<repo>/issues/<N>, <owner>/<repo>#<N>, #<N> or <N>."
            exit 1
        fi
    elif [ "${_force}" -eq 1 ]; then
        ux_error "--force only applies to a targeted run — pass an issue reference with it."
        exit 1
    fi

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
    # arrays of objects, and the flat-key fallback _hp_json_value uses for the
    # single-value herdr responses cannot walk those. Refusing loudly beats
    # dispatching against a half-parsed candidate set.
    if ! command -v jq >/dev/null 2>&1; then
        ux_error "jq not found in PATH — cannot parse the issue search or the watch list."
        ux_info "Install jq, or add it to the cron PATH."
        exit 1
    fi

    # The candidate-selection ops run in Python (#2157); the jq rollback is gone
    # (#2173), so without python3 >= 3.10 (RHEL 8 ships 3.6) there is no way to
    # pick a candidate. Refusing loudly beats a tick that silently selects nothing.
    if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))' >/dev/null 2>&1; then
        ux_error "python3 (>= 3.10) not found in PATH — cannot run the candidate selection."
        ux_info "Install python3 >= 3.10, or add it to the cron PATH."
        exit 1
    fi

    # A dry run reports what it would dispatch and touches nothing, so it must
    # stay usable on a machine with no herdr server.
    if [ "${_IW_DRY_RUN}" -eq 0 ] && ! command -v herdr >/dev/null 2>&1; then
        ux_error "herdr not found in PATH — cannot run the issue-watcher tick."
        ux_info "Install it via ./herdr/setup.sh, or add it to the cron PATH."
        exit 1
    fi

    # Targeted run: one named issue, no search. The checkout at the (possibly
    # --cwd) directory is only a fallback for repo resolution, so an origin it
    # cannot parse is not an error here unless the reference needs it.
    if [ -n "${_parsed}" ]; then
        _IW_TARGETED=1
        _cwd_entry=$(_iw_cwd_entry 2>/dev/null) || _cwd_entry=""
        _ref_host="${_parsed%%"${_IW_TAB}"*}"
        _parsed="${_parsed#*"${_IW_TAB}"}"
        _rc=0
        _iw_targeted_run "${_ref_host}" "${_parsed%%"${_IW_TAB}"*}" "${_parsed#*"${_IW_TAB}"}" \
            "${_force}" "${_cwd_entry}" || _rc=$?
        exit "${_rc}"
    fi

    # cwd mode (#2243): no --cwd, and the current directory is a checkout with
    # an origin remote -> watch that repo only and never read the watch list.
    # An origin that cannot be parsed is an error, not a fall-back to the file:
    # the caller clearly meant this repo.
    if [ -z "${_cwd}" ]; then
        _rc=0
        _IW_CWD_ENTRY=$(_iw_cwd_entry) || _rc=$?
        if [ "${_rc}" -eq 2 ]; then
            ux_error "cwd mode: cannot read owner/repo from origin URL: ${_IW_CWD_ENTRY}"
            ux_info "Fix the origin remote, or pass --cwd to use the watch list."
            exit 1
        fi
        [ "${_rc}" -eq 0 ] || _IW_CWD_ENTRY=""
    fi

    if [ -n "${_IW_CWD_ENTRY}" ]; then
        ux_info "cwd mode — watching ${_IW_CWD_ENTRY%%"${_IW_TAB}"*} only (watch list not read)."
    elif [ ! -f "$(_iw_repos_file)" ]; then
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

    # herdr agent names carry the repo basename and neither the host nor the
    # owner (herdr_agent_name.sh), so two watched repos ending in the same
    # segment — `acme/dotfiles` and `other/dotfiles` — share `iw-<repo>-issue-
    # <N>` and the second dispatch's prompt lands in the first one's pane. This
    # list is untracked and user-editable, so no review or lint stands between
    # a second entry and that collision; advisory only, the tick continues
    # either way (#1552).
    #
    # Slug through herdr_agent_repo_slug — the same lower-case/normalize/
    # truncate-to-16 pass herdr_agent_name uses to build the real agent name —
    # rather than a raw basename cut, so this check tracks the actual
    # collision condition instead of a looser stand-in for it.
    local _iw_dup
    _iw_dup=$(
        _iw_watch_list | while IFS="${_IW_TAB}" read -r _repo _path _host; do
            herdr_agent_repo_slug "${_repo}" && printf '\n'
        done | sort | uniq -d
    )
    if [ -n "${_iw_dup}" ]; then
        ux_warning "watch list has repos sharing a basename (${_iw_dup}) — herdr agent names collide (see herdr_agent_name.sh)." >&2
    fi

    _iw_tick_guards || exit 0

    if [ "${_IW_DRY_RUN}" -eq 1 ]; then
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

    _live=$(_iw_live_count)
    if [ "${_live}" -ge "${_IW_MAX_CONCURRENT}" ]; then
        ux_info "Holding this tick — ${_live} issue session(s) already running (max ${_IW_MAX_CONCURRENT})."
        # Unconditionally a saturated tick: nothing was dispatched and the total
        # cap is the only reason.
        _iw_saturation_tick 1
        exit 0
    fi

    _candidates=$(_iw_select_candidates "$(_iw_collect_candidates)")
    _select_rc=$?

    # Saturated only when some repo that had work sat at its own per-repo cap
    # (F-1) — that is the one fact `_select_rc == 2` certifies. A tick with
    # nothing queued and no cap hit is *also* evidence dispatch isn't blocked
    # by full slots right now, so it clears an in-progress episode the same
    # as an actual dispatch does (F-4): keying the clear on "did a cap block
    # anything" rather than "did a candidate happen to exist" is what stops a
    # resolved episode from lingering in `--status` for as long as the
    # backlog stays empty (PR #1624 review, agy FOLLOW-UP + codex Assumption).
    if [ "${_select_rc}" -eq 2 ]; then
        _iw_saturation_tick 1
    else
        _iw_saturation_tick 0
    fi

    if [ -z "${_candidates}" ]; then
        ux_info "No dispatchable issue this tick."
        exit 0
    fi

    # Resolved once for the whole tick (memoized — see _iw_ensure_config_dir):
    # every pane it opens shares one account, which is also what lets the
    # rate-limit gate read one pane's stall as evidence about the quota
    # behind all of them.
    _iw_ensure_config_dir

    # fd 3, not stdin: the loop body runs `gh` and `herdr`, either of which
    # may read stdin and would otherwise swallow the rest of the candidate list,
    # silently shortening the cycle (PR #1447 agy review).
    while IFS="${_IW_TAB}" read -r _repo _number _path _host <&3; do
        [ -n "${_repo}" ] || continue

        _rc=0
        _iw_process_issue "${_repo}" "${_number}" "${_path}" || _rc=$?

        if [ "${_rc}" -eq 0 ]; then
            _dispatched=$((_dispatched + 1))
            # Confirmed submitted, so this pane is a valid witness for the
            # quota — collected here, judged after the loop. The issue travels
            # with the agent name (#1604): when the judgment comes back a
            # strike, the gate has to be able to name what it killed, and this
            # is the only point where both halves are in scope.
            _confirmed="${_confirmed}$(_iw_agent_name "${_repo}" "${_number}")${_IW_TAB}${_repo}${_IW_TAB}${_number}
"
        elif [ "${_rc}" -eq 2 ]; then
            _skipped=$((_skipped + 1))
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
        ux_error "Tick complete — 0 dispatched, ${_skipped} skipped, ${_failed} failed."
        exit 1
    fi

    if [ "${_dispatched}" -eq 0 ] && [ "${_skipped}" -gt 0 ]; then
        ux_warning "Tick complete — 0 issue(s) dispatched, ${_skipped} skipped, 0 failed."
    else
        ux_success "Tick complete — ${_dispatched} issue(s) dispatched, ${_skipped} skipped, ${_failed} failed."
    fi
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
