#!/usr/bin/env bats
# tests/bats/setup/claude_setup.bats
# claude/setup.sh phase structure + single link table (#2141).

load '../test_helper'

setup() {
    setup_isolated_home
    setup_isolated_dotfiles_root
}

teardown() {
    teardown_isolated_home
}

# Source setup.sh (the BASH_SOURCE guard keeps main from running), load the
# libs, append one fixture row to _claude_link_table, then run main with the
# libs already loaded so the override survives.
_run_setup_with_extra_row() {
    printf 'fixture\n' >"$DOTFILES_ROOT/claude/extra.txt"
    run_in_bash "
        source '${DOTFILES_ROOT}/claude/setup.sh'
        _phase_load_libs
        eval \"_orig_link_table() \$(declare -f _claude_link_table | tail -n +2)\"
        _claude_link_table() {
            _orig_link_table
            printf '%s\n' 'claude/extra.txt|extra.txt|link|all'
        }
        _phase_load_libs() { :; }
        main
    "
}

@test "#2141: one table row reaches multi provisioning and verify" {
    _run_setup_with_extra_row
    assert_success
    for acct in personal work work1; do
        [ -L "$HOME/.claude-$acct/extra.txt" ]
        assert_output --partial "✓ $acct/extra.txt 심볼릭 링크 확인됨"
    done
}

@test "#2141: one table row reaches internal provisioning and verify" {
    echo "internal" >"$HOME/.dotfiles-setup-mode"
    _run_setup_with_extra_row
    assert_success
    [ -L "$HOME/.claude/extra.txt" ]
    assert_output --partial "✓ ~/.claude/extra.txt 심볼릭 링크 확인됨"
    # multi-only row (settings.json) is filtered out of internal mode: no SSOT
    # copy and no check (herdr, when installed, may still write the file).
    refute_output --partial "settings.json up to date"
    refute_output --partial "settings.json 실파일"
    if [ -f "$HOME/.claude/settings.json" ]; then
        run cmp -s "$DOTFILES_ROOT/claude/settings.json" "$HOME/.claude/settings.json"
        assert_failure
    fi
}

@test "#2141: internal mode prunes workspace skill links through the table's dir row" {
    echo "internal" >"$HOME/.dotfiles-setup-mode"
    _ws="$HOME/ws-root"
    mkdir -p "$_ws/packaging-skills/skills/alpha" "$_ws/packaging-skills/.git"
    : >"$_ws/packaging-skills/skills/alpha/SKILL.md"
    mkdir -p "$HOME/.claude/skills"
    ln -s "$_ws/packaging-skills/skills/alpha" "$HOME/.claude/skills/alpha"

    run_in_bash "export WORKSPACE_ROOT='$_ws'; bash '${DOTFILES_ROOT}/claude/setup.sh'"
    assert_success
    assert_output --partial "워크스페이스 스킬 링크 정리 1개"
    [ ! -L "$HOME/.claude/skills/alpha" ]
    [ -d "$HOME/.claude/skills" ] && [ ! -L "$HOME/.claude/skills" ]
}

@test "#2141: internal mode still replaces a real directory with the link (--allow-dir kept)" {
    # The internal branch used dotfiles_ensure_link --allow-dir --unmount-legacy
    # directly; it now goes through _claude_ensure_symlink, which must keep
    # both flags: a pre-existing real ~/.claude/docs converges to the link and
    # its content survives in the backup instead of failing the run.
    echo "internal" >"$HOME/.dotfiles-setup-mode"
    mkdir -p "$HOME/.claude/docs"
    echo "user-note" >"$HOME/.claude/docs/note.md"

    run_in_bash "bash '${DOTFILES_ROOT}/claude/setup.sh'"
    assert_success
    [ -L "$HOME/.claude/docs" ]
    [ "$(readlink "$HOME/.claude/docs")" = "$DOTFILES_ROOT/claude/docs" ]
    grep -rqs "user-note" "$HOME/.claude/" --include=note.md
}

@test "#2141: _claude_link_apply fails when an earlier row fails" {
    run_in_bash "
        source '${DOTFILES_ROOT}/claude/setup.sh'
        _phase_load_libs
        _claude_link_table() { printf '%s\\n' 'claude/no-such-src|a|link|all' '-|skills|dir|all'; }
        _claude_ensure_symlink() { [ -e \"\$1\" ]; }
        _claude_link_apply multi '$HOME/.claude-x'
    "
    assert_failure
}

@test "#2141: verify fails when a table row is missing" {
    run_in_bash "
        source '${DOTFILES_ROOT}/claude/setup.sh'
        _phase_load_libs
        mkdir -p '$HOME/.claude-x'
        _claude_link_verify multi '$HOME/.claude-x' x
    "
    assert_failure
    assert_output --partial "x/settings.json 실파일 생성 실패"
}

@test "#2141: internal mode reaches _phase_report (no early exit)" {
    echo "internal" >"$HOME/.dotfiles-setup-mode"
    run_in_bash "bash '${DOTFILES_ROOT}/claude/setup.sh'"
    assert_success
    assert_output --partial "요약: 마이그레이션 0건"
    assert_output --partial "Claude Code 단일 계정 설정 완료 (internal PC mode)"
}

@test "#2141: SETUP_MIGRATIONS counted inside the table loop is not lost to a subshell" {
    # A /model-written key in the live copy is migrated to settings.local.json
    # by _claude_ensure_settings_copy, which runs inside _claude_link_apply.
    mkdir -p "$HOME/.claude-personal"
    printf '{ "model": "opus" }\n' >"$HOME/.claude-personal/settings.json"
    run_in_bash "bash '${DOTFILES_ROOT}/claude/setup.sh'"
    assert_success
    assert_output --partial "요약: 마이그레이션 1건"
}
