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
#
# `미정` 은 나머지와 달리 토큰 경계를 요구한다 (PR #1455 agy BLOCKER):
# 부분 문자열로 잡으면 "김미정"(인명) · "장미정원" · "범위 미정의"(Step 2.1
# 어휘) 가 전부 미결로 오탐되고, 오탐의 대가는 **이슈 생성 차단**이라 누락보다
# 비싸다. 앞뒤가 줄 끝이거나 ASCII 공백/구두점이어야 하며, 뒤에는 아래 조사·
# 서술형 어미만 허용한다 — "미정임" / "미정이다" 는 살리고 "미정의" 는 버린다.
#
# 경계를 `[^가-힣]` 대신 `[[:space:]]|[[:punct:]]` 로 쓰는 것은 이식성 문제다:
# 다중바이트 범위 표현은 로케일에 의존해 C 로케일에서 grep 이
# `Invalid collation character` 로 죽는다(bats 격리 HOME 이 그 조건이다).
# ASCII 클래스는 한글 바이트와 절대 매치되지 않으므로 경계 의미는 동일하면서
# 로케일에 독립적이다.
_GH_OQ_TOKEN_L='(^|[[:space:]]|[[:punct:]])'
_GH_OQ_TOKEN_R='([[:space:]]|[[:punct:]]|$)'
_GH_OQ_MIJEONG="${_GH_OQ_TOKEN_L}미정(이다|이며|이고|입니다|임)?${_GH_OQ_TOKEN_R}"
_GH_OQ_DEFER="구현[[:space:]]*시[[:space:]]*결정|추후[[:space:]]*결정|논의[[:space:]]*필요|TBD|${_GH_OQ_MIJEONG}"

# ── D-2 rule 3: unjudgeable acceptance criteria ──────────────────────
_GH_OQ_VAGUE='적절히|필요[[:space:]]*시'

# 판정 기준이 사는 섹션들. `수용 기준` 만 보면 함께 배포되는 다른 템플릿의
# 검증 절이 통째로 빠진다 (PR #1455 codex BLOCKER): `fix`/`perf`/`refactor`/
# `test` 는 `## 검증`, `verify` 는 `## Verification Goal` 을 쓴다.
_GH_OQ_CRITERIA_SECTION='수용[[:space:]]*기준|Acceptance[[:space:]]+Criteria|검증|Verification'

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
    # The 미정 boundary lives in the pattern itself (see `_GH_OQ_MIJEONG`),
    # which is why there is no sed pre-pass here: "범위 미정의" is excluded
    # by the trailing 한글 boundary, same as "김미정" is by the leading one.
    if printf '%s\n' "$_body" | grep -qiE "$_GH_OQ_DEFER"; then
        printf 'deferred-wording\n'
    fi

    # Rule 3 — a criterion that cannot be judged: blank, still the `...`
    # skeleton, or hedged with 적절히 / 필요 시.
    #
    # Two widenings from the PR #1455 review. The checkbox pattern takes
    # `[ ]+` inside the brackets, because `- [   ]` is a checkbox a human
    # typed and `\[[ xX]\]` silently walked past it (agy FOLLOW-UP). And a
    # criterion counts whether or not it is a checkbox: `fix`/`perf`/
    # `refactor`/`test` write `## 검증` as plain bullets, so a checkbox-only
    # scan let every one of those through (codex BLOCKER).
    printf '%s\n' "$_body" | awk -v vague="$_GH_OQ_VAGUE" -v sect="$_GH_OQ_CRITERIA_SECTION" '
        /^##[[:space:]]/ { in_ac = ($0 ~ sect); next }
        in_ac && /^[[:space:]]*[-*][[:space:]]/ {
            item = $0
            sub(/^[[:space:]]*[-*][[:space:]]*(\[[ xX]+\][[:space:]]*)?/, "", item)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", item)
            if (item == "" || item == "..." || item ~ vague) {
                print "unjudgeable-criterion"
                exit
            }
        }
        in_ac && /^[[:space:]]*[-*][[:space:]]*$/ {
            print "unjudgeable-criterion"
            exit
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
#   $2 — "1" if --no-ask, "0" otherwise (default "0")
#
# Stdout: the marker that goes into `## 확정 사항 (Decisions)`.
# Returns: 0; 1 on an unknown source, or on `waived` under --no-ask.
#
# F-3 requires every entry to say *how* it was decided so the user can
# overturn it later. A user-confirmed decision needs no marker; the other
# two do.
#
# `waived` under --no-ask returns 1 on purpose (PR #1455 codex BLOCKER).
# "그냥 만들어" is a live human overriding the gate for their own issue, and
# a labeled deferral is still a deferral — it is not an executable choice for
# an unattended consumer. Unattended callers get the D-4 ladder (repo
# convention -> conservative default -> drop from the criteria), never a
# marker that just renames the unresolved item.
gh_issue_create_decision_mark() {
    _source="$1"
    _no_ask="${2:-0}"

    if [ "$_source" = "waived" ] && [ "$_no_ask" = "1" ]; then
        return 1
    fi

    case "$_source" in
        user) printf '\n' ;;
        no-ask) printf '(자율 판단)\n' ;;
        waived) printf '(보류 — 사용자 지시)\n' ;;
        *) return 1 ;;
    esac
    return 0
}
