#!/usr/bin/env bats
# tests/bats/lint/shell_common_fallback.bats
# Issue #1612 — scripts/lint_shell_common_fallback.sh 회귀 가드.
#
# 스킬 `**/*.md` 안의 `${SHELL_COMMON}/functions/...` 소싱 지시문에
# `$HOME` 폴백이 빠지면, $SHELL_COMMON 이 비어 있는 셸(Claude Code의 Bash
# tool)에서 agent 가 상대경로로 우회하다 라벨링 함수가 조용히 사라지는
# 실패로 이어진다 — 그 실패를 재현/고정한 회귀 테스트는
# devx_pr_review_all_source_path.bats. 이 파일은 그 원인이 된 문서 결함
# 자체를 잡는 린터를 검사한다.

load '../test_helper'

LINTER="${_BATS_REAL_DOTFILES_ROOT}/scripts/lint_shell_common_fallback.sh"

setup() {
    setup_isolated_home
    SKILLS_DIR="$BATS_TEST_TMPDIR/skills"
    mkdir -p "$SKILLS_DIR/some-skill/references"
}

teardown() {
    teardown_isolated_home
}

run_linter() {
    run env CLAUDE_SKILLS_DIR="$SKILLS_DIR" sh "$LINTER"
}

@test "missing skills directory fails closed" {
    rm -rf "$SKILLS_DIR"
    run_linter
    assert_failure 2
    assert_output --partial "찾을 수 없습니다"
}

@test "bare \${SHELL_COMMON}/functions/ with no \$HOME fallback fails" {
    printf '`source "${SHELL_COMMON}/functions/some_lib.sh"` then run it.\n' \
        >"$SKILLS_DIR/some-skill/SKILL.md"
    run_linter
    assert_failure 1
    assert_output --partial "some-skill/SKILL.md"
}

@test "same line with the \$HOME fallback idiom passes (positive control)" {
    printf '`source "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/some_lib.sh"` then run it.\n' \
        >"$SKILLS_DIR/some-skill/SKILL.md"
    run_linter
    assert_success
}

@test "violation nested under references/ is still caught" {
    printf '. "${SHELL_COMMON}/functions/some_lib.sh"\n' \
        >"$SKILLS_DIR/some-skill/references/detail.md"
    run_linter
    assert_failure 1
    assert_output --partial "references/detail.md"
}

@test "a directory with no violations passes" {
    printf '. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/some_lib.sh"\n' \
        >"$SKILLS_DIR/some-skill/SKILL.md"
    printf 'no shell-common references here\n' \
        >"$SKILLS_DIR/some-skill/references/detail.md"
    run_linter
    assert_success
}
