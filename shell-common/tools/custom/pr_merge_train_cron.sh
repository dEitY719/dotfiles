#!/bin/bash
# shell-common/tools/custom/pr_merge_train_cron.sh
# merge-train cron 디스패처 — 1회 tick (issue #1470).
#
# cron 이 주기마다 이 스크립트를 호출하면 tick 1회를 수행한다. tick 은 train 을
# 직접 돌리지 않는다 — 선행 조건 3개만 확인하고 claude 세션 하나를 띄운 뒤 끝난다:
#   1) 이번 tick 이 유일한 tick 인가 (flock)
#   2) 직전 tick 이 띄운 train 세션이 아직 살아 있는가 (herdr agent get)
#   3) 깨울 만한 대상 PR 이 있는가 (`gh pr list --author @me` + 스킬과 공유하는
#      필터 `_gh_pr_merge_train_filter_targets`: draft / `reply-pending` 라벨 /
#      D-6 조용한 기간, #1524)
#   4) herdr workspace -> tab -> agent -> `/gh-pr-merge-train <owner/repo>`
#
# 이 파일에는 tick 의 선행 조건 판정만 있다 — 라우팅 표(D-1)·정렬(D-2)·시도
# 상한(F-5)·리포트(F-9)는 전부 스킬 쪽 텍스트이다. train 본체가 왜 셸이 아니라
# claude 세션인지(D-8), NF-1 이 왜 두 겹인지의 근거는 한 곳에만 둔다:
#   claude/skills/gh-pr-merge-train/references/cron-dispatcher.md
#
# GitHub 에 어떤 쓰기도 하지 않는다 — 머지·코멘트·라벨 변경 없음. 조회 전용이다.
#
# Usage: pr_merge_train_cron.sh [--cwd <PATH>] [--dry-run] | [-h|--help|help]

set -u

# Initialize common tools environment (DOTFILES_ROOT/SHELL_COMMON + ux_lib)
. "$(dirname "$0")/init.sh" || exit 1

# init.sh returns early under DOTFILES_TEST_MODE=1 (and before it exports
# SHELL_COMMON), so resolve shell-common from this script's own location as a
# fallback. ux_lib, gh_host.sh and the claude integration all load from here.
_PMT_SHELL_COMMON="${SHELL_COMMON:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Same early return means ux_* can still be undefined here — every output path
# below depends on it.
if ! type ux_header >/dev/null 2>&1; then
    if [ -f "${_PMT_SHELL_COMMON}/tools/ux_lib/ux_lib.sh" ]; then
        # shellcheck source=/dev/null
        . "${_PMT_SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
    fi
fi

# The target filter (draft / `reply-pending` / quiet period) and the quiet
# period itself, shared verbatim with the `gh:pr-merge-train` skill (#1524).
# A hard failure, not a degradation: counting targets *is* this tick's job, and
# a dispatcher that guessed the filter would be the duplicated-logic bug #1524
# removed. Same precedent as the gh_host.sh check in _pmt_bind_target.
if [ ! -f "${_PMT_SHELL_COMMON}/functions/gh_pr_merge_train.sh" ]; then
    ux_error "gh_pr_merge_train.sh not found under ${_PMT_SHELL_COMMON}/functions — cannot filter target PRs."
    exit 1
fi
# shellcheck source=/dev/null
. "${_PMT_SHELL_COMMON}/functions/gh_pr_merge_train.sh" || exit 1

# ============================================================
# Constants (SSOT for the dispatcher)
# ============================================================

_PMT_STATE_SUBDIR="pr-merge-train"
_PMT_LOCK_BASENAME=".lock"

# D-6 — the quiet period is NOT a constant here. Its SSOT, together with the
# whole target filter (draft / `reply-pending` label / quiet period), is
# `shell-common/functions/gh_pr_merge_train.sh` — sourced below and called by
# both this dispatcher and the `gh:pr-merge-train` skill, so the two can no
# longer disagree (issue #1524). Read
# `_gh_pr_merge_train_quiet_minutes` when the number is needed for output.
#
# The dispatcher and the skill run the same filter for different purposes: the
# dispatcher only has to answer "is there anything worth waking a session for",
# while the skill re-applies it authoritatively at the moment it processes each
# PR, because minutes pass between this count and that decision.
#
# This filter also excludes the PR that just triggered Step 2.4.1's immediate
# wake call (claude/skills/gh-issue-flow/references/merge-train-wake.md) — its
# updatedAt is "just now", so it can't be its own tick's target. That doc
# documents the resulting ~11-16min real latency for the triggering PR
# (issue #1515). Still true post-#1524: the filter itself moved to
# `_gh_pr_merge_train_filter_targets`, but a brand-new PR's `updatedAt` is
# still "just now" no matter which code evaluates it.

# Upper bound on the open-PR window. The dispatcher only needs "more than
# zero", so this is a courtesy cap, not a correctness boundary.
_PMT_PR_LIMIT="50"

# herdr agent naming. One train per repo, so the name is deterministic and
# derived from the repo alone — that is what lets the *next* tick find the
# session this tick started (see _pmt_train_state). Composed by
# `herdr_agent_name`, the SSOT this file shares with issue_watcher_cron.sh and
# gh:pr-post-merge-verify (#1530); the prefix carries no trailing dash because
# the helper joins the parts. Pre-#1530 this was `pmt-` over a host-qualified
# slug, which produced `pmt-github.com-<owner>-<repo>` — a name herdr rejects
# outright (dot, and uppercase from a real owner), so the train never started
# once in 56 attempts. Dropping the host is the concession that buys the
# 32-character budget; the rationale and its expiry condition live in
# shell-common/functions/herdr_agent_name.sh.
#
# The prefix also keeps the *workspace label* — the same string since #1549 —
# clear of issue_watcher_cron.sh, which labels its workspaces with the bare
# checkout basename (`dotfiles`). Drop the `mt` and the train lands in
# issue-watcher's tabs (#1470, Impact); that collision surfaces as panes opening
# in the wrong workspace, not as a test failure.
_PMT_AGENT_PREFIX="mt"

# `herdr agent prompt --wait` 한 번의 상한 — 4분. train 자체는 수십 분을 돌 수
# 있지만 `--wait` 는 프롬프트가 *접수* 될 때까지만 기다린다. tick 이 겹치지 않게
# 막는 것은 flock 이므로 이 값은 cron 주기와 무관하다.
_PMT_TIMEOUT_MS="240000"
# Post-start idle checks (see _pmt_wait_for_idle): at most 10 checks, this far
# apart. The gap is overridable so the bats suite does not pay it in real sleep
# on every cold-agent path. Neither value is the time a healthy launch waits —
# `herdr agent start` already answers `"agent_status":"idle"`, so the loop
# returns on its *first* poll and the elapsed time is ~0s. These two only bound
# the unhealthy case, where the agent never reports idle at all.
_PMT_IDLE_POLL_MAX="10"
_PMT_IDLE_POLL_SLEEP="${PMT_IDLE_POLL_SLEEP:-0.5}"

# Upper bound on the settle wait between `agent start` and the first prompt
# (issue #1560; a poll rather than a flat sleep since #1570); the twin of
# _IW_SETTLE_SECONDS, whose comment carries the rationale and the measurement
# in full — including why raising _PMT_IDLE_POLL_MAX instead is a no-op and why
# the pane's own text, not `agent_status`, is what ends the wait. Applied by
# _pmt_launch_fresh only — the reuse path prompts a session that has been up
# for a whole cron period and must not pay this per PR. Overridable (to 0) so
# the bats suite does not sleep for real.
#
# 13 is the repo-wide constant for "herdr just brought something up, wait
# before touching it" (#1571). Its four twins are _PMT_START_RETRY_SLEEP below,
# _IW_SETTLE_SECONDS / _IW_START_RETRY_SLEEP in issue_watcher_cron.sh, and
# PMV_SETTLE_SECONDS in
# claude/skills/gh-pr-post-merge-verify/references/dispatch.sh.md. Change one,
# change all five — #1530/#1549 and #1560/#1571 are both the same defect
# recurring because only two of the three dispatchers were fixed. The *number*
# is what those five share; since #1570 the two settle constants spend it as a
# poll cap while the three start-retry gaps are still flat sleeps, because only
# a settle has a pane to read.
_PMT_SETTLE_SECONDS="${PMT_SETTLE_SECONDS:-13}"
# Gap between settle polls, and how many pane lines each poll reads — the twins
# of _IW_SETTLE_POLL_SLEEP / _IW_SETTLE_READ_LINES, overridable (to 0) for the
# same reason _PMT_IDLE_POLL_SLEEP is.
_PMT_SETTLE_POLL_SLEEP="${PMT_SETTLE_POLL_SLEEP:-1}"
_PMT_SETTLE_READ_LINES="3"
# The pane text herdr shows while claude is up but unusable (#1561). Stable
# across reads, so the "two frames agree" test alone would take it for ready.
_PMT_SETTLE_NOT_READY_MARK="Not logged in"
_PMT_PROMPT_ATTEMPT_MAX="3"

# `herdr agent start` attempts on a freshly created pane (see _pmt_launch_fresh,
# issue #1512). A pane's shell is not interactive the instant `tab create`
# answers, so the start can be refused with `agent_pane_busy` — a timing race
# against a pane that is perfectly good a moment later. herdr rejects it
# immediately rather than waiting, so `--timeout` (which only extends the
# readiness wait) cannot help; another attempt can. Bounded at 3 because cron
# re-runs anyway: a tick that kept trying would hold the lock while the *next*
# tick is the one that should be deciding. Bounded in *attempts*, not retries,
# so the `attempt N/MAX` warning reads exactly true. The gap between them is
# overridable for the same reason _PMT_IDLE_POLL_SLEEP is — the bats suite pays
# no real sleep.
#
# The gap is 13s, not the 2s it shipped with (#1571): this is the *same* class
# of wait as _PMT_SETTLE_SECONDS above — herdr answered before the thing it
# brought up was usable — and 2s was shorter than the 5s already measured to
# fail. Its twins are _PMT_SETTLE_SECONDS above, _IW_SETTLE_SECONDS /
# _IW_START_RETRY_SLEEP in issue_watcher_cron.sh, and PMV_SETTLE_SECONDS in
# claude/skills/gh-pr-post-merge-verify/references/dispatch.sh.md; all five
# move together. The wait and this retry are complements, not substitutes — 13s
# shrinks the race, the retry survives what is left of it.
_PMT_START_ATTEMPT_MAX="3"
_PMT_START_RETRY_SLEEP="${PMT_START_RETRY_SLEEP:-13}"

# CLAUDE_CONFIG_DIR for the pane this tick opens. Resolved once, and only on
# the path that actually opens one (see _pmt_bind_config_dir).
_PMT_CONFIG_DIR=""
# The pane the train's agent starts on, and the tab holding it — both bound by
# _pmt_tab_create. Globals rather than a packed return value because that is
# this file's idiom for a helper with more than one result (cf. _PMT_REPO /
# _PMT_HOST, _PMT_CONFIG_DIR). The tab id is what orphan cleanup closes (#1512).
_PMT_PANE_ID=""
_PMT_TAB_ID=""
# The stderr capture file handed to _pmt_agent_start. Global, not local, so the
# EXIT/INT/TERM trap that removes it can still name it after the function that
# created it has returned — a `local` would be unset by then and `set -u` would
# turn the cleanup into its own error (PR #1517 review, agy).
_PMT_ERRF=""
# Set by --dry-run: report what the tick would do, mutate nothing.
_PMT_DRY_RUN=0
# The GitHub target, bound once in main() from the checkout's `origin` (#1403).
_PMT_REPO=""
_PMT_HOST=""

# ============================================================
# Helpers — state paths and JSON
# ============================================================

# Nested defaults on purpose: under `set -u`, `${XDG_STATE_HOME:-$HOME/...}`
# still aborts with "HOME: unbound variable" when HOME itself is unset (a cron
# environment can be that bare), so HOME is never referenced unguarded.
_pmt_state_dir() {
    printf '%s/%s' \
        "${XDG_STATE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.local/state}" \
        "${_PMT_STATE_SUBDIR}"
}

# Extract one string field from JSON on stdin.
#   $1 = jq filter, e.g. '.result.agent.agent_status'.
#
# jq-only, and deliberately so: main() refuses to run without jq (the PR list
# is an array of objects, which no flat-key text scanner can walk), so every
# caller here is downstream of that check. Always returns 0 — a malformed
# document reads as "no such field", which is what every caller treats it as.
_pmt_json_value() {
    jq -r "${1} // empty" 2>/dev/null || return 0
}

# First string value of a flat key anywhere in the document. `herdr tab create`
# and `herdr workspace create` both answer with a pane but nest it under
# different parents (`.result.pane` vs `.result.root_pane`), and the CLI is
# free to add another. Keying on the leaf name rather than the path keeps this
# working across both shapes.
#
# The key travels as a jq *argument*, never as interpolated program text.
_pmt_json_first() {
    jq -r --arg k "$1" \
        '[.. | objects | .[$k]? // empty] | map(select(type == "string")) | first // empty' \
        2>/dev/null || return 0
}

# Echo epoch seconds, or nothing when the clock is unreadable.
_pmt_now() {
    local _now
    _now=$(date +%s 2>/dev/null) || return 0
    case "${_now}" in
    '' | *[!0-9]*) return 0 ;;
    esac
    printf '%s' "${_now}"
}

# ============================================================
# Helpers — the GitHub target (#1403 / #1407)
# ============================================================

# Bind `_PMT_REPO` and `_PMT_HOST` from one and the same remote URL, so the
# dispatcher's single `gh` call cannot drift to another server. Returns
# non-zero (with the reason in the cron log) when the checkout has no usable
# remote — the tick must not guess a target. Assigns the globals rather than
# echoing them, so every diagnostic here can go straight to the log instead of
# competing with a value on stdout.
_pmt_bind_target() {
    local _remote_url

    if [ ! -f "${_PMT_SHELL_COMMON}/functions/gh_host.sh" ]; then
        ux_error "gh_host.sh not found under ${_PMT_SHELL_COMMON}/functions — cannot resolve the GitHub target."
        return 1
    fi
    # shellcheck source=/dev/null
    . "${_PMT_SHELL_COMMON}/functions/gh_host.sh" || return 1

    # The herdr name SSOT (#1530). Sourced next to gh_host.sh because both
    # answer the same question — what this tick's target is called — and a
    # missing one is the same class of failure.
    if [ ! -f "${_PMT_SHELL_COMMON}/functions/herdr_agent_name.sh" ]; then
        ux_error "herdr_agent_name.sh not found under ${_PMT_SHELL_COMMON}/functions — cannot derive the train's agent name."
        return 1
    fi
    # shellcheck source=/dev/null
    . "${_PMT_SHELL_COMMON}/functions/herdr_agent_name.sh" || return 1

    _remote_url=$(git remote get-url origin 2>/dev/null) || {
        ux_error "No 'origin' remote in ${PWD} — cannot resolve the merge-train target."
        ux_info "Run the tick with --cwd pointing at a checkout that has one."
        return 1
    }

    _PMT_REPO=$(_gh_parse_owner_repo_url "${_remote_url}" 2>/dev/null) || {
        ux_error "Cannot parse owner/repo from origin's URL: ${_remote_url}"
        return 1
    }
    _PMT_HOST=$(_gh_host_from_url "${_remote_url}" 2>/dev/null) || _PMT_HOST=$(_gh_resolve_host)
    [ -n "${_PMT_HOST}" ] || {
        ux_error "Cannot resolve the GitHub host for ${_remote_url} — refusing to run unpinned (#1403)."
        return 1
    }
}

# ============================================================
# Precondition 3 — are there PRs worth waking a session for
# ============================================================

# Echo the number of PRs this tick considers targets. Returns non-zero when
# GitHub could not be asked at all — the caller ends the tick rather than
# launching a train that would start by guessing (issue #1470, Error Cases:
# "상태를 모르는 채 머지하지 않는다").
#
# The `--author @me` scope is this function's own (D-7: a colleague's PR is
# never auto-merged). Everything else — drafts, the `reply-pending` label, and
# the D-6 quiet period — is `_gh_pr_merge_train_filter_targets`, the SSOT the
# `gh:pr-merge-train` skill runs too (#1524). `labels` is in the `--json` list
# for that filter's sake; nothing here reads it directly.
_pmt_target_count() {
    local _json _filtered _now

    _json=$(GH_HOST="${_PMT_HOST}" gh pr list --repo "${_PMT_REPO}" \
        --author @me --state open --limit "${_PMT_PR_LIMIT}" \
        --json number,updatedAt,isDraft,labels 2>/dev/null) || return 1
    [ -n "${_json}" ] || return 1

    _now=$(_pmt_now)
    # No clock means no defensible cutoff. Counting every PR as a target would
    # merge inside the quiet window; counting none would wedge the train
    # permanently. Refusing the tick is the only answer that does neither.
    # The filter takes the clock as an argument for exactly this reason — it
    # never reads `date` itself, so this decision stays here.
    [ -n "${_now}" ] || return 1

    _filtered=$(printf '%s' "${_json}" |
        _gh_pr_merge_train_filter_targets --now "${_now}") || return 1

    printf '%s' "${_filtered}" | jq -r 'length' 2>/dev/null || return 1
}

# ============================================================
# Preconditions 1-2 — one train at a time (NF-1)
# ============================================================

# Layer 1 of NF-1: this lock covers *ticks* only. It cannot cover the train,
# which outlives the tick that started it — that is _pmt_train_state's job.
# Why neither layer subsumes the other: `references/cron-dispatcher.md`.
_pmt_acquire_lock() {
    local _dir _lock
    _dir=$(_pmt_state_dir)
    _lock="${_dir}/${_PMT_LOCK_BASENAME}"

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
        ux_warning "another pr_merge_train_cron tick is already running — skip"
        return 1
    fi
}

# Echo the agent status (idle|working|blocked|done|unknown). Returns non-zero
# when herdr itself rejects the query — agent missing, or pane closed.
_pmt_agent_status() {
    local _json _rc=0
    _json=$(herdr agent get "$1" 2>/dev/null) || _rc=$?
    [ "${_rc}" -eq 0 ] || return 1
    printf '%s' "${_json}" | _pmt_json_value '.result.agent.agent_status'
}

# Classify the previously started train session. Echoes one of:
#   live     a train is still running — this tick must not start another (NF-1)
#   reuse    the agent still resolves, so prompt it in place instead of
#            stacking a second tab on top of it
#   fresh    no such agent — open a workspace/tab/agent from scratch
#
# The split that matters is "does `herdr agent get` still resolve the name",
# not "is the status one we recognise" — measured against a live herdr server:
#
#   pane destroyed  -> `agent get` fails with `agent_not_found`, the name is
#                      released, and `agent start` under the same name on a new
#                      pane succeeds. That is `fresh`, and correct.
#   agent resolves  -> the name is still held. `agent start` under it on a
#                      *different* pane fails with `agent_name_taken`, and a
#                      stale pane does not disappear by itself — so mapping a
#                      resolvable `done`/`unknown` agent to `fresh` would wedge
#                      every subsequent tick on the same collision.
#
# Hence anything that resolves but is not `working`/`blocked` is `reuse`: the
# name's holder is the only thing that can be prompted, and prompting an agent
# that turns out to be unpromptable costs one failed tick, not a permanent one.
_pmt_train_state() {
    local _status

    _status=$(_pmt_agent_status "$1") || {
        printf 'fresh'
        return 0
    }

    case "${_status}" in
    working | blocked) printf 'live' ;;
    *) printf 'reuse' ;;
    esac
}

# ============================================================
# Launch — herdr pane -> claude -> prompt (D-8)
# ============================================================

# CLAUDE_CONFIG_DIR for the train's pane (issue #571 / #1393). Same account
# routing as issue_watcher_cron.sh's `_iw_resolve_config_dir`, which carries the
# per-branch rationale in full; only the error wording differs here. Returns 2
# when HOME is unset (the caller degrades to no routing), 1 on a real failure.
_pmt_resolve_config_dir() {
    [ -n "${HOME:-}" ] || return 2

    (
        # Captured before claude.sh is sourced: the *caller's* environment is
        # what says whether the single-account fallback applies. A set-but-empty
        # CLAUDE_DEFAULT_ACCOUNT counts as explicitly set.
        _enabled="${CLAUDE_ENABLED_ACCOUNTS:-}"
        _default_set=0
        [ -z "${CLAUDE_DEFAULT_ACCOUNT+x}" ] || _default_set=1

        DOTFILES_FORCE_INIT=1
        export DOTFILES_FORCE_INIT

        # shellcheck source=/dev/null
        . "${_PMT_SHELL_COMMON}/tools/integrations/claude.sh" >&2 || {
            ux_error "Cannot load ${_PMT_SHELL_COMMON}/tools/integrations/claude.sh — CLAUDE_CONFIG_DIR unresolvable."
            exit 1
        }

        # Internal-PC single-account override: must run before account
        # resolution — an empty CLAUDE_ENABLED_ACCOUNTS must not fail the tick.
        if [ "$(_dotfiles_setup_mode)" = "internal" ]; then
            _cfg_dir="$HOME/.claude"
        else
            _account="${CLAUDE_DEFAULT_ACCOUNT:-personal}"
            _cfg_dir=$(_claude_resolve_account "${_account}") || {
                # Pre-#1393 single-account user. ux_* is redirected because
                # this subshell reserves stdout for the resolved path.
                if [ -z "${_enabled}" ] && [ "${_default_set}" -eq 0 ] &&
                    [ -d "$HOME/.claude" ]; then
                    ux_warning "CLAUDE_ENABLED_ACCOUNTS not configured — falling back to \$HOME/.claude (single-account mode)." >&2
                    ux_info "Run 'claude-accounts setup' to opt into multi-account routing." >&2
                    printf '%s' "$HOME/.claude"
                    exit 0
                fi
                ux_error "Unknown claude account: ${_account} — cannot set CLAUDE_CONFIG_DIR for the merge-train pane."
                ux_info "Available: $(_claude_resolve_account --list | tr '\n' ' ')" >&2
                exit 1
            }
        fi

        if [ ! -d "${_cfg_dir}" ]; then
            ux_error "Claude account directory missing: ${_cfg_dir} — cannot bootstrap the merge-train pane."
            ux_info "Run: claude-accounts setup" >&2
            exit 1
        fi

        # A directory that exists is not an account that is logged in
        # (issue #1561) — `_claude_account_logged_in` in claude.sh, sourced
        # above, carries the rationale in full and owns the rule.
        if ! _claude_account_logged_in "${_cfg_dir}"; then
            ux_error "Claude account not logged in: ${_cfg_dir}/.credentials.json is missing, empty, or not valid JSON — the pane would open on 'Not logged in' and every prompt would stall."
            ux_info "Run: claude-accounts status   (then log that account in)" >&2
            exit 1
        fi

        printf '%s' "${_cfg_dir}"
    )
}

# Set _PMT_CONFIG_DIR for this tick's pane. Returns non-zero only for a real
# routing failure; an unset HOME degrades to "no routing" with a warning,
# because a pane without account routing still beats no train at all.
_pmt_bind_config_dir() {
    _PMT_CONFIG_DIR=$(_pmt_resolve_config_dir)
    case "$?" in
    0) return 0 ;;
    2)
        _PMT_CONFIG_DIR=""
        ux_warning "HOME is unset — starting claude without CLAUDE_CONFIG_DIR account routing."
        return 0
        ;;
    esac
    return 1
}

_pmt_herdr_create() {
    local _cwd="$1" _label="$2"
    shift 2

    set -- "$@" --cwd "${_cwd}" --label "${_label}" --no-focus
    [ -z "${_PMT_CONFIG_DIR}" ] || set -- "$@" --env "CLAUDE_CONFIG_DIR=${_PMT_CONFIG_DIR}"

    herdr "$@" 2>/dev/null
}

# Echo the workspace id whose label is <1>, creating it against cwd <2> when no
# such workspace exists. Label-matched rather than persisted: the herdr server
# is the SSOT for what is open, and a state file would only drift from it.
_pmt_workspace_for_label() {
    local _label="$1" _cwd="$2" _json _ws

    _json=$(herdr workspace list 2>/dev/null) || _json=""
    _ws=$(printf '%s' "${_json}" | jq -r --arg l "${_label}" '
        [ .result.workspaces[]? | select(.label == $l) | .workspace_id ] | first // empty
    ' 2>/dev/null) || _ws=""

    if [ -n "${_ws}" ]; then
        printf '%s' "${_ws}"
        return 0
    fi

    _json=$(_pmt_herdr_create "${_cwd}" "${_label}" workspace create) || _json=""
    _ws=$(printf '%s' "${_json}" | _pmt_json_first workspace_id)
    [ -n "${_ws}" ] || return 1
    printf '%s' "${_ws}"
}

# Open the train's tab, binding _PMT_PANE_ID and _PMT_TAB_ID. Nothing here used
# to need the `tab_id` — the agent is addressed by pane, and the *next* tick
# finds this session by agent name, not by tab. Orphan cleanup is what needs it
# now (#1512): when no agent can be started on this pane the caller closes the
# tab it just opened, so a cron period that fails stops leaving a dead tab
# behind on every tick.
#
# The pane id is required; the tab id is not, so a response that omits it
# leaves _PMT_TAB_ID empty rather than failing the tab creation.
_pmt_tab_create() {
    local _ws="$1" _cwd="$2" _label="$3" _json

    _json=$(_pmt_herdr_create "${_cwd}" "${_label}" tab create --workspace "${_ws}") || return 1

    _PMT_PANE_ID=$(printf '%s' "${_json}" | _pmt_json_first pane_id)
    [ -n "${_PMT_PANE_ID}" ] || return 1
    _PMT_TAB_ID=$(printf '%s' "${_json}" | _pmt_json_first tab_id)
}

# Best-effort close of a tab this tick opened but could never put an agent on.
# The workspace had collected 40+ of these before #1512, one per cron period,
# because the start failure returned without touching the pane it had just
# been handed. Never changes the tick's verdict: the tick has already failed,
# and a herdr that cannot close the tab is not a second, different failure to
# report. A missing tab id is a no-op, not an error.
#
# Raw `herdr`, not _pmt_herdr_create: that wrapper exists to append the
# pane-*creation* flags (--cwd/--label/--no-focus/--env CLAUDE_CONFIG_DIR),
# and `herdr tab close` takes a bare positional tab id and rejects options.
# The account routing it carries is for the claude process a new pane starts,
# not for herdr's own connection, so closing a tab by id needs none of it —
# same reason `agent get`, `workspace list` and `agent prompt` all call herdr
# directly (PR #1517 review, codex).
_pmt_tab_close() {
    local _tab="$1"

    [ -n "${_tab}" ] || return 0
    herdr tab close "${_tab}" >/dev/null 2>&1 ||
        ux_warning "Could not close orphaned tab ${_tab} — close it by hand if it lingers."
    return 0
}

# `-- ARG...` is passed through to the pane's claude invocation. Echoes herdr's
# response so the caller can read `.error.code`; returns herdr's exit status.
#
# `--dangerously-skip-permissions` is required, not a convenience: nobody is at
# the keyboard of a cron pane, so a single permission prompt would park the
# train forever instead of failing it (same reason issue_watcher_cron.sh passes
# it, #1393). What it grants *here* is broader than there, and worth stating:
# this session merges PRs, so the flag lets it run `gh pr merge` and the
# rebase/CI-fix atoms without stopping to ask. Two things bound it — NF-2
# forbids the train from ever calling `gh:pr-merge-emergency`, so the platform's
# own protections stay in force, and the approval gate (D-5, `approval-gate.md`)
# is fail-closed, so an unreadable policy skips the PR rather than merging it.
#
# stderr goes to the file named by $3 rather than /dev/null (#1512, same defect
# class as #1458): herdr is free to answer on either stream and in cron it
# answers on stderr, so discarding it threw away the one sentence that named
# the failure — `agent_pane_busy`. stdout stays on the pipe because the caller
# reads `.error.code` off it, which is why this is a file and not a `2>&1`.
_pmt_agent_start() {
    herdr agent start "$1" --kind claude --pane "$2" \
        -- --dangerously-skip-permissions 2>"$3"
}

# Echo the herdr error code behind a failed call: <1> is herdr's stdout, <2>
# the file its stderr was captured to. stdout first, stderr as the fallback.
# Both are consulted because the stream herdr picks is not ours to choose — and
# in production it picked the one nobody was reading, which is why even the
# `agent_name_taken` branch below could never fire. Nothing here is specific to
# `agent start`; the next call site that captures stderr can use it as is.
# Echoes nothing when neither stream carried a parsable error document.
_pmt_herdr_error_code() {
    local _json="$1" _errfile="$2" _code

    _code=$(printf '%s' "${_json}" | _pmt_json_value '.error.code')
    if [ -z "${_code}" ] && [ -s "${_errfile}" ]; then
        _code=$(_pmt_json_value '.error.code' <"${_errfile}")
    fi
    printf '%s' "${_code}"
}

# The human half of the same document: herdr's own sentence about the failure,
# from the stderr file <1>. `.error.message` first, because what herdr writes
# to stderr is a JSON document and dumping it raw into a cron log buries the
# sentence inside braces (PR #1517 review, codex). Falls back to the first raw
# line, which is what a non-JSON stderr (a crash, a shell error) carries — and
# is also what keeps this working if herdr ever changes its JSON shape. Echoes
# nothing when the file is empty.
_pmt_herdr_error_message() {
    local _errfile="$1" _msg

    [ -s "${_errfile}" ] || return 0
    _msg=$(_pmt_json_value '.error.message' <"${_errfile}")
    [ -n "${_msg}" ] || _msg=$(head -n 1 "${_errfile}" 2>/dev/null)
    printf '%s' "${_msg}"
}

# Set by _pmt_start_agent_retrying to the code of the attempt it gave up on —
# empty when herdr named none on either stream.
_PMT_START_CODE=""

# Start agent <1> on pane <2>, retrying only the #1512 `agent_pane_busy` race;
# herdr's stderr lands in the file named by <3>. 0 = an agent is running on the
# pane, 1 = gave up, with _PMT_START_CODE naming the last failure and <3>
# holding herdr's own sentence about it.
#
# Each attempt truncates <3>, so a retry that fails differently can never be
# reported with the previous attempt's cause.
_pmt_start_agent_retrying() {
    local _agent="$1" _pane="$2" _errf="$3" _json _attempt=1

    _PMT_START_CODE=""
    while :; do
        _json=$(_pmt_agent_start "${_agent}" "${_pane}" "${_errf}") && return 0
        _PMT_START_CODE=$(_pmt_herdr_error_code "${_json}" "${_errf}")

        # The one failure worth another attempt (#1512): the pane was created
        # moments ago and its shell is not interactive yet. Only this code —
        # a failure that does not name itself is not a race we understand, and
        # ending the tick immediately keeps that contract intact.
        if [ "${_PMT_START_CODE}" != "agent_pane_busy" ] ||
            [ "${_attempt}" -ge "${_PMT_START_ATTEMPT_MAX}" ]; then
            return 1
        fi

        ux_warning "Agent ${_agent} start failed with agent_pane_busy on pane ${_pane} (attempt ${_attempt}/${_PMT_START_ATTEMPT_MAX}) — retrying in ${_PMT_START_RETRY_SLEEP}s."
        [ "${_PMT_START_RETRY_SLEEP}" = "0" ] || sleep "${_PMT_START_RETRY_SLEEP}"
        _attempt=$((_attempt + 1))
    done
}

# Wait for a freshly started agent to report idle before prompting it.
# `herdr agent start` only confirms the pane looks interactive — a claude
# process can have drawn its prompt box before its key-input loop accepts
# Enter, so the command is typed but never submitted (issue #1399).
#
# This is a *health* check, not the settle wait. A live agent answers `idle` on
# the first poll, so the normal path leaves here in ~0s — the poll budget only
# bounds how long a missing agent or a closed pane can hold the tick, and
# hitting it still prompts, because a stalled prompt is reported rather than
# silently booked as a started train. The wait that actually makes the prompt
# land is _pmt_settle, which runs after this (issue #1560).
_pmt_wait_for_idle() {
    local _agent="$1" _i=0 _status _get_failed=0 _detail=""

    while [ "${_i}" -lt "${_PMT_IDLE_POLL_MAX}" ]; do
        if _status=$(_pmt_agent_status "${_agent}"); then
            [ "${_status}" != "idle" ] || return 0
        else
            _get_failed=$((_get_failed + 1))
        fi
        _i=$((_i + 1))
        [ "${_i}" -lt "${_PMT_IDLE_POLL_MAX}" ] || break
        [ "${_PMT_IDLE_POLL_SLEEP}" = "0" ] || sleep "${_PMT_IDLE_POLL_SLEEP}"
    done

    # Counted in checks, not seconds: the gap between them is overridable, so a
    # wall-clock figure here would be wrong in exactly the runs that read it.
    [ "${_get_failed}" -eq 0 ] ||
        _detail=" (${_get_failed}/${_PMT_IDLE_POLL_MAX} health-check failures)"
    ux_warning "Agent ${_agent} never reported idle in ${_PMT_IDLE_POLL_MAX} checks${_detail} — prompting anyway."
}

# Echo the tail of an agent's pane, or nothing when it cannot be read.
#   $1 = agent name
#
# `--format text` gives the pane as plain lines. herdr answers its error
# document as JSON on *stdout* with exit 0 when the target is gone, so an
# unreadable pane is recognised by parsing, not by the exit code. Always
# returns 0: "no text" is "nothing to conclude", never a failure.
_pmt_pane_text() {
    local _text
    _text=$(herdr agent read "$1" --lines "${_PMT_SETTLE_READ_LINES}" \
        --format text 2>/dev/null) || return 0
    [ -z "$(printf '%s' "${_text}" | _pmt_json_value '.error.code')" ] || return 0
    printf '%s' "${_text}"
}

# True when two consecutive pane reads say the agent is listening.
#   $1 = this read, $2 = the previous one
#
# The twin of _iw_pane_settled, whose comment carries the reasoning for all
# three conditions — non-empty, identical, and not the login banner.
_pmt_pane_settled() {
    [ -n "$1" ] || return 1
    [ "$1" = "$2" ] || return 1
    case "$1" in
    *"${_PMT_SETTLE_NOT_READY_MARK}"*) return 1 ;;
    esac
    return 0
}

# Echo how many settle polls fit in _PMT_SETTLE_SECONDS at _PMT_SETTLE_POLL_SLEEP
# apart — the twin of _iw_settle_max_polls; see it for the full rationale
# (agy + codex, PR #1611 review, both passes).
_pmt_settle_max_polls() {
    local _seconds="$1" _gap="$2"
    LC_ALL=C awk -v s="${_seconds}" -v g="${_gap}" \
        'BEGIN {
            if (g <= 0) { print s; exit }
            n = s / g; i = int(n); if (i < n) i++
            if (i < 2) i = 2
            # See _iw_settle_max_polls — agy, PR #1611 review, 4th pass.
            if (i > 1000) i = 1000
            print i
        }'
}

# Wait for a freshly launched pane to look ready before typing into it
# (issue #1560; polled since #1570). Separate from _pmt_wait_for_idle on
# purpose: that one asks herdr for the agent's *status*, which reports "not
# working" and says nothing about the key-input loop. This one reads the pane's
# own text. The twin of _iw_settle — see it for the full rationale.
#
# Always succeeds and always ends in a prompt attempt: reaching the cap with no
# ready signal warns and proceeds, exactly the pre-#1570 behaviour. The poll
# can only make the wait shorter, never introduce a new failure mode.
_pmt_settle() {
    local _agent="$1" _i=0 _prev="" _text _now _deadline="" _max_polls

    [ "${_PMT_SETTLE_SECONDS}" = "0" ] && return 0
    # A fractional cap cannot bound a poll count; it still means the flat wait
    # it meant before #1570.
    case "${_PMT_SETTLE_SECONDS}" in
    *[!0-9]*)
        sleep "${_PMT_SETTLE_SECONDS}"
        return 0
        ;;
    esac

    _max_polls=$(_pmt_settle_max_polls "${_PMT_SETTLE_SECONDS}" "${_PMT_SETTLE_POLL_SLEEP}")

    _now=$(_pmt_now)
    # `10#` forces base 10 — see _iw_settle for the full rationale (codex,
    # PR #1611 review, second pass).
    [ -z "${_now}" ] || _deadline=$((_now + 10#${_PMT_SETTLE_SECONDS}))

    while [ "${_i}" -lt "${_max_polls}" ]; do
        # Before the read, not after the sleep — see _iw_settle: a poll gap
        # wider than expected would otherwise let the last read land past the
        # cap.
        if [ -n "${_deadline}" ]; then
            _now=$(_pmt_now)
            [ -z "${_now}" ] || [ "${_now}" -lt "${_deadline}" ] || break
        fi
        _text=$(_pmt_pane_text "${_agent}")
        ! _pmt_pane_settled "${_text}" "${_prev}" || return 0
        _prev="${_text}"
        _i=$((_i + 1))
        [ "${_i}" -lt "${_max_polls}" ] || break
        [ "${_PMT_SETTLE_POLL_SLEEP}" = "0" ] || sleep "${_PMT_SETTLE_POLL_SLEEP}"
    done

    ux_warning "Agent ${_agent} pane never settled within ${_PMT_SETTLE_SECONDS}s — prompting anyway."
    return 0
}

_pmt_prompt_retryable() {
    case "$1" in
    timeout | agent_prompt_stalled) return 0 ;;
    esac
    return 1
}

_pmt_escalate_prompt_stall() {
    local _agent="$1" _code="$2" _label _body

    if [ -n "${_PMT_TAB_ID}" ]; then
        _label="${_PMT_AGENT_PREFIX}-$(basename "${_PMT_REPO}")-STUCK"
        if herdr tab rename "${_PMT_TAB_ID}" "${_label}" >/dev/null 2>&1; then
            ux_warning "Renamed tab ${_PMT_TAB_ID} to ${_label} after repeated prompt failure (${_code:-unknown})."
        else
            ux_warning "Could not rename tab ${_PMT_TAB_ID} after repeated prompt failure (${_code:-unknown})."
        fi
    fi

    _body="${_PMT_REPO} merge-train prompt failed repeatedly — herdr agent attach ${_agent}"
    if herdr notification show "merge-train prompt stalled" \
        --body "${_body}" --sound request >/dev/null 2>&1; then
        ux_warning "Posted a herdr notification for ${_PMT_REPO} prompt failure."
    else
        ux_warning "Could not post a herdr notification for ${_PMT_REPO} prompt failure."
    fi
}

# Hand the whole train over to the session. This is the one place where the
# dispatcher's job ends and the skill's begins (D-8).
#
# stderr goes to a file rather than /dev/null (#1551, same defect class as
# #1512/#1458): herdr answers `agent prompt`'s error document on stderr too,
# and discarding it is what turned a real timeout into an unexplained
# "(unknown)" reason with no `Tick complete` ever logged. A file rather than
# `2>&1` for the same reason `_pmt_agent_start` uses one (line ~543) — stdout
# stays on its own pipe because `.error.code` is read off it first.
_pmt_prompt_train() {
    local _agent="$1" _prompt _json _rc=0 _errf _code="" _cause="" _msg _attempt=1

    _prompt="/gh-pr-merge-train ${_PMT_REPO}"

    # A `local` capture file is enough here where _pmt_launch_fresh needs the
    # _PMT_ERRF global (line ~149): the trap is disarmed at the single exit
    # below, so it can never fire once _errf has gone out of scope.
    _errf=$(mktemp) || {
        ux_error "cannot open a capture file for herdr's stderr — ending this tick."
        return 1
    }
    trap 'rm -f "${_errf}"' EXIT INT TERM
    while [ "${_attempt}" -le "${_PMT_PROMPT_ATTEMPT_MAX}" ]; do
        _json=$(herdr agent prompt "${_agent}" "${_prompt}" \
            --wait --timeout "${_PMT_TIMEOUT_MS}" 2>"${_errf}") || _rc=$?

        # Read both halves of herdr's answer before a retry truncates the
        # capture file, so each attempt classifies only its own result.
        if [ "${_rc}" -ne 0 ]; then
            _code=$(_pmt_herdr_error_code "${_json}" "${_errf}")
            _cause=$(_pmt_herdr_error_message "${_errf}")
        else
            _code=""
            _cause=""
        fi

        if [ "${_rc}" -eq 0 ]; then
            trap - EXIT INT TERM
            rm -f "${_errf}"
            ux_success "Dispatched to ${_agent}: ${_prompt}"
            return 0
        fi

        if _pmt_prompt_retryable "${_code}" &&
            [ "${_attempt}" -lt "${_PMT_PROMPT_ATTEMPT_MAX}" ]; then
            ux_warning "herdr agent prompt ${_agent} failed (${_code}) — retrying after ${_PMT_SETTLE_SECONDS}s settle (${_attempt}/${_PMT_PROMPT_ATTEMPT_MAX})."
            : >"${_errf}"
            _attempt=$((_attempt + 1))
            _rc=0
            _pmt_settle "${_agent}"
            continue
        fi
        break
    done

    trap - EXIT INT TERM
    rm -f "${_errf}"

    if _pmt_prompt_retryable "${_code}"; then
        _pmt_escalate_prompt_stall "${_agent}" "${_code}"
    fi

    _msg="herdr agent prompt failed for agent ${_agent} (${_code:-unknown})."
    [ -z "${_cause}" ] || _msg="${_msg}
    원인: ${_cause}"
    ux_error "${_msg}"
    return 1
}

# Open a fresh workspace/tab/agent for the train and prompt it.
_pmt_launch_fresh() {
    local _agent="$1" _cwd="$2" _label _ws _msg _cause

    # The workspace label *is* the agent name (#1549), so `herdr workspace list`
    # and `herdr agent get` name the same train. Assigning it rather than
    # re-deriving it is what keeps the two from drifting apart again; main()
    # already validated this string when it built the agent name.
    _label="${_agent}"

    # Only this path opens a pane, so this is the only path that needs an
    # account to open it with. Resolving it in main() would make every reuse
    # tick — the common case once a train pane is open — pay for a subshell,
    # a sourced claude.sh and a setup-mode read whose result it never uses,
    # and let a routing failure end a tick that was not going to route.
    _pmt_bind_config_dir || return 1

    _ws=$(_pmt_workspace_for_label "${_label}" "${_cwd}") || {
        ux_error "No herdr workspace for ${_label} — ending this tick."
        return 1
    }
    _pmt_tab_create "${_ws}" "${_cwd}" "merge-train" || {
        ux_error "herdr tab create failed for ${_PMT_REPO} — ending this tick."
        return 1
    }

    # The trap covers the window where a signal can land between mktemp and the
    # rm below — a cron tick killed mid-start otherwise leaves the file in /tmp
    # forever (PR #1517 review, agy). It is cleared, not left armed, so the
    # function's own `rm` stays the normal path and nothing fires twice.
    _PMT_ERRF=$(mktemp) || {
        ux_error "cannot open a capture file for herdr's stderr — ending this tick."
        _pmt_tab_close "${_PMT_TAB_ID}"
        return 1
    }
    trap 'rm -f "${_PMT_ERRF}"' EXIT INT TERM
    if _pmt_start_agent_retrying "${_agent}" "${_PMT_PANE_ID}" "${_PMT_ERRF}"; then
        trap - EXIT INT TERM
        rm -f "${_PMT_ERRF}"
        _pmt_wait_for_idle "${_agent}"
        # Fresh launch only. The reuse branch in main() and the
        # `agent_name_taken` fallback below both talk to a session that has
        # been up for at least a cron period — settling those would spend a
        # poll round per PR on a pane that has been ready for minutes
        # (issue #1560).
        _pmt_settle "${_agent}"
        _pmt_prompt_train "${_agent}"
        return
    fi
    # herdr's own sentence about the failure, read before the file goes away.
    _cause=$(_pmt_herdr_error_message "${_PMT_ERRF}")
    trap - EXIT INT TERM
    rm -f "${_PMT_ERRF}"

    # Backstop for the race _pmt_train_state cannot close: the name can be
    # claimed between the probe and the start (a train launched by a manual
    # run, say). herdr answers `agent_name_taken` and the holder is by
    # definition a usable agent, so prompt it rather than ending every future
    # tick on the same collision. NF-1 is preserved — the name is what makes
    # "one train" true, and we are talking to its holder.
    #
    # The tab still closes. The agent we prompt lives on some *other* pane —
    # this tick's tab never received one and is exactly the orphan #1512 is
    # about, so keeping it would leak a dead tab on every probe/start race
    # (PR #1517 review, codex). Closing precedes the prompt so a prompt that
    # fails cannot strand it either.
    if [ "${_PMT_START_CODE}" = "agent_name_taken" ]; then
        ux_warning "Agent ${_agent} is already registered — prompting the existing session instead of a second one."
        _pmt_tab_close "${_PMT_TAB_ID}"
        _pmt_prompt_train "${_agent}"
        return
    fi

    # One line, plus the sentence herdr actually gave, indented under it
    # (#1458's idiom). Without it every cause — a busy pane, a dead server, a
    # rejected account — converged on the same unhelpful sentence, which is
    # precisely why #1512 went unnoticed for weeks of failed ticks.
    [ -n "${_cause}" ] || _cause="${_PMT_START_CODE}"
    _msg="herdr agent start ${_agent} failed on pane ${_PMT_PANE_ID} — ending this tick."
    [ -z "${_cause}" ] || _msg="${_msg}
    원인: ${_cause}"
    ux_error "${_msg}"
    _pmt_tab_close "${_PMT_TAB_ID}"
    return 1
}

# ============================================================
# Usage
# ============================================================

_pmt_usage() {
    ux_header "pr_merge_train_cron"
    ux_info "Usage: pr_merge_train_cron.sh [--cwd <PATH>] [--dry-run] | [-h|--help|help]"
    ux_info "Runs one merge-train tick: check preconditions, launch /gh-pr-merge-train."
    ux_bullet "options"
    ux_bullet_sub "--cwd <PATH>   run the tick from PATH; the target repo is PATH's origin remote"
    ux_bullet_sub "--dry-run      print what this tick would launch, change nothing"
    ux_bullet_sub "               (takes no lock and opens no pane)"
    ux_bullet_sub "-h, --help, help   show this help"
    ux_bullet "tick"
    ux_bullet_sub "1. flock — one tick at a time"
    ux_bullet_sub "2. herdr agent get ${_PMT_AGENT_PREFIX}-<repo> — a running train blocks a new one"
    ux_bullet_sub "3. gh pr list --author @me --state open — is there anything to merge"
    ux_bullet_sub "4. herdr workspace -> tab -> claude -> /gh-pr-merge-train <owner/repo>"
    ux_bullet_sub "no PR is ever written to from here — no merge, comment or label change"
    ux_bullet "target PRs"
    ux_bullet_sub "your own PRs only (--author @me) — a colleague's PR is never auto-merged (D-7)"
    ux_bullet_sub "a PR updated in the last $(_gh_pr_merge_train_quiet_minutes)m is excluded (D-6: gh:pr-reply may be in flight)"
    ux_bullet_sub "a PR carrying the reply-pending label is excluded (#1524: the deferred reply pass is still out)"
    ux_bullet_sub "drafts are excluded — DRAFT is a skip row in the routing table"
    ux_bullet_sub "gh pr list failure ends the tick: never merge without knowing state"
    ux_bullet "duplicate-start guard (NF-1)"
    ux_bullet_sub "the lock covers overlapping ticks; the agent probe covers the running train"
    ux_bullet_sub "agent working/blocked -> hold; still registered -> prompt that pane; missing -> open a new one"
    ux_bullet "state"
    ux_bullet_sub "\${XDG_STATE_HOME:-\$HOME/.local/state}/${_PMT_STATE_SUBDIR}/${_PMT_LOCK_BASENAME}   (tick lock)"
    ux_bullet "claude session (claude-yolo parity)"
    ux_bullet_sub "the pane runs claude --dangerously-skip-permissions (unattended cron)"
    ux_bullet_sub "that session can merge — NF-2 (no emergency bypass) and the fail-closed"
    ux_bullet_sub "approval gate are what bound it, not a permission prompt"
    ux_bullet_sub "internal setup mode  → CLAUDE_CONFIG_DIR=\$HOME/.claude"
    ux_bullet_sub "otherwise            → CLAUDE_CONFIG_DIR=\$HOME/.claude-\${CLAUDE_DEFAULT_ACCOUNT:-personal}"
    ux_bullet_sub "that directory must exist and hold a parseable .credentials.json"
    ux_bullet_sub "  (a logged-out account stalls every prompt — the tick fails fast instead)"
    ux_bullet "crontab"
    ux_bullet_sub "*/2 * * * * /path/to/pr_merge_train_cron.sh --cwd ~/dotfiles >> ~/.local/state/pr-merge-train/cron.log 2>&1"
}

# ============================================================
# Main
# ============================================================

main() {
    local _cwd="" _target _agent _state

    while [ "$#" -gt 0 ]; do
        case "$1" in
        -h | --help | help)
            _pmt_usage
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
            _PMT_DRY_RUN=1
            shift
            ;;
        *)
            ux_error "Unknown option: $1"
            ux_info "Run 'pr_merge_train_cron.sh --help' for usage."
            exit 1
            ;;
        esac
    done

    # --cwd is where the tick runs from, and therefore which checkout's origin
    # names the target repo. A cron tick starts in $HOME, which is not a repo.
    if [ -n "${_cwd}" ]; then
        if ! cd "${_cwd}"; then
            ux_error "Cannot cd to --cwd ${_cwd}."
            exit 1
        fi
    fi

    ux_header "pr-merge-train tick"

    if ! command -v gh >/dev/null 2>&1; then
        ux_error "gh not found in PATH — cannot query the open PRs."
        exit 1
    fi

    # jq is not optional on this path: `gh pr list --json` answers with an
    # array of objects, and the flat-key fallback _pmt_json_value uses for the
    # single-value herdr responses cannot walk that.
    if ! command -v jq >/dev/null 2>&1; then
        ux_error "jq not found in PATH — cannot parse the PR list."
        ux_info "Install jq, or add it to the cron PATH."
        exit 1
    fi

    # A dry run reports and touches nothing, so it must stay usable on a
    # machine with no herdr server.
    if [ "${_PMT_DRY_RUN}" -eq 0 ] && ! command -v herdr >/dev/null 2>&1; then
        ux_error "herdr not found in PATH — cannot launch the merge-train session."
        ux_info "Install it via ./herdr/setup.sh, or add it to the cron PATH."
        exit 1
    fi

    _pmt_bind_target || exit 1
    _agent=$(herdr_agent_name "${_PMT_AGENT_PREFIX}" "${_PMT_REPO}") || {
        ux_error "Cannot derive a herdr agent name from ${_PMT_REPO} — ending this tick."
        exit 1
    }

    # The dry run answers ahead of both guards, deliberately: taking the lock
    # would make a dry run silently no-op while a real tick is mid-cycle —
    # exactly when a human is most likely to be asking what the train sees.
    if [ "${_PMT_DRY_RUN}" -eq 1 ]; then
        if ! _target=$(_pmt_target_count); then
            # Non-zero here, unlike the real tick below, and the difference is
            # deliberate. A real tick exits 0 because cron must not treat a
            # transient GitHub failure as a hard error — there is nothing to
            # escalate, the next period retries. `--dry-run` is a human-facing
            # probe: its caller asked "what does the train see?", and answering
            # "nothing went wrong" to a question that could not be answered is
            # the one thing it must not do.
            ux_error "gh pr list failed for ${_PMT_REPO} — a real tick would end here."
            exit 1
        fi
        ux_success "Dry run — ${_PMT_REPO} on ${_PMT_HOST}: ${_target} target PR(s)."
        ux_bullet "would prompt agent ${_agent} with /gh-pr-merge-train ${_PMT_REPO}"
        exit 0
    fi

    _pmt_acquire_lock || exit 0

    # NF-1 layer 2 — the train the *previous* tick started outlives the tick
    # that started it, so the lock above cannot see it.
    _state=$(_pmt_train_state "${_agent}")
    if [ "${_state}" = "live" ]; then
        ux_info "A merge train is already running on ${_PMT_REPO} (agent ${_agent}) — skip."
        exit 0
    fi

    if ! _target=$(_pmt_target_count); then
        # Exit 0, unlike the --dry-run branch above: a transient API failure is
        # not something cron should mail about, and the next period retries.
        ux_error "gh pr list failed for ${_PMT_REPO} — ending this tick rather than merging blind."
        exit 0
    fi
    if [ "${_target}" -eq 0 ]; then
        ux_info "No target PR on ${_PMT_REPO} — nothing to wake a session for."
        exit 0
    fi

    ux_info "${_target} target PR(s) on ${_PMT_REPO} — starting the merge train."

    if [ "${_state}" = "reuse" ]; then
        # The previous train's agent still resolves: prompt it again rather
        # than stacking a second tab on the workspace every cron period — and,
        # for a `done`/`unknown` agent, rather than colliding with its own name
        # (`agent_name_taken`) forever. The pane already carries the account it
        # was opened with, so no CLAUDE_CONFIG_DIR is resolved on this path.
        _pmt_prompt_train "${_agent}" || exit 1
    else
        # PWD, not $(pwd): the --cwd handling above already cd'd here.
        _pmt_launch_fresh "${_agent}" "${PWD}" || exit 1
    fi

    ux_success "Tick complete — merge train handed to ${_agent}."
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
