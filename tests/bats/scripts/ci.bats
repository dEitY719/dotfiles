#!/usr/bin/env bats
# tests/bats/scripts/ci.bats
#
# scripts/ci.sh — local CI (validate = ported harness-skills skill-check.yml
# steps, bats = vendored bats libs). Each test builds a throwaway marketplace
# repo that passes every skill-check step, then breaks or trims it. `gh` is a
# stub on PATH that logs its argv, so --post is asserted without network.

load '../test_helper'

SCRIPT="${DOTFILES_ROOT}/scripts/ci.sh"

setup() {
    for tool in jq node shellcheck; do
        command -v "$tool" >/dev/null || skip "needs $tool"
    done
    python3 -c 'import yaml' 2>/dev/null || skip "needs python3 + PyYAML"
    setup_isolated_home
    REPO="${TEST_TEMP_HOME}/fx"
    GH_LOG="${TEST_TEMP_HOME}/gh.log"
    mkdir -p "${TEST_TEMP_HOME}/bin"
    printf '#!/bin/sh\necho "GH_HOST=$GH_HOST $*" >>"%s"\n' "$GH_LOG" >"${TEST_TEMP_HOME}/bin/gh"
    chmod +x "${TEST_TEMP_HOME}/bin/gh"
    export PATH="${TEST_TEMP_HOME}/bin:$PATH"
    _make_fixture
}

teardown() {
    teardown_isolated_home
}

# _make_fixture — plugin `fx`, one skill `alpha`, one passing bats test.
_make_fixture() {
    mkdir -p "$REPO" && cd "$REPO" || return 1
    git init -q . && git config user.email t@t && git config user.name t
    mkdir -p .claude-plugin .codex-plugin .kimi-plugin .hermes-plugin .opencode/plugins \
        .agents/plugins .github/workflows skills/alpha tests/bats
    local m='{"name": "fx", "version": "1.0.0", "license": "MIT"}'
    printf '%s\n' "$m" >.claude-plugin/plugin.json
    printf '%s\n' "$m" >.codex-plugin/plugin.json
    printf '%s\n' "$m" >.kimi-plugin/plugin.json
    printf '%s\n' "$m" >package.json
    printf '{"name": "fx", "version": "1.0.0"}\n' >gemini-extension.json
    printf '{"plugins": [{"name": "fx", "version": "1.0.0"}]}\n' >.claude-plugin/marketplace.json
    printf '{"plugins": [{"name": "fx"}]}\n' >.agents/plugins/marketplace.json
    printf 'name: fx\nversion: 1.0.0\n' >.hermes-plugin/plugin.yaml
    : >.hermes-plugin/__init__.py
    printf 'export default {};\n' >.opencode/plugins/fx.js
    for f in .opencode/INSTALL.md GEMINI.md CLAUDE.md README.md; do printf '# fx\n' >"$f"; done
    ln -s CLAUDE.md AGENTS.md
    printf 'MIT License\n' >LICENSE
    printf -- '---\nname: alpha\ndescription: Does alpha.\nlicense: MIT\n---\n# alpha\n' >skills/alpha/SKILL.md
    printf 'jobs:\n  validate:\n    uses: o/h/.github/workflows/skill-check.yml@main\n    with:\n      plugin-name: fx\n' \
        >.github/workflows/validate.yml
    printf 'bats_load_library bats-support\nbats_load_library bats-assert\n@test ok { run true; assert_success; }\n' \
        >tests/bats/ok.bats
    git remote add origin git@github.com:owner/fx.git
    _commit
}

_commit() {
    git add -A && git -c core.hooksPath=/dev/null commit -qm fx
}

@test "passing fixture: both suites succeed, dry post makes no gh call" {
    run "$SCRIPT" --repo "$REPO"
    assert_success
    assert_output --partial "ok    validate: Skill frontmatter name matches its directory"
    assert_output --partial "ok    bats: bats -r tests/bats"
    assert_output --partial "suite validate success"
    assert_output --partial "suite bats     success"
    assert_output --partial "post  (dry) local-ci/validate=success on owner/fx@"
    [ ! -e "$GH_LOG" ]
}

@test "SKILL.md name != dir fails validate with non-zero exit" {
    sed -i 's/^name: alpha/name: beta/' skills/alpha/SKILL.md
    _commit
    run "$SCRIPT" --repo "$REPO"
    assert_failure 1
    assert_output --partial "FAIL  validate: Skill frontmatter name matches its directory"
    assert_output --partial "name 'beta' != directory 'alpha'"
    assert_output --partial "suite validate failure"
    [ ! -e "$GH_LOG" ]
}

@test "uncommitted breakage is not measured: the clean clone of HEAD is" {
    sed -i 's/^name: alpha/name: beta/' skills/alpha/SKILL.md
    run "$SCRIPT" --repo "$REPO" --only validate
    assert_success
    assert_output --partial "has uncommitted changes"
}

@test "--post publishes one status per suite with state, context and GH_HOST" {
    sha=$(git rev-parse HEAD)
    run "$SCRIPT" --repo "$REPO" --post
    assert_success
    run cat "$GH_LOG"
    assert_line "GH_HOST=github.com api --silent repos/owner/fx/statuses/$sha -f state=success -f context=local-ci/validate -f description=16/16 skill-check steps passed"
    assert_line --partial "statuses/$sha -f state=success -f context=local-ci/bats "
    [ "${#lines[@]}" -eq 2 ]
}

@test "--post on a failure posts state=failure under a custom prefix and host" {
    git remote set-url origin https://ghe.example.com/org/fx.git
    printf '@test bad { false; }\n' >tests/bats/bad.bats
    _commit
    run "$SCRIPT" --repo "$REPO" --only bats --post --context-prefix my-ci
    assert_failure 1
    run cat "$GH_LOG"
    assert_line --partial "GH_HOST=ghe.example.com api --silent repos/org/fx/statuses/"
    assert_line --partial "-f state=failure -f context=my-ci/bats "
    [ "${#lines[@]}" -eq 1 ]
}

@test "no tests/bats: bats suite skipped, never posted" {
    git rm -rq tests/bats && _commit
    run "$SCRIPT" --repo "$REPO" --post
    assert_success
    assert_output --partial "skip  bats: no tests/bats"
    assert_output --partial "suite bats     skipped"
    run cat "$GH_LOG"
    refute_output --partial "context=local-ci/bats"
    assert_output --partial "context=local-ci/validate"
}

@test "not a skill repo: validate skipped, nothing measured, no post" {
    git rm -rq .github .claude-plugin tests/bats && _commit
    run "$SCRIPT" --repo "$REPO" --post
    assert_success
    assert_output --partial "skip  validate: no skill-check.yml caller"
    assert_output --partial "note  nothing measured"
    [ ! -e "$GH_LOG" ]
}

@test "bad --only is a usage error" {
    run "$SCRIPT" --repo "$REPO" --only lint
    assert_failure 2
}
