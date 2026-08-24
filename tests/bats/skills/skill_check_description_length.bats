#!/usr/bin/env bats
# tests/bats/skills/skill_check_description_length.bats
# Verify Check 16 (Description Length) documented in
#   claude/skills/skill-check/references/checks.md
# Source-of-truth fixture: _fixtures/skill_description_length.sh
#
# skill:check is AI-interpreted markdown with no shell entry point; the fixture
# is the executable form of Check 16 so bats can pin the boundaries.
#
# Issue #1411 verification checklist:
#   F-1  frontmatter description is extracted for both single-line and
#        folded (`>-`) forms, collapsed to one whitespace-normalised line
#   F-2  extraction stops at the next top-level key, never swallowing
#        allowed-tools / compatibility / metadata
#   F-3  length is counted in CHARACTERS, not bytes (Korean triggers are
#        3 bytes per glyph — byte counting would over-report by ~3x)
#   F-4  verdict boundaries: PASS <= 250 | WARN 251-400 | FAIL > 400
#   F-5  a skill with no description yields no verdict (Check 3 owns that)

load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/skill_description_length.sh"
    SKILL_MD="${TEST_TEMP_HOME}/SKILL.md"
}

teardown() {
    teardown_isolated_home
    unset SKILL_MD
}

# ---- fixture builders ----------------------------------------------------

_seed_single_line() {
    cat >"$SKILL_MD" <<'EOF'
---
name: demo:one
description: Short single-line description.
allowed-tools: Bash, Read
---

# demo
EOF
}

_seed_folded() {
    cat >"$SKILL_MD" <<'EOF'
---
name: demo:folded
description: >-
  First line of the folded description.
  Second line continues it.
  Third line ends it.
allowed-tools: Bash
---

# demo
EOF
}

_seed_folded_then_metadata() {
    cat >"$SKILL_MD" <<'EOF'
---
name: demo:meta
description: >-
  Only this sentence belongs to the description.
metadata:
  model_recommendation:
    tier: sonnet
    reason: "this must never be counted as description text"
compatibility:
  tools: Read
---

# demo
EOF
}

_seed_korean() {
    # 6 characters / 12 bytes — proves character counting, not byte counting.
    cat >"$SKILL_MD" <<'EOF'
---
name: demo:kor
description: 가나다abc
---

# demo
EOF
}

_seed_no_description() {
    cat >"$SKILL_MD" <<'EOF'
---
name: demo:none
allowed-tools: Bash
---

# demo
EOF
}

_seed_of_length() {
    # $1 = desired description character count (ASCII, so chars == bytes here)
    local _body
    _body="$(printf 'x%.0s' $(seq 1 "$1"))"
    {
        printf -- '---\n'
        printf 'name: demo:len\n'
        printf 'description: %s\n' "$_body"
        printf -- '---\n\n# demo\n'
    } >"$SKILL_MD"
}

# ---- F-1: extraction, both frontmatter forms ────────────────────────────

@test "extract: single-line description is returned verbatim" {
    _seed_single_line
    run skill_desc_extract "$SKILL_MD"
    assert_success
    assert_output 'Short single-line description.'
}

@test "extract: folded description is collapsed to one line" {
    _seed_folded
    run skill_desc_extract "$SKILL_MD"
    assert_success
    assert_output 'First line of the folded description. Second line continues it. Third line ends it.'
}

# ---- F-2: extraction stops at the next top-level key ────────────────────

@test "extract: does not swallow allowed-tools" {
    _seed_single_line
    run skill_desc_extract "$SKILL_MD"
    assert_success
    refute_output --partial 'allowed-tools'
    refute_output --partial 'Bash'
}

@test "extract: does not swallow metadata or compatibility blocks" {
    _seed_folded_then_metadata
    run skill_desc_extract "$SKILL_MD"
    assert_success
    assert_output 'Only this sentence belongs to the description.'
    refute_output --partial 'model_recommendation'
    refute_output --partial 'never be counted'
}

# ---- F-3: characters, not bytes ─────────────────────────────────────────

@test "length: Korean glyphs count as characters, not bytes" {
    _seed_korean
    run skill_desc_length "$SKILL_MD"
    assert_success
    # '가나다abc' is 6 characters but 12 bytes; byte counting would say 12.
    assert_output '6'
}

# ---- F-4: verdict boundaries ────────────────────────────────────────────

@test "verdict: 250 characters is the PASS ceiling" {
    run skill_desc_verdict 250
    assert_success
    assert_output 'PASS'
}

@test "verdict: 251 characters crosses into WARN" {
    run skill_desc_verdict 251
    assert_success
    assert_output 'WARN'
}

@test "verdict: 400 characters is the WARN ceiling" {
    run skill_desc_verdict 400
    assert_success
    assert_output 'WARN'
}

@test "verdict: 401 characters is FAIL" {
    run skill_desc_verdict 401
    assert_success
    assert_output 'FAIL'
}

@test "verdict: end-to-end from a seeded SKILL.md at the PASS ceiling" {
    _seed_of_length 250
    run skill_desc_length "$SKILL_MD"
    assert_success
    assert_output '250'

    run skill_desc_verdict "$(skill_desc_length "$SKILL_MD")"
    assert_success
    assert_output 'PASS'
}

@test "verdict: end-to-end from a seeded SKILL.md just over the ceiling" {
    _seed_of_length 251
    run skill_desc_verdict "$(skill_desc_length "$SKILL_MD")"
    assert_success
    assert_output 'WARN'
}

# ---- F-5: missing description is Check 3's business, not Check 16's ─────

@test "extract: missing description reports failure instead of empty PASS" {
    _seed_no_description
    run skill_desc_extract "$SKILL_MD"
    assert_failure
}

@test "length: missing description reports failure instead of 0" {
    _seed_no_description
    run skill_desc_length "$SKILL_MD"
    assert_failure
}
