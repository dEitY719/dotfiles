#!/usr/bin/env bats
# tests/bats/setup/test_no_backup_accumulation.bats
# Regression guard for issue #806 — home-directory backup accumulation.
#
# Two halves:
#   1. The dotfiles_backup.sh helper applies a FIXED suffix, so repeated
#      backups overwrite a single file instead of accumulating.
#   2. The setup scripts no longer stamp home-directory backups with a
#      timestamp, and the redundant ~/.zshrc auto-cleanup hook is gone.

load '../test_helper'

setup() {
    setup_isolated_home
    BACKUP_HELPER="${DOTFILES_ROOT}/shell-common/functions/dotfiles_backup.sh"
}

teardown() {
    teardown_isolated_home
}

@test "helper: dotfiles_backup.sh exists" {
    [ -f "$BACKUP_HELPER" ]
}

@test "helper: fixed suffixes default to .backup / .original" {
    run bash -c ". '$BACKUP_HELPER'; echo \"\$DOTFILES_BACKUP_SUFFIX|\$DOTFILES_ORIGINAL_SUFFIX\""
    assert_success
    assert_output ".backup|.original"
}

@test "helper: backup_path appends fixed suffix" {
    run bash -c ". '$BACKUP_HELPER'; dotfiles_backup_path /tmp/foo"
    assert_success
    assert_output "/tmp/foo.backup"
}

@test "helper: backup_copy is idempotent (no accumulation)" {
    run bash -c '
        . "'"$BACKUP_HELPER"'"
        d=$(mktemp -d "${TMPDIR:-/tmp}/backup_test.XXXXXX")
        printf one > "$d/target"
        dotfiles_backup_copy "$d/target" >/dev/null
        printf two > "$d/target"
        dotfiles_backup_copy "$d/target" >/dev/null
        # Exactly one backup file must exist.
        count=$(find "$d" -maxdepth 1 -name "target.backup*" | wc -l | tr -d " ")
        echo "count=$count"
        cat "$d/target.backup"
        rm -rf "$d"
    '
    assert_success
    assert_output --partial "count=1"
    # The single backup reflects the LATEST copy.
    assert_output --partial "two"
}

@test "helper: backup_move overwrites prior backup" {
    run bash -c '
        . "'"$BACKUP_HELPER"'"
        d=$(mktemp -d "${TMPDIR:-/tmp}/backup_test.XXXXXX")
        printf first > "$d/t.backup"   # stale prior backup
        printf live  > "$d/t"
        dotfiles_backup_move "$d/t" >/dev/null
        count=$(find "$d" -maxdepth 1 -name "t.backup*" | wc -l | tr -d " ")
        echo "count=$count"
        cat "$d/t.backup"
        rm -rf "$d"
    '
    assert_success
    assert_output --partial "count=1"
    assert_output --partial "live"
}

@test "bash/setup.sh: redundant _add_zshrc_auto_cleanup hook removed" {
    # The function must no longer be defined or invoked. A reference inside an
    # explanatory comment is fine, so match only a definition/call (parens) or
    # a bare invocation at the start of a line.
    run grep -nE '_add_zshrc_auto_cleanup\(\)|^_add_zshrc_auto_cleanup' "${DOTFILES_ROOT}/bash/setup.sh"
    assert_failure
}

@test "bash/setup.sh: no timestamped home backups remain" {
    run grep -nE '(-\$\(date|\.backup\.\$\(date)' "${DOTFILES_ROOT}/bash/setup.sh"
    assert_failure   # grep finds nothing
}

@test "zsh/setup.sh: no timestamped -original backup remains" {
    run grep -nE '\-\$\(date' "${DOTFILES_ROOT}/zsh/setup.sh"
    assert_failure
}

@test "git/setup.sh: fixed .original suffix" {
    run grep -nE '\-\$\(date' "${DOTFILES_ROOT}/git/setup.sh"
    assert_failure
}

@test "gh/setup.sh: fixed .original suffix" {
    run grep -nE '\-\$\{BACKUP_DATE\}-original|\-\$\(date' "${DOTFILES_ROOT}/gh/setup.sh"
    assert_failure
}

@test "ssh/setup.sh: fixed .backup suffix" {
    run grep -nE '\.backup\.\$\(date' "${DOTFILES_ROOT}/ssh/setup.sh"
    assert_failure
}

@test "vscode-extensions/setup.sh: fixed .original suffix" {
    run grep -nE '\-\$\(date' "${DOTFILES_ROOT}/vscode-extensions/setup.sh"
    assert_failure
}

@test "claude/setup.sh: JSON-migration backups use fixed suffix (issue #919)" {
    # The three migration helpers (statusline / plugin-path / stop-hook) must
    # not stamp a timestamped backup per run — latest-only fixed `.backup`.
    run grep -nE 'pre-[a-z-]+-fix-\$\(date' "${DOTFILES_ROOT}/claude/setup.sh"
    assert_failure
}

@test "claude_stop_hook_install.sh: fixed .backup suffix (issue #919)" {
    run grep -nE 'pre-stop-hook-fix-\$\(date' \
        "${DOTFILES_ROOT}/shell-common/functions/claude_stop_hook_install.sh"
    assert_failure
}

@test "shell-common/tools/integrations/claude.sh: init/repair backups are not timestamped (issue #2130)" {
    # Scope: _claude_ensure_symlink / _claude_prepare_skills_dir. The one-shot
    # claude_accounts_rollback still stamps whole account dirs with
    # `-${_car_ts}-original` on purpose (latest-only would overwrite a
    # previous rollback's account data), so it is excluded here.
    run grep -nE -e '-\$\(date' "${DOTFILES_ROOT}/shell-common/tools/integrations/claude.sh"
    assert_failure
}

@test "_claude_ensure_symlink: repeated backups keep exactly one .original (issue #2130, #2138)" {
    # A real file at the link target forces the backup branch. Re-create a
    # real file before the second call so BOTH calls take that branch — the
    # pre-#2130 timestamped naming would leave two backups here. Since #2138
    # (dotfiles_ensure_link) an existing backup is never overwritten: the
    # second displaced file stays in place with a warning instead.
    run_in_bash '
        src="$HOME/src.txt"; tgt="$HOME/.claude-test/settings.txt"
        mkdir -p "$HOME/.claude-test"; printf src > "$src"
        printf first > "$tgt"
        _claude_ensure_symlink "$src" "$tgt" >/dev/null 2>&1 || exit 1
        echo "link1=$(readlink "$tgt")"
        rm "$tgt"; printf second > "$tgt"
        _claude_ensure_symlink "$src" "$tgt" 2>&1 || exit 1
        echo "count=$(find "$HOME/.claude-test" -maxdepth 1 -name "settings.txt?*" | wc -l | tr -d " ")"
        echo "backup=$(cat "$tgt.original")"
        echo "target=$(cat "$tgt")"
    '
    assert_success
    assert_output --partial "link1=$HOME/src.txt"
    assert_output --partial "count=1"
    assert_output --partial "already exists"
    assert_output --partial "backup=first"
    assert_output --partial "target=second"
}

@test "_claude_prepare_skills_dir: unexpected file backed up to fixed .original (issue #2130)" {
    run_in_bash '
        tgt="$HOME/.claude-test/skills"
        mkdir -p "$HOME/.claude-test"
        printf one > "$tgt"
        _claude_prepare_skills_dir "$tgt" >/dev/null 2>&1 || exit 1
        rmdir "$tgt"; printf two > "$tgt"
        _claude_prepare_skills_dir "$tgt" >/dev/null 2>&1 || exit 1
        echo "count=$(find "$HOME/.claude-test" -maxdepth 1 -name "skills?*" | wc -l | tr -d " ")"
        [ -d "$tgt" ] && echo "dir=yes"
        cat "$tgt.original"
    '
    assert_success
    assert_output --partial "count=1"
    assert_output --partial "dir=yes"
    assert_output --partial "two"
}

@test "helper: backup_move fails instead of nesting when the old backup cannot be removed" {
    [ "$(id -u)" -ne 0 ] || skip "root can remove read-only dirs"
    run bash -c '
        . "'"$BACKUP_HELPER"'"
        d=$(mktemp -d "${TMPDIR:-/tmp}/backup_test.XXXXXX")
        mkdir -p "$d/t.original/locked"; : > "$d/t.original/locked/f"
        chmod 555 "$d/t.original/locked"
        printf live > "$d/t"
        dotfiles_backup_move "$d/t" .original >/dev/null; echo "rc=$?"
        [ -f "$d/t" ] && echo "target=kept"
        [ -e "$d/t.original/t" ] && echo "nested=yes"
        chmod 755 "$d/t.original/locked"; rm -rf "$d"
    '
    assert_success
    assert_output --partial "rc=1"
    assert_output --partial "target=kept"
    refute_output --partial "nested=yes"
}

@test "_claude_backup_original: never overwrites a non-empty directory backup (issue #2130)" {
    run_in_bash '
        tgt="$HOME/.claude-test/skills"
        mkdir -p "$tgt.original" "$tgt"
        printf precious > "$tgt.original/data"; printf new > "$tgt/data"
        _claude_backup_original "$tgt" "revealed directory" >/dev/null 2>&1; echo "rc=$?"
        cat "$tgt.original/data"; echo; cat "$tgt/data"
    '
    assert_success
    assert_output --partial "rc=1"
    assert_output --partial "precious"
    assert_output --partial "new"
}

@test "claude.sh: variable-timestamp -original backups only in claude_accounts_rollback (issue #2130)" {
    # Catches `ts=$(date ...); mv x "$x-${ts}-original"` too, which the inline
    # `-$(date` grep above cannot see. Rollback (`_car_ts`) is the documented
    # exception.
    run bash -c "grep -nE '\\}-original|[a-z_]-original\"' '${DOTFILES_ROOT}/shell-common/tools/integrations/claude.sh' | grep -v '_car_ts'"
    assert_failure
}
