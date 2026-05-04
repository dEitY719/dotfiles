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

# ---------- Task 7: migrate ----------

@test "bash: claude_accounts_migrate moves ~/.claude → ~/.claude-personal" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    mkdir -p "$HOME/.claude/projects" "$HOME/.claude/sessions"
    echo "creds" > "$HOME/.claude/.credentials.json"
    echo "history" > "$HOME/.claude/history.jsonl"

    # printf instead of `yes` because dotfiles bootstrap enables pipefail —
    # `yes` gets SIGPIPE (141) when the function returns, masking the
    # function's true exit status.
    run_in_bash 'export CLAUDE_SKIP_BIND_MOUNT=1; printf "y\n" | claude_accounts_migrate'
    assert_success

    [ -d "$HOME/.claude-personal" ]
    [ -f "$HOME/.claude-personal/.credentials.json" ]
    [ -f "$HOME/.claude-personal/history.jsonl" ]
    [ -d "$HOME/.claude-personal/projects" ]
}

@test "bash: claude_accounts_migrate promotes ~/.claude/plugins → ~/.claude-shared/" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    mkdir -p "$HOME/.claude/plugins/marketplaces"
    echo "plugin" > "$HOME/.claude/plugins/marketplaces/test"

    run_in_bash 'export CLAUDE_SKIP_BIND_MOUNT=1; printf "y\n" | claude_accounts_migrate'
    assert_success

    [ -d "$HOME/.claude-shared/plugins/marketplaces" ]
    [ -f "$HOME/.claude-shared/plugins/marketplaces/test" ]
    [ -L "$HOME/.claude-personal/plugins" ]
}

@test "bash: claude_accounts_migrate is idempotent (already migrated)" {
    mkdir -p "$HOME/.claude-personal"
    run_in_bash 'claude_accounts_migrate'
    assert_success
    assert_output --partial "Already migrated"
}

@test "bash: claude_accounts_migrate aborts on user 'n'" {
    mkdir -p "$HOME/.claude/projects"
    run_in_bash 'export CLAUDE_SKIP_BIND_MOUNT=1; printf "n\n" | claude_accounts_migrate'
    assert_failure
    [ -d "$HOME/.claude" ]
    [ ! -d "$HOME/.claude-personal" ]
}

# ---------- Task 8: claude_accounts CLI ----------
#
# Aliases need `shopt -s expand_aliases` AND a separate parsing unit
# (bash parses the whole `-c` string in one go before aliases register).
# Use `eval` to force re-parsing — same pattern as
# tests/integration/test_help_compact_policy.py.

@test "bash: claude-accounts list shows enabled accounts" {
    run_in_bash 'shopt -s expand_aliases; eval "claude-accounts list" | tr "\n" " "'
    assert_success
    assert_output "personal work "
}

@test "bash: claude-accounts (no arg) defaults to status" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    run_in_bash 'shopt -s expand_aliases; CLAUDE_SKIP_BIND_MOUNT=1 claude_accounts_init && eval "claude-accounts"'
    assert_success
    assert_output --partial "Default: personal"
}

@test "bash: claude-accounts unknown subcommand fails" {
    run_in_bash 'shopt -s expand_aliases; eval "claude-accounts foo"'
    assert_failure
    assert_output --partial "Unknown"
}

@test "bash: claude-accounts -h shows help" {
    run_in_bash 'shopt -s expand_aliases; eval "claude-accounts -h"'
    assert_success
    assert_output --partial "status"
    assert_output --partial "setup"
    assert_output --partial "migrate"
}

# ---------- Task 9: claude_yolo dispatcher ----------

# Mock `claude` binary — instead of real call, echo what would have been invoked.
_setup_claude_mock() {
    mkdir -p "$HOME/bin"
    cat > "$HOME/bin/claude" <<'MOCK'
#!/bin/sh
echo "MOCK_CLAUDE: CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR:-unset} ARGS=$*"
MOCK
    chmod +x "$HOME/bin/claude"
}

@test "bash: claude_yolo defaults to personal account" {
    _setup_claude_mock
    mkdir -p "$HOME/.claude-personal"
    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; CLAUDE_YOLO_STAY=1 claude_yolo"
    assert_success
    assert_output --partial "CLAUDE_CONFIG_DIR=$HOME/.claude-personal"
}

@test "bash: claude_yolo --user work routes to work" {
    _setup_claude_mock
    mkdir -p "$HOME/.claude-work"
    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; CLAUDE_YOLO_STAY=1 claude_yolo --user work"
    assert_success
    assert_output --partial "CLAUDE_CONFIG_DIR=$HOME/.claude-work"
}

@test "bash: claude_yolo --user=work syntax also works" {
    _setup_claude_mock
    mkdir -p "$HOME/.claude-work"
    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; CLAUDE_YOLO_STAY=1 claude_yolo --user=work"
    assert_success
    assert_output --partial "CLAUDE_CONFIG_DIR=$HOME/.claude-work"
}

@test "bash: claude_yolo passes extra args through to claude" {
    _setup_claude_mock
    mkdir -p "$HOME/.claude-work"
    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; CLAUDE_YOLO_STAY=1 claude_yolo --user work --resume foo"
    assert_success
    assert_output --partial "ARGS=--dangerously-skip-permissions --resume foo"
}

@test "bash: claude_yolo --user xyz fails with available list" {
    _setup_claude_mock
    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; CLAUDE_YOLO_STAY=1 claude_yolo --user xyz"
    assert_failure
    assert_output --partial "Unknown account: xyz"
    assert_output --partial "Available"
}

@test "bash: claude_yolo errors when account dir missing" {
    _setup_claude_mock
    rm -rf "$HOME/.claude-work"
    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; CLAUDE_YOLO_STAY=1 claude_yolo --user work"
    assert_failure
    assert_output --partial "Account directory missing"
    assert_output --partial "claude-accounts setup"
}

@test "bash: claude_yolo respects CLAUDE_DEFAULT_ACCOUNT=work (Internal-PC)" {
    _setup_claude_mock
    mkdir -p "$HOME/.claude-work"
    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; CLAUDE_DEFAULT_ACCOUNT=work CLAUDE_YOLO_STAY=1 claude_yolo"
    assert_success
    assert_output --partial "CLAUDE_CONFIG_DIR=$HOME/.claude-work"
}

# ---------- Task 10: alias auto-derivation ----------

@test "bash: claude-yolo-personal alias exists (default ENABLED)" {
    run_in_bash 'shopt -s expand_aliases; alias claude-yolo-personal'
    assert_success
    assert_output --partial "claude_yolo --user personal"
}

@test "bash: claude-yolo-work alias exists (default ENABLED)" {
    run_in_bash 'shopt -s expand_aliases; alias claude-yolo-work'
    assert_success
    assert_output --partial "claude_yolo --user work"
}

@test "bash: _claude_yolo_register_aliases iterates ENABLED only" {
    # Verify the function reads from --list (not hardcoded). Clear all aliases
    # registered at file load, override ENABLED, re-run, then check that only
    # the work alias was re-registered.
    run_in_bash 'shopt -s expand_aliases; CLAUDE_ENABLED_ACCOUNTS="work" unalias -a 2>/dev/null; CLAUDE_ENABLED_ACCOUNTS="work" _claude_yolo_register_aliases; alias | grep "claude-yolo-" || echo NONE'
    assert_success
    assert_output --partial "claude-yolo-work"
    refute_output --partial "claude-yolo-personal"
}

@test "bash: claude-yolo-work alias expansion targets work account" {
    run_in_bash 'shopt -s expand_aliases; alias claude-yolo-work'
    assert_output --partial "--user work"
}

# ---------- Task 11: claude/setup.sh integration ----------

# settings.json is gitignored (PC-specific) — generate from template if missing.
# Same applies to other source dirs that may be empty in a fresh checkout.
_setup_sh_prereqs() {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    mkdir -p "${DOTFILES_ROOT}/claude/global-memory"
    if [ ! -f "${DOTFILES_ROOT}/claude/settings.json" ]; then
        if [ -f "${DOTFILES_ROOT}/claude/settings.template.json" ]; then
            cp "${DOTFILES_ROOT}/claude/settings.template.json" \
               "${DOTFILES_ROOT}/claude/settings.json"
        else
            echo '{}' > "${DOTFILES_ROOT}/claude/settings.json"
        fi
    fi
}

@test "bash: claude/setup.sh creates ~/.claude-personal/ structure" {
    _setup_sh_prereqs

    run_in_bash "CLAUDE_SKIP_BIND_MOUNT=1 CLAUDE_SKIP_SUDOERS=1 bash '${DOTFILES_ROOT}/claude/setup.sh'"
    assert_success

    [ -L "$HOME/.claude-personal/settings.json" ]
    [ -L "$HOME/.claude-personal/projects/GLOBAL/memory" ]
}

@test "bash: claude/setup.sh respects CLAUDE_ENABLED_ACCOUNTS=work (Internal-PC)" {
    _setup_sh_prereqs

    run_in_bash "CLAUDE_ENABLED_ACCOUNTS=work CLAUDE_DEFAULT_ACCOUNT=work CLAUDE_SKIP_BIND_MOUNT=1 CLAUDE_SKIP_SUDOERS=1 bash '${DOTFILES_ROOT}/claude/setup.sh'"
    assert_success

    [ ! -d "$HOME/.claude-personal" ]
    [ -d "$HOME/.claude-work" ]
    [ -L "$HOME/.claude-work/settings.json" ]
}

@test "bash: claude/setup.sh is idempotent (second run)" {
    _setup_sh_prereqs

    run_in_bash "CLAUDE_SKIP_BIND_MOUNT=1 CLAUDE_SKIP_SUDOERS=1 bash '${DOTFILES_ROOT}/claude/setup.sh'"
    run_in_bash "CLAUDE_SKIP_BIND_MOUNT=1 CLAUDE_SKIP_SUDOERS=1 bash '${DOTFILES_ROOT}/claude/setup.sh'"
    assert_success
    assert_output --partial "already"
}
