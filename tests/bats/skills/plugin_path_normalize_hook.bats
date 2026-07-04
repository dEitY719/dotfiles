#!/usr/bin/env bats
# tests/bats/skills/plugin_path_normalize_hook.bats
# claude/hooks/session-start-plugin-path-normalize.sh — rewrites plugin path
# fields in the shared SSOT to the ACTIVE $CLAUDE_CONFIG_DIR spelling so that
# Claude Code 2.1.199+'s literal-prefix installLocation check passes in every
# account, despite all account dirs symlinking to one ~/.claude-shared (#1098).

load '../test_helper'

HOOK="${_BATS_REAL_DOTFILES_ROOT}/claude/hooks/session-start-plugin-path-normalize.sh"

setup() {
    setup_isolated_home
    # Shared physical dir + the active-account symlink into it (the #1098 layout).
    SHARED="$TEST_TEMP_HOME/.claude-shared/plugins"
    mkdir -p "$SHARED"
    export CLAUDE_CONFIG_DIR="$TEST_TEMP_HOME/.claude-work"
    mkdir -p "$TEST_TEMP_HOME/.claude-work"
    ln -s "$SHARED" "$TEST_TEMP_HOME/.claude-work/plugins"
    MP="$TEST_TEMP_HOME/.claude-work/plugins/known_marketplaces.json"
    PL="$TEST_TEMP_HOME/.claude-work/plugins/installed_plugins.json"
}

teardown() {
    teardown_isolated_home
}

_session_start() {
    payload='{"hook_event_name":"SessionStart","session_id":"s1","source":"startup"}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
}

# Seed a marketplace file whose installLocation uses the .claude-shared realpath
# spelling — the corrupted-by-validation state after a raw Claude Code write.
_seed_shared_spelling() {
    cat > "$MP" <<JSON
{"mp-a": {"source": {"source": "github", "repo": "org/a"},
          "installLocation": "$TEST_TEMP_HOME/.claude-shared/plugins/marketplaces/mp-a"}}
JSON
}

@test "installLocation rewritten from .claude-shared to active CLAUDE_CONFIG_DIR spelling" {
    _seed_shared_spelling
    _session_start
    assert_success
    run jq -r '.["mp-a"].installLocation' "$MP"
    assert_output "$TEST_TEMP_HOME/.claude-work/plugins/marketplaces/mp-a"
}

@test "installPath in installed_plugins.json normalized too (#1098 preventive)" {
    cat > "$PL" <<JSON
{"plugins": {"plug-a@mp-a": [{"scope": "user",
        "installPath": "$TEST_TEMP_HOME/.claude-shared/plugins/cache/mp-a/plug-a/1.0.0"}]}}
JSON
    _session_start
    assert_success
    run jq -r '.plugins["plug-a@mp-a"][0].installPath' "$PL"
    assert_output "$TEST_TEMP_HOME/.claude-work/plugins/cache/mp-a/plug-a/1.0.0"
}

@test "idempotent: already-normalized file is left byte-identical (mtime unchanged)" {
    cat > "$MP" <<JSON
{"mp-a": {"source": {"source": "github", "repo": "org/a"},
          "installLocation": "$TEST_TEMP_HOME/.claude-work/plugins/marketplaces/mp-a"}}
JSON
    before=$(stat -c %Y "$MP" 2>/dev/null || stat -f %m "$MP")
    sleep 1
    _session_start
    assert_success
    after=$(stat -c %Y "$MP" 2>/dev/null || stat -f %m "$MP")
    [ "$before" = "$after" ]
}

@test "a single backup is written only when a change is made" {
    _seed_shared_spelling
    _session_start
    assert_success
    run bash -c "ls '$TEST_TEMP_HOME/.claude-shared/plugins/'known_marketplaces.json.bak.* 2>/dev/null | wc -l"
    assert_output "1"
}

@test "non-SessionStart event is a no-op" {
    _seed_shared_spelling
    payload='{"hook_event_name":"Stop","session_id":"s1"}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    run jq -r '.["mp-a"].installLocation' "$MP"
    assert_output "$TEST_TEMP_HOME/.claude-shared/plugins/marketplaces/mp-a"
}

@test "missing SSOT files → clean no-op" {
    # No MP/PL files created at all.
    _session_start
    assert_success
}

@test "terminal stdin → immediate exit" {
    _seed_shared_spelling
    run bash -c "'$HOOK' < /dev/tty" 2>/dev/null || true
    # File untouched (hook bailed before reading).
    run jq -r '.["mp-a"].installLocation' "$MP"
    assert_output "$TEST_TEMP_HOME/.claude-shared/plugins/marketplaces/mp-a"
}

@test "unrelated (non-.claude) install paths are left untouched" {
    cat > "$MP" <<JSON
{"mp-x": {"source": {"source": "github", "repo": "org/x"},
          "installLocation": "/opt/custom/plugins/marketplaces/mp-x"}}
JSON
    _session_start
    assert_success
    run jq -r '.["mp-x"].installLocation' "$MP"
    assert_output "/opt/custom/plugins/marketplaces/mp-x"
}
