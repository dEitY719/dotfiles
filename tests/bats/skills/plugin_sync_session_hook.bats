#!/usr/bin/env bats
# tests/bats/skills/plugin_sync_session_hook.bats
# claude/hooks/plugin-sync-session.sh — SSOT-diff path that catches the
# built-in `/plugin` slash commands the PostToolUse+Bash hook misses (#1082).
#
# The Stop branch shells out to $HOME/dotfiles/claude/hooks/plugin-sync.sh, so
# each test copies the real CLI-path hook into the isolated $HOME first.
#
# #1685: the public scope that hook writes is the gitignored overlay
# claude/plugin/{marketplaces,plugins}.local.json — the tracked contract is
# read-only and no public commit is made. The bulk-resync commit title
# (#1558) is therefore asserted on the company/ scope.

load '../test_helper'

HOOK="${_BATS_REAL_DOTFILES_ROOT}/claude/hooks/plugin-sync-session.sh"
SID="sess-1082"

setup() {
    setup_isolated_home
    MAIN_ROOT="$TEST_TEMP_HOME/dotfiles"
    mkdir -p "$MAIN_ROOT/claude/plugin" "$MAIN_ROOT/claude/hooks"
    cp "${_BATS_REAL_DOTFILES_ROOT}/claude/hooks/plugin-sync.sh" \
        "$MAIN_ROOT/claude/hooks/plugin-sync.sh"
    chmod +x "$MAIN_ROOT/claude/hooks/plugin-sync.sh"
    git -C "$MAIN_ROOT" init -q
    git -C "$MAIN_ROOT" config user.email "hook-test@example.com"
    git -C "$MAIN_ROOT" config user.name "hook-test"

    SRC="$TEST_TEMP_HOME/.claude-shared/plugins"
    mkdir -p "$SRC"
}

teardown() {
    teardown_isolated_home
}

# --- SSOT fixtures -----------------------------------------------------------

_ssot_one() {
    cat > "$SRC/known_marketplaces.json" <<'JSON'
{"mp-a": {"source": {"source": "github", "repo": "org/a"}}}
JSON
    cat > "$SRC/installed_plugins.json" <<'JSON'
{"plugins": {"plug-a@mp-a": [{"scope": "user"}]}}
JSON
}

_ssot_two() {
    cat > "$SRC/known_marketplaces.json" <<'JSON'
{"mp-a": {"source": {"source": "github", "repo": "org/a"}},
 "mp-b": {"source": {"source": "github", "repo": "org/b"}}}
JSON
    cat > "$SRC/installed_plugins.json" <<'JSON'
{"plugins": {"plug-a@mp-a": [{"scope": "user"}], "plug-b@mp-b": [{"scope": "user"}]}}
JSON
}

# 사내(non-github) 버전의 같은 픽스처 — company/ 스코프 검증용.
_ssot_internal_one() {
    _company_repo
    cat > "$SRC/known_marketplaces.json" <<'JSON'
{"mp-a": {"source": {"source": "git", "url": "git@ghes.example.com:org/a.git"}}}
JSON
    cat > "$SRC/installed_plugins.json" <<'JSON'
{"plugins": {"plug-a@mp-a": [{"scope": "user"}]}}
JSON
}

_ssot_internal_two() {
    cat > "$SRC/known_marketplaces.json" <<'JSON'
{"mp-a": {"source": {"source": "git", "url": "git@ghes.example.com:org/a.git"}},
 "mp-b": {"source": {"source": "git", "url": "git@ghes.example.com:org/b.git"}}}
JSON
    cat > "$SRC/installed_plugins.json" <<'JSON'
{"plugins": {"plug-a@mp-a": [{"scope": "user"}], "plug-b@mp-b": [{"scope": "user"}]}}
JSON
}

_company_repo() {
    mkdir -p "$MAIN_ROOT/claude/plugin/company"
    git -C "$MAIN_ROOT/claude/plugin/company" init -q
    git -C "$MAIN_ROOT/claude/plugin/company" config user.email "hook-test@example.com"
    git -C "$MAIN_ROOT/claude/plugin/company" config user.name "hook-test"
}

_session_start() {
    payload="{\"hook_event_name\":\"SessionStart\",\"session_id\":\"$SID\",\"source\":\"startup\"}"
    run bash -c "printf '%s' '$payload' | '$HOOK'"
}

_stop() {
    payload="{\"hook_event_name\":\"Stop\",\"session_id\":\"$SID\",\"stop_hook_active\":false}"
    run bash -c "printf '%s' '$payload' | '$HOOK'"
}

# --- (a) hash unchanged → no-op ---------------------------------------------

@test "unchanged SSOT between SessionStart and Stop → no sync, no manifest" {
    _ssot_one
    _session_start
    assert_success
    _stop
    assert_success
    # add-sync never ran: the overlay file was never written.
    [ ! -f "$MAIN_ROOT/claude/plugin/plugins.local.json" ]
    # no commit either (repo has no commits at all)
    run git -C "$MAIN_ROOT" rev-parse HEAD
    assert_failure
}

# --- (b) hash changed → sync runs -------------------------------------------

@test "SSOT changes after SessionStart → Stop syncs the public overlay" {
    _ssot_one
    _session_start
    assert_success
    # A /plugin install happened during the session (SSOT grew a second entry).
    _ssot_two
    _stop
    assert_success

    run jq -e '.plugins | (any(. == "plug-a@mp-a") and any(. == "plug-b@mp-b"))' \
        "$MAIN_ROOT/claude/plugin/plugins.local.json"
    assert_success
    # 공용 스코프는 tracked 파일을 건드리지 않으므로 커밋도 없다 (#1685).
    run git -C "$MAIN_ROOT" rev-parse HEAD
    assert_failure
}

@test "SSOT changes after SessionStart → Stop commits the company scope with the bulk title (#1558)" {
    # End-to-end proof of #1558: this driver reaches plugin-sync.sh through the
    # __slash_command_sync__ sentinel, which has no single target — so the
    # title names every key the re-sync actually added instead of the bare
    # subject that used to make an 11-plugin sync look like a no-op one.
    # #1685 이후 이 커밋이 남는 스코프는 company/ 뿐이다.
    _ssot_internal_one
    _session_start
    assert_success
    _ssot_internal_two
    _stop
    assert_success

    run git -C "$MAIN_ROOT/claude/plugin/company" log -1 --format=%s
    assert_output "chore(claude-plugin): sync manifest (+mp-a +mp-b +plug-a@mp-a +plug-b@mp-b)"
}

# --- (c) no baseline (first session) → Stop still syncs ----------------------

@test "no baseline yet → Stop treats it as changed and syncs" {
    _ssot_two
    # No SessionStart call → baseline file absent.
    _stop
    assert_success
    run jq -e '.plugins | (any(. == "plug-a@mp-a") and any(. == "plug-b@mp-b"))' \
        "$MAIN_ROOT/claude/plugin/plugins.local.json"
    assert_success
}

# --- removal detected via key-set diff --------------------------------------

@test "plugin + marketplace removed from SSOT → Stop drops them from manifest" {
    _ssot_two
    # Seed an overlay that already carries both entries (previously synced).
    cat > "$MAIN_ROOT/claude/plugin/marketplaces.local.json" <<'JSON'
{"mp-a": "org/a", "mp-b": "org/b"}
JSON
    cat > "$MAIN_ROOT/claude/plugin/plugins.local.json" <<'JSON'
{"plugins": ["plug-a@mp-a", "plug-b@mp-b"]}
JSON

    _session_start
    assert_success
    # /plugin uninstall plug-b + /plugin marketplace remove mp-b → SSOT shrinks.
    _ssot_one
    _stop
    assert_success

    run jq -e 'has("mp-b")' "$MAIN_ROOT/claude/plugin/marketplaces.local.json"
    assert_failure
    run jq -e '.plugins | any(. == "plug-b@mp-b")' "$MAIN_ROOT/claude/plugin/plugins.local.json"
    assert_failure
    # surviving entries stay
    run jq -e 'has("mp-a")' "$MAIN_ROOT/claude/plugin/marketplaces.local.json"
    assert_success
    run jq -e '.plugins | any(. == "plug-a@mp-a")' "$MAIN_ROOT/claude/plugin/plugins.local.json"
    assert_success
}

# --- plugin-only SSOT (no known_marketplaces.json) still detects removals -----

@test "only installed_plugins.json present → plugin removal still propagates" {
    # No known_marketplaces.json at all — the Stop guard must not early-exit.
    cat > "$SRC/installed_plugins.json" <<'JSON'
{"plugins": {"plug-a@mp-a": [{"scope": "user"}]}}
JSON
    cat > "$MAIN_ROOT/claude/plugin/plugins.local.json" <<'JSON'
{"plugins": ["plug-a@mp-a"]}
JSON

    _session_start
    assert_success
    # /plugin uninstall plug-a → installed_plugins.json empties out.
    echo '{"plugins": {}}' > "$SRC/installed_plugins.json"
    _stop
    assert_success

    run jq -e '.plugins | any(. == "plug-a@mp-a")' "$MAIN_ROOT/claude/plugin/plugins.local.json"
    assert_failure
}

# --- guards ------------------------------------------------------------------

@test "no session_id → no-op" {
    _ssot_two
    payload='{"hook_event_name":"Stop","stop_hook_active":false}'
    run bash -c "printf '%s' '$payload' | '$HOOK'"
    assert_success
    [ ! -f "$MAIN_ROOT/claude/plugin/plugins.local.json" ]
}

@test "terminal stdin → immediate exit, no work" {
    _ssot_two
    run bash -c "'$HOOK' < /dev/tty" 2>/dev/null || true
    [ ! -f "$MAIN_ROOT/claude/plugin/plugins.local.json" ]
}
