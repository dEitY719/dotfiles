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
