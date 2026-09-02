#!/usr/bin/env bats
# tests/bats/skills/gh_issue_create_open_questions_gate.bats
# Locks the Step 3.1 미결 게이트 and the `--no-ask` escape it ships
# with (#1446): behaviour, via
# _fixtures/gh_issue_create_open_questions_gate.sh — the D-2 detection
# rules and the create/ask/auto-decide dispatch.
#
# #1680: gh-issue-create / devx-autopilot / gh-issue-proceed moved out to
# their own marketplace repos, so the whole "Doc drift" section (which
# grepped claude/skills/**) was dropped — those guards belong in those
# repos now. The fixture below is therefore no longer pinned to the
# SKILL.md prose it mirrors.

bats_require_minimum_version 1.5.0

load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/gh_issue_create_open_questions_gate.sh"
}

teardown() {
    teardown_isolated_home
}

# ── D-2 rule 1: a non-empty `## Open Questions` section ──────────────
@test "gate: a filled-in Open Questions section is an open item" {
    run gh_issue_create_detect_open_items \
        "## Open Questions
- 감지 임계값은 실제 관측 데이터가 필요하다
"
    assert_success
    assert_output 'open-questions'
}

@test "gate: the bare '-' template placeholder is not an open item" {
    run gh_issue_create_detect_open_items \
        "## Open Questions
-

## References
- 없음
"
    assert_success
    assert_output ''
}

@test "gate: Open Questions detection stops at the next heading" {
    run gh_issue_create_detect_open_items \
        "## Open Questions

## References
- 관련 이슈 없음
"
    assert_success
    assert_output ''
}

# ── D-2 rule 2: deferral wording outside any Open Questions section ──
# This is the #1436 case: the deferral sat in the 설계 개요 prose.
@test "gate: '구현 시 결정' in prose is an open item" {
    run gh_issue_create_detect_open_items \
        "## 설계 개요 (Design)
정확한 임계값과 백오프 길이는 구현 시 결정하며, 우선 골격만 잡는다.
"
    assert_success
    assert_output 'deferred-wording'
}

@test "gate: '추후 결정' is an open item" {
    run gh_issue_create_detect_open_items "알림 여부는 추후 결정한다."
    assert_success
    assert_output 'deferred-wording'
}

@test "gate: '논의 필요' is an open item" {
    run gh_issue_create_detect_open_items "이 부분은 논의 필요."
    assert_success
    assert_output 'deferred-wording'
}

@test "gate: 'TBD' is an open item (case-insensitive)" {
    run gh_issue_create_detect_open_items "backoff: tbd"
    assert_success
    assert_output 'deferred-wording'
}

@test "gate: '미정' is an open item" {
    run gh_issue_create_detect_open_items "알림 채널: 미정"
    assert_success
    assert_output 'deferred-wording'
}

# Negative: Step 2.1's own vocabulary must not leak into this gate.
@test "gate: '범위 미정의' is Step 2.1 wording, not a deferral" {
    run gh_issue_create_detect_open_items \
        "이 요청은 feature 범위 미정의 상태로 들어왔다."
    assert_success
    assert_output ''
}

# 미정 token boundary — PR #1455 agy BLOCKER. A false positive here BLOCKS
# issue creation, so precision beats recall on this one pattern.
@test "gate: '김미정' (a personal name) is not a deferral" {
    run gh_issue_create_detect_open_items "리뷰어는 김미정 님으로 배정한다."
    assert_success
    assert_output ''
}

@test "gate: '장미정원' does not trip the 미정 rule" {
    run gh_issue_create_detect_open_items "테스트 픽스처 이름은 장미정원이다."
    assert_success
    assert_output ''
}

@test "gate: '미정임' (with a copula ending) is still an open item" {
    run gh_issue_create_detect_open_items "알림 채널은 미정임"
    assert_success
    assert_output 'deferred-wording'
}

@test "gate: '미정이다' is still an open item" {
    run gh_issue_create_detect_open_items "백오프 길이는 아직 미정이다."
    assert_success
    assert_output 'deferred-wording'
}

@test "gate: '미정' followed by punctuation is an open item" {
    run gh_issue_create_detect_open_items "임계값: 미정."
    assert_success
    assert_output 'deferred-wording'
}

# ── D-2 rule 3: unjudgeable acceptance criteria ──────────────────────
@test "gate: an empty acceptance-criterion checkbox is an open item" {
    run gh_issue_create_detect_open_items \
        "## 수용 기준 (Acceptance Criteria)
- [ ]
"
    assert_success
    assert_output 'unjudgeable-criterion'
}

@test "gate: the '...' skeleton criterion is an open item" {
    run gh_issue_create_detect_open_items \
        "## 수용 기준 (Acceptance Criteria)
- [ ] ...
"
    assert_success
    assert_output 'unjudgeable-criterion'
}

@test "gate: a criterion hedged with '적절히' is an open item" {
    run gh_issue_create_detect_open_items \
        "## 수용 기준 (Acceptance Criteria)
- [ ] 백오프가 적절히 늘어난다
"
    assert_success
    assert_output 'unjudgeable-criterion'
}

@test "gate: a criterion hedged with '필요 시' is an open item" {
    run gh_issue_create_detect_open_items \
        "## Acceptance Criteria
- [ ] 필요 시 알림을 보낸다
"
    assert_success
    assert_output 'unjudgeable-criterion'
}

@test "gate: a concrete, checkable criterion is not an open item" {
    run gh_issue_create_detect_open_items \
        "## 수용 기준 (Acceptance Criteria)
- [ ] 3회 연속 실패하면 tick 을 보류하고 exit 2 로 끝난다
"
    assert_success
    assert_output ''
}

# 적절히 / 필요 시 outside the acceptance-criteria section is prose, not a
# criterion — rule 3 is scoped to the section on purpose.
@test "gate: '적절히' outside the acceptance criteria does not fire rule 3" {
    run gh_issue_create_detect_open_items \
        "## 배경 (Why)
기존 구현은 재시도를 적절히 하지 못한다.
"
    assert_success
    assert_output ''
}

# Multi-space checkbox — PR #1455 agy FOLLOW-UP. `- [   ]` is a checkbox a
# human typed; the old `\[[ xX]\]` pattern walked straight past it.
@test "gate: a multi-space empty checkbox is an open item" {
    run gh_issue_create_detect_open_items \
        "## 수용 기준 (Acceptance Criteria)
- [   ]
"
    assert_success
    assert_output 'unjudgeable-criterion'
}

# Non-feat templates — PR #1455 codex BLOCKER. `fix`/`perf`/`refactor`/`test`
# ship `## 검증` and `verify` ships `## Verification Goal`; both write plain
# bullets, so a checkbox-only scan under 수용 기준 missed them entirely.
@test "gate: an empty bullet under '## 검증' is an open item" {
    run gh_issue_create_detect_open_items \
        "## 검증 (Verification)
-
"
    assert_success
    assert_output 'unjudgeable-criterion'
}

@test "gate: a hedged bullet under '## 검증' is an open item" {
    run gh_issue_create_detect_open_items \
        "## 검증
- 재현 스크립트를 필요 시 돌려 본다
"
    assert_success
    assert_output 'unjudgeable-criterion'
}

@test "gate: a hedged bullet under '## Verification Goal' is an open item" {
    run gh_issue_create_detect_open_items \
        "## Verification Goal
- 로그를 적절히 확인한다
"
    assert_success
    assert_output 'unjudgeable-criterion'
}

@test "gate: a concrete bullet under '## 검증' is not an open item" {
    run gh_issue_create_detect_open_items \
        "## 검증 (Verification)
- \`./tests/test\` 가 exit 0 으로 끝난다
"
    assert_success
    assert_output ''
}

# ── Multiple rules ───────────────────────────────────────────────────
@test "gate: rules report in rule order, at most once each" {
    run gh_issue_create_detect_open_items \
        "## Open Questions
- 임계값 미정

## 설계 개요
백오프 길이는 구현 시 결정한다. 알림 여부도 추후 결정.

## 수용 기준 (Acceptance Criteria)
- [ ] ...
"
    assert_success
    assert_line --index 0 'open-questions'
    assert_line --index 1 'deferred-wording'
    assert_line --index 2 'unjudgeable-criterion'
    [ "${#lines[@]}" -eq 3 ]
}

# ── NF-1: silent on a clean draft ────────────────────────────────────
@test "gate: a fully decided draft produces no output at all" {
    run gh_issue_create_detect_open_items \
        "## TL;DR
게이트를 추가한다.

## 확정 사항 (Decisions)
- 임계값 3회 — 근거: 인접 구현 issue-watcher 와 동일

## 수용 기준 (Acceptance Criteria)
- [ ] 3회 실패 후 tick 이 보류된다
"
    assert_success
    assert_output ''
}

# ── F-5: --as-discussion skips the gate entirely ─────────────────────
@test "gate: DISCUSSION_MODE skips detection even with open items" {
    run gh_issue_create_detect_open_items \
        "## Open Questions
- 이게 정말 필요한가?
" 1
    assert_success
    assert_output ''
}

# ── Dispatch: create / ask / auto-decide ─────────────────────────────
@test "dispatch: no open items -> create" {
    run gh_issue_create_gate_action '' 0
    assert_success
    assert_output 'create'
}

@test "dispatch: open items without --no-ask -> ask (never create)" {
    run gh_issue_create_gate_action 'open-questions' 0
    assert_success
    assert_output 'ask'
    refute_output 'create'
}

@test "dispatch: open items with --no-ask -> auto-decide, never ask" {
    run gh_issue_create_gate_action 'deferred-wording' 1
    assert_success
    assert_output 'auto-decide'
    refute_output 'ask'
}

@test "dispatch: --no-ask on a clean draft still just creates" {
    run gh_issue_create_gate_action '' 1
    assert_success
    assert_output 'create'
}

# ── F-3: the 확정 사항 markers ───────────────────────────────────────
@test "decision mark: a user-confirmed decision carries no marker" {
    run gh_issue_create_decision_mark user
    assert_success
    assert_output ''
}

@test "decision mark: a --no-ask decision is marked (자율 판단)" {
    run gh_issue_create_decision_mark no-ask
    assert_success
    assert_output '(자율 판단)'
}

@test "decision mark: a user-waived item is marked (보류 — 사용자 지시)" {
    run gh_issue_create_decision_mark waived
    assert_success
    assert_output '(보류 — 사용자 지시)'
}

# PR #1455 codex BLOCKER — the "그냥 만들어" escape is a live human overriding
# the gate for their own issue. Unattended callers must never reach it: a
# labeled deferral is still a deferral, not an executable choice.
@test "decision mark: waived is refused under --no-ask" {
    run gh_issue_create_decision_mark waived 1
    assert_failure
    assert_output ''
}

@test "decision mark: waived is still allowed with a human present" {
    run gh_issue_create_decision_mark waived 0
    assert_success
    assert_output '(보류 — 사용자 지시)'
}

@test "decision mark: an unknown source is a caller bug" {
    run gh_issue_create_decision_mark bogus
    assert_failure
}
