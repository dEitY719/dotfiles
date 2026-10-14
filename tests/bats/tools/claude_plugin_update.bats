#!/usr/bin/env bats
# tests/bats/tools/claude_plugin_update.bats
# claude/plugin/update-plugins.sh — refresh the Claude Code plugin store
# (marketplace update + plugin update). A fake `claude` on PATH logs its args;
# PATH is pinned to the fake bin + /usr/bin:/bin so the real CLI never runs.

load '../test_helper'

UPDATE="${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/update-plugins.sh"

setup() {
    setup_isolated_home
    PLUGDIR="$TEST_TEMP_HOME/plugdir"
    FAKEBIN="$TEST_TEMP_HOME/bin"
    CLAUDE_LOG="$TEST_TEMP_HOME/claude.log"
    export CLAUDE_LOG
    mkdir -p "$PLUGDIR" "$FAKEBIN"
    cp "$UPDATE" "$PLUGDIR/update-plugins.sh"
    chmod +x "$PLUGDIR/update-plugins.sh"

    cat >"$PLUGDIR/marketplaces.json" <<'JSON'
{
  "gh-flow-skills": "dEitY719/gh-flow-skills",
  "notes-skills": "dEitY719/notes-skills",
  "caveman": "JuliusBrussee/caveman"
}
JSON
    cat >"$PLUGDIR/plugins.json" <<'JSON'
{"plugins": ["gh-flow@gh-flow-skills", "notes@notes-skills", "caveman@caveman"]}
JSON

    # Fake claude: logs args (plus the CLAUDE_CONFIG_DIR it saw), fails when the
    # args contain $FAKE_CLAUDE_FAIL, reports "updated" for $FAKE_CLAUDE_UPDATED.
    cat >"$FAKEBIN/claude" <<'SH'
#!/bin/bash
echo "$* [cfg=${CLAUDE_CONFIG_DIR:-}]" >>"$CLAUDE_LOG"
if [ -n "${FAKE_CLAUDE_FAIL:-}" ]; then
    case " $* " in *" $FAKE_CLAUDE_FAIL "*) echo "boom" >&2; exit 1 ;; esac
fi
if [ "$1 $2" = "plugin update" ]; then
    if [ "$3" = "${FAKE_CLAUDE_UPDATED:-}" ]; then
        printf '{"outcome":"ok","updateOutcome":"updated","oldVersion":"0.1.13","newVersion":"0.2.0"}\n'
    else
        printf '{"outcome":"ok","updateOutcome":"up_to_date","oldVersion":"1.0.0","newVersion":"1.0.0"}\n'
    fi
fi
exit 0
SH
    chmod +x "$FAKEBIN/claude"
    export PATH="$FAKEBIN:/usr/bin:/bin"
    unset CLAUDE_DEFAULT_ACCOUNT
    # The store the script refuses to run without (setup links it per account).
    mkdir -p "$TEST_TEMP_HOME/.claude-personal/plugins" "$TEST_TEMP_HOME/.claude-work1/plugins" \
        "$TEST_TEMP_HOME/.claude/plugins"
}

teardown() {
    teardown_isolated_home
}

@test "update-plugins.sh passes bash syntax check and is executable" {
    run bash -n "$UPDATE"
    assert_success
    [ -x "$UPDATE" ]
}

@test "update-plugins.sh updates only the default owner's marketplaces and their plugins" {
    # --jobs 1: the exact cross-marketplace call order is only fixed serially.
    run "$PLUGDIR/update-plugins.sh" --jobs 1
    assert_success
    run cat "$CLAUDE_LOG"
    assert_output "plugin marketplace update gh-flow-skills [cfg=$TEST_TEMP_HOME/.claude-personal]
plugin update gh-flow@gh-flow-skills --json [cfg=$TEST_TEMP_HOME/.claude-personal]
plugin marketplace update notes-skills [cfg=$TEST_TEMP_HOME/.claude-personal]
plugin update notes@notes-skills --json [cfg=$TEST_TEMP_HOME/.claude-personal]"
}

@test "update-plugins.sh --owner selects another owner" {
    run "$PLUGDIR/update-plugins.sh" --owner JuliusBrussee
    assert_success
    run cat "$CLAUDE_LOG"
    assert_output --partial "plugin marketplace update caveman"
    assert_output --partial "plugin update caveman@caveman --json"
    refute_output --partial "gh-flow"
}

@test "update-plugins.sh --all selects every marketplace" {
    run "$PLUGDIR/update-plugins.sh" --all
    assert_success
    run grep -c "marketplace update" "$CLAUDE_LOG"
    assert_output "3"
}

@test "update-plugins.sh --user routes CLAUDE_CONFIG_DIR to that account" {
    run "$PLUGDIR/update-plugins.sh" --user work1
    assert_success
    run grep -Fx "plugin marketplace update gh-flow-skills [cfg=$TEST_TEMP_HOME/.claude-work1]" "$CLAUDE_LOG"
    assert_success
}

@test "update-plugins.sh counts updated vs up-to-date and hints a restart" {
    export FAKE_CLAUDE_UPDATED="gh-flow@gh-flow-skills"
    run "$PLUGDIR/update-plugins.sh"
    assert_success
    assert_output --partial "gh-flow@gh-flow-skills: updated 0.1.13 -> 0.2.0"
    assert_output --partial "notes@notes-skills: up to date (1.0.0)"
    assert_output --partial "Marketplaces refreshed: 2/2"
    assert_output --partial "Plugins updated: 1"
    assert_output --partial "Plugins up to date: 1"
    assert_output --partial "Restart running Claude Code sessions"
}

@test "update-plugins.sh with nothing updated prints no restart hint" {
    run "$PLUGDIR/update-plugins.sh"
    assert_success
    assert_output --partial "Plugins updated: 0"
    refute_output --partial "Restart running Claude Code sessions"
}

@test "update-plugins.sh --dry-run makes no claude calls" {
    run "$PLUGDIR/update-plugins.sh" --dry-run
    assert_success
    assert_output --partial "would run 'claude plugin marketplace update gh-flow-skills'"
    assert_output --partial "would run 'claude plugin update notes@notes-skills'"
    [ ! -e "$CLAUDE_LOG" ]
}

@test "update-plugins.sh --dry-run works without a claude binary" {
    rm "$FAKEBIN/claude"
    run "$PLUGDIR/update-plugins.sh" --dry-run
    assert_success
    assert_output --partial "Plugins (would update): 2"
}

@test "update-plugins.sh without a claude binary warns and exits 0" {
    rm "$FAKEBIN/claude"
    run "$PLUGDIR/update-plugins.sh"
    assert_success
    assert_output --partial "claude CLI not found"
}

@test "update-plugins.sh continues after a failed plugin update and exits non-zero" {
    export FAKE_CLAUDE_FAIL="gh-flow@gh-flow-skills"
    run "$PLUGDIR/update-plugins.sh"
    assert_failure 1
    assert_output --partial "gh-flow@gh-flow-skills: update failed"
    assert_output --partial "Failed: 1"
    run grep -c "notes" "$CLAUDE_LOG"
    assert_output "2"
}

@test "update-plugins.sh continues after a failed marketplace update and exits non-zero" {
    export FAKE_CLAUDE_FAIL="gh-flow-skills"
    run "$PLUGDIR/update-plugins.sh"
    assert_failure 1
    assert_output --partial "gh-flow-skills: marketplace update failed"
    assert_output --partial "Marketplaces refreshed: 1/2"
    run grep -c "marketplace update notes-skills" "$CLAUDE_LOG"
    assert_output "1"
}

@test "update-plugins.sh includes the company manifest on internal mode" {
    echo "internal" >"$TEST_TEMP_HOME/.dotfiles-setup-mode"
    mkdir -p "$PLUGDIR/company"
    git -C "$PLUGDIR/company" init -q
    echo '{"internal-tools": "git@ghes.example.com:team/internal-tools.git"}' >"$PLUGDIR/company/marketplaces.json"
    echo '{"plugins": ["secret@internal-tools"]}' >"$PLUGDIR/company/plugins.json"
    run "$PLUGDIR/update-plugins.sh"
    assert_success
    run cat "$CLAUDE_LOG"
    assert_output --partial "plugin marketplace update internal-tools [cfg=$TEST_TEMP_HOME/.claude]"
    assert_output --partial "plugin update secret@internal-tools --json"
}

@test "update-plugins.sh skips plugins/marketplaces missing from the plugin store" {
    mkdir -p "$TEST_TEMP_HOME/.claude-personal/plugins"
    echo '{"gh-flow-skills": {}}' >"$TEST_TEMP_HOME/.claude-personal/plugins/known_marketplaces.json"
    echo '{"plugins": {}}' >"$TEST_TEMP_HOME/.claude-personal/plugins/installed_plugins.json"
    run "$PLUGDIR/update-plugins.sh"
    assert_success
    assert_output --partial "gh-flow@gh-flow-skills: not installed"
    assert_output --partial "notes-skills: marketplace not registered"
    assert_output --partial "Plugins skipped (not installed): 1"
    run cat "$CLAUDE_LOG"
    assert_output "plugin marketplace update gh-flow-skills [cfg=$TEST_TEMP_HOME/.claude-personal]"
}

@test "update-plugins.sh includes the machine-local overlay manifests" {
    echo '{"local-skills": "dEitY719/local-skills"}' >"$PLUGDIR/marketplaces.local.json"
    echo '{"plugins": ["local@local-skills"]}' >"$PLUGDIR/plugins.local.json"
    run "$PLUGDIR/update-plugins.sh"
    assert_success
    run cat "$CLAUDE_LOG"
    assert_output --partial "plugin marketplace update local-skills"
    assert_output --partial "plugin update local@local-skills --json"
}

@test "update-plugins.sh --owner matches case-insensitively" {
    run "$PLUGDIR/update-plugins.sh" --owner deity719
    assert_success
    run grep -c "marketplace update" "$CLAUDE_LOG"
    assert_output "2"
}

@test "update-plugins.sh fails loudly on a malformed plugins manifest" {
    echo '{not json' >"$PLUGDIR/plugins.json"
    run "$PLUGDIR/update-plugins.sh"
    assert_failure 1
    assert_output --partial "Failed to read plugin manifest"
}

@test "update-plugins.sh reads the JSON result even with a trailing stderr line" {
    cat >"$FAKEBIN/claude" <<'SH'
#!/bin/bash
echo "$*" >>"$CLAUDE_LOG"
if [ "$1 $2" = "plugin update" ]; then
    printf '{"updateOutcome":"up_to_date","oldVersion":"1.0.0","newVersion":"1.0.0"}\n'
    echo "notice: something" >&2
fi
exit 0
SH
    chmod +x "$FAKEBIN/claude"
    run "$PLUGDIR/update-plugins.sh"
    assert_success
    assert_output --partial "gh-flow@gh-flow-skills: up to date (1.0.0)"
    assert_output --partial "Plugins updated: 0"
}

@test "update-plugins.sh reports an unrecognized outcome instead of counting it as updated" {
    cat >"$FAKEBIN/claude" <<'SH'
#!/bin/bash
echo "$*" >>"$CLAUDE_LOG"
[ "$1 $2" = "plugin update" ] && echo "done, probably"
exit 0
SH
    chmod +x "$FAKEBIN/claude"
    run "$PLUGDIR/update-plugins.sh"
    assert_success
    assert_output --partial "gh-flow@gh-flow-skills: unrecognized update result (no JSON)"
    assert_output --partial "Plugins updated: 0"
    assert_output --partial "Plugins with an unrecognized result: 2"
    refute_output --partial "Restart running Claude Code sessions"
}

@test "update-plugins.sh skips with a warning when the plugin store is missing" {
    rm -rf "$TEST_TEMP_HOME/.claude-personal/plugins"
    run "$PLUGDIR/update-plugins.sh"
    assert_success
    assert_output --partial "Plugin store not found"
    [ ! -e "$CLAUDE_LOG" ]
    [ ! -e "$TEST_TEMP_HOME/.claude-personal/plugins" ]
}

@test "update-plugins.sh warns when the plugin store lists nothing" {
    echo '{}' >"$TEST_TEMP_HOME/.claude-personal/plugins/known_marketplaces.json"
    run "$PLUGDIR/update-plugins.sh"
    assert_success
    assert_output --partial "lists no marketplaces/plugins"
}

@test "update-plugins.sh warns about a non-string marketplace source" {
    echo '{"obj-skills": {"source": "git", "url": "https://example.com/x.git"}}' >"$PLUGDIR/marketplaces.local.json"
    run "$PLUGDIR/update-plugins.sh" --all
    assert_success
    assert_output --partial "Unsupported (non-string) marketplace source — skipped: obj-skills"
    run cat "$CLAUDE_LOG"
    refute_output --partial "obj-skills"
}

@test "update-plugins.sh lets the tracked manifest win an overlay key conflict" {
    echo '{"gh-flow-skills": "someone-else/gh-flow-skills"}' >"$PLUGDIR/marketplaces.local.json"
    run "$PLUGDIR/update-plugins.sh"
    assert_success
    run cat "$CLAUDE_LOG"
    assert_output --partial "plugin marketplace update gh-flow-skills"
}

@test "update-plugins.sh rejects an unknown flag" {
    run "$PLUGDIR/update-plugins.sh" --bogus
    assert_failure 2
    assert_output --partial "Unknown argument: --bogus"
}

# --- #2198: --jobs N parallel execution ---------------------------------------

@test "update-plugins.sh --jobs 1 and --jobs 4 give identical output and exit code" {
    export FAKE_CLAUDE_FAIL="notes@notes-skills" FAKE_CLAUDE_UPDATED="gh-flow@gh-flow-skills"
    run "$PLUGDIR/update-plugins.sh" --all --jobs 1
    local out1="$output" rc1="$status"
    [ "$rc1" -eq 1 ]
    run "$PLUGDIR/update-plugins.sh" --all --jobs 4
    [ "$status" -eq "$rc1" ]
    [ "$output" = "$out1" ]
    DOTFILES_SKILLS_JOBS=2 run "$PLUGDIR/update-plugins.sh" --all
    [ "$status" -eq "$rc1" ]
    [ "$output" = "$out1" ]
}

@test "update-plugins.sh parallel run keeps going past a failure and counts exactly" {
    export FAKE_CLAUDE_FAIL="notes-skills" FAKE_CLAUDE_UPDATED="gh-flow@gh-flow-skills"
    run "$PLUGDIR/update-plugins.sh" --all --jobs 4
    assert_failure 1
    assert_output --partial "notes-skills: marketplace update failed"
    assert_output --partial "Marketplaces refreshed: 2/3"
    assert_output --partial "Plugins updated: 1"
    assert_output --partial "Plugins up to date: 2"
    assert_output --partial "Failed: 1"
    # Each marketplace still runs its own refresh before its plugin update.
    run grep -n "caveman" "$CLAUDE_LOG"
    assert_line --index 0 --partial "marketplace update caveman"
}

@test "update-plugins.sh --dry-run output is identical across --jobs" {
    run "$PLUGDIR/update-plugins.sh" --dry-run --all --jobs 1
    local out1="$output"
    assert_success
    run "$PLUGDIR/update-plugins.sh" --dry-run --all --jobs 4
    assert_success
    [ "$output" = "$out1" ]
}

@test "update-plugins.sh rejects a non-positive --jobs value" {
    run "$PLUGDIR/update-plugins.sh" --jobs 0
    assert_failure 2
    assert_output --partial "--jobs"
}
