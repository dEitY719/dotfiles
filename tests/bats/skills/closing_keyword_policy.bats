#!/usr/bin/env bats
# tests/bats/skills/closing_keyword_policy.bats
# Verify the closing-keyword policy from issue #392:
#   - skill (gh-commit / gh-pr) docs only generate Closes/Fixes
#   - commit-msg hook (git/hooks/checks/closing_keyword_check.sh) rejects
#     Refs / Resolves / See / References at the start of a footer line
#   - hook accepts Closes / Fixes / no-footer
#   - --no-verify escape works (covered indirectly: git itself skips the
#     hook on --no-verify, so we only verify the hook returns 0/1 cleanly)

load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/git/hooks/checks/closing_keyword_check.sh"
    MSG_FILE="$TEST_TEMP_HOME/COMMIT_EDITMSG"
}

teardown() {
    teardown_isolated_home
}

# ─── Hook: accepts allowed keywords ──────────────────────────────────────

@test "hook: 'Closes #N' footer passes" {
    cat >"$MSG_FILE" <<'EOF'
feat(scope): subject

body explaining the why.

Closes #392
EOF
    run check_closing_keyword "$MSG_FILE"
    assert_success
}

@test "hook: 'Fixes #N' footer passes" {
    cat >"$MSG_FILE" <<'EOF'
fix(scope): subject

Fixes #100
EOF
    run check_closing_keyword "$MSG_FILE"
    assert_success
}

@test "hook: no footer at all passes" {
    cat >"$MSG_FILE" <<'EOF'
chore: tidy up

just cleanup, no issue linked.
EOF
    run check_closing_keyword "$MSG_FILE"
    assert_success
}

@test "hook: inline '(part of #N)' in body passes" {
    cat >"$MSG_FILE" <<'EOF'
feat(scope): partial work

This is WIP (part of #200) — leaving the issue open intentionally.
EOF
    run check_closing_keyword "$MSG_FILE"
    assert_success
}

# ─── Hook: rejects forbidden keywords ────────────────────────────────────

@test "hook: 'Refs #N' is rejected" {
    cat >"$MSG_FILE" <<'EOF'
feat(scope): subject

Refs #200
EOF
    run check_closing_keyword "$MSG_FILE"
    [ "$status" -eq 1 ]
    assert_output --partial "forbidden closing keyword"
    assert_output --partial "Closes #N"
}

@test "hook: 'Resolves #N' is rejected" {
    cat >"$MSG_FILE" <<'EOF'
feat(scope): subject

Resolves #300
EOF
    run check_closing_keyword "$MSG_FILE"
    [ "$status" -eq 1 ]
    assert_output --partial "forbidden closing keyword"
}

@test "hook: 'See #N' is rejected" {
    cat >"$MSG_FILE" <<'EOF'
feat(scope): subject

See #400
EOF
    run check_closing_keyword "$MSG_FILE"
    [ "$status" -eq 1 ]
    assert_output --partial "forbidden closing keyword"
}

@test "hook: 'References #N' is rejected" {
    cat >"$MSG_FILE" <<'EOF'
feat(scope): subject

References #500
EOF
    run check_closing_keyword "$MSG_FILE"
    [ "$status" -eq 1 ]
    assert_output --partial "forbidden closing keyword"
}

@test "hook: comment line starting with '#' does not trigger" {
    # git commented-out template hints (e.g. "# Refs #N" instructional
    # text) must be ignored by the check.
    cat >"$MSG_FILE" <<'EOF'
feat(scope): subject

# This commented line mentions Refs #999 but should be ignored.
Closes #1
EOF
    run check_closing_keyword "$MSG_FILE"
    assert_success
}

@test "hook: missing message file is a no-op (does not block)" {
    run check_closing_keyword "$TEST_TEMP_HOME/does-not-exist"
    assert_success
}

@test "hook: lowercase 'refs #N' is rejected (GitHub keywords are case-insensitive)" {
    cat >"$MSG_FILE" <<'EOF'
feat(scope): subject

refs #200
EOF
    run check_closing_keyword "$MSG_FILE"
    [ "$status" -eq 1 ]
    assert_output --partial "forbidden closing keyword"
}

@test "hook: mixed-case 'Resolves #N' / 'RESOLVES #N' both rejected" {
    cat >"$MSG_FILE" <<'EOF'
feat(scope): subject

RESOLVES #300
EOF
    run check_closing_keyword "$MSG_FILE"
    [ "$status" -eq 1 ]
    assert_output --partial "forbidden closing keyword"
}

@test "hook: line numbers reported are relative to the original file" {
    # Subject on line 1, blank line on 2, comment on 3, blank on 4, footer on 5.
    # The diagnostic must report '5:' not '2:' (which is what the old
    # `grep -v '^#' | grep -n` two-stage pipeline would produce).
    cat >"$MSG_FILE" <<'EOF'
feat(scope): subject

# A commented hint line that mentions Closes #1 (just guidance).

Refs #200
EOF
    run check_closing_keyword "$MSG_FILE"
    [ "$status" -eq 1 ]
    assert_output --partial "5:Refs #200"
}

# ─── Skill side: docs do not instruct skill to emit forbidden keywords ──

@test "skill: gh-commit format doc has no 'Refs #' template/instruction" {
    # Search the canonical skill doc — only Closes/Fixes should appear in
    # template lines or rule lines. Old commit examples elsewhere may use
    # Refs (history not rewritten), but THIS file is the skill SSOT.
    run grep -nE '^[[:space:]]*Refs[[:space:]]+#' \
        "${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-commit/references/commit-message-format.md"
    [ "$status" -eq 1 ]
}

@test "skill: gh-commit format doc has no 'Resolves #' template" {
    run grep -nE '^[[:space:]]*Resolves[[:space:]]+#' \
        "${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-commit/references/commit-message-format.md"
    [ "$status" -eq 1 ]
}

@test "skill: gh-pr body template has no 'Refs #' / 'Resolves #' template line" {
    run grep -nE '^[[:space:]]*(Refs|Resolves)[[:space:]]+#' \
        "${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-pr/references/pr-body-template.md"
    [ "$status" -eq 1 ]
}

@test "skill: gh-commit format doc explicitly forbids the four keywords" {
    run grep -E 'Refs.*Resolves.*See.*References|금지 키워드' \
        "${_BATS_REAL_DOTFILES_ROOT}/claude/skills/gh-commit/references/commit-message-format.md"
    assert_success
}
