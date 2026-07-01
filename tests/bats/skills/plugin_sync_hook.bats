#!/usr/bin/env bats
# tests/bats/skills/plugin_sync_hook.bats
# claude/hooks/plugin-sync.sh — install/marketplace add 병합(union) 경로 검증.
# 삭제(uninstall/marketplace remove) 경로는 plugin_sync_hook_delete.bats.

load '../test_helper'

HOOK="${_BATS_REAL_DOTFILES_ROOT}/claude/hooks/plugin-sync.sh"

setup() {
    setup_isolated_home
    MAIN_ROOT="$TEST_TEMP_HOME/dotfiles"
    mkdir -p "$MAIN_ROOT/claude/plugin"
    git -C "$MAIN_ROOT" init -q
    git -C "$MAIN_ROOT" config user.email "hook-test@example.com"
    git -C "$MAIN_ROOT" config user.name "hook-test"

    SRC="$TEST_TEMP_HOME/.claude-shared/plugins"
    mkdir -p "$SRC"
}

teardown() {
    teardown_isolated_home
}

_known_marketplaces() {
    cat > "$SRC/known_marketplaces.json" <<'JSON'
{
  "claude-plugins-official": {"source": {"source": "github", "repo": "anthropics/claude-plugins-official"}},
  "gitkraken": {"source": {"source": "directory", "path": "/home/user/.claude/plugins/marketplaces/gitkraken"}},
  "internal-tools": {"source": {"source": "git", "url": "git@ghes.example.com:team/internal-tools.git"}}
}
JSON
}

# Simulate git/hooks/checks/main_branch_guard.sh: refuse direct commits on
# main/master unless the ALLOW_MAIN_COMMIT=1 escape hatch is set. Lets the
# isolated test repo reproduce the protected-branch condition (#1072) that
# the real CI repos never hit.
_install_protected_branch_guard() {
    mkdir -p "$1/.git/hooks"
    cat > "$1/.git/hooks/pre-commit" <<'HOOK'
#!/usr/bin/env bash
[ "${ALLOW_MAIN_COMMIT:-0}" = "1" ] && exit 0
branch=$(git symbolic-ref --short HEAD 2>/dev/null || true)
case "$branch" in
    main | master) echo "BLOCKING: direct commit on protected branch" >&2; exit 1 ;;
esac
exit 0
HOOK
    chmod +x "$1/.git/hooks/pre-commit"
}

_installed_plugins() {
    cat > "$SRC/installed_plugins.json" <<'JSON'
{
  "plugins": {
    "ralph-loop@claude-plugins-official": [{"scope": "user"}],
    "gitkraken-hooks@gitkraken": [{"scope": "user"}],
    "secret@internal-tools": [{"scope": "user"}],
    "visuals@claude-plugin-visuals": [{"scope": "local"}]
  }
}
JSON
}

@test "tool_name != Bash → no manifest change" {
    _known_marketplaces
    _installed_plugins
    payload='{"tool_name":"Read","tool_input":{"command":"claude plugin install foo@bar"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    run jq -e 'length == 0' "$MAIN_ROOT/claude/plugin/marketplaces.json"
    assert_failure  # file shouldn't even exist yet — mkdir/write never ran
}

@test "non-matching Bash command → no manifest change" {
    _known_marketplaces
    _installed_plugins
    payload='{"tool_name":"Bash","tool_input":{"command":"claude mcp list"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    [ ! -f "$MAIN_ROOT/claude/plugin/marketplaces.json" ]
}

@test "install → public manifest gets github-sourced scope:user entries only" {
    _known_marketplaces
    _installed_plugins
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install ralph-loop@claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    run jq -e '.["claude-plugins-official"] == "anthropics/claude-plugins-official"' \
        "$MAIN_ROOT/claude/plugin/marketplaces.json"
    assert_success
    run jq -e 'has("gitkraken") | not' "$MAIN_ROOT/claude/plugin/marketplaces.json"
    assert_success

    run jq -e '.plugins == ["ralph-loop@claude-plugins-official"]' \
        "$MAIN_ROOT/claude/plugin/plugins.json"
    assert_success

    # committed locally
    run git -C "$MAIN_ROOT" log -1 --format=%s
    assert_output "chore(claude-plugin): sync manifest"
}

@test "install → directory-source and scope:local entries excluded" {
    _known_marketplaces
    _installed_plugins
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install ralph-loop@claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    run jq -e 'has("gitkraken")' "$MAIN_ROOT/claude/plugin/marketplaces.json"
    assert_failure
    run jq -e '.plugins | any(. == "gitkraken-hooks@gitkraken")' "$MAIN_ROOT/claude/plugin/plugins.json"
    assert_failure
    run jq -e '.plugins | any(. == "visuals@claude-plugin-visuals")' "$MAIN_ROOT/claude/plugin/plugins.json"
    assert_failure
}

@test "install → merge preserves pre-existing manifest entries not in current local state" {
    _known_marketplaces
    _installed_plugins
    mkdir -p "$MAIN_ROOT/claude/plugin"
    echo '{"pre-existing": "someone/else"}' > "$MAIN_ROOT/claude/plugin/marketplaces.json"
    echo '{"plugins": ["pre-existing-plugin@pre-existing"]}' > "$MAIN_ROOT/claude/plugin/plugins.json"

    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install ralph-loop@claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    run jq -e '.["pre-existing"] == "someone/else"' "$MAIN_ROOT/claude/plugin/marketplaces.json"
    assert_success
    run jq -e '.plugins | any(. == "pre-existing-plugin@pre-existing")' "$MAIN_ROOT/claude/plugin/plugins.json"
    assert_success
    run jq -e '.plugins | any(. == "ralph-loop@claude-plugins-official")' "$MAIN_ROOT/claude/plugin/plugins.json"
    assert_success
}

@test "install → internal (non-github) entries go to claude/plugin/company only when that repo exists" {
    _known_marketplaces
    _installed_plugins
    mkdir -p "$MAIN_ROOT/claude/plugin/company"
    git -C "$MAIN_ROOT/claude/plugin/company" init -q
    git -C "$MAIN_ROOT/claude/plugin/company" config user.email "hook-test@example.com"
    git -C "$MAIN_ROOT/claude/plugin/company" config user.name "hook-test"

    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install secret@internal-tools"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    run jq -e '.["internal-tools"] == "git@ghes.example.com:team/internal-tools.git"' \
        "$MAIN_ROOT/claude/plugin/company/marketplaces.json"
    assert_success
    run jq -e '.plugins == ["secret@internal-tools"]' "$MAIN_ROOT/claude/plugin/company/plugins.json"
    assert_success
    # public manifest untouched by the internal-only plugin
    run jq -e 'has("internal-tools")' "$MAIN_ROOT/claude/plugin/marketplaces.json"
    assert_failure

    run git -C "$MAIN_ROOT/claude/plugin/company" log -1 --format=%s
    assert_output "chore(claude-plugin): sync manifest"
}

@test "install → internal entries skipped entirely when company/ repo not cloned" {
    _known_marketplaces
    _installed_plugins
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install secret@internal-tools"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    [ ! -d "$MAIN_ROOT/claude/plugin/company" ]
}

@test "marketplace add → treated the same as install (re-sync)" {
    _known_marketplaces
    _installed_plugins
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin marketplace add anthropics/claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    run jq -e '.["claude-plugins-official"] == "anthropics/claude-plugins-official"' \
        "$MAIN_ROOT/claude/plugin/marketplaces.json"
    assert_success
}

@test "install → pre-existing 0-byte manifest does not break the merge (empty-file guard)" {
    _known_marketplaces
    _installed_plugins
    mkdir -p "$MAIN_ROOT/claude/plugin"
    : > "$MAIN_ROOT/claude/plugin/marketplaces.json"   # 0-byte, valid-JSON-less
    : > "$MAIN_ROOT/claude/plugin/plugins.json"

    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install ralph-loop@claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    run jq -e '.["claude-plugins-official"] == "anthropics/claude-plugins-official"' \
        "$MAIN_ROOT/claude/plugin/marketplaces.json"
    assert_success
    run jq -e '.plugins == ["ralph-loop@claude-plugins-official"]' \
        "$MAIN_ROOT/claude/plugin/plugins.json"
    assert_success
}

@test "install → commit lands even on protected 'main' branch (#1072 escape hatch)" {
    _known_marketplaces
    _installed_plugins
    git -C "$MAIN_ROOT" symbolic-ref HEAD refs/heads/main
    _install_protected_branch_guard "$MAIN_ROOT"

    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install ralph-loop@claude-plugins-official"}}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success

    # The manifest is actually committed — not silently blocked and left
    # unstaged as it was before the ALLOW_MAIN_COMMIT=1 fix.
    run git -C "$MAIN_ROOT" log -1 --format=%s
    assert_output "chore(claude-plugin): sync manifest"
    run git -C "$MAIN_ROOT" status --porcelain
    assert_output ""
}

@test "no-op re-run does not create an empty commit" {
    _known_marketplaces
    _installed_plugins
    payload='{"tool_name":"Bash","tool_input":{"command":"claude plugin install ralph-loop@claude-plugins-official"}}'
    bash -c "printf '%s' '$payload' | '$HOOK'"
    before=$(git -C "$MAIN_ROOT" rev-parse HEAD)

    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    after=$(git -C "$MAIN_ROOT" rev-parse HEAD)
    [ "$before" = "$after" ]
}
