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

@test "bash: CLAUDE_ENABLED_ACCOUNTS defaults to 'personal work work1' (external mode)" {
    run_in_bash 'echo "$CLAUDE_ENABLED_ACCOUNTS"'
    assert_success
    assert_output "personal work work1"
}

@test "zsh: CLAUDE_DEFAULT_ACCOUNT defaults to personal" {
    run_in_zsh 'echo "$CLAUDE_DEFAULT_ACCOUNT"'
    assert_success
    assert_output "personal"
}

@test "zsh: CLAUDE_ENABLED_ACCOUNTS defaults to 'personal work work1' (external mode)" {
    run_in_zsh 'echo "$CLAUDE_ENABLED_ACCOUNTS"'
    assert_success
    assert_output "personal work work1"
}

@test "bash: internal setup-mode → CLAUDE_ENABLED_ACCOUNTS='work'" {
    echo "internal" > "$HOME/.dotfiles-setup-mode"
    run_in_bash 'echo "$CLAUDE_DEFAULT_ACCOUNT|$CLAUDE_ENABLED_ACCOUNTS"'
    assert_success
    assert_output "work|work"
}

@test "bash: stale CLAUDE_ENABLED_ACCOUNTS is overwritten by setup-mode default" {
    # Regression for the d36ac3a stale-env trap: ${VAR:-default} preserved
    # a previously-exported value across shell re-init. Setup-mode must win.
    run_in_bash 'export CLAUDE_ENABLED_ACCOUNTS="stale leftover"; source "${DOTFILES_ROOT}/shell-common/env/claude.sh"; echo "$CLAUDE_ENABLED_ACCOUNTS"'
    assert_success
    assert_output "personal work work1"
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

@test "bash: resolve --list-all returns same as --list (deprecated alias, issue #568)" {
    run_in_bash '_claude_resolve_account --list-all | tr "\n" " "'
    assert_success
    assert_output "personal work work1 "
}

@test "bash: resolve --list returns ENABLED accounts only (default)" {
    run_in_bash '_claude_resolve_account --list | tr "\n" " "'
    assert_success
    assert_output "personal work work1 "
}

@test "bash: resolve --list filters by CLAUDE_ENABLED_ACCOUNTS=work" {
    run_in_bash 'CLAUDE_ENABLED_ACCOUNTS="work" _claude_resolve_account --list | tr "\n" " "'
    assert_success
    assert_output "work "
}

@test "zsh: resolve --list works under zsh (POSIX parity smoke test)" {
    run_in_zsh '_claude_resolve_account --list | tr "\n" " "'
    assert_success
    assert_output "personal work work1 "
}

# ---------- issue #568: convention-based dispatcher ----------

@test "bash: resolve work1 returns ~/.claude-work1 when ENABLED contains work1" {
    run_in_bash 'CLAUDE_ENABLED_ACCOUNTS="personal work work1" _claude_resolve_account work1'
    assert_success
    assert_output "$HOME/.claude-work1"
}

@test "bash: resolve work1 fails when ENABLED omits it" {
    # Issue #568 added work1 to the default ENABLED list, so a bare
    # `_claude_resolve_account work1` succeeds. Override ENABLED to
    # restore the original test premise: dispatcher must reject any
    # name not present in the active list.
    run_in_bash 'CLAUDE_ENABLED_ACCOUNTS="personal work" _claude_resolve_account work1'
    assert_failure
    refute_output --partial "/"
}

@test "bash: resolve --list includes work1 when ENABLED contains work1" {
    run_in_bash 'CLAUDE_ENABLED_ACCOUNTS="personal work work1" _claude_resolve_account --list | tr "\n" " "'
    assert_success
    assert_output "personal work work1 "
}

@test "bash: resolve rejects uppercase name (Work)" {
    run_in_bash 'CLAUDE_ENABLED_ACCOUNTS="Work" _claude_resolve_account Work'
    assert_failure
    refute_output --partial "/"
}

@test "bash: resolve rejects digit-leading name (1work)" {
    run_in_bash 'CLAUDE_ENABLED_ACCOUNTS="1work" _claude_resolve_account 1work'
    assert_failure
    refute_output --partial "/"
}

@test "bash: resolve rejects special-char name (foo\$bar)" {
    run_in_bash 'CLAUDE_ENABLED_ACCOUNTS="foo\$bar" _claude_resolve_account "foo\$bar"'
    assert_failure
    refute_output --partial "/"
}

@test "bash: resolve --list silently skips invalid tokens in ENABLED" {
    run_in_bash 'CLAUDE_ENABLED_ACCOUNTS="personal Work work" _claude_resolve_account --list | tr "\n" " "'
    assert_success
    assert_output "personal work "
}

@test "zsh: resolve work1 routes under zsh (POSIX parity)" {
    run_in_zsh 'CLAUDE_ENABLED_ACCOUNTS="personal work work1" _claude_resolve_account work1'
    assert_success
    assert_output "$HOME/.claude-work1"
}

@test "bash: resolve --list does NOT infinite-recurse on flag-shaped ENABLED token (PR #569 review)" {
    # Regression: an earlier draft of the --list branch called
    # _claude_resolve_account recursively, which would loop forever if
    # CLAUDE_ENABLED_ACCOUNTS happened to contain --list / --list-all.
    # The inline-validation rewrite must drop such tokens silently.
    run_in_bash 'CLAUDE_ENABLED_ACCOUNTS="personal --list work" _claude_resolve_account --list | tr "\n" " "'
    assert_success
    assert_output "personal work "
}

@test "bash: resolve --list survives empty ENABLED under set -u (PR #569 review)" {
    # Regression for the ${VAR:-} hardening — calling --list without
    # CLAUDE_ENABLED_ACCOUNTS exported must not abort under set -u.
    run_in_bash 'unset CLAUDE_ENABLED_ACCOUNTS; set -u; _claude_resolve_account --list'
    assert_success
    assert_output ""
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

@test "bash: _claude_account_setup_one creates directory-level symlinks (issue #575 → #707)" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    mkdir -p "$HOME/.claude-shared/plugins"

    run_in_bash "_claude_account_setup_one personal '$HOME/.claude-personal'"
    assert_success

    # settings.json is a real-file copy of the SSOT since #940 — a symlink
    # would let /model write through into the tracked dotfiles file (#924).
    [ -f "$HOME/.claude-personal/settings.json" ]
    [ ! -L "$HOME/.claude-personal/settings.json" ]
    cmp -s "${DOTFILES_ROOT}/claude/settings.json" "$HOME/.claude-personal/settings.json"
    [ -L "$HOME/.claude-personal/statusline-command.sh" ]
    [ -L "$HOME/.claude-personal/plugins" ]
    [ -L "$HOME/.claude-personal/projects/GLOBAL/memory" ]
    # docs/ is still a single directory-level symlink (#575). skills/ was
    # promoted to a real directory of per-entry symlinks by #707, F-8 so
    # a private overlay can be layered into the same target dir.
    [ -d "$HOME/.claude-personal/skills" ]
    [ ! -L "$HOME/.claude-personal/skills" ]
    [ -L "$HOME/.claude-personal/docs" ]
    [ "$(readlink "$HOME/.claude-personal/docs")" = "${DOTFILES_ROOT}/claude/docs" ]
    # settings.local.json is intentionally a per-PC hand-created regular
    # file (#584) — never a dotfiles symlink.
    [ ! -L "$HOME/.claude-personal/settings.local.json" ]
}

@test "bash: _claude_ensure_settings_copy converts a legacy settings.json symlink to a real file (#940)" {
    mkdir -p "$HOME/.claude-personal"
    ln -s "${DOTFILES_ROOT}/claude/settings.json" "$HOME/.claude-personal/settings.json"

    run_in_bash "_claude_ensure_settings_copy '${DOTFILES_ROOT}/claude/settings.json' '$HOME/.claude-personal/settings.json'"
    assert_success

    [ -f "$HOME/.claude-personal/settings.json" ]
    [ ! -L "$HOME/.claude-personal/settings.json" ]
    cmp -s "${DOTFILES_ROOT}/claude/settings.json" "$HOME/.claude-personal/settings.json"
}

@test "bash: _claude_ensure_settings_copy migrates a /model-written model key into settings.local.json (#940)" {
    mkdir -p "$HOME/.claude-personal"
    # Simulate the post-/model state: real file = SSOT + personal model key.
    jq '.model = "opus"' "${DOTFILES_ROOT}/claude/settings.json" \
        > "$HOME/.claude-personal/settings.json"

    run_in_bash "_claude_ensure_settings_copy '${DOTFILES_ROOT}/claude/settings.json' '$HOME/.claude-personal/settings.json'"
    assert_success

    # SSOT wins in settings.json; the model preference survives in local.
    cmp -s "${DOTFILES_ROOT}/claude/settings.json" "$HOME/.claude-personal/settings.json"
    [ "$(jq -r '.model' "$HOME/.claude-personal/settings.local.json")" = "opus" ]
}

@test "bash: _claude_ensure_settings_copy removes a dangling settings.local.json symlink (#940)" {
    mkdir -p "$HOME/.claude-personal"
    ln -s "/tmp/torn-down-worktree-DOES-NOT-EXIST/claude/settings.local.json" \
        "$HOME/.claude-personal/settings.local.json"

    run_in_bash "_claude_ensure_settings_copy '${DOTFILES_ROOT}/claude/settings.json' '$HOME/.claude-personal/settings.json'"
    assert_success

    [ ! -L "$HOME/.claude-personal/settings.local.json" ]
    [ ! -e "$HOME/.claude-personal/settings.local.json" ]
}

@test "bash: _claude_ensure_settings_copy is idempotent (second run reports up to date)" {
    mkdir -p "$HOME/.claude-personal"

    run_in_bash "
        _claude_ensure_settings_copy '${DOTFILES_ROOT}/claude/settings.json' '$HOME/.claude-personal/settings.json' >/dev/null 2>&1
        _claude_ensure_settings_copy '${DOTFILES_ROOT}/claude/settings.json' '$HOME/.claude-personal/settings.json'
    "
    assert_success
    assert_output --partial "up to date"
}

@test "bash: _claude_account_setup_one unmounts a legacy bind mount on skills (issue #575 migration)" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    mkdir -p "$HOME/.claude-shared/plugins"
    # Simulate a Home-PC that came up under the #287 bind-mount layout:
    # ~/.claude-personal/skills/ exists as a real (would-be-mounted) dir.
    mkdir -p "$HOME/.claude-personal/skills"

    fake_bin="$HOME/fake-bin"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/findmnt" <<SH
#!/usr/bin/env bash
[ "\$1" = "$HOME/.claude-personal/skills" ] && exit 0
exit 1
SH
    chmod +x "$fake_bin/findmnt"
    cat > "$fake_bin/sudo" <<'SH'
#!/usr/bin/env bash
if [ "$1" = "umount" ]; then
    printf '%s\n' "$2" >> "$HOME/fake-umount.log"
    rmdir -- "$2" 2>/dev/null || true
    exit 0
fi
exit 1
SH
    chmod +x "$fake_bin/sudo"

    run_in_bash "export PATH=\"$fake_bin:\$PATH\"; _claude_account_setup_one personal '$HOME/.claude-personal'"
    assert_success
    assert_output --partial "bind-mount detected at $HOME/.claude-personal/skills"
    # #707, F-8: post-unmount the slot is a real directory of per-entry
    # symlinks, not a single dir-symlink. The umount log still records
    # the legacy bind-mount path that was unmounted.
    [ -d "$HOME/.claude-personal/skills" ]
    [ ! -L "$HOME/.claude-personal/skills" ]
    grep -qF "$HOME/.claude-personal/skills" "$HOME/fake-umount.log"
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

@test "bash: claude_accounts_init treats ~/.claude-work1 as 'already migrated' when work1 is ENABLED (issue #568)" {
    # Convention-based refactor: the migration guard must iterate
    # CLAUDE_ENABLED_ACCOUNTS, not a hardcoded personal/work pair.
    # Otherwise adding work1 to ENABLED would re-trigger the migrate
    # prompt every shell startup.
    mkdir -p "$HOME/.claude" "$HOME/.claude-work1"
    echo '{"fake":"creds"}' > "$HOME/.claude/.credentials.json"

    run_in_bash 'CLAUDE_ENABLED_ACCOUNTS="personal work work1" CLAUDE_SKIP_BIND_MOUNT=1 claude_accounts_init'
    assert_success
    refute_output --partial "claude-accounts migrate"
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

    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; claude_yolo"
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

    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; claude_yolo"
    assert_success
    refute_output --partial "Restored"
    grep -q "live@b" "$HOME/.claude-personal/.claude.json"
}

@test "bash: claude_yolo does NOT restore when no snapshot (fresh setup, issue #294)" {
    _setup_claude_mock
    mkdir -p "$HOME/.claude-personal"
    # First-start placeholder, but no migrate snapshot — fresh PC.
    printf '{"firstStartTime":"x"}' > "$HOME/.claude-personal/.claude.json"

    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; claude_yolo"
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

    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; claude_yolo"
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
    assert_output "personal work work1 "
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
    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; claude_yolo"
    assert_success
    assert_output --partial "CLAUDE_CONFIG_DIR=$HOME/.claude-personal"
}

@test "bash: claude_yolo --user work routes to work" {
    _setup_claude_mock
    mkdir -p "$HOME/.claude-work"
    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; claude_yolo --user work"
    assert_success
    assert_output --partial "CLAUDE_CONFIG_DIR=$HOME/.claude-work"
}

@test "bash: claude_yolo --user=work syntax also works" {
    _setup_claude_mock
    mkdir -p "$HOME/.claude-work"
    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; claude_yolo --user=work"
    assert_success
    assert_output --partial "CLAUDE_CONFIG_DIR=$HOME/.claude-work"
}

@test "bash: claude_yolo passes extra args through to claude" {
    _setup_claude_mock
    mkdir -p "$HOME/.claude-work"
    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; claude_yolo --user work --resume foo"
    assert_success
    assert_output --partial "ARGS=--dangerously-skip-permissions --resume foo"
}

@test "bash: claude_yolo --user xyz fails with available list" {
    _setup_claude_mock
    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; claude_yolo --user xyz"
    assert_failure
    assert_output --partial "Unknown account: xyz"
    assert_output --partial "Available"
}

@test "bash: claude_yolo errors when account dir missing" {
    _setup_claude_mock
    rm -rf "$HOME/.claude-work"
    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; claude_yolo --user work"
    assert_failure
    assert_output --partial "Account directory missing"
    assert_output --partial "claude-accounts setup"
}

@test "bash: claude_yolo respects CLAUDE_DEFAULT_ACCOUNT=work (Internal-PC)" {
    _setup_claude_mock
    mkdir -p "$HOME/.claude-work"
    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; CLAUDE_DEFAULT_ACCOUNT=work claude_yolo"
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
# (settings.json migration) land in a throwaway tree instead of the
# version-controlled checkout (issue #303). Backup files now live under
# $HOME/.claude-backups (issue #554) — also throwaway since $HOME is isolated.
_setup_sh_prereqs() {
    setup_isolated_dotfiles_root
}

@test "bash: claude/setup.sh creates ~/.claude-personal/ structure" {
    _setup_sh_prereqs

    run_in_bash "CLAUDE_SKIP_BIND_MOUNT=1 CLAUDE_SKIP_SUDOERS=1 bash '${DOTFILES_ROOT}/claude/setup.sh'"
    assert_success

    # settings.json is a real-file copy since #940 — not a symlink.
    [ -f "$HOME/.claude-personal/settings.json" ]
    [ ! -L "$HOME/.claude-personal/settings.json" ]
    [ -L "$HOME/.claude-personal/projects/GLOBAL/memory" ]
}

@test "bash: claude/setup.sh respects Internal-PC mode via .dotfiles-setup-mode" {
    # Issue #571 (F-1) made Internal-PC mode key off the .dotfiles-setup-mode
    # SSOT (single source of truth, set by shell-common/setup.sh) instead of
    # an inline CLAUDE_ENABLED_ACCOUNTS env var — the latter is unconditionally
    # overwritten by shell-common/env/claude.sh (the d36ac3a stale-env fix).
    # Internal-PC now uses ~/.claude/ directly with no per-account dirs.
    _setup_sh_prereqs
    echo "internal" > "$HOME/.dotfiles-setup-mode"

    run_in_bash "CLAUDE_SKIP_BIND_MOUNT=1 CLAUDE_SKIP_SUDOERS=1 bash '${DOTFILES_ROOT}/claude/setup.sh'"
    assert_success

    [ ! -d "$HOME/.claude-personal" ]
    [ ! -d "$HOME/.claude-work" ]
    [ -d "$HOME/.claude" ]
    [ -L "$HOME/.claude/statusline-command.sh" ]
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
# fixture writes are torn down with $TEST_TEMP_HOME — no save/restore needed.
# Backup files since issue #554 land in $HOME/.claude-backups/, which is
# also under the isolated $TEST_TEMP_HOME.
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
    # Backup file lives in $HOME/.claude-backups, NOT in the dotfiles tree
    # (issue #554). Asserting both rules keeps a regression visible.
    ls "$HOME/.claude-backups/" | grep -qE 'settings\.json\.pre-statusline-fix-[0-9]{14}'
    ! ls "${DOTFILES_ROOT}/claude/" 2>/dev/null | grep -qE 'settings\.json\.pre-statusline-fix-'
}

@test "issue #300-A: setup.sh leaves already-migrated statusLine.command alone" {
    _setup_sh_prereqs
    _use_settings_fixture '${HOME}/dotfiles/claude/statusline-command.sh'
    ln -s "${DOTFILES_ROOT}" "$HOME/dotfiles"

    run_in_bash "CLAUDE_SKIP_BIND_MOUNT=1 CLAUDE_SKIP_SUDOERS=1 bash '${DOTFILES_ROOT}/claude/setup.sh'"
    assert_success
    refute_output --partial "자동 마이그레이션 완료"

    # No backup spawned for a no-op run — check both the legacy in-tree
    # location and the new $HOME/.claude-backups location (issue #554).
    ! ls "${DOTFILES_ROOT}/claude/" 2>/dev/null | grep -qE 'settings\.json\.pre-statusline-fix-'
    ! ls "$HOME/.claude-backups/" 2>/dev/null | grep -qE 'settings\.json\.pre-statusline-fix-'
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

# ---------- Regression: issue #554 ----------
#
# claude/setup.sh sources shell-common/{env,tools/integrations}/claude.sh
# to load _claude_resolve_account / _claude_has_unmigrated_data. Both files
# carry an interactive guard that early-returns under non-interactive
# bash unless DOTFILES_FORCE_INIT is set. When ./setup.sh is invoked by an
# end user (no env override), the guard skipped the function definitions,
# producing "command not found" errors and a silently empty
# ENABLED_ACCOUNTS — the entire multi-account install loop was skipped.
#
# run_in_bash always exports DOTFILES_FORCE_INIT=1, so this test
# deliberately bypasses it to mimic the real-user invocation path.

@test "regression #554: claude/setup.sh defines multi-account helpers without DOTFILES_FORCE_INIT" {
    _setup_sh_prereqs

    # No DOTFILES_FORCE_INIT, no DOTFILES_TEST_MODE — mirror the real
    # ./setup.sh invocation as seen on a fresh PC.
    run bash --noprofile --norc -c "
        unset DOTFILES_FORCE_INIT
        unset DOTFILES_TEST_MODE
        export HOME='$HOME'
        export TERM=dumb
        CLAUDE_SKIP_BIND_MOUNT=1 CLAUDE_SKIP_SUDOERS=1 \
            bash '${DOTFILES_ROOT}/claude/setup.sh'
    "
    assert_success
    refute_output --partial "_claude_has_unmigrated_data: command not found"
    refute_output --partial "_claude_resolve_account: command not found"
    refute_output --partial "command not found"
}

@test "regression #571: internal setup defines mount helper without DOTFILES_FORCE_INIT" {
    _setup_sh_prereqs
    echo "internal" > "$HOME/.dotfiles-setup-mode"

    # No DOTFILES_FORCE_INIT — mirror the failing internal-PC invocation path.
    run bash --noprofile --norc -c "
        unset DOTFILES_FORCE_INIT
        unset DOTFILES_TEST_MODE
        export HOME='$HOME'
        export TERM=dumb
        CLAUDE_SKIP_BIND_MOUNT=1 CLAUDE_SKIP_SUDOERS=1 \
            bash '${DOTFILES_ROOT}/claude/setup.sh'
    "
    assert_success
    refute_output --partial "_is_mounted: command not found"
    refute_output --partial "command not found"
    # #707, F-8: skills/ is a real composed directory; docs/ stays a symlink.
    [ -d "$HOME/.claude/skills" ]
    [ ! -L "$HOME/.claude/skills" ]
    [ -L "$HOME/.claude/docs" ]
}

@test "regression #571: internal setup unmounts legacy skills/docs bind mounts" {
    _setup_sh_prereqs
    echo "internal" > "$HOME/.dotfiles-setup-mode"
    mkdir -p "$HOME/.claude/skills" "$HOME/.claude/docs"

    fake_bin="$HOME/fake-bin"
    mkdir -p "$fake_bin"

    cat > "$fake_bin/findmnt" <<SH
#!/usr/bin/env bash
case "\$1" in
    "$HOME/.claude/skills"|"$HOME/.claude/docs") exit 0 ;;
    *) exit 1 ;;
esac
SH
    chmod +x "$fake_bin/findmnt"

    cat > "$fake_bin/sudo" <<'SH'
#!/usr/bin/env bash
if [ "$1" = "umount" ]; then
    printf '%s\n' "$2" >> "$HOME/fake-umount.log"
    exit 0
fi
exit 1
SH
    chmod +x "$fake_bin/sudo"

    run bash --noprofile --norc -c "
        unset DOTFILES_FORCE_INIT
        unset DOTFILES_TEST_MODE
        export HOME='$HOME'
        export TERM=dumb
        export PATH='$fake_bin':\$PATH
        CLAUDE_SKIP_BIND_MOUNT=1 CLAUDE_SKIP_SUDOERS=1 \
            bash '${DOTFILES_ROOT}/claude/setup.sh'
    "
    assert_success
    assert_output --partial "bind-mount detected at $HOME/.claude/skills"
    assert_output --partial "bind-mount detected at $HOME/.claude/docs"
    [ "$(cat "$HOME/fake-umount.log")" = "$HOME/.claude/skills
$HOME/.claude/docs" ]
    # #707, F-8: skills/ converges to a real composed directory; docs/ stays a symlink.
    [ -d "$HOME/.claude/skills" ]
    [ ! -L "$HOME/.claude/skills" ]
    [ -L "$HOME/.claude/docs" ]
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

    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; CLAUDE_ACCOUNT_EMAIL_personal=alice@example.com claude_yolo"
    assert_success
    refute_output --partial "Account mismatch"
}

@test "issue #300-B: claude_yolo warns on CLAUDE_ACCOUNT_EMAIL mismatch" {
    _setup_claude_mock
    mkdir -p "$HOME/.claude-work"
    printf '{"oauthAccount":{"emailAddress":"personal@gmail.com"}}' \
        > "$HOME/.claude-work/.claude.json"

    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; CLAUDE_ACCOUNT_EMAIL_work=work@corp.com claude_yolo --user work"
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

    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; claude_yolo --user work"
    assert_success
    refute_output --partial "Account mismatch"
}

# ---------- Issue #575 → #707: skills/ entry composition, docs/ dir-symlink ----------
#
# Issue #575 collapsed the bind-mount (#287) + per-skill symlinks
# (#342/#344) into a single directory-level symlink. Issue #707, F-8
# then promoted skills/ to a real directory of per-entry symlinks so a
# private overlay (~/company-skills) can layer into the same target.
# docs/ retained the #575 single directory-symlink design.

# Stage a FAKE_DOTFILES_ROOT under $HOME with skills/<name>/SKILL.md fixtures.
# bash/main.bash unconditionally re-derives DOTFILES_ROOT from its own path
# (see bash/main.bash:59), so setup_isolated_dotfiles_root cannot survive a
# run_in_bash. Instead we override DOTFILES_ROOT *after* main.bash sources —
# claude.sh reads ${DOTFILES_ROOT} at call time, not load time, so the
# override takes effect for the function call under test.
_seed_ssot_skills() {
    export FAKE_DOTFILES_ROOT="$HOME/fake-dotfiles"
    rm -rf "$FAKE_DOTFILES_ROOT"
    mkdir -p "$FAKE_DOTFILES_ROOT/claude/skills" "$FAKE_DOTFILES_ROOT/claude/docs"
    for _skill in "$@"; do
        mkdir -p "$FAKE_DOTFILES_ROOT/claude/skills/${_skill}"
        printf -- '---\nname: %s\ndescription: stub for %s\n---\n' "$_skill" "$_skill" \
            > "$FAKE_DOTFILES_ROOT/claude/skills/${_skill}/SKILL.md"
    done
}

# Wrap run_in_bash with a DOTFILES_ROOT override for the seeded fake root.
run_with_fake_ssot() {
    run_in_bash "export DOTFILES_ROOT='$FAKE_DOTFILES_ROOT'; $1"
}

@test "issue #575 → #707: claude_accounts_init composes skills/ entries and dir-symlinks docs/" {
    _seed_ssot_skills alpha beta
    mkdir -p "$HOME/.claude-shared/plugins"

    run_with_fake_ssot 'CLAUDE_ENABLED_ACCOUNTS=personal claude_accounts_init'
    assert_success

    # docs/ remains a single directory-level symlink (#575).
    [ -L "$HOME/.claude-personal/docs" ]
    [ "$(readlink "$HOME/.claude-personal/docs")" = "$FAKE_DOTFILES_ROOT/claude/docs" ]
    # skills/ is a real composed directory of per-entry symlinks (#707, F-8).
    [ -d "$HOME/.claude-personal/skills" ]
    [ ! -L "$HOME/.claude-personal/skills" ]
    [ -L "$HOME/.claude-personal/skills/alpha" ]
    [ "$(readlink "$HOME/.claude-personal/skills/alpha")" = "$FAKE_DOTFILES_ROOT/claude/skills/alpha" ]
    [ -L "$HOME/.claude-personal/skills/beta" ]
    [ -f "$HOME/.claude-personal/skills/alpha/SKILL.md" ]
}

@test "issue #707, F-8: re-running setup picks up newly added SSOT skill entries" {
    # #575's instant-visibility property (a new SSOT entry visible without
    # re-running setup) was intentionally traded by #707, F-8 for overlay
    # support: skills/ is now a real directory of per-entry symlinks, so a
    # new entry is wired in only on the next compose call. This test pins
    # the new contract — visible after re-run, not before.
    _seed_ssot_skills alpha
    mkdir -p "$HOME/.claude-shared/plugins"

    run_with_fake_ssot 'CLAUDE_ENABLED_ACCOUNTS=personal claude_accounts_init'
    assert_success

    mkdir -p "$FAKE_DOTFILES_ROOT/claude/skills/just-added"
    printf -- '---\nname: just-added\ndescription: post-setup skill\n---\n' \
        > "$FAKE_DOTFILES_ROOT/claude/skills/just-added/SKILL.md"

    # Pre-rerun: the new SSOT entry is NOT yet wired into the composed dir.
    [ ! -e "$HOME/.claude-personal/skills/just-added" ]

    # Re-run is idempotent for existing entries and wires the new one in.
    run_with_fake_ssot 'CLAUDE_ENABLED_ACCOUNTS=personal claude_accounts_init'
    assert_success
    [ -L "$HOME/.claude-personal/skills/just-added" ]
    [ -f "$HOME/.claude-personal/skills/just-added/SKILL.md" ]
}

@test "issue #707, F-8: user data in skills/ coexists with dotfiles per-entry symlinks" {
    # #575 backed up the entire skills/ directory on real-dir collision.
    # #707, F-8 dropped that path: the composed-directory model treats a
    # pre-existing real skills/ as the target itself, lays per-entry
    # symlinks alongside user data, and refuses to overwrite non-symlink
    # children (logs `skill entry blocked by non-symlink — skipped`).
    _seed_ssot_skills alpha
    mkdir -p "$HOME/.claude-shared/plugins"
    mkdir -p "$HOME/.claude-personal/skills/leftover"
    echo "user-data" > "$HOME/.claude-personal/skills/leftover/notes.md"

    run_with_fake_ssot '_claude_account_setup_one personal "$HOME/.claude-personal"'
    assert_success

    # skills/ stays a real composed directory — no top-level backup of user data.
    [ -d "$HOME/.claude-personal/skills" ]
    [ ! -L "$HOME/.claude-personal/skills" ]
    [ -z "$(ls -d "$HOME/.claude-personal/skills-"*-original 2>/dev/null)" ]
    # User data preserved in place; dotfiles entry wired alongside.
    grep -q "user-data" "$HOME/.claude-personal/skills/leftover/notes.md"
    [ -L "$HOME/.claude-personal/skills/alpha" ]
}

@test "issue #575 → #707: second _claude_account_setup_one is idempotent for skills/docs" {
    _seed_ssot_skills alpha
    mkdir -p "$HOME/.claude-shared/plugins"

    run_with_fake_ssot '_claude_account_setup_one personal "$HOME/.claude-personal"'
    assert_success

    run_with_fake_ssot '_claude_account_setup_one personal "$HOME/.claude-personal"'
    assert_success
    assert_output --partial "already linked"

    # docs/ remains a symlink; skills/ remains a composed real directory.
    [ -L "$HOME/.claude-personal/docs" ]
    [ -d "$HOME/.claude-personal/skills" ]
    [ ! -L "$HOME/.claude-personal/skills" ]
    [ -L "$HOME/.claude-personal/skills/alpha" ]
    # No backups created on the second run — state was already correct.
    [ -z "$(ls -d "$HOME/.claude-personal/skills-"*-original 2>/dev/null)" ]
    [ -z "$(ls -d "$HOME/.claude-personal/docs-"*-original 2>/dev/null)" ]
}

@test "issue #575: claude-accounts no longer exposes the skills-sync subcommand" {
    run_in_bash 'shopt -s expand_aliases; eval "claude-accounts -h"'
    assert_success
    refute_output --partial "skills-sync"
}

@test "issue #575: claude_skills_sync, _claude_dir_sync_one, claude-mount-* are gone" {
    run_in_bash 'declare -F claude_skills_sync claude_mount_skills claude_mount_docs claude_mount_all _claude_dir_sync_one _claude_count_dir_sync _claude_ensure_bind_mount 2>&1 || true'
    refute_output --partial "claude_skills_sync"
    refute_output --partial "claude_mount_skills"
    refute_output --partial "claude_mount_docs"
    refute_output --partial "claude_mount_all"
    refute_output --partial "_claude_dir_sync_one"
    refute_output --partial "_claude_count_dir_sync"
    refute_output --partial "_claude_ensure_bind_mount"
}

# ---------- Issue #500: setup.sh / migrate 자동화 갭 보강 ----------

@test "issue #500-F1 → #584: setup.sh fails fast when tracked settings.json is missing" {
    # Issue #584 promoted claude/settings.json to a tracked SSOT, so the
    # #500-F1 auto-bootstrap-from-template path was retired — the SSOT is
    # always expected to be present in any healthy checkout. setup.sh
    # now refuses to run rather than silently fabricating one. This test
    # pins that refusal so a future re-introduction of an auto-bootstrap
    # cannot silently re-land.
    _setup_sh_prereqs
    rm -f "${DOTFILES_ROOT}/claude/settings.json"
    ln -s "${DOTFILES_ROOT}" "$HOME/dotfiles"

    run_in_bash "CLAUDE_SKIP_BIND_MOUNT=1 CLAUDE_SKIP_SUDOERS=1 bash '${DOTFILES_ROOT}/claude/setup.sh'"
    assert_failure
    assert_output --partial "settings.json 없음"
    [ ! -f "${DOTFILES_ROOT}/claude/settings.json" ]
}

@test "issue #500-F1: setup.sh leaves existing settings.json untouched (idempotent)" {
    _setup_sh_prereqs
    # _setup_sh_prereqs 가 이미 template -> settings.json 복사를 해두었음.
    sentinel='__issue_500_idempotent_marker__'
    cp "${DOTFILES_ROOT}/claude/settings.json" "${DOTFILES_ROOT}/claude/settings.json.before"
    # 사용자 편집 흔적을 남겨 두번째 실행 후에도 보존되는지 검증.
    jq --arg s "$sentinel" '. + {marker: $s}' \
        "${DOTFILES_ROOT}/claude/settings.json" > "${DOTFILES_ROOT}/claude/settings.json.tmp" \
        && mv "${DOTFILES_ROOT}/claude/settings.json.tmp" "${DOTFILES_ROOT}/claude/settings.json"
    ln -s "${DOTFILES_ROOT}" "$HOME/dotfiles"

    run_in_bash "CLAUDE_SKIP_BIND_MOUNT=1 CLAUDE_SKIP_SUDOERS=1 bash '${DOTFILES_ROOT}/claude/setup.sh'"
    assert_success
    refute_output --partial "자동 부트스트랩"
    grep -q "$sentinel" "${DOTFILES_ROOT}/claude/settings.json"
}

@test "issue #500-F2: claude_yolo restores missing .claude.json from snapshot" {
    _setup_claude_mock
    mkdir -p "$HOME/.claude-personal"
    # 사용자가 .claude.json 을 삭제했거나 다른 사고로 사라진 상태.
    printf '{"firstStartTime":"x","oauthAccount":{"e":"a@b"},"migrationVersion":5}' \
        > "$HOME/.claude-personal/.claude.json.preserved-by-migrate"

    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; claude_yolo"
    assert_success
    assert_output --partial "missing .claude.json"
    assert_output --partial "Restored"
    [ -f "$HOME/.claude-personal/.claude.json" ]
    grep -q "oauthAccount" "$HOME/.claude-personal/.claude.json"
    grep -q "migrationVersion" "$HOME/.claude-personal/.claude.json"
}

@test "issue #500-F2: claude_yolo silent on missing .claude.json with no snapshot" {
    _setup_claude_mock
    mkdir -p "$HOME/.claude-personal"
    # snapshot 도 없는 fresh PC — 기존 동작 유지 (silent return).

    run_in_bash "export PATH=\"$HOME/bin:\$PATH\"; claude_yolo"
    assert_success
    refute_output --partial "Restored"
    refute_output --partial "missing .claude.json"
}

@test "issue #500-F3: claude_accounts_migrate warns on missing pre-migrate .claude.json" {
    mkdir -p "${DOTFILES_ROOT}/claude/skills" "${DOTFILES_ROOT}/claude/docs"
    mkdir -p "$HOME/.claude/projects"
    # .claude.json 자체가 부재한 디렉토리 (Home-PC 일부 회복 시나리오).

    run_in_bash 'export CLAUDE_SKIP_BIND_MOUNT=1; printf "y\n" | claude_accounts_migrate'
    assert_success
    assert_output --partial "Pre-migrate ~/.claude/.claude.json missing"
    assert_output --partial "sealed snapshot not created"
    # 부재 시에는 sealed snapshot 도 만들어지지 않아야 함.
    [ ! -f "$HOME/.claude-personal/.claude.json.preserved-by-migrate" ]
}

# Issue #344 (per-skill backup scanner pollution) is no longer reachable
# under #575 — skills/ is a single directory symlink with no per-entry
# backups in scanner view. Tests that exercised the legacy path were
# removed with `_claude_dir_sync_one`.

# ---------- _claude_yolo_export_settings_env: gateway env propagation ----------

@test "bash: settings.local.json env block exports to shell process" {
    mkdir -p "$HOME/.claude-test"
    cat > "$HOME/.claude-test/settings.local.json" <<'JSON'
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://gw.example.local:8090",
    "ANTHROPIC_AUTH_TOKEN": "",
    "ANTHROPIC_MODEL": "TestModel-7B",
    "NODE_TLS_REJECT_UNAUTHORIZED": 0,
    "ANTHROPIC_CUSTOM_HEADERS": "x-foo: bar\nx-baz: qux",
    "GH_PR_REPLY_AUTO_APPROVE_REPOS": "owner/repo"
  }
}
JSON

    run_in_bash '
        unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_MODEL \
              NODE_TLS_REJECT_UNAUTHORIZED ANTHROPIC_CUSTOM_HEADERS \
              GH_PR_REPLY_AUTO_APPROVE_REPOS
        _claude_yolo_export_settings_env "$HOME/.claude-test"
        printf "BASE=[%s]\nTOKEN=[%s]\nMODEL=[%s]\nTLS=[%s]\nHEADERS=[%s]\nREPOS=[%s]\n" \
            "${ANTHROPIC_BASE_URL}" "${ANTHROPIC_AUTH_TOKEN}" "${ANTHROPIC_MODEL}" \
            "${NODE_TLS_REJECT_UNAUTHORIZED}" "${ANTHROPIC_CUSTOM_HEADERS}" \
            "${GH_PR_REPLY_AUTO_APPROVE_REPOS}"
    '
    assert_success
    assert_output --partial "BASE=[http://gw.example.local:8090]"
    assert_output --partial "TOKEN=[]"
    assert_output --partial "MODEL=[TestModel-7B]"
    assert_output --partial "TLS=[0]"
    # ANTHROPIC_CUSTOM_HEADERS has an embedded newline — assert both halves.
    assert_output --partial "HEADERS=[x-foo: bar"
    assert_output --partial "x-baz: qux]"
    assert_output --partial "REPOS=[owner/repo]"
}

@test "bash: _claude_yolo_export_settings_env silent no-op when file missing" {
    # No settings.local.json under the test dir.
    mkdir -p "$HOME/.claude-empty"

    run_in_bash '
        unset ANTHROPIC_BASE_URL
        _claude_yolo_export_settings_env "$HOME/.claude-empty"
        echo "exit=$?"
        echo "BASE=[${ANTHROPIC_BASE_URL-<unset>}]"
    '
    assert_success
    assert_output --partial "exit=0"
    assert_output --partial "BASE=[<unset>]"
}

@test "bash: _claude_yolo_export_settings_env silent no-op when env block absent" {
    mkdir -p "$HOME/.claude-noenv"
    echo '{"permissions": {"allow": []}}' > "$HOME/.claude-noenv/settings.local.json"

    run_in_bash '
        unset ANTHROPIC_BASE_URL
        _claude_yolo_export_settings_env "$HOME/.claude-noenv"
        echo "exit=$?"
        echo "BASE=[${ANTHROPIC_BASE_URL-<unset>}]"
    '
    assert_success
    assert_output --partial "exit=0"
    assert_output --partial "BASE=[<unset>]"
}

@test "bash: _claude_yolo_export_settings_env in subshell does not leak to caller" {
    # claude_yolo wraps the helper + `command claude` in (...) precisely
    # so that NODE_TLS_REJECT_UNAUTHORIZED=0 (security-relaxing) and the
    # gateway URL do not persist in the caller's interactive shell.
    mkdir -p "$HOME/.claude-iso"
    cat > "$HOME/.claude-iso/settings.local.json" <<'JSON'
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://iso.example.local:8090",
    "NODE_TLS_REJECT_UNAUTHORIZED": 0
  }
}
JSON

    run_in_bash '
        unset ANTHROPIC_BASE_URL NODE_TLS_REJECT_UNAUTHORIZED
        (
            _claude_yolo_export_settings_env "$HOME/.claude-iso"
            echo "INSIDE_BASE=[${ANTHROPIC_BASE_URL}]"
            echo "INSIDE_TLS=[${NODE_TLS_REJECT_UNAUTHORIZED}]"
        )
        echo "OUTSIDE_BASE=[${ANTHROPIC_BASE_URL-<unset>}]"
        echo "OUTSIDE_TLS=[${NODE_TLS_REJECT_UNAUTHORIZED-<unset>}]"
    '
    assert_success
    assert_output --partial "INSIDE_BASE=[http://iso.example.local:8090]"
    assert_output --partial "INSIDE_TLS=[0]"
    assert_output --partial "OUTSIDE_BASE=[<unset>]"
    assert_output --partial "OUTSIDE_TLS=[<unset>]"
}

@test "bash: _claude_yolo_export_settings_env silent no-op on malformed JSON" {
    mkdir -p "$HOME/.claude-bad"
    echo '{invalid json' > "$HOME/.claude-bad/settings.local.json"

    run_in_bash '
        unset ANTHROPIC_BASE_URL
        _claude_yolo_export_settings_env "$HOME/.claude-bad"
        echo "exit=$?"
        echo "BASE=[${ANTHROPIC_BASE_URL-<unset>}]"
    '
    assert_success
    assert_output --partial "exit=0"
    assert_output --partial "BASE=[<unset>]"
}
