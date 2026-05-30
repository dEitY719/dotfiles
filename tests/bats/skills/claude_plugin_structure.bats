#!/usr/bin/env bats
# tests/bats/skills/claude_plugin_structure.bats
# Verify the structure spec shared by
#   claude/skills/claude-plugin-structure-check/   (M1-M6 / R1-R4 evaluation)
#   claude/skills/claude-plugin-structure-refactor/ (dry-run / --apply / --op)
# Source-of-truth fixture: _fixtures/claude_plugin_structure.sh
#
# Four scenarios from the design test strategy:
#   1. Perfect structure        -> check PASS / refactor no-op
#   2. Mandatory missing        -> check FAIL / refactor --apply -> recheck PASS
#   3. Recommended missing       -> check WARN / refactor --op    -> recheck PASS
#   4. Dry-run idempotency       -> dry-run touches nothing, verdict unchanged

load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1091
    source "${_BATS_REAL_DOTFILES_ROOT}/tests/bats/skills/_fixtures/claude_plugin_structure.sh"
    REPO="${TEST_TEMP_HOME}/repo"
}

teardown() {
    teardown_isolated_home
    unset REPO
}

# ---- fixture builders ----------------------------------------------------

_seed_skill() {
    # $1=repo  builds plugins/demo/skills/visualize/SKILL.md (name matches dir)
    mkdir -p "$1/plugins/demo/skills/visualize"
    printf 'name: visualize\ndescription: demo skill\n' \
        > "$1/plugins/demo/skills/visualize/SKILL.md"
}

_seed_mandatory_json() {
    mkdir -p "$1/.claude-plugin" "$1/plugins/demo/.claude-plugin"
    printf '{ "name": "repo", "plugins": ["./plugins/demo"] }\n' \
        > "$1/.claude-plugin/marketplace.json"
    printf '{ "name": "demo", "version": "0.0.0", "skills": ["./skills/visualize"] }\n' \
        > "$1/plugins/demo/.claude-plugin/plugin.json"
}

_seed_docs_dirs() { mkdir -p "$1/docs/skill-guides" "$1/docs/skill-output"; }

_seed_readme() { printf '# repo\n\nSee [docs/](./docs/).\n' > "$1/README.md"; }

_seed_recommended_files() {
    printf '<!-- guide -->\n' > "$1/docs/skill-guides/visualize.html"
    printf '<!-- usage -->\n' > "$1/docs/skill-output/visualize-usage.md"
}

build_perfect() {
    _seed_skill "$1"; _seed_mandatory_json "$1"; _seed_docs_dirs "$1"
    _seed_readme "$1"; _seed_recommended_files "$1"
}

# ---- Scenario 1: perfect -------------------------------------------------

@test "perfect repo -> verdict PASS" {
    build_perfect "$REPO"
    run cps_verdict "$REPO"
    assert_success
    assert_output PASS
}

@test "perfect repo -> refactor --apply is a no-op (verdict still PASS)" {
    build_perfect "$REPO"
    before="$(find "$REPO" -type f | sort)"
    cps_refactor "$REPO" op apply
    after="$(find "$REPO" -type f | sort)"
    [ "$before" = "$after" ]
    run cps_verdict "$REPO"
    assert_output PASS
}

# ---- Scenario 2: mandatory missing --------------------------------------

@test "mandatory missing (no marketplace/plugin json) -> verdict FAIL" {
    _seed_skill "$REPO"; _seed_docs_dirs "$REPO"
    _seed_readme "$REPO"; _seed_recommended_files "$REPO"
    run cps_check_M1 "$REPO"; assert_output FAIL
    run cps_check_M3 "$REPO"; assert_output FAIL
    run cps_verdict "$REPO"; assert_output FAIL
}

@test "mandatory missing -> refactor --apply (mp) -> recheck PASS" {
    _seed_skill "$REPO"; _seed_docs_dirs "$REPO"
    _seed_readme "$REPO"; _seed_recommended_files "$REPO"
    cps_refactor "$REPO" mp apply
    run cps_check_M1 "$REPO"; assert_output PASS
    run cps_check_M3 "$REPO"; assert_output PASS
    run cps_verdict "$REPO"; assert_output PASS
}

@test "mandatory apply writes VALID json skeletons" {
    _seed_skill "$REPO"; _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    _seed_recommended_files "$REPO"
    cps_refactor "$REPO" mp apply
    run jq empty "$REPO/.claude-plugin/marketplace.json"; assert_success
    run jq empty "$REPO/plugins/demo/.claude-plugin/plugin.json"; assert_success
}

# ---- Scenario 3: recommended missing ------------------------------------

@test "recommended missing (no guide/usage) -> verdict WARN" {
    _seed_skill "$REPO"; _seed_mandatory_json "$REPO"
    _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    run cps_check_R1 "$REPO"; assert_output WARN
    run cps_check_R2 "$REPO"; assert_output WARN
    run cps_verdict "$REPO"; assert_output WARN
}

@test "recommended missing -> refactor --apply --op -> recheck PASS" {
    _seed_skill "$REPO"; _seed_mandatory_json "$REPO"
    _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    cps_refactor "$REPO" op apply
    run cps_check_R1 "$REPO"; assert_output PASS
    run cps_check_R2 "$REPO"; assert_output PASS
    run cps_verdict "$REPO"; assert_output PASS
}

@test "mandatory scope (mp) does NOT create recommended stubs" {
    _seed_skill "$REPO"; _seed_mandatory_json "$REPO"
    _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    cps_refactor "$REPO" mp apply
    run cps_check_R1 "$REPO"; assert_output WARN
}

# ---- Scenario 4: dry-run idempotency ------------------------------------

@test "dry-run touches nothing and leaves verdict FAIL" {
    _seed_skill "$REPO"; _seed_docs_dirs "$REPO"
    _seed_readme "$REPO"; _seed_recommended_files "$REPO"
    before="$(find "$REPO" -type f | sort)"
    cps_refactor "$REPO" op dry-run
    after="$(find "$REPO" -type f | sort)"
    [ "$before" = "$after" ]
    [ ! -f "$REPO/.claude-plugin/marketplace.json" ]
    run cps_verdict "$REPO"; assert_output FAIL
}

# ---- N/A rule ------------------------------------------------------------

@test "plugin with 0 skills -> R1/R2 are N/A, not FAIL" {
    mkdir -p "$REPO/plugins/demo/skills"
    _seed_mandatory_json "$REPO"; _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    run cps_check_R1 "$REPO"; assert_output "N/A"
    run cps_check_R2 "$REPO"; assert_output "N/A"
}

# ---- R4 naming -----------------------------------------------------------

@test "R4 naming mismatch (name colon != dir hyphen) -> WARN" {
    mkdir -p "$REPO/plugins/demo/skills/structure-check"
    printf 'name: structure:wrong\ndescription: x\n' \
        > "$REPO/plugins/demo/skills/structure-check/SKILL.md"
    _seed_mandatory_json "$REPO"; _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    run cps_check_R4 "$REPO"; assert_output WARN
}

@test "R4 naming match (structure:check <-> structure-check) -> PASS" {
    mkdir -p "$REPO/plugins/demo/skills/structure-check"
    printf 'name: structure:check\ndescription: x\n' \
        > "$REPO/plugins/demo/skills/structure-check/SKILL.md"
    _seed_mandatory_json "$REPO"; _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    run cps_check_R4 "$REPO"; assert_output PASS
}

@test "R4 tolerates a quoted name: value (PR #894 gemini review)" {
    mkdir -p "$REPO/plugins/demo/skills/structure-check"
    printf 'name: "structure:check"\ndescription: x\n' \
        > "$REPO/plugins/demo/skills/structure-check/SKILL.md"
    _seed_mandatory_json "$REPO"; _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    run cps_check_R4 "$REPO"; assert_output PASS
}

# ---- N/A for absent subject on mandatory checks (PR #894 gemini review) --

@test "no plugins -> M3 is N/A (M2 owns the FAIL), verdict still FAIL" {
    mkdir -p "$REPO/.claude-plugin"
    printf '{ "name": "repo", "plugins": [] }\n' > "$REPO/.claude-plugin/marketplace.json"
    _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    run cps_check_M2 "$REPO"; assert_output FAIL
    run cps_check_M3 "$REPO"; assert_output "N/A"
    run cps_verdict "$REPO"; assert_output FAIL
}

@test "plugin with 0 skills -> M4 is N/A, not FAIL" {
    mkdir -p "$REPO/plugins/demo/skills"
    _seed_mandatory_json "$REPO"; _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    run cps_check_M4 "$REPO"; assert_output "N/A"
}

# ---- multi-plugin / multi-skill JSON skeletons (PR #894 gemini review) --

@test "mandatory apply lists ALL plugins in marketplace.json" {
    mkdir -p "$REPO/plugins/alpha/skills/s1" "$REPO/plugins/beta/skills/s2"
    printf 'name: s1\ndescription: x\n' > "$REPO/plugins/alpha/skills/s1/SKILL.md"
    printf 'name: s2\ndescription: x\n' > "$REPO/plugins/beta/skills/s2/SKILL.md"
    _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    cps_refactor "$REPO" mp apply
    run jq -r '.plugins | length' "$REPO/.claude-plugin/marketplace.json"
    assert_output 2
    run jq -e '.plugins | index("./plugins/alpha") and index("./plugins/beta")' \
        "$REPO/.claude-plugin/marketplace.json"
    assert_success
}

@test "mandatory apply lists ALL skills in plugin.json" {
    mkdir -p "$REPO/plugins/demo/skills/s1" "$REPO/plugins/demo/skills/s2"
    printf 'name: s1\ndescription: x\n' > "$REPO/plugins/demo/skills/s1/SKILL.md"
    printf 'name: s2\ndescription: x\n' > "$REPO/plugins/demo/skills/s2/SKILL.md"
    _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    cps_refactor "$REPO" mp apply
    run jq -r '.skills | length' "$REPO/plugins/demo/.claude-plugin/plugin.json"
    assert_output 2
}
