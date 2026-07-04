#!/usr/bin/env bats
# tests/bats/tools/claude_plugin_reconcile.bats
# claude/plugin/reconcile.sh — SSOT → manifest full-recompute drift 감지/복구.
# 실제 claude CLI 를 부르지 않으며, SSOT 는 CLAUDE_SHARED_PLUGINS_DIR 픽스처로 주입한다.

load '../test_helper'

RECONCILE="${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/reconcile.sh"

setup() {
    setup_isolated_home
    # A throwaway git repo hosting the public manifest, so --apply can commit.
    REPO="$TEST_TEMP_HOME/repo"
    mkdir -p "$REPO/claude/plugin"
    cp "$RECONCILE" "$REPO/claude/plugin/reconcile.sh"
    chmod +x "$REPO/claude/plugin/reconcile.sh"
    git -C "$REPO" init -q
    git -C "$REPO" config user.email t@example.com
    git -C "$REPO" config user.name tester
    SCRIPT="$REPO/claude/plugin/reconcile.sh"

    export CLAUDE_SHARED_PLUGINS_DIR="$TEST_TEMP_HOME/shared"
    mkdir -p "$CLAUDE_SHARED_PLUGINS_DIR"
    cat > "$CLAUDE_SHARED_PLUGINS_DIR/known_marketplaces.json" <<'JSON'
{
  "official":   {"source": {"source": "github", "repo": "anthropics/official"}},
  "understand": {"source": {"source": "github", "repo": "Egonex-AI/Understand"}},
  "localdir":   {"source": {"source": "directory", "path": "/opt/x"}}
}
JSON
    cat > "$CLAUDE_SHARED_PLUGINS_DIR/installed_plugins.json" <<'JSON'
{"plugins": {
  "superpowers@official":         [{"scope": "user"}],
  "understand-anything@understand": [{"scope": "user"}],
  "localthing@localdir":          [{"scope": "user"}]
}}
JSON
}

teardown() {
    teardown_isolated_home
}

# In-sync manifest fixture (matches the SSOT above, directory-source excluded).
_seed_in_sync_manifest() {
    cat > "$REPO/claude/plugin/marketplaces.json" <<'JSON'
{
  "official": "anthropics/official",
  "understand": "Egonex-AI/Understand"
}
JSON
    cat > "$REPO/claude/plugin/plugins.json" <<'JSON'
{
  "plugins": [
    "superpowers@official",
    "understand-anything@understand"
  ]
}
JSON
    git -C "$REPO" add -A
    git -C "$REPO" commit -qm seed
}

# Drifted manifest: a ghost marketplace + ghost plugin, and missing 'understand'.
_seed_drifted_manifest() {
    cat > "$REPO/claude/plugin/marketplaces.json" <<'JSON'
{"official": "anthropics/official", "ghost-mp": "someone/ghost"}
JSON
    cat > "$REPO/claude/plugin/plugins.json" <<'JSON'
{"plugins": ["superpowers@official", "ghost@ghost-mp"]}
JSON
    git -C "$REPO" add -A
    git -C "$REPO" commit -qm seed
}

@test "reconcile.sh --help prints usage and exits 0" {
    run "$SCRIPT" --help
    assert_success
    assert_output --partial 'Usage: reconcile.sh'
    assert_output --partial '--apply'
}

@test "reconcile.sh rejects an unknown flag" {
    run "$SCRIPT" --bogus
    assert_failure 2
    assert_output --partial '알 수 없는 인자: --bogus'
}

@test "reconcile.sh --check on an in-sync manifest reports no drift, exit 0" {
    _seed_in_sync_manifest
    run "$SCRIPT" --check
    assert_success
    assert_output --partial 'no drift'
}

@test "reconcile.sh defaults to --check when no flag is given" {
    _seed_in_sync_manifest
    run "$SCRIPT"
    assert_success
    assert_output --partial 'no drift'
}

@test "reconcile.sh --check on drift prints a table and exits non-zero" {
    _seed_drifted_manifest
    run "$SCRIPT" --check
    assert_failure
    assert_output --partial '+ understand'
    assert_output --partial '- ghost-mp'
    assert_output --partial '+ understand-anything@understand'
    assert_output --partial '- ghost@ghost-mp'
}

@test "reconcile.sh --apply rebuilds manifest to match SSOT (adds + prunes ghosts)" {
    _seed_drifted_manifest
    run "$SCRIPT" --apply
    assert_success

    # Ghost entries pruned, SSOT entries present, directory-source excluded.
    run jq -r 'keys | join(",")' "$REPO/claude/plugin/marketplaces.json"
    assert_output 'official,understand'
    run jq -r '.plugins | join(",")' "$REPO/claude/plugin/plugins.json"
    assert_output 'superpowers@official,understand-anything@understand'
}

@test "reconcile.sh --apply leaves exactly one sync commit, then --check is clean" {
    _seed_drifted_manifest
    before=$(git -C "$REPO" rev-list --count HEAD)
    run "$SCRIPT" --apply
    assert_success
    after=$(git -C "$REPO" rev-list --count HEAD)
    [ "$((after - before))" -eq 1 ]
    run git -C "$REPO" log -1 --pretty=%s
    assert_output 'chore(claude-plugin): sync manifest'

    run "$SCRIPT" --check
    assert_success
    assert_output --partial 'no drift'
}

@test "reconcile.sh --apply makes no commit when already in sync" {
    _seed_in_sync_manifest
    before=$(git -C "$REPO" rev-list --count HEAD)
    run "$SCRIPT" --apply
    assert_success
    after=$(git -C "$REPO" rev-list --count HEAD)
    [ "$after" -eq "$before" ]
}

@test "reconcile.sh errors clearly when the SSOT file is missing" {
    rm -f "$CLAUDE_SHARED_PLUGINS_DIR/installed_plugins.json"
    run "$SCRIPT" --check
    assert_failure 1
    assert_output --partial 'SSOT 파일이 없습니다'
    assert_output --partial 'installed_plugins.json'
}

@test "reconcile.sh skips company/ on a non-internal PC" {
    echo "external" > "$TEST_TEMP_HOME/.dotfiles-setup-mode"
    _seed_in_sync_manifest
    run "$SCRIPT" --check
    assert_success
    assert_output --partial 'company/ 건너뜀'
    refute_output --partial 'company/marketplaces.json'
}
