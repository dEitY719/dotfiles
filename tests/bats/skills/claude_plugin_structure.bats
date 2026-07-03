#!/usr/bin/env bats
# tests/bats/skills/claude_plugin_structure.bats
# Verify the structure spec shared by
#   claude/skills/claude-plugin-structure-check/   (M1-M10 / R1-R8 evaluation)
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
    # $schema + description satisfy R6/R7 (#1084); string-form plugins satisfy
    # M7 (source shorthand) / M8 (valid mono path) / M9 (plugins/demo exists).
    mkdir -p "$1/.claude-plugin" "$1/plugins/demo/.claude-plugin"
    printf '{ "$schema": "https://anthropic.com/claude-code/marketplace.schema.json", "name": "repo", "description": "demo marketplace", "plugins": ["./plugins/demo"] }\n' \
        > "$1/.claude-plugin/marketplace.json"
    printf '{ "name": "demo", "version": "0.0.0" }\n' \
        > "$1/plugins/demo/.claude-plugin/plugin.json"
}

_seed_docs_dirs() { mkdir -p "$1/docs/skill-guides" "$1/docs/skill-output"; }

_seed_readme() { printf '# repo\n\nSee [docs/](./docs/).\n' > "$1/README.md"; }

_seed_recommended_files() {
    printf '<!-- guide -->\n' > "$1/docs/skill-guides/visualize.html"
    printf '<!-- usage -->\n' > "$1/docs/skill-output/visualize-usage.md"
}

_seed_readme_links() {
    # $1=repo $2=skill : append a per-skill guide+usage link line (R5)
    printf -- '- `%s`: [guide](docs/skill-guides/%s.html) [usage](docs/skill-output/%s-usage.md)\n' \
        "$2" "$2" "$2" >> "$1/README.md"
}

build_perfect() {
    _seed_skill "$1"; _seed_mandatory_json "$1"; _seed_docs_dirs "$1"
    _seed_readme "$1"; _seed_recommended_files "$1"
    _seed_readme_links "$1" visualize
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
    _seed_readme_links "$REPO" visualize    # recommended satisfied; only mandatory missing
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

# ---- R5 per-skill README links (#905) -----------------------------------

@test "R5 PASS when README links both guide and usage for each skill" {
    build_perfect "$REPO"
    run cps_check_R5 "$REPO"; assert_output PASS
}

@test "R5 WARN when README links the guide but not the usage" {
    _seed_skill "$REPO"; _seed_mandatory_json "$REPO"
    _seed_docs_dirs "$REPO"; _seed_readme "$REPO"; _seed_recommended_files "$REPO"
    printf -- '- [guide](docs/skill-guides/visualize.html)\n' >> "$REPO/README.md"
    run cps_check_R5 "$REPO"; assert_output WARN
    run cps_verdict "$REPO"; assert_output WARN
}

@test "R5 WARN when README has a docs/ link but no per-skill links (R3 PASS gap)" {
    _seed_skill "$REPO"; _seed_mandatory_json "$REPO"
    _seed_docs_dirs "$REPO"; _seed_readme "$REPO"; _seed_recommended_files "$REPO"
    run cps_check_R3 "$REPO"; assert_output PASS
    run cps_check_R5 "$REPO"; assert_output WARN
}

@test "R5 WARN when one of two skills is missing its links" {
    mkdir -p "$REPO/plugins/demo/skills/visualize" "$REPO/plugins/demo/skills/excalidraw"
    printf 'name: visualize\ndescription: x\n' > "$REPO/plugins/demo/skills/visualize/SKILL.md"
    printf 'name: excalidraw\ndescription: x\n' > "$REPO/plugins/demo/skills/excalidraw/SKILL.md"
    _seed_mandatory_json "$REPO"; _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    _seed_readme_links "$REPO" visualize    # excalidraw links intentionally absent
    run cps_check_R5 "$REPO"; assert_output WARN
}

@test "R5 is N/A when the plugin has 0 skills" {
    mkdir -p "$REPO/plugins/demo/skills"
    _seed_mandatory_json "$REPO"; _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    run cps_check_R5 "$REPO"; assert_output "N/A"
}

@test "R5 missing -> refactor --apply --op backfills links -> recheck PASS" {
    _seed_skill "$REPO"; _seed_mandatory_json "$REPO"
    _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    run cps_check_R5 "$REPO"; assert_output WARN
    cps_refactor "$REPO" op apply
    run cps_check_R5 "$REPO"; assert_output PASS
    run cps_verdict "$REPO"; assert_output PASS
}

@test "R5 backfill is idempotent (no duplicate link lines on second apply)" {
    _seed_skill "$REPO"; _seed_mandatory_json "$REPO"
    _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    cps_refactor "$REPO" op apply
    first="$(grep -c 'skill-guides/visualize.html' "$REPO/README.md")"
    cps_refactor "$REPO" op apply
    second="$(grep -c 'skill-guides/visualize.html' "$REPO/README.md")"
    [ "$first" = "$second" ]
}

@test "R5 PASS when guide linked via github.com Pages URL (#911)" {
    # github.com Pages pattern: https://<owner>.github.io/<repo>/skill-guides/<s>.html
    _seed_skill "$REPO"; _seed_mandatory_json "$REPO"
    _seed_docs_dirs "$REPO"; _seed_readme "$REPO"; _seed_recommended_files "$REPO"
    printf -- '- `visualize` ([visual guide](https://acme.github.io/repo/skill-guides/visualize.html))\n' >> "$REPO/README.md"
    printf -- '- [usage](docs/skill-output/visualize-usage.md)\n' >> "$REPO/README.md"
    run cps_check_R5 "$REPO"; assert_output PASS
}

@test "R5 PASS when guide linked via GHE Pages URL (#911)" {
    # GHE Pages pattern: https://<host>/pages/<owner>/<repo>/skill-guides/<s>.html
    _seed_skill "$REPO"; _seed_mandatory_json "$REPO"
    _seed_docs_dirs "$REPO"; _seed_readme "$REPO"; _seed_recommended_files "$REPO"
    printf -- '- `visualize` ([visual guide](https://github.samsungds.net/pages/owner/repo/skill-guides/visualize.html))\n' >> "$REPO/README.md"
    printf -- '- [usage](docs/skill-output/visualize-usage.md)\n' >> "$REPO/README.md"
    run cps_check_R5 "$REPO"; assert_output PASS
}

@test "R5 backfill appends ONLY the missing link (no duplicate of present one)" {
    # gemini #906 review: guide already linked, only usage missing.
    _seed_skill "$REPO"; _seed_mandatory_json "$REPO"
    _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    printf -- '- [guide](docs/skill-guides/visualize.html)\n' >> "$REPO/README.md"
    run cps_check_R5 "$REPO"; assert_output WARN          # usage missing
    cps_refactor "$REPO" op apply
    # guide link still appears exactly once (not re-appended), usage now present
    [ "$(grep -c 'skill-guides/visualize.html' "$REPO/README.md")" = "1" ]
    [ "$(grep -c 'skill-output/visualize-usage.md' "$REPO/README.md")" = "1" ]
    run cps_check_R5 "$REPO"; assert_output PASS
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

@test "mandatory apply writes a plugin.json WITHOUT a skills field (M10, #1084)" {
    # skills are auto-scanned; a skills field fails manifest validation. The
    # skeleton must never write one (superseding the old "lists ALL skills").
    mkdir -p "$REPO/plugins/demo/skills/s1" "$REPO/plugins/demo/skills/s2"
    printf 'name: s1\ndescription: x\n' > "$REPO/plugins/demo/skills/s1/SKILL.md"
    printf 'name: s2\ndescription: x\n' > "$REPO/plugins/demo/skills/s2/SKILL.md"
    _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    cps_refactor "$REPO" mp apply
    run jq -e 'has("skills")' "$REPO/plugins/demo/.claude-plugin/plugin.json"
    assert_output false
    run cps_check_M10 "$REPO"; assert_output PASS
}

# ---- single layout mode (#914) ------------------------------------------
# single = the repo itself is one plugin: marketplace source "./", plugin
# manifest at the repo root, skills at root skills/<s>/ (no plugins/ dir).

_seed_single_skill() {
    # $1=repo  builds root-level skills/visualize/SKILL.md (name matches dir)
    mkdir -p "$1/skills/visualize"
    printf 'name: visualize\ndescription: demo skill\n' \
        > "$1/skills/visualize/SKILL.md"
}

_seed_single_mandatory_json() {
    # marketplace source "./" (single signal) + root plugin.json manifest.
    # $schema + description + the object plugin's homepage satisfy R6/R7 (#1084)
    # so a fully-standard single repo scores PASS.
    mkdir -p "$1/.claude-plugin"
    printf '{ "$schema": "https://anthropic.com/claude-code/marketplace.schema.json", "name": "repo", "description": "demo marketplace", "plugins": [{ "source": "./", "homepage": "https://example.com/repo" }] }\n' \
        > "$1/.claude-plugin/marketplace.json"
    printf '{ "name": "repo", "version": "0.0.0" }\n' \
        > "$1/.claude-plugin/plugin.json"
}

build_single_perfect() {
    _seed_single_skill "$1"; _seed_single_mandatory_json "$1"; _seed_docs_dirs "$1"
    _seed_readme "$1"; _seed_recommended_files "$1"; _seed_readme_links "$1" visualize
}

@test "mode auto-detects single from marketplace source \"./\"" {
    build_single_perfect "$REPO"
    run _cps_detect_mode "$REPO"
    assert_output single
}

@test "mode auto-detects mono from a plugins/ layout" {
    build_perfect "$REPO"
    run _cps_detect_mode "$REPO"
    assert_output mono
}

@test "mode auto-detects mono from a bare 'plugins/..' source (no leading ./)" {
    # gemini #917 review: hand-written marketplace may omit the leading ./
    mkdir -p "$REPO/.claude-plugin"
    printf '{ "name": "repo", "plugins": [{ "source": "plugins/demo" }] }\n' \
        > "$REPO/.claude-plugin/marketplace.json"
    run _cps_detect_mode "$REPO"
    assert_output mono
}

@test "mode auto-detects single from root plugin.json (no marketplace source)" {
    # filesystem fallback: no plugins/, root manifest present
    mkdir -p "$REPO/.claude-plugin"
    printf '{ "name": "repo", "version": "0.0.0" }\n' > "$REPO/.claude-plugin/plugin.json"
    run _cps_detect_mode "$REPO"
    assert_output single
}

@test "mode defaults to mono when ambiguous (no signals)" {
    mkdir -p "$REPO"; _seed_readme "$REPO"
    run _cps_detect_mode "$REPO"
    assert_output mono
}

@test "single perfect repo -> verdict PASS (no false M2/M3/M4 FAIL)" {
    build_single_perfect "$REPO"
    run cps_verdict "$REPO"
    assert_success
    assert_output PASS
}

@test "single repo scores M2/M3/M4 at the ROOT (#914 false-FAIL fix)" {
    # The core regression: before mode support, a single repo (no plugins/)
    # falsely FAILed M2/M3/M4. With auto-detect they pass at the root.
    build_single_perfect "$REPO"
    run cps_check_M2 "$REPO"; assert_output PASS
    run cps_check_M3 "$REPO"; assert_output PASS
    run cps_check_M4 "$REPO"; assert_output PASS
}

@test "single repo: M5/R1/R2/R5 apply mode-independently" {
    build_single_perfect "$REPO"
    run cps_check_M5 "$REPO"; assert_output PASS
    run cps_check_R1 "$REPO"; assert_output PASS
    run cps_check_R2 "$REPO"; assert_output PASS
    run cps_check_R5 "$REPO"; assert_output PASS
}

@test "single repo missing root manifest -> M2 FAIL, M3 N/A (not double FAIL)" {
    _seed_single_skill "$REPO"; _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    mkdir -p "$REPO/.claude-plugin"
    printf '{ "name": "repo", "plugins": [{ "source": "./" }] }\n' \
        > "$REPO/.claude-plugin/marketplace.json"   # marketplace only, no plugin.json
    run cps_check_M2 "$REPO"; assert_output FAIL
    run cps_check_M3 "$REPO"; assert_output "N/A"
    run cps_verdict "$REPO"; assert_output FAIL
}

# ---- forced override (--single / --mono) --------------------------------

@test "forced --mono on a single repo -> M2 FAIL (override scores as mono)" {
    # override means 'score by THIS mode' — a wrong override surfaces as a
    # normal M2 FAIL (no plugins/ dir), never a silent skip.
    build_single_perfect "$REPO"
    run cps_check_M2 "$REPO" mono; assert_output FAIL
}

@test "forced --single on a mono repo -> M2 FAIL (no root manifest)" {
    build_perfect "$REPO"   # mono: manifest under plugins/demo, not root
    run cps_check_M2 "$REPO" single; assert_output FAIL
}

@test "forced --single honored even when marketplace says mono" {
    build_single_perfect "$REPO"
    # corrupt the signal: claim mono in marketplace, but force single ($schema/
    # description/homepage kept so R6/R7 stay PASS — this test isolates mode).
    printf '{ "$schema": "https://anthropic.com/claude-code/marketplace.schema.json", "name": "repo", "description": "demo", "plugins": [{ "source": "./plugins/x", "homepage": "https://example.com/x" }] }\n' \
        > "$REPO/.claude-plugin/marketplace.json"
    run _cps_detect_mode "$REPO" single; assert_output single
    run cps_verdict "$REPO" single; assert_output PASS
}

# ---- single layout REFACTOR (#915) --------------------------------------
# refactor fixes a single repo toward the ROOT golden layout and NEVER
# creates a plugins/ directory (the core danger #915 guards against).

@test "single perfect repo -> refactor op apply is a no-op (no plugins/ dir)" {
    build_single_perfect "$REPO"
    before="$(find "$REPO" -type f | sort)"
    cps_refactor "$REPO" op apply
    after="$(find "$REPO" -type f | sort)"
    [ "$before" = "$after" ]
    [ ! -d "$REPO/plugins" ]
    run cps_verdict "$REPO"; assert_output PASS
}

@test "single repo missing root plugin.json -> refactor mp -> PASS, no plugins/ dir" {
    _seed_single_skill "$REPO"; _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    _seed_recommended_files "$REPO"; _seed_readme_links "$REPO" visualize
    mkdir -p "$REPO/.claude-plugin"   # single signal, root plugin.json missing
    printf '{ "$schema": "https://anthropic.com/claude-code/marketplace.schema.json", "name": "repo", "description": "demo", "plugins": [{ "source": "./", "homepage": "https://example.com/repo" }] }\n' \
        > "$REPO/.claude-plugin/marketplace.json"
    run cps_check_M2 "$REPO"; assert_output FAIL     # 0 plugin roots yet
    run cps_verdict "$REPO"; assert_output FAIL
    cps_refactor "$REPO" mp apply
    [ ! -d "$REPO/plugins" ]                          # single fix never makes plugins/
    run cps_check_M3 "$REPO"; assert_output PASS
    run cps_verdict "$REPO"; assert_output PASS
}

@test "single mandatory apply writes VALID root JSON with source ./" {
    _seed_single_skill "$REPO"; _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    mkdir -p "$REPO/.claude-plugin"
    printf '{ "name": "repo", "plugins": [{ "source": "./" }] }\n' \
        > "$REPO/.claude-plugin/marketplace.json"
    cps_refactor "$REPO" mp apply
    run jq empty "$REPO/.claude-plugin/plugin.json"; assert_success
    run jq -r '.plugins[0].source' "$REPO/.claude-plugin/marketplace.json"
    assert_output "./"
    run jq -e 'has("skills")' "$REPO/.claude-plugin/plugin.json"   # no skills field (M10)
    assert_output false
    run cps_check_M10 "$REPO"; assert_output PASS
    [ ! -d "$REPO/plugins" ]
}

@test "single missing recommended -> refactor op -> recheck PASS (root stubs+links)" {
    _seed_single_skill "$REPO"; _seed_single_mandatory_json "$REPO"
    _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    run cps_check_R1 "$REPO"; assert_output WARN
    cps_refactor "$REPO" op apply
    [ ! -d "$REPO/plugins" ]
    run cps_check_R1 "$REPO"; assert_output PASS
    run cps_check_R2 "$REPO"; assert_output PASS
    run cps_check_R5 "$REPO"; assert_output PASS
    run cps_verdict "$REPO"; assert_output PASS
}

# ---- layout-conversion guard (#915) -------------------------------------
# A forced TARGET mode that differs from the detected CURRENT layout is a
# single<->mono conversion — OUT OF SCOPE: write nothing, return 3.

@test "forced --mono on a detected-single repo -> conversion guard no-op (rc=3)" {
    build_single_perfect "$REPO"
    rm -f "$REPO/docs/skill-guides/visualize.html"   # a same-mode op WOULD rewrite this
    before="$(find "$REPO" -type f | sort)"
    run cps_refactor "$REPO" op apply mono
    [ "$status" -eq 3 ]
    after="$(find "$REPO" -type f | sort)"
    [ "$before" = "$after" ]
    [ ! -d "$REPO/plugins" ]
}

@test "forced --single on a detected-mono repo -> conversion guard no-op (rc=3)" {
    _seed_skill "$REPO"; _seed_docs_dirs "$REPO"; _seed_readme "$REPO"  # mono, mandatory missing
    before="$(find "$REPO" -type f | sort)"
    run cps_refactor "$REPO" mp apply single
    [ "$status" -eq 3 ]
    after="$(find "$REPO" -type f | sort)"
    [ "$before" = "$after" ]
    [ ! -f "$REPO/.claude-plugin/marketplace.json" ]   # nothing written
}

@test "forced --single on a detected-single repo proceeds (target == current)" {
    _seed_single_skill "$REPO"; _seed_single_mandatory_json "$REPO"
    _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    run cps_refactor "$REPO" op apply single
    [ "$status" -eq 0 ]
    run cps_check_R5 "$REPO"; assert_output PASS
    run cps_verdict "$REPO"; assert_output PASS
}

@test "forced --mono on a detected-mono repo proceeds (mono regression intact)" {
    # mirrors test "mandatory missing -> refactor --apply (mp)" but with an
    # explicit --mono target == the detected layout: identical mono behavior.
    _seed_skill "$REPO"; _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    _seed_recommended_files "$REPO"; _seed_readme_links "$REPO" visualize
    run cps_refactor "$REPO" mp apply mono
    [ "$status" -eq 0 ]
    run cps_check_M1 "$REPO"; assert_output PASS
    run cps_check_M3 "$REPO"; assert_output PASS
    run cps_verdict "$REPO"; assert_output PASS
}

# ---- M7 plugins[].source presence (#1084 / claude-plugin-jira#61) --------

@test "M7 FAIL: plugin object lacks its own source (#61 install-fail shape)" {
    # #61 root cause: plugins[] object relied on the inherited top-level source,
    # which Claude Code 2.1.198 does not honor at install time.
    _seed_skill "$REPO"; _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    mkdir -p "$REPO/.claude-plugin"
    printf '{ "name": "repo", "source": { "source": "url", "url": "https://x/y.git" }, "plugins": [{ "name": "demo" }] }\n' \
        > "$REPO/.claude-plugin/marketplace.json"
    run cps_check_M7 "$REPO"; assert_output FAIL
    run cps_verdict "$REPO"; assert_output FAIL
}

@test "M7 PASS: string-form plugin element is the source (shorthand)" {
    _seed_skill "$REPO"; _seed_mandatory_json "$REPO"
    _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    run cps_check_M7 "$REPO"; assert_output PASS
}

@test "M7 PASS: object plugin with its own git-URL source (#61 post-fix / #63)" {
    _seed_skill "$REPO"; _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    mkdir -p "$REPO/.claude-plugin"
    printf '{ "name": "repo", "plugins": [{ "name": "demo", "source": "url", "url": "https://x/y.git" }] }\n' \
        > "$REPO/.claude-plugin/marketplace.json"
    run cps_check_M7 "$REPO"; assert_output PASS
    run cps_check_M8 "$REPO"; assert_output PASS
}

@test "M7 N/A when marketplace lists 0 plugins (M2 owns the FAIL)" {
    mkdir -p "$REPO/.claude-plugin"
    printf '{ "name": "repo", "plugins": [] }\n' > "$REPO/.claude-plugin/marketplace.json"
    _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    run cps_check_M7 "$REPO"; assert_output "N/A"
    run cps_check_M8 "$REPO"; assert_output "N/A"
}

@test "M7 FAIL -> refactor mp apply injects source -> M7 PASS (auto-fix)" {
    # AC: structure-refactor --apply fixes M7 FAIL by inserting a source field.
    _seed_skill "$REPO"; _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    _seed_recommended_files "$REPO"; _seed_readme_links "$REPO" visualize
    mkdir -p "$REPO/.claude-plugin"
    printf '{ "name": "repo", "description": "d", "$schema": "s", "plugins": [{ "name": "demo" }] }\n' \
        > "$REPO/.claude-plugin/marketplace.json"
    run cps_check_M7 "$REPO"; assert_output FAIL
    cps_refactor "$REPO" mp apply
    run cps_check_M7 "$REPO"; assert_output PASS
    run cps_check_M8 "$REPO"; assert_output PASS    # injected ./plugins/demo is a valid shape
    run cps_check_M9 "$REPO"; assert_output PASS    # plugins/demo/ exists on disk
    run jq -e '.plugins[0].source' "$REPO/.claude-plugin/marketplace.json"; assert_success
}

@test "M7 auto-fix derives git-URL source from plugin homepage (…​.git)" {
    _seed_skill "$REPO"; _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    mkdir -p "$REPO/.claude-plugin"
    printf '{ "name": "repo", "plugins": [{ "name": "demo", "homepage": "https://x/y.git" }] }\n' \
        > "$REPO/.claude-plugin/marketplace.json"
    cps_refactor "$REPO" mp apply
    run jq -r '.plugins[0].source' "$REPO/.claude-plugin/marketplace.json"; assert_output "url"
    run jq -r '.plugins[0].url' "$REPO/.claude-plugin/marketplace.json"; assert_output "https://x/y.git"
    run cps_check_M7 "$REPO"; assert_output PASS
    run cps_check_M8 "$REPO"; assert_output PASS
}

# ---- M8 plugins[].source shape validity (#1084) --------------------------

@test "M8 FAIL: object source is a raw URL without the url-type shape" {
    _seed_skill "$REPO"; _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    mkdir -p "$REPO/.claude-plugin"
    # .source is a raw https URL string — neither a local path nor the
    # { source:"url", url:... } shape → invalid.
    printf '{ "name": "repo", "plugins": [{ "source": "https://x/y.git" }] }\n' \
        > "$REPO/.claude-plugin/marketplace.json"
    run cps_check_M7 "$REPO"; assert_output PASS     # source key present
    run cps_check_M8 "$REPO"; assert_output FAIL     # but shape invalid
    run cps_verdict "$REPO"; assert_output FAIL
}

@test "M8 PASS: bare './' single source and bare './plugins/x' mono source" {
    mkdir -p "$REPO/.claude-plugin"
    printf '{ "name": "repo", "plugins": ["./plugins/demo"] }\n' \
        > "$REPO/.claude-plugin/marketplace.json"
    run cps_check_M8 "$REPO"; assert_output PASS
}

@test "M8 FAIL: explicit null source is not skipped (#1085 gemini review)" {
    # M7 passes (the "source" key exists) but the value is null → M8 must FAIL,
    # not silently skip it as a missing-source (M7) case.
    mkdir -p "$REPO/.claude-plugin"
    printf '{ "name": "repo", "plugins": [{ "name": "demo", "source": null }] }\n' \
        > "$REPO/.claude-plugin/marketplace.json"
    run cps_check_M7 "$REPO"; assert_output PASS
    run cps_check_M8 "$REPO"; assert_output FAIL
}

@test "M8 FAIL: a null plugin element is collected, not skipped (#1085)" {
    mkdir -p "$REPO/.claude-plugin"
    printf '{ "name": "repo", "plugins": [null] }\n' \
        > "$REPO/.claude-plugin/marketplace.json"
    run cps_check_M8 "$REPO"; assert_output FAIL
}

# ---- M9 pluginRoot ↔ on-disk consistency (mono only, #1084) --------------

@test "M9 FAIL: mono marketplace declares a plugin dir that is absent" {
    _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    mkdir -p "$REPO/.claude-plugin" "$REPO/plugins/demo"   # 'ghost' declared, not present
    printf '{ "name": "repo", "plugins": ["./plugins/demo", "./plugins/ghost"] }\n' \
        > "$REPO/.claude-plugin/marketplace.json"
    run cps_check_M9 "$REPO"; assert_output FAIL
    run cps_verdict "$REPO"; assert_output FAIL
}

@test "M9 PASS: every declared mono plugin dir exists on disk" {
    build_perfect "$REPO"
    run cps_check_M9 "$REPO"; assert_output PASS
}

@test "M9 N/A in single mode (no plugins/ layout)" {
    build_single_perfect "$REPO"
    run cps_check_M9 "$REPO"; assert_output "N/A"
}

@test "M9 N/A for a mono repo whose sources are all remote git URLs (#63)" {
    _seed_skill "$REPO"; _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    mkdir -p "$REPO/.claude-plugin"
    printf '{ "name": "repo", "plugins": [{ "name": "demo", "source": "url", "url": "https://x/y.git" }] }\n' \
        > "$REPO/.claude-plugin/marketplace.json"
    run cps_check_M9 "$REPO"; assert_output "N/A"    # nothing local to verify
}

# ---- M10 plugin.json known-field whitelist (#1084 / claude-plugin-jira#65) --

_seed_plugin_json() {
    # $1=repo $2=raw-json : overwrite plugins/demo/.claude-plugin/plugin.json
    mkdir -p "$1/plugins/demo/.claude-plugin"
    printf '%s\n' "$2" > "$1/plugins/demo/.claude-plugin/plugin.json"
}

@test "M10 FAIL: plugin.json carries a schema-violating skills field (jira@0.2.0)" {
    # claude-plugin-jira#65 repro: install succeeds but the manifest fails
    # validation at load ("skills: Invalid input") → 0 skills load.
    _seed_skill "$REPO"; _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    mkdir -p "$REPO/.claude-plugin"
    printf '{ "name": "repo", "plugins": ["./plugins/demo"] }\n' \
        > "$REPO/.claude-plugin/marketplace.json"
    _seed_plugin_json "$REPO" '{ "name": "jira", "version": "0.2.0", "skills": ["skills/jira-core"] }'
    run cps_check_M10 "$REPO"; assert_output FAIL
    run cps_check_M3 "$REPO"; assert_output PASS      # JSON is valid — M3 doesn't catch it
    run cps_verdict "$REPO"; assert_output FAIL
}

@test "M10 PASS: plugin.json with only known manifest fields" {
    _seed_skill "$REPO"; _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    mkdir -p "$REPO/.claude-plugin"
    printf '{ "name": "repo", "plugins": ["./plugins/demo"] }\n' \
        > "$REPO/.claude-plugin/marketplace.json"
    _seed_plugin_json "$REPO" '{ "name": "demo", "version": "0.2.0", "description": "d", "homepage": "https://x", "keywords": ["a"] }'
    run cps_check_M10 "$REPO"; assert_output PASS
}

@test "M10 PASS on the perfect fixture (skeleton is schema-clean)" {
    build_perfect "$REPO"
    run cps_check_M10 "$REPO"; assert_output PASS
    run cps_verdict "$REPO"; assert_output PASS
}

@test "M10 N/A when no plugin root has a valid manifest (M3 owns it)" {
    mkdir -p "$REPO/.claude-plugin"
    printf '{ "name": "repo", "plugins": [] }\n' > "$REPO/.claude-plugin/marketplace.json"
    _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    run cps_check_M10 "$REPO"; assert_output "N/A"
}

@test "M10 FAIL -> refactor mp apply strips unknown field + leaves .bak -> M10 PASS" {
    # AC: structure-refactor --apply fixes M10 (remove unknown field, keep backup).
    _seed_skill "$REPO"; _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    _seed_recommended_files "$REPO"; _seed_readme_links "$REPO" visualize
    mkdir -p "$REPO/.claude-plugin"
    printf '{ "$schema": "s", "name": "repo", "description": "d", "plugins": ["./plugins/demo"] }\n' \
        > "$REPO/.claude-plugin/marketplace.json"
    _seed_plugin_json "$REPO" '{ "name": "demo", "version": "0.2.0", "skills": ["skills/x"] }'
    run cps_check_M10 "$REPO"; assert_output FAIL
    cps_refactor "$REPO" mp apply
    run cps_check_M10 "$REPO"; assert_output PASS
    run jq -e 'has("skills")' "$REPO/plugins/demo/.claude-plugin/plugin.json"; assert_output false
    run jq -r '.name' "$REPO/plugins/demo/.claude-plugin/plugin.json"; assert_output demo
    [ -f "$REPO/plugins/demo/.claude-plugin/plugin.json.bak" ]        # backup kept
    run jq -e 'has("skills")' "$REPO/plugins/demo/.claude-plugin/plugin.json.bak"; assert_output true
    run cps_verdict "$REPO"; assert_output PASS
}

@test "M10 refactor is a no-op on a clean manifest (no .bak spam)" {
    build_perfect "$REPO"
    cps_refactor "$REPO" mp apply
    [ ! -f "$REPO/plugins/demo/.claude-plugin/plugin.json.bak" ]
}

# ---- R6 $schema / R7 description+homepage / R8 add-URL hint (#1084) -------

@test "R6 WARN when marketplace omits top-level \$schema" {
    build_perfect "$REPO"                      # everything else clean
    printf '{ "name": "repo", "description": "d", "plugins": ["./plugins/demo"] }\n' \
        > "$REPO/.claude-plugin/marketplace.json"   # drop $schema only
    run cps_check_R6 "$REPO"; assert_output WARN
    run cps_verdict "$REPO"; assert_output WARN
}

@test "R6 PASS when \$schema is declared" {
    _seed_skill "$REPO"; _seed_mandatory_json "$REPO"
    _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    run cps_check_R6 "$REPO"; assert_output PASS
}

@test "R7 WARN when top-level description is missing" {
    _seed_skill "$REPO"; _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    mkdir -p "$REPO/.claude-plugin"
    printf '{ "$schema": "s", "name": "repo", "plugins": ["./plugins/demo"] }\n' \
        > "$REPO/.claude-plugin/marketplace.json"
    run cps_check_R7 "$REPO"; assert_output WARN
}

@test "R7 WARN when an object plugin lacks homepage" {
    _seed_skill "$REPO"; _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    mkdir -p "$REPO/.claude-plugin"
    printf '{ "$schema": "s", "name": "repo", "description": "d", "plugins": [{ "source": "./plugins/demo" }] }\n' \
        > "$REPO/.claude-plugin/marketplace.json"
    run cps_check_R7 "$REPO"; assert_output WARN
}

@test "R7 PASS with description and (string plugins have no homepage req)" {
    _seed_skill "$REPO"; _seed_mandatory_json "$REPO"
    _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    run cps_check_R7 "$REPO"; assert_output PASS
}

@test "R7 WARN when metadata is a non-string type (no jq crash → false PASS) (#1085)" {
    # boolean/number description or homepage must not crash jq and slip through
    # the `|| echo 0` fallback as a PASS — the type guard makes them WARN.
    _seed_skill "$REPO"; _seed_docs_dirs "$REPO"; _seed_readme "$REPO"
    mkdir -p "$REPO/.claude-plugin"
    printf '{ "$schema": "s", "name": "repo", "description": true, "plugins": [{ "source": "./plugins/demo", "homepage": 42 }] }\n' \
        > "$REPO/.claude-plugin/marketplace.json"
    run cps_check_R7 "$REPO"; assert_output WARN
}

@test "R8 N/A when README has no /plugin marketplace add example" {
    build_perfect "$REPO"
    run cps_check_R8 "$REPO"; assert_output "N/A"
}

@test "R8 WARN when the add example uses a .git clone URL" {
    build_perfect "$REPO"
    printf '\n`/plugin marketplace add https://github.com/o/repo.git`\n' >> "$REPO/README.md"
    run cps_check_R8 "$REPO"; assert_output WARN
    run cps_verdict "$REPO"; assert_output WARN
}

@test "R8 PASS when the add example uses the raw marketplace.json URL" {
    build_perfect "$REPO"
    printf '\n`/plugin marketplace add https://raw.githubusercontent.com/o/repo/main/.claude-plugin/marketplace.json`\n' >> "$REPO/README.md"
    run cps_check_R8 "$REPO"; assert_output PASS
    run cps_verdict "$REPO"; assert_output PASS
}
