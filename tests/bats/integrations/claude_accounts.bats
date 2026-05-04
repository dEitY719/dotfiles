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

# ---------- Issue #294: .claude.json preservation + recovery ----------

@test "bash: claude_accounts_migrate preserves .claude.json content (issue #294)" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    mkdir -p "$HOME/.claude/projects"
    # Realistic .claude.json with the fields users care about preserving.
    cat > "$HOME/.claude/.claude.json" <<'JSON'
{
  "firstStartTime": "2026-01-01T00:00:00Z",
  "oauthAccount": {"emailAddress": "test@example.com"},
  "opusProMigrationComplete": true,
  "sonnet1m45MigrationComplete": true,
  "migrationVersion": 5
}
JSON
    pre_size=$(wc -c < "$HOME/.claude/.claude.json")

    run_in_bash 'export CLAUDE_SKIP_BIND_MOUNT=1; printf "y\n" | claude_accounts_migrate'
    assert_success

    [ -f "$HOME/.claude-personal/.claude.json" ]
    post_size=$(wc -c < "$HOME/.claude-personal/.claude.json")
    [ "$pre_size" = "$post_size" ]
    grep -q "oauthAccount" "$HOME/.claude-personal/.claude.json"
    grep -q "migrationVersion" "$HOME/.claude-personal/.claude.json"
}

@test "bash: claude_accounts_migrate logs pre/post .claude.json size (issue #294)" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    mkdir -p "$HOME/.claude/projects"
    printf '{"firstStartTime":"x","oauthAccount":{"e":"a@b"},"migrationVersion":5}' \
        > "$HOME/.claude/.claude.json"

    run_in_bash 'export CLAUDE_SKIP_BIND_MOUNT=1; printf "y\n" | claude_accounts_migrate'
    assert_success
    assert_output --partial "Pre-migrate"
    assert_output --partial "Post-migrate"
}

@test "bash: claude_accounts_migrate creates sealed snapshot for recovery (issue #294)" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    mkdir -p "$HOME/.claude/projects"
    printf '{"firstStartTime":"x","oauthAccount":{"e":"a@b"},"migrationVersion":5}' \
        > "$HOME/.claude/.claude.json"

    run_in_bash 'export CLAUDE_SKIP_BIND_MOUNT=1; printf "y\n" | claude_accounts_migrate'
    assert_success

    [ -f "$HOME/.claude-personal/.claude.json.preserved-by-migrate" ]
    grep -q "oauthAccount" "$HOME/.claude-personal/.claude.json.preserved-by-migrate"
}

@test "bash: claude_accounts_migrate warns when pre-mv .claude.json is tiny (issue #294)" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    mkdir -p "$HOME/.claude/projects"
    # Already in first-start placeholder state before migrate runs.
    printf '{"firstStartTime":"x"}' > "$HOME/.claude/.claude.json"

    run_in_bash 'export CLAUDE_SKIP_BIND_MOUNT=1; printf "y\n" | claude_accounts_migrate'
    assert_success
    assert_output --partial "suspiciously small"
}

@test "bash: claude_yolo restores reset .claude.json from snapshot (issue #294)" {
    _setup_claude_mock
    mkdir -p "$HOME/.claude-personal"
    # Snapshot has the real content.
    printf '{"firstStartTime":"x","oauthAccount":{"e":"a@b"},"migrationVersion":5}' \
        > "$HOME/.claude-personal/.claude.json.preserved-by-migrate"
    # Live file has been reset to first-start placeholder (50B-ish).
    printf '{"firstStartTime":"y"}' > "$HOME/.claude-personal/.claude.json"

    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; CLAUDE_YOLO_STAY=1 claude_yolo"
    assert_success
    assert_output --partial "Restored"
    grep -q "oauthAccount" "$HOME/.claude-personal/.claude.json"
    grep -q "migrationVersion" "$HOME/.claude-personal/.claude.json"
}

@test "bash: claude_yolo does NOT restore healthy .claude.json (issue #294)" {
    _setup_claude_mock
    mkdir -p "$HOME/.claude-personal"
    # Live file is healthy: > 500B AND has oauth marker.
    {
        printf '{"firstStartTime":"x","oauthAccount":{"e":"live@b"},"pad":"'
        # 600 chars of padding to push size > 500B
        printf 'x%.0s' $(seq 1 600)
        printf '"}'
    } > "$HOME/.claude-personal/.claude.json"
    # Snapshot exists with DIFFERENT content; must not be used.
    printf '{"firstStartTime":"y","oauthAccount":{"e":"snapshot@b"},"migrationVersion":5}' \
        > "$HOME/.claude-personal/.claude.json.preserved-by-migrate"

    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; CLAUDE_YOLO_STAY=1 claude_yolo"
    assert_success
    refute_output --partial "Restored"
    grep -q "live@b" "$HOME/.claude-personal/.claude.json"
}

@test "bash: claude_yolo does NOT restore when no snapshot (fresh setup, issue #294)" {
    _setup_claude_mock
    mkdir -p "$HOME/.claude-personal"
    # First-start placeholder, but no migrate snapshot — fresh PC.
    printf '{"firstStartTime":"x"}' > "$HOME/.claude-personal/.claude.json"

    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; CLAUDE_YOLO_STAY=1 claude_yolo"
    assert_success
    refute_output --partial "Restored"
    # Live file untouched.
    grep -q "firstStartTime" "$HOME/.claude-personal/.claude.json"
}

@test "bash: claude_yolo does NOT restore when small file has oauth (issue #294)" {
    _setup_claude_mock
    mkdir -p "$HOME/.claude-personal"
    # Small (< 500B) BUT contains oauthAccount → not the reset state.
    printf '{"oauthAccount":{"e":"a@b"}}' > "$HOME/.claude-personal/.claude.json"
    printf '{"oauthAccount":{"e":"OLD@b"},"migrationVersion":1}' \
        > "$HOME/.claude-personal/.claude.json.preserved-by-migrate"

    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; CLAUDE_YOLO_STAY=1 claude_yolo"
    assert_success
    refute_output --partial "Restored"
    grep -q '"a@b"' "$HOME/.claude-personal/.claude.json"
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

# Stage an isolated DOTFILES_ROOT under $TEST_TEMP_HOME so setup.sh's writes
# (settings.json migration, *.pre-statusline-fix-* backup files) land in a
# throwaway tree instead of the version-controlled checkout (issue #303).
_setup_sh_prereqs() {
    setup_isolated_dotfiles_root
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

# ---------- Regression: issue #296 ----------
#
# After PR #292 (multi-account migration), `~/.claude/` becomes a guard
# directory and `~/.claude/statusline-command.sh` no longer exists. The
# template previously hardcoded that legacy path, causing statusline to
# silently fail under `CLAUDE_CONFIG_DIR=~/.claude-personal`.
# Fix: settings.template.json points at the dotfiles SSOT path, which is
# reachable from every account's CONFIG_DIR via $HOME.

@test "regression #296: statusLine.command in account settings.json resolves to executable" {
    _setup_sh_prereqs

    # Make $HOME/dotfiles resolve to the worktree so the template's
    # ${HOME}/dotfiles/... path is reachable inside the isolated $HOME.
    ln -s "${DOTFILES_ROOT}" "$HOME/dotfiles"

    run_in_bash "CLAUDE_SKIP_BIND_MOUNT=1 CLAUDE_SKIP_SUDOERS=1 bash '${DOTFILES_ROOT}/claude/setup.sh'"
    assert_success

    for cdir in "$HOME/.claude-personal" "$HOME/.claude-work"; do
        cmd=$(jq -r '.statusLine.command' < "$cdir/settings.json")

        # The legacy ~/.claude/ path is the regression we are guarding against.
        [ "$cmd" != '${HOME}/.claude/statusline-command.sh' ]

        # Expand ${HOME} the same way Claude Code does and verify exec bit.
        expanded=${cmd//\$\{HOME\}/$HOME}
        [ -x "$expanded" ]
    done
}

# ---------- Issue #300, item A: setup.sh auto-migrates legacy statusLine ----------
#
# These tests overwrite settings.json with a fixture that triggers (or
# avoids triggering) the item-A migration. Since _setup_sh_prereqs now
# stages an isolated DOTFILES_ROOT under $TEST_TEMP_HOME (issue #303),
# fixture writes and any *.pre-statusline-fix-* backup files setup.sh
# produces are torn down with $TEST_TEMP_HOME — no save/restore needed.
_use_settings_fixture() {
    cat > "${DOTFILES_ROOT}/claude/settings.json" <<JSON
{
  "statusLine": {
    "type": "command",
    "command": "$1"
  }
}
JSON
}

@test "issue #300-A: setup.sh rewrites legacy statusLine.command literal" {
    _setup_sh_prereqs
    _use_settings_fixture '${HOME}/.claude/statusline-command.sh'
    ln -s "${DOTFILES_ROOT}" "$HOME/dotfiles"

    run_in_bash "CLAUDE_SKIP_BIND_MOUNT=1 CLAUDE_SKIP_SUDOERS=1 bash '${DOTFILES_ROOT}/claude/setup.sh'"
    assert_success
    assert_output --partial "자동 마이그레이션 완료"

    cmd=$(jq -r '.statusLine.command' "${DOTFILES_ROOT}/claude/settings.json")
    [ "$cmd" = '${HOME}/dotfiles/claude/statusline-command.sh' ]
    # Backup file present alongside the source.
    ls "${DOTFILES_ROOT}/claude/" | grep -qE 'settings\.json\.pre-statusline-fix-[0-9]{14}'
}

@test "issue #300-A: setup.sh leaves already-migrated statusLine.command alone" {
    _setup_sh_prereqs
    _use_settings_fixture '${HOME}/dotfiles/claude/statusline-command.sh'
    ln -s "${DOTFILES_ROOT}" "$HOME/dotfiles"

    run_in_bash "CLAUDE_SKIP_BIND_MOUNT=1 CLAUDE_SKIP_SUDOERS=1 bash '${DOTFILES_ROOT}/claude/setup.sh'"
    assert_success
    refute_output --partial "자동 마이그레이션 완료"

    # No backup spawned for a no-op run.
    ! ls "${DOTFILES_ROOT}/claude/" | grep -qE 'settings\.json\.pre-statusline-fix-'
}

@test "issue #300-A: setup.sh preserves user-customised statusLine.command" {
    _setup_sh_prereqs
    _use_settings_fixture "$HOME/bin/my-custom-statusline.sh"
    ln -s "${DOTFILES_ROOT}" "$HOME/dotfiles"

    run_in_bash "CLAUDE_SKIP_BIND_MOUNT=1 CLAUDE_SKIP_SUDOERS=1 bash '${DOTFILES_ROOT}/claude/setup.sh'"
    assert_success
    refute_output --partial "자동 마이그레이션 완료"

    cmd=$(jq -r '.statusLine.command' "${DOTFILES_ROOT}/claude/settings.json")
    [ "$cmd" = "$HOME/bin/my-custom-statusline.sh" ]
}

# ---------- Issue #300, item C: claude_accounts_status shows oauth binding ----------

@test "issue #300-C: claude_accounts_status prints email/org from .claude.json" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    mkdir -p "$HOME/.claude-personal"
    echo "creds" > "$HOME/.claude-personal/.credentials.json"
    cat > "$HOME/.claude-personal/.claude.json" <<'JSON'
{
  "oauthAccount": {
    "emailAddress": "alice@example.com",
    "organizationName": "Example Inc",
    "organizationType": "claude_team"
  }
}
JSON

    run_in_bash 'CLAUDE_SKIP_BIND_MOUNT=1 CLAUDE_ENABLED_ACCOUNTS=personal claude_accounts_init >/dev/null && CLAUDE_ENABLED_ACCOUNTS=personal claude_accounts_status'
    assert_success
    assert_output --partial "Email: alice@example.com"
    assert_output --partial "Org:   Example Inc (claude_team)"
}

@test "issue #300-C: claude_accounts_status omits oauth lines when .claude.json missing" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    mkdir -p "$HOME/.claude-personal"
    echo "creds" > "$HOME/.claude-personal/.credentials.json"
    # No .claude.json — first run / fresh login.

    run_in_bash 'CLAUDE_SKIP_BIND_MOUNT=1 CLAUDE_ENABLED_ACCOUNTS=personal claude_accounts_init >/dev/null && CLAUDE_ENABLED_ACCOUNTS=personal claude_accounts_status'
    assert_success
    refute_output --partial "Email:"
    refute_output --partial "Org:"
}

@test "issue #300-C: claude_accounts_status flags expected/actual mismatch with marker" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    mkdir -p "$HOME/.claude-work"
    echo "creds" > "$HOME/.claude-work/.credentials.json"
    cat > "$HOME/.claude-work/.claude.json" <<'JSON'
{"oauthAccount":{"emailAddress":"personal@gmail.com","organizationName":"Personal"}}
JSON

    run_in_bash 'CLAUDE_SKIP_BIND_MOUNT=1 CLAUDE_ENABLED_ACCOUNTS=work CLAUDE_DEFAULT_ACCOUNT=work claude_accounts_init >/dev/null && CLAUDE_ENABLED_ACCOUNTS=work CLAUDE_DEFAULT_ACCOUNT=work CLAUDE_ACCOUNT_EMAIL_work=work@corp.com claude_accounts_status'
    assert_success
    assert_output --partial "Email: personal@gmail.com"
    assert_output --partial "expected work@corp.com"
}

# ---------- Issue #300, item B: claude_yolo expected ↔ actual email check ----------

@test "issue #300-B: claude_yolo silent when CLAUDE_ACCOUNT_EMAIL matches actual" {
    _setup_claude_mock
    mkdir -p "$HOME/.claude-personal"
    printf '{"oauthAccount":{"emailAddress":"alice@example.com"}}' \
        > "$HOME/.claude-personal/.claude.json"

    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; CLAUDE_YOLO_STAY=1 CLAUDE_ACCOUNT_EMAIL_personal=alice@example.com claude_yolo"
    assert_success
    refute_output --partial "Account mismatch"
}

@test "issue #300-B: claude_yolo warns on CLAUDE_ACCOUNT_EMAIL mismatch" {
    _setup_claude_mock
    mkdir -p "$HOME/.claude-work"
    printf '{"oauthAccount":{"emailAddress":"personal@gmail.com"}}' \
        > "$HOME/.claude-work/.claude.json"

    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; CLAUDE_YOLO_STAY=1 CLAUDE_ACCOUNT_EMAIL_work=work@corp.com claude_yolo --user work"
    assert_success
    assert_output --partial "Account mismatch on 'work'"
    assert_output --partial "expected: work@corp.com"
    assert_output --partial "actual:   personal@gmail.com"
    assert_output --partial "복구:"
}

@test "issue #300-B: claude_yolo silent when no CLAUDE_ACCOUNT_EMAIL mapping defined" {
    _setup_claude_mock
    mkdir -p "$HOME/.claude-work"
    printf '{"oauthAccount":{"emailAddress":"anyone@anywhere.com"}}' \
        > "$HOME/.claude-work/.claude.json"

    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; CLAUDE_YOLO_STAY=1 claude_yolo --user work"
    assert_success
    refute_output --partial "Account mismatch"
}
