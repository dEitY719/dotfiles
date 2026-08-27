#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_issue_implement_claim.sh
# Source-of-truth mirror for the Step 3 substep gating documented in
#   claude/skills/gh-issue-implement/references/claim.md
#
# Each function here is the executable form of one substep; the bats
# suite injects test inputs via FAKE_* env vars rather than calling
# real gh / network. Keep these in sync with claim.md whenever the
# substep policy changes.
#
# Inputs (all FAKE_*):
#   FAKE_LABELS         — comma-separated label names on the issue
#   FAKE_ASSIGNEES      — comma-separated current assignees
#   FAKE_ME             — current user login (for self-assign decision)
#   FAKE_BODY           — issue body text (depends-on grep target)
#   FAKE_DEPS_STATES    — "M:STATE,M2:STATE2" map for dep-issue lookup
#                         (e.g. "100:CLOSED,101:OPEN"). Missing key → OPEN.
#   FAKE_BOARD_ATTACHED — "1" if a projectV2 is attached, "0" otherwise.
#   FAKE_BOARD_STATUS   — current board Status column ("Backlog", "Ready",
#                         "In progress", ...). Unset → treated as
#                         Backlog/Ready, i.e. the pre-#1507 behavior.
#   FAKE_OPEN_PRS_CLOSING     — comma-separated PR numbers that are open and
#                               close this issue. Empty → none found.
#   FAKE_DUPLICATE_PR_API_FAIL — "1" simulates the PR search itself erroring.

# 3.2 Block-label guard. Returns 2 (refusal) when any label on the
# issue matches an entry in GH_ISSUE_BLOCK_LABELS; 0 otherwise.
gh_issue_block_label_guard() {
    local _issue_num="${1:-?}"
    local _block_csv="${GH_ISSUE_BLOCK_LABELS:-do-not-work,on-hold,보류,⏸️ Postpone}"
    local _labels_csv="${FAKE_LABELS-}"

    [ -z "$_labels_csv" ] && return 0

    local _labels _block
    IFS=',' read -r -a _labels <<< "$_labels_csv"
    IFS=',' read -r -a _block <<< "$_block_csv"

    local _l _b
    for _l in "${_labels[@]}"; do
        for _b in "${_block[@]}"; do
            if [ "$_l" = "$_b" ]; then
                printf 'Refusing to start #%s — blocked by label "%s".\n' \
                    "$_issue_num" "$_l"
                printf '  Remove the label and re-run, or check whether\n'
                printf '  the issue should stay parked.\n'
                return 2
            fi
        done
    done
    return 0
}

# 3.3 Self-assign decision. Echoes one of:
#   "skip"        — GH_ISSUE_SKIP_SELF_ASSIGN=1
#   "noop-self"   — already assigned to me
#   "add"         — unassigned (or others) but I'm not in the list AND
#                   no other user holds it
#   "warn-other"  — someone else holds it; do not override
# Always returns 0 (decision-only; the actual gh call happens in the skill).
gh_issue_self_assign_decide() {
    local _me="${FAKE_ME:-me}"
    local _assignees_csv="${FAKE_ASSIGNEES-}"

    if [ "${GH_ISSUE_SKIP_SELF_ASSIGN:-0}" = "1" ]; then
        printf 'skip'
        return 0
    fi

    if [ -z "$_assignees_csv" ]; then
        printf 'add'
        return 0
    fi

    local _assignees
    IFS=',' read -r -a _assignees <<< "$_assignees_csv"

    local _a
    for _a in "${_assignees[@]}"; do
        if [ "$_a" = "$_me" ]; then
            printf 'noop-self'
            return 0
        fi
    done

    # Non-empty list, none of them is me → someone else holds it.
    printf 'warn-other'
    return 0
}

# 3.3b Duplicate open-PR guard (#1507). Read-only, soft, never blocks:
# warns once when an open PR already closes this issue, which is the
# fingerprint of another session in a sibling worktree having started
# the same issue under the same account.
# Always returns 0. Prints one "[WARN] ..." line, or nothing.
gh_issue_duplicate_pr_guard() {
    local _issue_num="${1:-?}"

    if [ "${GH_ISSUE_SKIP_DUPLICATE_CHECK:-0}" = "1" ]; then
        return 0
    fi
    # NF-1 soft-fail: the search itself errored → stay silent, continue.
    if [ "${FAKE_DUPLICATE_PR_API_FAIL:-0}" = "1" ]; then
        return 0
    fi

    local _prs_csv="${FAKE_OPEN_PRS_CLOSING-}"
    [ -z "$_prs_csv" ] && return 0

    # Name the first match — one line, however many PRs came back.
    local _first="${_prs_csv%%,*}"
    printf '[WARN] Issue #%s 을 이미 닫는 open PR #%s 이 있습니다 — 중복 구현 가능성. 계속 진행하기 전에 확인하세요.\n' \
        "$_issue_num" "$_first"
    return 0
}

# 3.4 Board Status transition decision. Returns 0 in all cases (the
# real helper is best-effort), but emits a single tag word so tests
# can verify which branch ran:
#   "skip"                — GH_ISSUE_SKIP_BOARD_TRANSITION=1
#   "no-board"            — FAKE_BOARD_ATTACHED=0 (no projectV2 attached)
#   "already-in-progress" — Status outside {Backlog,Ready}, so the real
#                           helper's --only-from whitelist absorbs the
#                           mutation. Preceded by an F-2 [WARN] line (#1507).
#   "synced"              — would invoke _gh_project_status_sync
gh_issue_board_transition_decide() {
    local _issue_num="${1:-?}"

    if [ "${GH_ISSUE_SKIP_BOARD_TRANSITION:-0}" = "1" ]; then
        printf 'skip'
        return 0
    fi
    if [ "${FAKE_BOARD_ATTACHED:-1}" = "0" ]; then
        printf 'no-board'
        return 0
    fi

    # F-2 (#1507): --only-from "Backlog,Ready" silently no-ops on every
    # other column. Say so out loud — an already-"In progress" card is
    # how a duplicate session looks from the board's side.
    local _status="${FAKE_BOARD_STATUS-}"
    if [ -n "$_status" ] && [ "$_status" != "Backlog" ] && [ "$_status" != "Ready" ]; then
        printf '[WARN] Issue #%s Status 가 이미 "%s" 입니다 — 다른 세션의 중복 착수이거나, 이슈가 이미 다른 단계로 넘어갔을 수 있습니다.\n' \
            "$_issue_num" "$_status"
        printf 'already-in-progress'
        return 0
    fi

    printf 'synced'
    return 0
}

# 3.5 Depends-on guard. Greps "Depends on #M" lines in the body and
# warns once per unresolved dep. Always returns 0 (soft).
# Prints zero or more lines starting with "⚠️" when a dep is OPEN.
gh_issue_deps_guard() {
    local _issue_num="${1:-?}"
    local _body="${FAKE_BODY-}"

    if [ "${GH_ISSUE_SKIP_DEPS_CHECK:-0}" = "1" ]; then
        return 0
    fi
    [ -z "$_body" ] && return 0

    # Case-insensitive match on "Depends on #<digits>", capture the
    # number after the hash. POSIX-grep -oE then strip the prefix.
    local _deps
    _deps=$(printf '%s\n' "$_body" \
        | grep -oEi 'Depends on #[0-9]+' \
        | sed 's/.*#//')

    [ -z "$_deps" ] && return 0

    local _m _state
    while IFS= read -r _m; do
        [ -z "$_m" ] && continue
        _state=$(_gh_issue_state_lookup "$_m")
        if [ "$_state" != "CLOSED" ]; then
            printf '⚠️  Issue #%s depends on #%s which is still %s.\n' \
                "$_issue_num" "$_m" "$_state"
        fi
    done <<EOF
$_deps
EOF
    return 0
}

# Test helper: looks up the state of dep #M from FAKE_DEPS_STATES.
# Format: "100:CLOSED,101:OPEN". Missing key → OPEN.
_gh_issue_state_lookup() {
    local _key="$1"
    local _map="${FAKE_DEPS_STATES-}"
    [ -z "$_map" ] && { printf 'OPEN'; return 0; }

    local _entries
    IFS=',' read -r -a _entries <<< "$_map"

    local _e _k _v
    for _e in "${_entries[@]}"; do
        _k="${_e%%:*}"
        _v="${_e#*:}"
        if [ "$_k" = "$_key" ]; then
            printf '%s' "$_v"
            return 0
        fi
    done
    printf 'OPEN'
}
