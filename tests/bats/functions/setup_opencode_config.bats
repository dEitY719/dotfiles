#!/usr/bin/env bats
# tests/bats/functions/setup_opencode_config.bats
# Verify setup_opencode_config preserves user-edited account ID across re-runs
# (issue #792). Three scenarios mirror the issue's acceptance criteria:
#   1. fresh install (no target)        — cp template, no backup
#   2. re-run with placeholder unchanged — cp template again (current behavior)
#   3. re-run with account ID customised — preserve, no backup spam

load '../test_helper'

setup() {
    setup_isolated_home

    # Build a tiny dotfiles fixture so the function's cp source resolves.
    FIXTURE_DOTFILES="$TEST_TEMP_HOME/dotfiles"
    mkdir -p \
        "$FIXTURE_DOTFILES/opencode" \
        "$FIXTURE_DOTFILES/shell-common/env" \
        "$FIXTURE_DOTFILES/shell-common/tools/ux_lib"
    cp "$_BATS_REAL_DOTFILES_ROOT/opencode/opencode.json.internal" \
       "$FIXTURE_DOTFILES/opencode/opencode.json.internal"
    cp "$_BATS_REAL_DOTFILES_ROOT/shell-common/tools/ux_lib/ux_lib.sh" \
       "$FIXTURE_DOTFILES/shell-common/tools/ux_lib/ux_lib.sh"
    cp "$_BATS_REAL_DOTFILES_ROOT/shell-common/setup.sh" \
       "$FIXTURE_DOTFILES/shell-common/setup.sh"

    TARGET="$HOME/.config/opencode/opencode.json"
    mkdir -p "$(dirname "$TARGET")"
}

teardown() {
    teardown_isolated_home
}

# Source setup.sh in a subshell, then invoke setup_opencode_config alone.
# The direct-exec guard in setup.sh prevents main() from prompting.
run_setup_opencode() {
    run bash --noprofile --norc -c "
        set -e
        cd '$FIXTURE_DOTFILES/shell-common'
        . './setup.sh'
        setup_opencode_config internal
    "
}

# Fake (non-placeholder) gateway URL standing in for the real one (#1967).
FAKE_REAL_URL='http://gw.corp-fake.test:9999/v1'
LOCAL_SH() { printf '%s\n' "$FIXTURE_DOTFILES/shell-common/env/internal.local.sh"; }
write_local_url() {
    printf 'export DOTFILES_OPENCODE_BASE_URL="%s"\n' "$FAKE_REAL_URL" >"$(LOCAL_SH)"
}

count_backups() {
    ls "${TARGET}.backup."* 2>/dev/null | wc -l
}

@test "fresh install: copies template when target does not exist" {
    run_setup_opencode
    assert_success
    [ -f "$TARGET" ]
    grep -q 'your-account-id' "$TARGET"
    [ "$(count_backups)" -eq 0 ]
}

@test "re-run with placeholder unchanged: keeps the existing file" {
    run_setup_opencode
    assert_success

    run_setup_opencode
    assert_success
    [ -f "$TARGET" ]
    grep -q 'your-account-id' "$TARGET"
}

@test "re-run with account ID customised: preserves file, creates no backup" {
    write_local_url
    run_setup_opencode
    assert_success

    # User replaces the placeholder with a real account ID. Use a temp-file
    # rewrite (not `sed -i`) — GNU sed and BSD sed disagree on the `-i`
    # argument syntax, so the in-place form breaks on macOS dev machines.
    sed 's/your-account-id/abc123acct/' "$TARGET" > "${TARGET}.tmp" \
        && mv "${TARGET}.tmp" "$TARGET"
    customised_content="$(cat "$TARGET")"

    run_setup_opencode
    assert_success
    assert_output --partial "Preserved customised OpenCode config"

    # File untouched.
    [ "$(cat "$TARGET")" = "$customised_content" ]
    # No backup spam.
    [ "$(count_backups)" -eq 0 ]
}

@test "stray external-mode symlink at target: overwritten with template copy" {
    # Simulate user switching from external (symlink) to internal mode.
    ln -s "$FIXTURE_DOTFILES/opencode/opencode.json.internal" "$TARGET"

    run_setup_opencode
    assert_success

    [ -f "$TARGET" ]
    [ ! -L "$TARGET" ]
    grep -q 'your-account-id' "$TARGET"
}

# --- Account ID SSOT auto-fill (issue #1121, #1982) -----------------------------------
# The four scenarios below mirror the issue's acceptance criteria: fill from
# each SSOT, suppress the warning, and stay idempotent across re-runs.

# Legacy account-ID names, read via setup.sh's read-only fallback (#1982).
LEGACY_TERM=knox
LEGACY_ENV="DOTFILES_$(printf '%s' "$LEGACY_TERM" | tr '[:lower:]' '[:upper:]')_ID"
LEGACY_FILE=".dotfiles-${LEGACY_TERM}-id"
LEGACY_TOKEN="your-${LEGACY_TERM}-id"

# Same as run_setup_opencode but with env var $2 (default DOTFILES_ACCOUNT_ID)
# set to $1 in the child.
run_setup_opencode_env() {
    run bash --noprofile --norc -c "
        set -e
        export ${2:-DOTFILES_ACCOUNT_ID}='$1'
        cd '$FIXTURE_DOTFILES/shell-common'
        . './setup.sh'
        setup_opencode_config internal
    "
}

@test "env SSOT: DOTFILES_ACCOUNT_ID substitutes placeholder, no warning" {
    run_setup_opencode_env "envacct42"
    assert_success
    [ -f "$TARGET" ]
    grep -q 'envacct42' "$TARGET"
    refute grep -q 'your-account-id' "$TARGET"
    refute_output --partial "replace 'your-account-id'"
}

@test "file SSOT: ~/.dotfiles-account-id substitutes placeholder, no warning" {
    printf 'fileacct99\n' >"$HOME/.dotfiles-account-id"

    run_setup_opencode
    assert_success
    grep -q 'fileacct99' "$TARGET"
    refute grep -q 'your-account-id' "$TARGET"
    refute_output --partial "replace 'your-account-id'"
}

@test "env SSOT takes precedence over file SSOT" {
    printf 'fileacct99\n' >"$HOME/.dotfiles-account-id"

    run_setup_opencode_env "envacct42"
    assert_success
    grep -q 'envacct42' "$TARGET"
    refute grep -q 'fileacct99' "$TARGET"
}

@test "file SSOT: re-run is idempotent (preserve, no warning, no backup)" {
    printf 'fileacct99\n' >"$HOME/.dotfiles-account-id"
    write_local_url

    run_setup_opencode
    assert_success
    filled_content="$(cat "$TARGET")"

    # Second run: placeholder is gone, so the #792 preserve guard fires.
    run_setup_opencode
    assert_success
    assert_output --partial "Preserved customised OpenCode config"
    [ "$(cat "$TARGET")" = "$filled_content" ]
    [ "$(count_backups)" -eq 0 ]
}

@test "no SSOT + non-interactive: keeps placeholder and warns (fallback)" {
    # No env var, no file, no tty (bash -c) — must degrade gracefully.
    run_setup_opencode
    assert_success
    grep -q 'your-account-id' "$TARGET"
    assert_output --partial "replace 'your-account-id'"
}

# --- Gateway URL from internal.local.sh (issue #1967) -----------------------
# The tracked template carries a fake URL; setup renders the real one from the
# gitignored env/internal.local.sh and never downgrades a deployed config.


@test "#1967 render: internal.local.sh URL replaces the template placeholder" {
    write_local_url

    run_setup_opencode
    assert_success
    grep -qF "\"baseURL\": \"$FAKE_REAL_URL\"" "$TARGET"
    refute grep -q 'example.invalid' "$TARGET"
    # The tracked template itself is never rewritten (no value leaks into it).
    cmp -s "$FIXTURE_DOTFILES/opencode/opencode.json.internal" \
        "$_BATS_REAL_DOTFILES_ROOT/opencode/opencode.json.internal"
    refute grep -qF "$FAKE_REAL_URL" "$FIXTURE_DOTFILES/opencode/opencode.json.internal"
}

@test "#1967 deployed config kept untouched when no URL is available" {
    # A deployed config with real (here: fake-but-non-placeholder) values.
    sed "s|http://llm-gateway.example.invalid/v1|$FAKE_REAL_URL|" \
        "$FIXTURE_DOTFILES/opencode/opencode.json.internal" >"$TARGET"
    deployed="$(cat "$TARGET")"

    run_setup_opencode
    assert_success
    assert_output --partial "Kept existing"
    [ "$(cat "$TARGET")" = "$deployed" ]
    [ "$(count_backups)" -eq 0 ]
}

@test "#1967 placeholder URL in internal.local.sh counts as unavailable" {
    cp "$_BATS_REAL_DOTFILES_ROOT/shell-common/env/internal.local.example" "$(LOCAL_SH)"
    sed "s|http://llm-gateway.example.invalid/v1|$FAKE_REAL_URL|" \
        "$FIXTURE_DOTFILES/opencode/opencode.json.internal" >"$TARGET"
    deployed="$(cat "$TARGET")"

    run_setup_opencode
    assert_success
    [ "$(cat "$TARGET")" = "$deployed" ]
}

@test "#1967 fresh install without URL: writes placeholder template and warns" {
    run_setup_opencode
    assert_success
    grep -q 'llm-gateway.example.invalid' "$TARGET"
    assert_output --partial "DOTFILES_OPENCODE_BASE_URL"
}

@test "#1967 account-ID fill on a kept deployed config changes only the placeholder" {
    sed "s|http://llm-gateway.example.invalid/v1|$FAKE_REAL_URL|" \
        "$FIXTURE_DOTFILES/opencode/opencode.json.internal" >"$TARGET"

    run_setup_opencode_env "envacct42"
    assert_success
    grep -qF "$FAKE_REAL_URL" "$TARGET"
    grep -q 'envacct42' "$TARGET"
}

# --- Legacy-name fallback (#1982) --------------------------------------------
# Internal PCs set up before the rename keep working without any manual step.

@test "#1982 legacy env var alone fills the placeholder" {
    run_setup_opencode_env "legacyenv7" "$LEGACY_ENV"
    assert_success
    grep -q 'legacyenv7' "$TARGET"
    refute grep -q 'your-account-id' "$TARGET"
}

@test "#1982 legacy file alone fills and is copied to the new name, old kept" {
    printf 'legacyfile8\n' >"$HOME/$LEGACY_FILE"

    run_setup_opencode
    assert_success
    grep -q 'legacyfile8' "$TARGET"
    [ "$(cat "$HOME/.dotfiles-account-id")" = "legacyfile8" ]
    [ -f "$HOME/$LEGACY_FILE" ]

    # Idempotent: a re-run never overwrites the new file.
    printf 'newfile9\n' >"$HOME/.dotfiles-account-id"
    run_setup_opencode
    assert_success
    [ "$(cat "$HOME/.dotfiles-account-id")" = "newfile9" ]
}

@test "#1982 new names win over legacy names" {
    printf 'legacyfile8\n' >"$HOME/$LEGACY_FILE"
    printf 'newfile9\n' >"$HOME/.dotfiles-account-id"

    run bash --noprofile --norc -c "
        set -e
        export $LEGACY_ENV='legacyenv7' DOTFILES_ACCOUNT_ID='envacct42'
        cd '$FIXTURE_DOTFILES/shell-common'
        . './setup.sh'
        setup_opencode_config internal
    "
    assert_success
    grep -q 'envacct42' "$TARGET"

    rm -f "$TARGET"
    run_setup_opencode
    assert_success
    grep -q 'newfile9' "$TARGET"
}

@test "#1982 deployed config with the legacy token is still substituted" {
    sed -e "s|http://llm-gateway.example.invalid/v1|$FAKE_REAL_URL|" \
        -e "s|your-account-id|$LEGACY_TOKEN|" \
        "$FIXTURE_DOTFILES/opencode/opencode.json.internal" >"$TARGET"

    run_setup_opencode_env "envacct42"
    assert_success
    grep -qF "$FAKE_REAL_URL" "$TARGET"
    grep -q 'envacct42' "$TARGET"
    refute grep -q "$LEGACY_TOKEN" "$TARGET"
}

@test "#1982 legacy token without any ID: kept, neutral warning" {
    sed -e "s|http://llm-gateway.example.invalid/v1|$FAKE_REAL_URL|" \
        -e "s|your-account-id|$LEGACY_TOKEN|" \
        "$FIXTURE_DOTFILES/opencode/opencode.json.internal" >"$TARGET"
    deployed="$(cat "$TARGET")"

    run_setup_opencode
    assert_success
    [ "$(cat "$TARGET")" = "$deployed" ]
    assert_output --partial "replace 'your-account-id'"
}
