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

@test "zsh: resolve --list works under zsh (POSIX parity smoke test)" {
    run_in_zsh '_claude_resolve_account --list | tr "\n" " "'
    assert_success
    assert_output "personal work "
}

# ---------- Task 4: ensure helpers (idempotency) ----------

@test "bash: _claude_ensure_symlink creates new symlink" {
    mkdir -p "$HOME/src" "$HOME/tgt-dir"
    touch "$HOME/src/file.txt"
    run_in_bash "_claude_ensure_symlink '$HOME/src/file.txt' '$HOME/tgt-dir/link'"
    assert_success
    [ -L "$HOME/tgt-dir/link" ]
}

@test "bash: _claude_ensure_symlink is idempotent (already correct)" {
    mkdir -p "$HOME/src" "$HOME/tgt-dir"
    touch "$HOME/src/file.txt"
    ln -s "$HOME/src/file.txt" "$HOME/tgt-dir/link"
    run_in_bash "_claude_ensure_symlink '$HOME/src/file.txt' '$HOME/tgt-dir/link'"
    assert_success
    assert_output --partial "already"
}

@test "bash: _claude_ensure_symlink backs up regular file collision" {
    mkdir -p "$HOME/src" "$HOME/tgt-dir"
    touch "$HOME/src/file.txt"
    echo "old" > "$HOME/tgt-dir/link"
    run_in_bash "_claude_ensure_symlink '$HOME/src/file.txt' '$HOME/tgt-dir/link'"
    assert_success
    [ -L "$HOME/tgt-dir/link" ]
    # Backup uses claude/setup.sh:100 legacy convention: <name>-YYYYMMDDHHMMSS-original
    ls "$HOME/tgt-dir/" | grep -qE "link-[0-9]{14}-original"
}

# ---------- Task 5: account setup ----------

@test "bash: _claude_account_setup_one creates symlinks (skips bind mount)" {
    # bind mount needs sudo; skip via env var
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    mkdir -p "$HOME/.claude-shared/plugins"

    run_in_bash "CLAUDE_SKIP_BIND_MOUNT=1 _claude_account_setup_one personal '$HOME/.claude-personal'"
    assert_success

    [ -L "$HOME/.claude-personal/settings.json" ]
    [ -L "$HOME/.claude-personal/statusline-command.sh" ]
    [ -L "$HOME/.claude-personal/plugins" ]
    [ -L "$HOME/.claude-personal/projects/GLOBAL/memory" ]
}

@test "bash: claude_accounts_init creates only ENABLED account dirs" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"

    run_in_bash 'CLAUDE_ENABLED_ACCOUNTS="work" CLAUDE_SKIP_BIND_MOUNT=1 claude_accounts_init'
    assert_success

    [ ! -d "$HOME/.claude-personal" ]
    [ -d "$HOME/.claude-work" ]
    [ -d "$HOME/.claude" ]
    [ -d "$HOME/.claude-shared/plugins" ]
}

@test "bash: claude_accounts_init refuses if ~/.claude/ has unmigrated data" {
    # Use a real user-data artifact (.credentials.json), not a random file.
    # The guard intentionally ignores empty bind-mount leftovers like skills/.
    mkdir -p "$HOME/.claude"
    echo '{"fake":"creds"}' > "$HOME/.claude/.credentials.json"

    run_in_bash 'CLAUDE_SKIP_BIND_MOUNT=1 claude_accounts_init'
    assert_failure
    assert_output --partial "claude-accounts migrate"
}

@test "bash: claude_accounts_init tolerates empty skills/docs leftovers" {
    # Real Home-PC scenario: user unmounted bind mounts, leaving empty dirs.
    # Guard must NOT false-positive on these.
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    mkdir -p "$HOME/.claude/skills" "$HOME/.claude/docs"

    run_in_bash 'CLAUDE_SKIP_BIND_MOUNT=1 claude_accounts_init'
    assert_success
    [ -d "$HOME/.claude-personal" ]
}

@test "bash: claude_accounts_init is idempotent (second run skips)" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"

    run_in_bash 'CLAUDE_SKIP_BIND_MOUNT=1 claude_accounts_init'
    run_in_bash 'CLAUDE_SKIP_BIND_MOUNT=1 claude_accounts_init'
    assert_success
    assert_output --partial "already"
}

# ---------- Task 6: status ----------

@test "bash: claude_accounts_status shows enabled accounts" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    run_in_bash 'CLAUDE_SKIP_BIND_MOUNT=1 claude_accounts_init && claude_accounts_status'
    assert_success
    assert_output --partial "Default: personal"
    assert_output --partial "Account: personal"
    assert_output --partial "Account: work"
}

@test "bash: claude_accounts_status reports NOT logged in when no .credentials.json" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    run_in_bash 'CLAUDE_SKIP_BIND_MOUNT=1 claude_accounts_init && claude_accounts_status'
    assert_output --partial "NOT logged in"
}

@test "bash: claude_accounts_status hides disabled accounts (Internal-PC)" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    run_in_bash 'CLAUDE_ENABLED_ACCOUNTS="work" CLAUDE_DEFAULT_ACCOUNT=work CLAUDE_SKIP_BIND_MOUNT=1 claude_accounts_init && CLAUDE_ENABLED_ACCOUNTS="work" CLAUDE_DEFAULT_ACCOUNT=work claude_accounts_status'
    assert_success
    refute_output --partial "Account: personal"
    assert_output --partial "Account: work"
}
