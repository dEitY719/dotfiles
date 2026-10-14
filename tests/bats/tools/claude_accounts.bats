#!/usr/bin/env bats
# tests/bats/tools/claude_accounts.bats
# The claude-accounts executable (issue #2146): tools/integrations/claude.sh
# keeps the `claude_accounts` dispatcher as a function and delegates the
# subcommand bodies here; the bodies live in lib/claude_accounts_*.sh.

load '../test_helper'

SCRIPT="${DOTFILES_ROOT}/shell-common/tools/custom/claude_accounts.sh"
LIB_DIR="${DOTFILES_ROOT}/shell-common/tools/custom/lib"

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

@test "claude_accounts.sh and its libs parse under bash -n" {
    local f
    for f in "$SCRIPT" "$LIB_DIR"/claude_accounts_auth.sh \
        "$LIB_DIR"/claude_accounts_lifecycle.sh "$LIB_DIR"/claude_accounts_skills.sh; do
        run bash -n "$f"
        assert_success
    done
}

@test "claude_accounts.sh --help prints the subcommand list" {
    run "$SCRIPT" --help
    assert_success
    assert_output --partial "claude-accounts — Claude Code multi-account management"
    assert_output --partial "repair [--dry-run]"
}

@test "claude_accounts.sh routes each subcommand to its function" {
    run bash -c "
        . '$SCRIPT'
        claude_accounts_status() { echo 'status' \"\$@\"; }
        claude_accounts_init() { echo 'init' \"\$@\"; }
        claude_accounts_migrate() { echo 'migrate' \"\$@\"; }
        claude_accounts_rollback() { echo 'rollback' \"\$@\"; }
        claude_accounts_repair() { echo 'repair' \"\$@\"; }
        claude_accounts_link() { echo 'link' \"\$@\"; }
        claude_accounts_unlink() { echo 'unlink' \"\$@\"; }
        main; main status; main setup; main migrate
        main rollback work; main repair --dry-run; main link x --force; main unlink x
    "
    assert_success
    assert_output "status
status
init
migrate
rollback work
repair --dry-run
link x --force
unlink x"
}

@test "claude_accounts.sh: unknown subcommand fails with help" {
    run "$SCRIPT" bogus
    assert_failure
    assert_output --partial "Unknown subcommand: bogus"
}

@test "claude_accounts.sh list prints the enabled accounts" {
    run env CLAUDE_ENABLED_ACCOUNTS="personal work" "$SCRIPT" list
    assert_success
    assert_output "personal
work"
}

@test "integrations/claude.sh: dispatcher delegates and moved names stay defined" {
    run bash -c "
        . '${DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh'
        . '${DOTFILES_ROOT}/shell-common/tools/integrations/claude.sh'
        for f in claude_accounts claude_accounts_status claude_accounts_init \
            claude_accounts_link _claude_resolve_account _claude_ensure_symlink \
            _claude_prune_workspace_skills _claude_install_herdr_hook \
            _claude_account_setup_one _claude_has_unmigrated_data; do
            declare -F \"\$f\" >/dev/null || echo \"missing \$f\"
        done
        CLAUDE_ENABLED_ACCOUNTS='a b' claude_accounts list
    "
    assert_success
    assert_output "a
b"
}

@test "integrations/claude.sh: lazy loader re-dispatches to the real body (bash, zsh)" {
    local tgt="$TEST_TEMP_HOME/lazy-skills" sh
    for sh in bash zsh; do
        command -v "$sh" >/dev/null 2>&1 || continue
        rm -rf "$tgt"
        : >"$tgt"   # a stray file: the real _claude_prepare_skills_dir backs it up
        run "$sh" -c "
            . '${DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh'
            . '${DOTFILES_ROOT}/shell-common/tools/integrations/claude.sh'
            _claude_prepare_skills_dir '$tgt' >/dev/null 2>&1 || exit 1
            [ -d '$tgt' ] && [ -e '$tgt.original' ] || exit 2
            # second call goes straight to the real body (no reload)
            _claude_accounts_load() { return 1; }
            _claude_prepare_skills_dir '$tgt' >/dev/null 2>&1 || exit 3
        "
        assert_success
        rm -rf "$tgt" "$tgt.original"
    done
}

@test "integrations/claude.sh stays under 500 lines" {
    run wc -l <"${DOTFILES_ROOT}/shell-common/tools/integrations/claude.sh"
    assert_success
    [ "$output" -le 500 ]
}
