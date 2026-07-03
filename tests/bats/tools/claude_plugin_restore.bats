#!/usr/bin/env bats
# tests/bats/tools/claude_plugin_restore.bats
# claude/plugin/restore.sh — dry-run 출력 및 모드별(internal/external) 분기 검증.
# 실제 claude CLI를 부르지 않도록 --dry-run만 테스트한다 (설치 부작용 없음).

load '../test_helper'

RESTORE="${_BATS_REAL_DOTFILES_ROOT}/claude/plugin/restore.sh"

setup() {
    setup_isolated_home
    PLUGDIR="$TEST_TEMP_HOME/plugdir"
    mkdir -p "$PLUGDIR"
    cp "$RESTORE" "$PLUGDIR/restore.sh"
    chmod +x "$PLUGDIR/restore.sh"

    cat > "$PLUGDIR/marketplaces.json" <<'JSON'
{"understand-anything": "Egonex-AI/Understand-Anything"}
JSON
    cat > "$PLUGDIR/plugins.json" <<'JSON'
{"plugins": ["understand-anything@understand-anything"]}
JSON
}

teardown() {
    teardown_isolated_home
}

@test "restore.sh --dry-run lists public marketplace and plugin without installing" {
    run "$PLUGDIR/restore.sh" --dry-run
    assert_success
    assert_output --partial 'add: understand-anything (Egonex-AI/Understand-Anything)'
    assert_output --partial 'install: understand-anything@understand-anything'
}

@test "restore.sh skips company manifest on external mode" {
    echo "external" > "$TEST_TEMP_HOME/.dotfiles-setup-mode"
    mkdir -p "$PLUGDIR/company"
    git -C "$PLUGDIR/company" init -q
    cat > "$PLUGDIR/company/marketplaces.json" <<'JSON'
{"internal-tools": "git@ghes.example.com:team/internal-tools.git"}
JSON
    cat > "$PLUGDIR/company/plugins.json" <<'JSON'
{"plugins": ["secret@internal-tools"]}
JSON

    run "$PLUGDIR/restore.sh" --dry-run
    assert_success
    refute_output --partial 'internal-tools'
    assert_output --partial '모드: external'
}

@test "restore.sh restores company manifest on internal mode when company/.git exists" {
    echo "internal" > "$TEST_TEMP_HOME/.dotfiles-setup-mode"
    mkdir -p "$PLUGDIR/company"
    git -C "$PLUGDIR/company" init -q
    cat > "$PLUGDIR/company/marketplaces.json" <<'JSON'
{"internal-tools": "git@ghes.example.com:team/internal-tools.git"}
JSON
    cat > "$PLUGDIR/company/plugins.json" <<'JSON'
{"plugins": ["secret@internal-tools"]}
JSON

    run "$PLUGDIR/restore.sh" --dry-run
    assert_success
    assert_output --partial 'add: internal-tools (git@ghes.example.com:team/internal-tools.git)'
    assert_output --partial 'install: secret@internal-tools'
}

@test "restore.sh prompts for manual clone on internal mode without company/.git" {
    echo "internal" > "$TEST_TEMP_HOME/.dotfiles-setup-mode"

    run "$PLUGDIR/restore.sh" --dry-run
    assert_success
    assert_output --partial '사내 전용 레포 미설정'
}

@test "restore.sh --help prints usage and exits 0 without touching CLI" {
    run "$PLUGDIR/restore.sh" --help
    assert_success
    assert_output --partial 'Usage: restore.sh'
    assert_output --partial '--sync'
}

@test "restore.sh rejects an unknown flag" {
    run "$PLUGDIR/restore.sh" --bogus
    assert_failure 2
    assert_output --partial '알 수 없는 인자: --bogus'
}

# --- --sync prune pass -----------------------------------------------------

# Seed a local ground-truth fixture (mirrors ~/.claude-shared/plugins) and
# point restore.sh at it via CLAUDE_SHARED_PLUGINS_DIR.
_seed_local_state() {
    export CLAUDE_SHARED_PLUGINS_DIR="$TEST_TEMP_HOME/shared"
    mkdir -p "$CLAUDE_SHARED_PLUGINS_DIR"
    cat > "$CLAUDE_SHARED_PLUGINS_DIR/known_marketplaces.json" <<'JSON'
{
  "understand-anything": {"source": {"source": "github", "repo": "Egonex-AI/Understand-Anything"}},
  "surplus-mp":          {"source": {"source": "github", "repo": "foo/surplus"}},
  "gitkraken":           {"source": {"source": "directory", "path": "/opt/gitkraken"}}
}
JSON
    cat > "$CLAUDE_SHARED_PLUGINS_DIR/installed_plugins.json" <<'JSON'
{
  "plugins": {
    "understand-anything@understand-anything": [{"scope": "user"}],
    "surplus@surplus-mp":                       [{"scope": "user"}],
    "gk@gitkraken":                             [{"scope": "user"}],
    "projectplug@surplus-mp":                   [{"scope": "project"}]
  }
}
JSON
}

@test "restore.sh --sync --dry-run prunes surplus marketplace + plugin, keeps SSOT items" {
    _seed_local_state
    run "$PLUGDIR/restore.sh" --sync --dry-run
    assert_success
    assert_output --partial 'remove: surplus-mp'
    assert_output --partial 'uninstall: surplus@surplus-mp'
    # SSOT-present items must NOT be pruned.
    refute_output --partial 'remove: understand-anything'
    refute_output --partial 'uninstall: understand-anything@understand-anything'
}

@test "restore.sh --sync leaves source:directory marketplaces alone" {
    _seed_local_state
    run "$PLUGDIR/restore.sh" --sync --dry-run
    assert_success
    refute_output --partial 'remove: gitkraken'
    refute_output --partial 'uninstall: gk@gitkraken'
}

@test "restore.sh --sync ignores scope:project plugins" {
    _seed_local_state
    run "$PLUGDIR/restore.sh" --sync --dry-run
    assert_success
    refute_output --partial 'projectplug@surplus-mp'
}

@test "restore.sh --sync respects the .local-marketplaces.json whitelist" {
    _seed_local_state
    cat > "$PLUGDIR/.local-marketplaces.json" <<'JSON'
{"marketplaces": ["surplus-mp"], "plugins": ["surplus@surplus-mp"]}
JSON
    run "$PLUGDIR/restore.sh" --sync --dry-run
    assert_success
    refute_output --partial 'remove: surplus-mp'
    refute_output --partial 'uninstall: surplus@surplus-mp'
}

@test "restore.sh --sync reports nothing to prune when local matches SSOT" {
    export CLAUDE_SHARED_PLUGINS_DIR="$TEST_TEMP_HOME/shared"
    mkdir -p "$CLAUDE_SHARED_PLUGINS_DIR"
    cat > "$CLAUDE_SHARED_PLUGINS_DIR/known_marketplaces.json" <<'JSON'
{"understand-anything": {"source": {"source": "github", "repo": "Egonex-AI/Understand-Anything"}}}
JSON
    cat > "$CLAUDE_SHARED_PLUGINS_DIR/installed_plugins.json" <<'JSON'
{"plugins": {"understand-anything@understand-anything": [{"scope": "user"}]}}
JSON
    run "$PLUGDIR/restore.sh" --sync --dry-run
    assert_success
    assert_output --partial '제거할 잉여 항목 없음'
}

@test "restore.sh --sync keeps company plugins on internal mode with company/.git" {
    echo "internal" > "$TEST_TEMP_HOME/.dotfiles-setup-mode"
    mkdir -p "$PLUGDIR/company"
    git -C "$PLUGDIR/company" init -q
    cat > "$PLUGDIR/company/marketplaces.json" <<'JSON'
{"internal-tools": "git@ghes.example.com:team/internal-tools.git"}
JSON
    cat > "$PLUGDIR/company/plugins.json" <<'JSON'
{"plugins": ["secret@internal-tools"]}
JSON
    export CLAUDE_SHARED_PLUGINS_DIR="$TEST_TEMP_HOME/shared"
    mkdir -p "$CLAUDE_SHARED_PLUGINS_DIR"
    cat > "$CLAUDE_SHARED_PLUGINS_DIR/known_marketplaces.json" <<'JSON'
{"internal-tools": {"source": {"source": "git", "url": "git@ghes.example.com:team/internal-tools.git"}}}
JSON
    cat > "$CLAUDE_SHARED_PLUGINS_DIR/installed_plugins.json" <<'JSON'
{"plugins": {"secret@internal-tools": [{"scope": "user"}]}}
JSON
    run "$PLUGDIR/restore.sh" --sync --dry-run
    assert_success
    # internal-tools is company SSOT → part of the keep-set → not pruned.
    refute_output --partial 'remove: internal-tools'
    refute_output --partial 'uninstall: secret@internal-tools'
}
