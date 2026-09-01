#!/usr/bin/env bats
# tests/bats/tools/claude_plugin_scaffold.bats
# claude/plugin/ 스캐폴드 + .gitignore 무시 규칙 검증.

load '../test_helper'

@test "claude/plugin/marketplaces.json exists and is valid empty JSON object" {
    run jq -e 'type == "object" and length == 0' "${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/marketplaces.json"
    assert_success
}

@test "claude/plugin/plugins.json exists with empty plugins array" {
    run jq -e '.plugins == []' "${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/plugins.json"
    assert_success
}

@test ".gitignore ignores claude/plugin/company/" {
    run git -C "${_BATS_REAL_DOTFILES_ROOT}" check-ignore -q claude/plugin/company/dummy.json
    assert_success
}

@test "every plugins.json entry's marketplace key exists in marketplaces.json" {
    run jq -e --slurpfile mp "${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/marketplaces.json" \
        '[.plugins[] | split("@")[1]] - ($mp[0] | keys) == []' \
        "${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/plugins.json"
    assert_success
}

@test "packaging-skills marketplace and packaging plugin are registered (#1638)" {
    run jq -e '."packaging-skills" == "dEitY719/packaging-skills"' \
        "${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/marketplaces.json"
    assert_success

    run jq -e '.plugins | index("packaging@packaging-skills") != null' \
        "${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/plugins.json"
    assert_success
}

@test "harness-skills marketplace and harness plugin are registered (#1645)" {
    run jq -e '."harness-skills" == "dEitY719/harness-skills"' \
        "${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/marketplaces.json"
    assert_success

    run jq -e '.plugins | index("harness@harness-skills") != null' \
        "${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/plugins.json"
    assert_success
}
