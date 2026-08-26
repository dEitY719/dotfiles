#!/usr/bin/env bats
# tests/bats/lint/changelog_fragments.bats
# Issue #1471 — scripts/lint_changelog_fragments.sh 회귀 가드.
#
# fragment 포맷 규칙을 코드로 강제한다. 규칙이 산문(CLAUDE.md/AGENTS.md)에만
# 있던 시절 `docs/public/changelog.md` 에 `## 2026-08-13` 헤더가 두 개 뚫린 것이
# 이 테스트가 존재하는 이유다.
#
# 각 FAIL 케이스마다 "그 한 가지만 바꾼" 양성 대조(PASS)를 함께 둔다 — 린터가
# 통째로 죽어도 FAIL 단언만으로는 구별되지 않기 때문이다.

load '../test_helper'

LINTER="${_BATS_REAL_DOTFILES_ROOT}/scripts/lint_changelog_fragments.sh"

setup() {
    setup_isolated_home
    FRAG_DIR="$BATS_TEST_TMPDIR/changelog.d"
    mkdir -p "$FRAG_DIR"
}

teardown() {
    teardown_isolated_home
}

run_linter() {
    run env CHANGELOG_FRAGMENT_DIR="$FRAG_DIR" sh "$LINTER"
}

# ─────────────────────────────────────────────────────────────────────────
# 정상 케이스 (양성 대조의 기준선)
# ─────────────────────────────────────────────────────────────────────────

@test "valid fragment directory passes" {
    printf -- '- 변경: **A**\n' >"$FRAG_DIR/2026-08-13-1103.md"
    printf -- '- 변경: **B**\n- 변경: **C**\n' >"$FRAG_DIR/2026-08-26-1471.md"
    run_linter
    assert_success
}

@test "missing fragment directory fails closed" {
    # changelog.d 가 유일한 changelog 소스가 된 뒤로 "디렉터리 부재"는
    # 검사할 게 없는 상태가 아니라 소스 전체가 사라진 상태다 — 조용히
    # 통과하면 lint-docs 가 초록인 채로 changelog 를 잃는다 (PR #1475 codex).
    # 형제 린터 lint_docs_filenames.sh 와 같은 rc 2 를 쓴다: 1(=위반 발견)과
    # 구별되는 "검사 대상 자체가 없음" 코드.
    rm -rf "$FRAG_DIR"
    run_linter
    assert_failure 2
    assert_output --partial "찾을 수 없습니다"
}

# ─────────────────────────────────────────────────────────────────────────
# FAIL 1: 파일명이 <YYYY-MM-DD>-<issue>.md 가 아니다
# ─────────────────────────────────────────────────────────────────────────

@test "filename without the date prefix fails" {
    printf -- '- 변경: **A**\n' >"$FRAG_DIR/changelog-entry.md"
    run_linter
    assert_failure 1
    assert_output --partial "changelog-entry.md"
    assert_output --partial "파일명"
}

@test "filename with a non-numeric issue suffix fails" {
    printf -- '- 변경: **A**\n' >"$FRAG_DIR/2026-08-26-issue.md"
    run_linter
    assert_failure 1
    assert_output --partial "2026-08-26-issue.md"
}

@test "filename with the date prefix and a numeric suffix passes (positive control)" {
    printf -- '- 변경: **A**\n' >"$FRAG_DIR/2026-08-26-1471.md"
    run_linter
    assert_success
}

# ─────────────────────────────────────────────────────────────────────────
# FAIL 2: fragment 안에 마크다운 헤더가 들어 있다 (중복 헤더 클래스의 씨앗)
# ─────────────────────────────────────────────────────────────────────────

@test "fragment containing a date header fails" {
    printf -- '## 2026-08-26\n- 변경: **A**\n' >"$FRAG_DIR/2026-08-26-1471.md"
    run_linter
    assert_failure 1
    assert_output --partial "헤더"
}

@test "same fragment without the header passes (positive control)" {
    printf -- '- 변경: **A**\n' >"$FRAG_DIR/2026-08-26-1471.md"
    run_linter
    assert_success
}

# ─────────────────────────────────────────────────────────────────────────
# FAIL 3: 빈 fragment (수집기가 조용히 무시해 항목이 증발한다)
# ─────────────────────────────────────────────────────────────────────────

@test "empty fragment fails" {
    : >"$FRAG_DIR/2026-08-26-1471.md"
    run_linter
    assert_failure 1
    assert_output --partial "비어"
}

@test "whitespace-only fragment fails" {
    printf -- '   \n\n' >"$FRAG_DIR/2026-08-26-1471.md"
    run_linter
    assert_failure 1
    assert_output --partial "비어"
}

# ─────────────────────────────────────────────────────────────────────────
# FAIL 4: 불릿이 아닌 줄 — 수집기는 비어 있지 않은 모든 줄을 항목으로 싣는다
# ─────────────────────────────────────────────────────────────────────────

@test "non-bullet line fails" {
    printf -- '- 변경: **A**\n그냥 산문 한 줄\n' >"$FRAG_DIR/2026-08-26-1471.md"
    run_linter
    assert_failure 1
    assert_output --partial "산문 한 줄"
}

@test "blank line between bullets passes (positive control)" {
    printf -- '- 변경: **A**\n\n- 변경: **B**\n' >"$FRAG_DIR/2026-08-26-1471.md"
    run_linter
    assert_success
}

# ─────────────────────────────────────────────────────────────────────────
# FAIL 5: `- 변경: **요약**` 계약 — 문서가 강제한다고 말하는 바로 그 형식
# ─────────────────────────────────────────────────────────────────────────

@test "bullet without the 변경: prefix fails" {
    printf -- '- 그냥 불릿\n' >"$FRAG_DIR/2026-08-26-1471.md"
    run_linter
    assert_failure 1
    assert_output --partial "변경:"
}

@test "bullet without a bold summary fails" {
    printf -- '- 변경: 강조 없는 요약\n' >"$FRAG_DIR/2026-08-26-1471.md"
    run_linter
    assert_failure 1
    assert_output --partial "변경:"
}

@test "bullet with an unclosed bold summary fails" {
    printf -- '- 변경: **닫히지 않은 강조\n' >"$FRAG_DIR/2026-08-26-1471.md"
    run_linter
    assert_failure 1
    assert_output --partial "변경:"
}

@test "documented format passes (positive control)" {
    printf -- '- 변경: **요약**\n' >"$FRAG_DIR/2026-08-26-1471.md"
    run_linter
    assert_success
}

# ─────────────────────────────────────────────────────────────────────────
# FAIL 6: 들여쓴 하위 불릿 — CLAUDE.md 가 금지하지만 강제되지 않던 규칙
# ─────────────────────────────────────────────────────────────────────────

@test "indented sub-bullet fails" {
    printf -- '- 변경: **A**\n  - 하위 불릿\n' >"$FRAG_DIR/2026-08-26-1471.md"
    run_linter
    assert_failure 1
}

@test "same two bullets unindented pass (positive control)" {
    printf -- '- 변경: **A**\n- 변경: **B**\n' >"$FRAG_DIR/2026-08-26-1471.md"
    run_linter
    assert_success
}

# ─────────────────────────────────────────────────────────────────────────
# 실제 저장소의 fragment 는 항상 통과해야 한다
# ─────────────────────────────────────────────────────────────────────────

@test "the repository's own changelog.d passes" {
    run env CHANGELOG_FRAGMENT_DIR="${_BATS_REAL_DOTFILES_ROOT}/docs/public/changelog.d" \
        sh "$LINTER"
    assert_success
}

@test "changelog.md is gone — fragments are the only source" {
    assert [ ! -e "${_BATS_REAL_DOTFILES_ROOT}/docs/public/changelog.md" ]
}
