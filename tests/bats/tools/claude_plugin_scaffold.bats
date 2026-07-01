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
