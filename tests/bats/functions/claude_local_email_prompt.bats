#!/usr/bin/env bats
# tests/bats/functions/claude_local_email_prompt.bats
# Verify copy_local_files' external branch auto-populates per-account email
# mappings interactively (issue #1173) while staying safe non-interactively.
#
# Scope note: like tests/bats/functions/setup_opencode_config.bats (the
# _resolve_knox_id precedent), the interactive *prompt loop* itself (tty
# read via `_prompt_claude_account_emails`) has no pty/expect harness in this
# suite, so it stays manually verified only. But the escaping/export-writing
# logic it calls — `_pcae_write_email_export` — was deliberately extracted
# into a pure function (no prompt, no tty check) precisely so it CAN be
# unit-tested directly (PR #1176 review feedback: codex flagged the escaping
# safety contract as untested). What is covered here:
#   1. non-interactive run → CLAUDE_ENABLED_ACCOUNTS written, NO email lines (F-4)
#   2. git-tracked claude.local.example stays byte-identical (NF-1)
#   3. _pcae_write_email_export: shell-metacharacter input is escaped so the
#      resulting export line is inert when the generated file is sourced
#   4. _pcae_write_email_export: empty input writes no line

load '../test_helper'

setup() {
    setup_isolated_home

    # Minimal dotfiles fixture: copy_local_files() finds *.local.example under
    # $SHELL_COMMON_DIR, so we stage only claude.local.example plus the two
    # optional sources setup.sh sources at load time (both `[ -f ]`-guarded).
    FIXTURE_DOTFILES="$TEST_TEMP_HOME/dotfiles"
    mkdir -p \
        "$FIXTURE_DOTFILES/shell-common/env" \
        "$FIXTURE_DOTFILES/shell-common/tools/ux_lib"
    cp "$_BATS_REAL_DOTFILES_ROOT/shell-common/setup.sh" \
       "$FIXTURE_DOTFILES/shell-common/setup.sh"
    cp "$_BATS_REAL_DOTFILES_ROOT/shell-common/tools/ux_lib/ux_lib.sh" \
       "$FIXTURE_DOTFILES/shell-common/tools/ux_lib/ux_lib.sh"
    cp "$_BATS_REAL_DOTFILES_ROOT/shell-common/env/claude.local.example" \
       "$FIXTURE_DOTFILES/shell-common/env/claude.local.example"

    EXAMPLE="$FIXTURE_DOTFILES/shell-common/env/claude.local.example"
    LOCAL="$FIXTURE_DOTFILES/shell-common/env/claude.local.sh"
}

teardown() {
    teardown_isolated_home
}

# Source setup.sh in a subshell, then invoke copy_local_files alone. The
# direct-exec guard in setup.sh keeps main() from running on source. stdin is
# redirected from /dev/null so `[ -t 0 ]` is deterministically false — this
# exercises the non-interactive path and cannot hang on `read` even if bats
# is launched from an interactive terminal.
run_copy_local_files() {
    run bash --noprofile --norc -c "
        set -e
        cd '$FIXTURE_DOTFILES/shell-common'
        . './setup.sh'
        copy_local_files external
    " </dev/null
}

@test "non-interactive external: enables accounts but writes no email lines (F-4)" {
    run_copy_local_files
    assert_success

    [ -f "$LOCAL" ]
    # Anchor to `^export`: the copied template also carries *commented*
    # `# export CLAUDE_ENABLED_ACCOUNTS=...` / `# export CLAUDE_ACCOUNT_EMAIL_*`
    # example lines, so only the active (uncommented) exports are meaningful.
    grep -q '^export CLAUDE_ENABLED_ACCOUNTS="personal work work1"' "$LOCAL"
    # No tty → the prompt loop is skipped entirely, so no active email exports.
    ! grep -q '^export CLAUDE_ACCOUNT_EMAIL_' "$LOCAL"
}

@test "git-tracked claude.local.example is never modified (NF-1)" {
    run_copy_local_files
    assert_success

    # The generated .local.sh is where writes land; the tracked .example
    # template must remain byte-identical to the pristine repo source.
    cmp "$EXAMPLE" "$_BATS_REAL_DOTFILES_ROOT/shell-common/env/claude.local.example"
}

# --- _pcae_write_email_export: escaping safety (PR #1176 review) -----------
# claude.local.sh is `.`-sourced on every shell startup (shell-common/env/
# claude.sh), so an unescaped `"`, backtick, or `$(...)` typed at the prompt
# would execute as shell syntax the next time a shell starts. These tests
# call the pure write function directly (no read, no tty) so the escaping
# contract is verified without needing a pty/expect harness.

run_write_email_export() {
    run bash --noprofile --norc -c "
        set -e
        cd '$FIXTURE_DOTFILES/shell-common'
        . './setup.sh'
        _pcae_write_email_export \"\$1\" \"\$2\" \"\$3\"
    " _ "$1" "$2" "$3"
}

@test "_pcae_write_email_export: shell metacharacters are escaped inert" {
    OUT="$TEST_TEMP_HOME/out.sh"
    : >"$OUT"
    run_write_email_export personal 'a"; touch INJECTED; echo "' "$OUT"
    assert_success

    grep -q '^export CLAUDE_ACCOUNT_EMAIL_personal=' "$OUT"

    # Sourcing the generated line must not execute the embedded command and
    # must preserve the literal value.
    run bash --noprofile --norc -c ". '$OUT'; printf '%s' \"\$CLAUDE_ACCOUNT_EMAIL_personal\""
    assert_success
    [ "$output" = 'a"; touch INJECTED; echo "' ]
    [ ! -e "$TEST_TEMP_HOME/INJECTED" ]
    [ ! -e "./INJECTED" ]
}

@test "_pcae_write_email_export: dollar and backtick are escaped inert" {
    OUT="$TEST_TEMP_HOME/out.sh"
    : >"$OUT"
    run_write_email_export work 'a$(touch INJECTED2)`touch INJECTED3`b' "$OUT"
    assert_success

    run bash --noprofile --norc -c ". '$OUT'; printf '%s' \"\$CLAUDE_ACCOUNT_EMAIL_work\""
    assert_success
    [ "$output" = 'a$(touch INJECTED2)`touch INJECTED3`b' ]
    [ ! -e "$TEST_TEMP_HOME/INJECTED2" ]
    [ ! -e "$TEST_TEMP_HOME/INJECTED3" ]
}

@test "_pcae_write_email_export: empty input writes no line" {
    OUT="$TEST_TEMP_HOME/out.sh"
    : >"$OUT"
    run_write_email_export work1 "" "$OUT"
    assert_success
    [ ! -s "$OUT" ]
}
