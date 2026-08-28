#!/usr/bin/env bats
# tests/bats/skills/gh_pr_merge_train_close_impl_tab.bats
# Verify the step-7 impl-tab close documented in
#   claude/skills/gh-pr-merge-train/SKILL.md → references/train-loop.md
# Source-of-truth fixture: _fixtures/gh_pr_merge_train_close_impl_tab.sh.
#
# Issue #1565: gh:pr-merge Step 5's post-merge-verify dispatch was prose
# ("call `Skill(gh:pr-post-merge-verify, ...)`") at the tail of a skill the
# train invokes in a loop, and it executed 0/10 times inside that loop. The
# impl tabs of 10 merged PRs stayed open, `_iw_live_agents` in
# shell-common/tools/custom/issue_watcher_cron.sh counted their worktrees as
# running, and `_IW_MAX_PER_REPO=3` stopped issue-watcher after ~3 merges.
#
# Cases:
#   1. idle agent on the merged branch's worktree → tab closed, one [INFO]
#   2. agent_status == working / blocked           → NEVER closed, no output
#   3. no worktree / no herdr / no jq / dead herdr  → silent skip, rc 0
#   4. two agents on one cwd                       → first wins, closed once
#   5. herdr tab close fails                       → [WARN], never fatal
#   6. anti-starvation regression: the live count does not grow across N merges
#   7. doc/fixture drift guard + the SKILL.md pointer

load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_pr_merge_train_close_impl_tab.sh"

    WT_DIR="/home/dev/wt/issue-1565"
    export WT_DIR

    FAKE_WORKTREE_LIST="worktree /home/dev/dotfiles
HEAD 1111111111111111111111111111111111111111
branch refs/heads/main

worktree ${WT_DIR}
HEAD 2222222222222222222222222222222222222222
branch refs/heads/wt/issue-1565/1
"
    export FAKE_WORKTREE_LIST

    FAKE_CALL_LOG="${TEST_TEMP_HOME}/calls.log"
    export FAKE_CALL_LOG
    : >"$FAKE_CALL_LOG"

    # Shadow `git` so `git worktree list --porcelain` reads a fixed table
    # instead of this repo's real worktrees.
    git() {
        printf 'git %s\n' "$*" >>"$FAKE_CALL_LOG"
        if [ "$1" = "worktree" ] && [ "$2" = "list" ]; then
            printf '%s' "${FAKE_WORKTREE_LIST-}"
            return 0
        fi
        command git "$@"
    }

    # Shadow `herdr`. `agent list` is canned and steerable; `tab close` records
    # the tab it was asked to close so the tests assert on calls made, not only
    # on printed text. FAKE_CLOSE_RC simulates a refusal.
    herdr() {
        printf 'herdr %s\n' "$*" >>"$FAKE_CALL_LOG"
        if [ "$1" = "agent" ] && [ "$2" = "list" ]; then
            [ "${FAKE_AGENT_RC:-0}" -eq 0 ] || return "$FAKE_AGENT_RC"
            printf '%s' "${FAKE_AGENT_JSON-}"
            return 0
        fi
        if [ "$1" = "tab" ] && [ "$2" = "close" ]; then
            [ "${FAKE_CLOSE_RC:-0}" -eq 0 ] || return "$FAKE_CLOSE_RC"
            printf '%s\n' "$3" >>"${FAKE_CLOSED_LOG:-/dev/null}"
            return 0
        fi
        return 1
    }

    FAKE_CLOSED_LOG="${TEST_TEMP_HOME}/closed.log"
    export FAKE_CLOSED_LOG
    : >"$FAKE_CLOSED_LOG"
}

teardown() {
    teardown_isolated_home
    unset -f git herdr 2>/dev/null || true
    unset WT_DIR FAKE_WORKTREE_LIST FAKE_AGENT_JSON FAKE_AGENT_RC FAKE_CALL_LOG \
        FAKE_CLOSE_RC FAKE_CLOSED_LOG
}

# Build an agent-list payload from `cwd|tab_id|status` specs.
_agents_json() {
    local spec sep="" out='{"result":{"agents":['
    local cwd tab st
    for spec in "$@"; do
        IFS='|' read -r cwd tab st <<<"$spec"
        out+="${sep}{\"cwd\":\"${cwd}\",\"foreground_cwd\":\"${cwd}\",\"tab_id\":\"${tab}\",\"agent_status\":\"${st}\"}"
        sep=","
    done
    printf '%s]}}' "$out"
}

# --- 1. the happy path ----------------------------------------------------

@test "close-impl-tab: an idle agent on the merged worktree gets its tab closed" {
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|idle")"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    assert_output --partial '[INFO] gh:pr-merge-train: closed implementation tab tab-7'
    assert_output --partial "(${WT_DIR})"
    [ "${#lines[@]}" -eq 1 ]
}

@test "close-impl-tab: the close really is invoked, with that tab id" {
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|idle")"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    run cat "$FAKE_CLOSED_LOG"
    assert_output "tab-7"
}

@test "close-impl-tab: the branch decides the worktree, not the directory name" {
    # Two worktrees, one agent each; only the merged branch's tab may close.
    FAKE_WORKTREE_LIST="worktree /home/dev/wt/issue-1000
HEAD aaaa
branch refs/heads/wt/issue-1000/1

worktree ${WT_DIR}
HEAD bbbb
branch refs/heads/wt/issue-1565/1
"
    FAKE_AGENT_JSON="$(_agents_json \
        "/home/dev/wt/issue-1000|tab-other|idle" \
        "${WT_DIR}|tab-7|idle")"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    run cat "$FAKE_CLOSED_LOG"
    assert_output "tab-7"
}

# --- 2. non-idle is never closed (the decision that keeps work alive) ------

@test "close-impl-tab: agent_status=working is NEVER closed and prints nothing" {
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|working")"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    [ -z "$output" ]
    run cat "$FAKE_CLOSED_LOG"
    assert_output ""
}

@test "close-impl-tab: agent_status=blocked is NEVER closed" {
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|blocked")"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    [ -z "$output" ]
    run cat "$FAKE_CLOSED_LOG"
    assert_output ""
}

@test "close-impl-tab: an unknown future status is treated as not-idle" {
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|compacting")"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    [ -z "$output" ]
    run cat "$FAKE_CLOSED_LOG"
    assert_output ""
}

@test "close-impl-tab: a null agent_status is treated as not-idle" {
    FAKE_AGENT_JSON="{\"result\":{\"agents\":[{\"cwd\":\"${WT_DIR}\",\"tab_id\":\"tab-7\"}]}}"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    [ -z "$output" ]
    run cat "$FAKE_CLOSED_LOG"
    assert_output ""
}

@test "close-impl-tab: no herdr call is made at all for a working tab beyond the list" {
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|working")"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    run bash -c "grep -c 'herdr tab close' '$FAKE_CALL_LOG' || true"
    assert_output "0"
}

# --- 3. the silent skips --------------------------------------------------

@test "close-impl-tab: no local worktree for the merged branch → silent skip" {
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|idle")"
    run gh_pr_merge_train_close_impl_tab "feature/merged-elsewhere"
    assert_success
    [ -z "$output" ]
    run cat "$FAKE_CLOSED_LOG"
    assert_output ""
}

@test "close-impl-tab: an empty head branch → silent skip" {
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|idle")"
    run gh_pr_merge_train_close_impl_tab ""
    assert_success
    [ -z "$output" ]
}

@test "close-impl-tab: herdr not installed → silent skip, rc=0" {
    local bin="${TEST_TEMP_HOME}/nobin"
    mkdir -p "$bin"
    local tool
    for tool in awk jq cut head; do
        ln -sf "$(command -v "$tool")" "$bin/$tool"
    done
    unset -f herdr
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|idle")"

    local old_path="$PATH"
    PATH="$bin"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    PATH="$old_path"
    assert_success
    [ -z "$output" ]
}

@test "close-impl-tab: herdr agent list fails → silent skip, nothing closed" {
    FAKE_AGENT_RC=1
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|idle")"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    [ -z "$output" ]
    run cat "$FAKE_CLOSED_LOG"
    assert_output ""
}

@test "close-impl-tab: an empty agent set → silent skip" {
    FAKE_AGENT_JSON='{"result":{"agents":[]}}'
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    [ -z "$output" ]
}

@test "close-impl-tab: garbage from herdr agent list → silent skip" {
    FAKE_AGENT_JSON='not json at all'
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    [ -z "$output" ]
    run cat "$FAKE_CLOSED_LOG"
    assert_output ""
}

@test "close-impl-tab: agents exist but none sit on the worktree → silent skip" {
    FAKE_AGENT_JSON="$(_agents_json "/home/dev/somewhere-else|tab-9|idle")"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    [ -z "$output" ]
}

# The gh:pr-merge Step 5 dispatch closes this tab first when it ran. Finding
# nothing is therefore the EXPECTED outcome of a healthy pipeline, not an error.
@test "close-impl-tab: a tab gh:pr-merge already closed is a quiet no-op" {
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|idle")"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    FAKE_AGENT_JSON='{"result":{"agents":[]}}'
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    [ -z "$output" ]
}

# --- 4/5. abnormal states -------------------------------------------------

@test "close-impl-tab: two agents on one cwd → first wins, closed once" {
    FAKE_AGENT_JSON="$(_agents_json \
        "${WT_DIR}|tab-first|idle" \
        "${WT_DIR}|tab-second|idle")"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    [ "${#lines[@]}" -eq 1 ]
    assert_output --partial 'tab-first'
    refute_output --partial 'tab-second'
    run cat "$FAKE_CLOSED_LOG"
    assert_output "tab-first"
}

@test "close-impl-tab: a failing herdr tab close warns and never fails the merge" {
    FAKE_CLOSE_RC=1
    FAKE_AGENT_JSON="$(_agents_json "${WT_DIR}|tab-7|idle")"
    run gh_pr_merge_train_close_impl_tab "wt/issue-1565/1"
    assert_success
    assert_output --partial '[WARN] gh:pr-merge-train: herdr tab close tab-7 failed'
}

# --- 6. the anti-starvation regression gate -------------------------------
#
# The failure #1565 describes is not a missing [INFO] line: it is that
# `_iw_live_agents` counts a `wt/issue-*` worktree as running whenever a herdr
# agent sits on it, so merged-but-open tabs fill `_IW_MAX_PER_REPO=3` and
# issue-watcher stops dispatching. This drives N merges against a mutable
# registry and asserts the live count never grows — the pre-fix train left it
# pinned at N.

# Count the worktrees `_iw_live_agents` would call live: a `wt/issue-*`
# worktree with a herdr agent standing on it (same predicate, same jq shape).
_live_count() {
    printf '%s' "$FAKE_AGENT_JSON" |
        jq -r '[.result.agents[]? | (.cwd // empty)
               | select(test("/wt/issue-"))] | length'
}

# Drop the agent whose tab_id was just closed, the way a real herdr does.
_forget_closed_tab() {
    FAKE_AGENT_JSON=$(printf '%s' "$FAKE_AGENT_JSON" |
        jq -c --arg t "$1" '.result.agents |= map(select(.tab_id != $t))')
}

@test "close-impl-tab: the live worktree count does not grow across N merges" {
    local n=5 i specs=() wt_list="" counts=""

    for ((i = 1; i <= n; i++)); do
        wt_list+="worktree /home/dev/wt/issue-${i}
HEAD ${i}${i}${i}${i}
branch refs/heads/wt/issue-${i}/1

"
        specs+=("/home/dev/wt/issue-${i}|tab-${i}|idle")
    done
    FAKE_WORKTREE_LIST="$wt_list"
    FAKE_AGENT_JSON="$(_agents_json "${specs[@]}")"

    # Before the train runs, all N merged PRs are counted as live sessions —
    # this is the state that starved issue-watcher.
    [ "$(_live_count)" -eq "$n" ] || fail "expected ${n} live worktrees to start"

    local prev="$n" now
    for ((i = 1; i <= n; i++)); do
        run gh_pr_merge_train_close_impl_tab "wt/issue-${i}/1"
        assert_success
        assert_output --partial "closed implementation tab tab-${i}"
        _forget_closed_tab "tab-${i}"
        now="$(_live_count)"
        counts+="${now} "
        [ "$now" -le "$prev" ] \
            || fail "live count grew from ${prev} to ${now} at merge ${i}"
        prev="$now"
    done

    [ "$prev" -eq 0 ] || fail "after ${n} merges ${prev} tabs are still live (${counts})"
}

@test "close-impl-tab: a working tab keeps its slot — starvation is not traded for lost work" {
    # The counter-case to the test above: the count staying flat must come from
    # closing idle tabs, never from closing tabs that still have work in them.
    FAKE_WORKTREE_LIST="worktree /home/dev/wt/issue-1
HEAD aaaa
branch refs/heads/wt/issue-1/1

worktree /home/dev/wt/issue-2
HEAD bbbb
branch refs/heads/wt/issue-2/1
"
    FAKE_AGENT_JSON="$(_agents_json \
        "/home/dev/wt/issue-1|tab-1|idle" \
        "/home/dev/wt/issue-2|tab-2|working")"

    run gh_pr_merge_train_close_impl_tab "wt/issue-1/1"
    assert_success
    _forget_closed_tab "tab-1"

    run gh_pr_merge_train_close_impl_tab "wt/issue-2/1"
    assert_success
    [ -z "$output" ]

    [ "$(_live_count)" -eq 1 ] || fail "the working session must still be counted live"
    run cat "$FAKE_CLOSED_LOG"
    assert_output "tab-1"
}

# --- 7. doc/fixture correspondence ----------------------------------------

@test "close-impl-tab: reference doc and fixture have not drifted apart" {
    local doc="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-merge-train/references/train-loop.md"
    local fixture="${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_pr_merge_train_close_impl_tab.sh"
    local f pat
    for pat in \
        '/^worktree /{p=substr($0,10)} /^branch /{if (substr($0,8)==b) print p}' \
        '.result.agents[]? | select(.cwd == $cwd)' \
        '"\(.tab_id)\t\(.agent_status)"' \
        '= "idle" ]' \
        '[INFO] gh:pr-merge-train: closed implementation tab %s (%s).' \
        '[WARN] gh:pr-merge-train: herdr tab close %s failed'; do
        for f in "$doc" "$fixture"; do
            run grep -F -- "$pat" "$f"
            assert_success
        done
    done
}

@test "close-impl-tab: the train-loop close block is gated on idle, never unconditional" {
    local doc="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-merge-train/references/train-loop.md"
    # `herdr tab close` may appear only inside the idle-gated branch: the one
    # thing this step must never become is a blanket close.
    run bash -c "grep -c 'herdr tab close \"' '$doc'"
    assert_output "1"
}

@test "close-impl-tab: the merge-train SKILL.md points at the close step" {
    local skill="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-merge-train/SKILL.md"
    run grep -qF -- "Closing the merged" "$skill"
    assert_success
    run grep -qF -- "_IW_MAX_PER_REPO" "$skill"
    assert_success
}

@test "close-impl-tab: the close runs only after a successful merge" {
    local doc="${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr-merge-train/references/train-loop.md"
    run grep -qF -- "only after" "$doc"
    assert_success
    run grep -qF -- "only on a successful merge" "$doc"
    assert_success
}
