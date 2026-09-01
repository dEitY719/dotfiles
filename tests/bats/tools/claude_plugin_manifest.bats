#!/usr/bin/env bats
# tests/bats/tools/claude_plugin_manifest.bats
# shell-common/functions/claude_plugin_manifest.sh — direct unit coverage for
# _claude_plugin_read_json_or (issue #1696, agy + codex PR #1697 review: the
# unified helper itself had no dedicated test, only indirect coverage through
# its four callers).

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

FILE="${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/claude_plugin_manifest.sh"

@test "claude_plugin_manifest.sh sources cleanly under bash and defines the reader" {
    run bash --noprofile --norc -c "
        source '${FILE}'
        command -v _claude_plugin_read_json_or >/dev/null 2>&1 || { echo missing; exit 1; }
        echo defined
    "
    assert_success
    assert_output --partial 'defined'
}

@test "claude_plugin_manifest.sh sources cleanly under zsh and defines the reader" {
    run zsh --no-rcs -c "
        source '${FILE}'
        command -v _claude_plugin_read_json_or >/dev/null 2>&1 || { echo missing; exit 1; }
        echo defined
    "
    assert_success
    assert_output --partial 'defined'
}

@test "_claude_plugin_read_json_or returns the default when the file is missing" {
    run bash --noprofile --norc -c "
        source '${FILE}'
        _claude_plugin_read_json_or '$TEST_TEMP_HOME/does-not-exist.json' '{}'
    "
    assert_success
    assert_output '{}'
}

@test "_claude_plugin_read_json_or returns the default when the file is 0-byte" {
    : > "$TEST_TEMP_HOME/empty.json"
    run bash --noprofile --norc -c "
        source '${FILE}'
        _claude_plugin_read_json_or '$TEST_TEMP_HOME/empty.json' '{\"plugins\":[]}'
    "
    assert_success
    assert_output '{"plugins":[]}'
}

@test "_claude_plugin_read_json_or returns the default when the file is malformed JSON" {
    printf 'not json {' > "$TEST_TEMP_HOME/broken.json"
    run bash --noprofile --norc -c "
        source '${FILE}'
        _claude_plugin_read_json_or '$TEST_TEMP_HOME/broken.json' '{}'
    "
    assert_success
    assert_output '{}'
}

@test "_claude_plugin_read_json_or returns the file's compact JSON when valid" {
    cat > "$TEST_TEMP_HOME/manifest.json" <<'JSON'
{
  "kept": "org/kept"
}
JSON
    run bash --noprofile --norc -c "
        source '${FILE}'
        _claude_plugin_read_json_or '$TEST_TEMP_HOME/manifest.json' '{}'
    "
    assert_success
    assert_output '{"kept":"org/kept"}'
}
