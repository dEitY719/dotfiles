#!/usr/bin/env bats
# tests/bats/functions/claude_plugin_list.bats
# shell-common/functions/claude_plugin_list.sh — 마켓플레이스별 그룹 요약 뷰.

load '../test_helper'

setup() {
    setup_isolated_home
    export CLAUDE_SHARED_PLUGINS_DIR="$TEST_TEMP_HOME/shared"
    mkdir -p "$CLAUDE_SHARED_PLUGINS_DIR"
}

teardown() {
    teardown_isolated_home
}

_run_list() {
    bash --noprofile --norc -c "
        export DOTFILES_FORCE_INIT=1
        export HOME='$TEST_TEMP_HOME'
        export CLAUDE_SHARED_PLUGINS_DIR='$CLAUDE_SHARED_PLUGINS_DIR'
        unset CLAUDE_CONFIG_DIR
        source '${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh'
        source '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/claude_plugin_list.sh'
        claude_plugin_list ${1:-}
    "
}

_seed() {
    cat > "$CLAUDE_SHARED_PLUGINS_DIR/known_marketplaces.json" <<'JSON'
{
  "official": {"source": {"source": "github", "repo": "anthropics/claude-plugins-official"}}
}
JSON
    cat > "$CLAUDE_SHARED_PLUGINS_DIR/installed_plugins.json" <<'JSON'
{"plugins": {
  "superpowers@official":  [{"scope": "user", "version": "6.0.3", "installedAt": "2026-05-22T00:00:00Z"}],
  "hookify@official":      [{"scope": "user", "version": "unknown", "installedAt": "2026-05-09T00:00:00Z"}]
}}
JSON
}

# --- command-design-pattern.md §10 structural checks ------------------------

_run_probe() {
    bash --noprofile --norc -c "
        export DOTFILES_FORCE_INIT=1
        source '${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh'
        source '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/claude_plugin_list.sh'
        $1
    "
}

@test "claude_plugin_list: public function exists" {
    run _run_probe 'type claude_plugin_list'
    assert_success
    assert_output --partial 'function'
}

@test "claude_plugin_list: private sub-functions exist (_cpl_help, _cpl_resolve_dir)" {
    run _run_probe 'type _cpl_help && type _cpl_resolve_dir'
    assert_success
}

@test "claude_plugin_list: alias claude-plugin-list maps to the function" {
    run _run_probe 'alias claude-plugin-list'
    assert_success
    assert_output --partial 'claude_plugin_list'
}

@test "claude-plugin-list --help prints usage without needing the SSOT" {
    run _run_list --help
    assert_success
    assert_output --partial 'claude-plugin-list'
}

@test "claude-plugin-list groups plugins under their marketplace with the repo" {
    _seed
    run _run_list
    assert_success
    assert_output --partial 'official  (anthropics/claude-plugins-official)'
    assert_output --partial 'superpowers'
    assert_output --partial '6.0.3'
    assert_output --partial 'hookify'
}

@test "claude-plugin-list shows 'unknown' versions rather than hiding them" {
    _seed
    run _run_list
    assert_success
    assert_output --partial 'unknown'
}

@test "claude-plugin-list errors clearly when the SSOT is absent" {
    run _run_list
    assert_failure
    assert_output --partial 'installed_plugins.json 을 찾을 수 없습니다'
}

@test "claude-plugin-list reports an empty plugin set gracefully" {
    echo '{}' > "$CLAUDE_SHARED_PLUGINS_DIR/known_marketplaces.json"
    echo '{"plugins": {}}' > "$CLAUDE_SHARED_PLUGINS_DIR/installed_plugins.json"
    run _run_list
    assert_success
    assert_output --partial '설치된 플러그인이 없습니다'
}
