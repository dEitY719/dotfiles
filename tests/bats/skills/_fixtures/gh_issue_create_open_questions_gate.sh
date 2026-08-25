#!/usr/bin/env bash
# tests/bats/skills/_fixtures/gh_issue_create_open_questions_gate.sh
# Source-of-truth mirror for the Step 3.1 미결 게이트 documented in
# claude/skills/gh-issue-create/SKILL.md and
# references/clarification.md -> "미결 게이트 (Step 3.1)".
#
# The skill itself runs inside Claude, but the gate boils down to two
# pure decisions:
#
#   1. Given a drafted issue body — which of the three D-2 rules fire?
#   2. Given that answer plus --no-ask / DISCUSSION_MODE — does the run
#      call `gh issue create`, ask the user, or decide autonomously?
#
# Both halves live here so a wording change in the skill cannot silently
# widen or narrow the gate. `gh issue create` itself is out of scope —
# mocking `gh` would test the mock — so these tests stay network-free.
#
# Keep this file in sync with references/clarification.md. If a deferral
# phrase or a rule is added, mirror it here so the bats suite catches drift.

# ── D-2 rule 2: deferral wording ─────────────────────────────────────
# "이건 나중에" 를 뜻하는 표현들. 공백 변형("구현시 결정")까지 흡수한다.
_GH_OQ_DEFER='구현[[:space:]]*시[[:space:]]*결정|추후[[:space:]]*결정|논의[[:space:]]*필요|TBD|미정'

# ── D-2 rule 3: unjudgeable acceptance criteria ──────────────────────
_GH_OQ_VAGUE='적절히|필요[[:space:]]*시'

# gh_issue_create_detect_open_items
#   $1 — the drafted issue body
#   $2 — "1" if DISCUSSION_MODE (--as-discussion), "0" otherwise (default "0")
#
# Stdout: one rule id per firing D-2 rule, in rule order, at most once each:
#           open-questions | deferred-wording | unjudgeable-criterion
# Returns: 0 always — the gate classifies, it never errors out.
#
# NF-1: a draft with nothing unresolved prints nothing at all.
gh_issue_create_detect_open_items() {
    _body="$1"
    _discussion="${2:-0}"

    # F-5: an RFC is *supposed* to carry Open Questions. Skip the whole gate.
    if [ "$_discussion" = "1" ]; then
        return 0
    fi

    # Rule 1 — a `## Open Questions` section that is not empty. The bare
    # `-` placeholder the templates ship counts as empty: a skeleton bullet
    # nobody filled in is not an unresolved decision.
    printf '%s\n' "$_body" | awk '
        /^##[[:space:]]/ {
            in_oq = ($0 ~ /^##[[:space:]]+Open[[:space:]]+Questions[[:space:]]*$/)
            next
        }
        in_oq {
            line = $0
            sub(/^[[:space:]]*[-*][[:space:]]*/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            if (line != "") { print "open-questions"; exit }
        }'

    # Rule 2 — deferral wording anywhere in the body, `## Open Questions`
    # section or not. This is the rule that would have caught #1436, whose
    # "구현 시 결정" sat in the 설계 개요 prose.
    #
    # The sed pass is load-bearing: "범위 미정의" is Step 2.1's vocabulary
    # for an ambiguous *request*, not a deferred decision, and a bare 미정
    # substring match would drag every one of those into this gate.
    if printf '%s\n' "$_body" |
        sed 's/미정의/⟪SCOPE-UNDEFINED⟫/g' |
        grep -qiE "$_GH_OQ_DEFER"; then
        printf 'deferred-wording\n'
    fi

    # Rule 3 — an acceptance-criterion checkbox that cannot be judged:
    # blank, still the `...` skeleton, or hedged with 적절히 / 필요 시.
    printf '%s\n' "$_body" | awk -v vague="$_GH_OQ_VAGUE" '
        /^##[[:space:]]/ {
            in_ac = ($0 ~ /수용[[:space:]]*기준/ || $0 ~ /Acceptance[[:space:]]+Criteria/)
            next
        }
        in_ac && /^[[:space:]]*[-*][[:space:]]*\[[ xX]\]/ {
            item = $0
            sub(/^[[:space:]]*[-*][[:space:]]*\[[ xX]\][[:space:]]*/, "", item)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", item)
            if (item == "" || item == "..." || item ~ vague) {
                print "unjudgeable-criterion"
                exit
            }
        }'

    return 0
}

# gh_issue_create_gate_action
#   $1 — detection output from gh_issue_create_detect_open_items (may be empty)
#   $2 — "1" if --no-ask, "0" otherwise (default "0")
#
# Stdout: create | ask | auto-decide
# Returns: 0 always.
#
# DISCUSSION_MODE is not a third argument on purpose: it already zeroed the
# detection output in the function above, so it reaches here as `create`
# through the same branch as "nothing unresolved". One skip, one code path.
gh_issue_create_gate_action() {
    _items="$1"
    _no_ask="${2:-0}"

    # NF-1 / F-5: nothing to settle -> straight to Step 3.5.
    if [ -z "$_items" ]; then
        printf 'create\n'
        return 0
    fi

    # F-4: unattended callers never block the chain — they decide instead.
    if [ "$_no_ask" = "1" ]; then
        printf 'auto-decide\n'
        return 0
    fi

    # F-2: ask, and do not call `gh issue create` before the answer lands.
    printf 'ask\n'
    return 0
}

# gh_issue_create_decision_mark
#   $1 — how the item was settled: user | no-ask | waived
#
# Stdout: the marker that goes into `## 확정 사항 (Decisions)`.
# Returns: 0, or 1 on an unknown source (a caller bug, not a user input).
#
# F-3 requires every entry to say *how* it was decided so the user can
# overturn it later. A user-confirmed decision needs no marker; the other
# two do.
gh_issue_create_decision_mark() {
    case "$1" in
        user) printf '\n' ;;
        no-ask) printf '(자율 판단)\n' ;;
        waived) printf '(보류 — 사용자 지시)\n' ;;
        *) return 1 ;;
    esac
    return 0
}
