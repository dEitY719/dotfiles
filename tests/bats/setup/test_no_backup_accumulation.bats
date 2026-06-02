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
    # not stamp a timestamped backup per run — latest-only fixed `.bak`.
    run grep -nE 'pre-[a-z-]+-fix-\$\(date' "${DOTFILES_ROOT}/claude/setup.sh"
    assert_failure
}

@test "claude_stop_hook_install.sh: fixed .bak suffix (issue #919)" {
    run grep -nE 'pre-stop-hook-fix-\$\(date' \
        "${DOTFILES_ROOT}/shell-common/functions/claude_stop_hook_install.sh"
    assert_failure
}
