#!/usr/bin/env bats
# tests/bats/skills/plugin_sync_hook_delete.bats
# claude/hooks/plugin-sync.sh — uninstall / marketplace remove 경로.
# 병합(install/add) 경로 커버리지는 plugin_sync_hook.bats.

load '../test_helper'

HOOK="${_BATS_REAL_DOTFILES_ROOT}/claude/hooks/plugin-sync.sh"

setup() {
    setup_isolated_home
    MAIN_ROOT="$TEST_TEMP_HOME/dotfiles"
    mkdir -p "$MAIN_ROOT/claude/plugin"
    git -C "$MAIN_ROOT" init -q
    git -C "$MAIN_ROOT" config user.email "hook-test@example.com"
    git -C "$MAIN_ROOT" config user.name "hook-test"

    cat > "$MAIN_ROOT/claude/plugin/marketplaces.json" <<'JSON'
{"claude-plugins-official": "anthropics/claude-plugins-official", "understand-anything": "Egonex-AI/Understand-Anything"}
JSON
    cat > "$MAIN_ROOT/claude/plugin/plugins.json" <<'JSON'
{"plugins": ["ralph-loop@claude-plugins-official", "understand-anything@understand-anything"]}
JSON
    git -C "$MAIN_ROOT" add claude/plugin
    git -C "$MAIN_ROOT" commit -q -m "seed"
}

teardown() {
    teardown_isolated_home
}

@test "uninstall <plugin>@<marketplace> removes exactly that entry" {
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin uninstall ralph-loop@claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    run jq -e '.plugins == ["understand-anything@understand-anything"]' \
        "$MAIN_ROOT/claude/plugin/plugins.json"
    assert_success
    # untouched marketplace entries stay
    run jq -e 'has("claude-plugins-official")' "$MAIN_ROOT/claude/plugin/marketplaces.json"
    assert_success
}

@test "uninstall <bare-plugin-name> removes the matching plugin@marketplace entry" {
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin uninstall ralph-loop"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    run jq -e '.plugins | any(. == "ralph-loop@claude-plugins-official")' \
        "$MAIN_ROOT/claude/plugin/plugins.json"
    assert_failure
}

@test "marketplace remove deletes the marketplace and cascades to its plugins" {
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin marketplace remove claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    run jq -e 'has("claude-plugins-official")' "$MAIN_ROOT/claude/plugin/marketplaces.json"
    assert_failure
    run jq -e '.plugins | any(. == "ralph-loop@claude-plugins-official")' \
        "$MAIN_ROOT/claude/plugin/plugins.json"
    assert_failure
    # unrelated marketplace/plugin survives
    run jq -e 'has("understand-anything")' "$MAIN_ROOT/claude/plugin/marketplaces.json"
    assert_success
}

@test "uninstall with no target token → no-op" {
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin uninstall"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    run jq -e '.plugins == ["ralph-loop@claude-plugins-official", "understand-anything@understand-anything"]' \
        "$MAIN_ROOT/claude/plugin/plugins.json"
    assert_success
}

@test "uninstall commits the removal locally" {
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin uninstall ralph-loop@claude-plugins-official"}}'
    before=$(git -C "$MAIN_ROOT" rev-parse HEAD)
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    after=$(git -C "$MAIN_ROOT" rev-parse HEAD)
    [ "$before" != "$after" ]
    run git -C "$MAIN_ROOT" log -1 --format=%s
    assert_output "chore(claude-plugin): sync manifest"
}

@test "marketplace remove also removes the matching entry from claude/plugin/company/" {
    mkdir -p "$MAIN_ROOT/claude/plugin/company"
    git -C "$MAIN_ROOT/claude/plugin/company" init -q
    git -C "$MAIN_ROOT/claude/plugin/company" config user.email "hook-test@example.com"
    git -C "$MAIN_ROOT/claude/plugin/company" config user.name "hook-test"
    cat > "$MAIN_ROOT/claude/plugin/company/marketplaces.json" <<'JSON'
{"internal-tools": "git@ghes.example.com:team/internal-tools.git"}
JSON
    cat > "$MAIN_ROOT/claude/plugin/company/plugins.json" <<'JSON'
{"plugins": ["secret@internal-tools"]}
JSON
    git -C "$MAIN_ROOT/claude/plugin/company" add .
    git -C "$MAIN_ROOT/claude/plugin/company" commit -q -m "seed"

    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin marketplace remove internal-tools"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    run jq -e 'has("internal-tools")' "$MAIN_ROOT/claude/plugin/company/marketplaces.json"
    assert_failure
    run jq -e '.plugins == []' "$MAIN_ROOT/claude/plugin/company/plugins.json"
    assert_success
}
