#!/usr/bin/env bats
# tests/bats/integrations/claude_accounts.bats
# Verify multi-account env vars and helper functions.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# ---------- Task 1: env defaults ----------

@test "bash: CLAUDE_DEFAULT_ACCOUNT defaults to personal" {
    run_in_bash 'echo "$CLAUDE_DEFAULT_ACCOUNT"'
    assert_success
    assert_output "personal"
}

@test "bash: CLAUDE_ENABLED_ACCOUNTS defaults to 'personal work'" {
    run_in_bash 'echo "$CLAUDE_ENABLED_ACCOUNTS"'
    assert_success
    assert_output "personal work"
}

@test "zsh: CLAUDE_DEFAULT_ACCOUNT defaults to personal" {
    run_in_zsh 'echo "$CLAUDE_DEFAULT_ACCOUNT"'
    assert_success
    assert_output "personal"
}

@test "zsh: CLAUDE_ENABLED_ACCOUNTS defaults to 'personal work'" {
    run_in_zsh 'echo "$CLAUDE_ENABLED_ACCOUNTS"'
    assert_success
    assert_output "personal work"
}

@test "bash: claude.local.sh exports win over claude.sh defaults" {
    # Avoid writing into the real repo (unprecedented in this codebase and
    # gitignored so a leak is invisible). Stage the override under the
    # isolated $HOME instead — torn down by teardown_isolated_home.
    cat > "$HOME/claude.local.sh" <<'LOCAL'
export CLAUDE_DEFAULT_ACCOUNT="work"
export CLAUDE_ENABLED_ACCOUNTS="work"
LOCAL

    run_in_bash '. "$HOME/claude.local.sh"; echo "$CLAUDE_DEFAULT_ACCOUNT|$CLAUDE_ENABLED_ACCOUNTS"'
    assert_success
    assert_output "work|work"
}

# ---------- Task 3: _claude_resolve_account ----------

@test "bash: resolve personal returns ~/.claude-personal" {
    run_in_bash '_claude_resolve_account personal'
    assert_success
    assert_output "$HOME/.claude-personal"
}

@test "bash: resolve work returns ~/.claude-work" {
    run_in_bash '_claude_resolve_account work'
    assert_success
    assert_output "$HOME/.claude-work"
}

@test "bash: resolve unknown account returns non-zero" {
    run_in_bash '_claude_resolve_account xyz'
    assert_failure
    refute_output --partial "/"
}

@test "bash: resolve --list-all returns 'personal work'" {
    run_in_bash '_claude_resolve_account --list-all'
    assert_success
    assert_output "personal work"
}

@test "bash: resolve --list returns ENABLED accounts only (default)" {
    run_in_bash '_claude_resolve_account --list | tr "\n" " "'
    assert_success
    assert_output "personal work "
}

@test "bash: resolve --list filters by CLAUDE_ENABLED_ACCOUNTS=work" {
    run_in_bash 'CLAUDE_ENABLED_ACCOUNTS="work" _claude_resolve_account --list | tr "\n" " "'
    assert_success
    assert_output "work "
}
