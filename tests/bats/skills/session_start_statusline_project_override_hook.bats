#!/usr/bin/env bats
# tests/bats/skills/session_start_statusline_project_override_hook.bats
# Verify the SessionStart hook documented in
#   claude/hooks/session-start-statusline-project-override.sh (issue #1236)
#
# The hook seeds the dotfiles global .statusLine (from claude/settings.json,
# resolved relative to the hook's own dir) into a project's gitignored
# <cwd>/.claude/settings.local.json when that project ships a git-tracked
# .claude/settings.json defining its own .statusLine — so the global
# statusline survives fresh clones / new worktrees.
#
# Cases:
#   1. non-SessionStart event                    → exit 0, silent
#   2. empty stdin                               → exit 0, silent
#   3. missing .cwd                              → exit 0, silent
#   4. no project settings.json                  → exit 0, silent
#   5. project settings.json without .statusLine → exit 0, silent
#   6. happy path (gitignored)                   → seeds settings.local.json
#   7. existing local .statusLine preserved      → never overwritten
#   8. merge preserves other pre-existing keys
#   9. settings.local.json NOT gitignored        → safety skip, hint printed
#  10. idempotent — second happy-path run = same end state

load '../test_helper'

setup() {
    setup_isolated_home
    command -v jq >/dev/null 2>&1 || skip "jq not available"
    command -v git >/dev/null 2>&1 || skip "git not available"

    # Isolated dotfiles/claude tree so SSOT (…/claude/settings.json, resolved
    # relative to the hook) is fully under test control.
    ISO_CLAUDE="$TEST_TEMP_HOME/iso/claude"
    mkdir -p "$ISO_CLAUDE/hooks"
    cp "${_BATS_REAL_DOTFILES_ROOT}/claude/hooks/session-start-statusline-project-override.sh" \
        "$ISO_CLAUDE/hooks/session-start-statusline-project-override.sh"
    HOOK="$ISO_CLAUDE/hooks/session-start-statusline-project-override.sh"

    # SSOT with the dotfiles global statusLine.
    SSOT="$ISO_CLAUDE/settings.json"
    cat >"$SSOT" <<'JSON'
{ "statusLine": { "type": "command", "command": "${HOME}/dotfiles/claude/statusline-command.sh" } }
JSON

    # Isolated fake project as a real git repo (so `git check-ignore` works).
    PROJ="$TEST_TEMP_HOME/project"
    mkdir -p "$PROJ/.claude"
    git -C "$PROJ" init -q
    PROJ_SETTINGS="$PROJ/.claude/settings.json"
    PROJ_LOCAL="$PROJ/.claude/settings.local.json"
}

teardown() {
    teardown_isolated_home
}

# Feed a SessionStart payload to the hook on stdin. stderr is redirected to a
# file so $output holds only the stdout JSON (bats otherwise merges the two,
# corrupting the JSON parse). Optional args: $1 event, $2 cwd.
_run_hook() {
    local event="${1:-SessionStart}"
    local cwd="${2:-$PROJ}"
    run bash -c "printf '{\"hook_event_name\":\"%s\",\"cwd\":\"%s\"}' '$event' '$cwd' | '$HOOK' 2>'$TEST_TEMP_HOME/stderr'"
    STDERR_CONTENT=$(cat "$TEST_TEMP_HOME/stderr" 2>/dev/null)
}

# Project settings.json that itself defines a .statusLine (the override case).
_project_has_statusline() {
    cat >"$PROJ_SETTINGS" <<'JSON'
{ "statusLine": { "type": "command", "command": "./project-statusline.sh" } }
JSON
}

# Make settings.local.json gitignored in the project.
_gitignore_local() {
    printf '.claude/settings.local.json\n' >"$PROJ/.gitignore"
}

@test "statusline-override: non-SessionStart event → silent, exit 0" {
    _project_has_statusline
    _gitignore_local
    _run_hook "Stop"
    assert_success
    [ -z "$output" ]
    [ ! -f "$PROJ_LOCAL" ]
}

@test "statusline-override: empty stdin → silent, exit 0" {
    run bash -c "printf '' | '$HOOK'"
    assert_success
    [ -z "$output" ]
}

@test "statusline-override: missing .cwd → silent, exit 0" {
    run bash -c "printf '{\"hook_event_name\":\"SessionStart\"}' | '$HOOK' 2>'$TEST_TEMP_HOME/stderr'"
    assert_success
    [ -z "$output" ]
}

@test "statusline-override: no project settings.json → silent, exit 0" {
    _gitignore_local
    _run_hook
    assert_success
    [ -z "$output" ]
    [ ! -f "$PROJ_LOCAL" ]
}

@test "statusline-override: project settings.json without .statusLine → silent, exit 0" {
    printf '{ "foo": 1 }\n' >"$PROJ_SETTINGS"
    _gitignore_local
    _run_hook
    assert_success
    [ -z "$output" ]
    [ ! -f "$PROJ_LOCAL" ]
}

@test "statusline-override: happy path → seeds settings.local.json + additionalContext" {
    _project_has_statusline
    _gitignore_local
    _run_hook
    assert_success
    assert_output --partial '"hookEventName": "SessionStart"'
    assert_output --partial 'Seeded'
    [[ "$STDERR_CONTENT" == *"Seeded"* ]]

    [ -f "$PROJ_LOCAL" ]
    seeded=$(jq -r '.statusLine.command' "$PROJ_LOCAL")
    [ "$seeded" = '${HOME}/dotfiles/claude/statusline-command.sh' ]
}

@test "statusline-override: existing local .statusLine is preserved, never overwritten" {
    _project_has_statusline
    _gitignore_local
    cat >"$PROJ_LOCAL" <<'JSON'
{ "statusLine": { "type": "command", "command": "./my-personal-statusline.sh" } }
JSON
    _run_hook
    assert_success
    [ -z "$output" ]
    kept=$(jq -r '.statusLine.command' "$PROJ_LOCAL")
    [ "$kept" = "./my-personal-statusline.sh" ]
}

@test "statusline-override: merge preserves other pre-existing keys" {
    _project_has_statusline
    _gitignore_local
    cat >"$PROJ_LOCAL" <<'JSON'
{ "model": "sonnet", "env": { "FOO": "bar" } }
JSON
    _run_hook
    assert_success
    [ "$(jq -r '.model' "$PROJ_LOCAL")" = "sonnet" ]
    [ "$(jq -r '.env.FOO' "$PROJ_LOCAL")" = "bar" ]
    [ "$(jq -r '.statusLine.command' "$PROJ_LOCAL")" = '${HOME}/dotfiles/claude/statusline-command.sh' ]
}

@test "statusline-override: settings.local.json NOT gitignored → safety skip, hint printed" {
    _project_has_statusline
    # No .gitignore entry → path is tracked-eligible.
    _run_hook
    assert_success
    assert_output --partial 'NOT gitignored'
    [[ "$STDERR_CONTENT" == *"NOT gitignored"* ]]
    [ ! -f "$PROJ_LOCAL" ]
}

@test "statusline-override: idempotent — second happy-path run = same end state" {
    _project_has_statusline
    _gitignore_local
    _run_hook
    assert_success
    first=$(cat "$PROJ_LOCAL")

    _run_hook
    assert_success
    second=$(cat "$PROJ_LOCAL")
    [ "$first" = "$second" ]
    [ "$(jq -r '.statusLine.command' "$PROJ_LOCAL")" = '${HOME}/dotfiles/claude/statusline-command.sh' ]
}
