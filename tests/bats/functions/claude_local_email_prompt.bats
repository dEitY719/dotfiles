#!/usr/bin/env bats
# tests/bats/functions/claude_local_email_prompt.bats
# Verify copy_local_files' external branch auto-populates per-account email
# mappings interactively (issue #1173) while staying safe non-interactively.
#
# Scope note: like tests/bats/functions/setup_opencode_config.bats (the
# _resolve_knox_id precedent), only the non-interactive path is automated —
# the test suite has no pty/expect harness, so the interactive prompt-success
# path (a typed email producing an `export CLAUDE_ACCOUNT_EMAIL_<name>` line)
# is manually verified only. What is covered here:
#   1. non-interactive run → CLAUDE_ENABLED_ACCOUNTS written, NO email lines (F-4)
#   2. git-tracked claude.local.example stays byte-identical (NF-1)

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
