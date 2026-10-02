#!/usr/bin/env bats
# tests/bats/functions/claude_herdr_hook_install.bats
# _claude_install_herdr_hook: install the herdr Claude hook script into an
# account dir, idempotently, and never fail the parent setup.

load '../test_helper'

setup() {
    setup_isolated_home
    CDIR="$TEST_TEMP_HOME/.claude-x"
    BIN="$TEST_TEMP_HOME/bin"
    CALLS="$TEST_TEMP_HOME/herdr.calls"
    mkdir -p "$BIN"

    # Fake herdr: records the call and creates the hook script like the real one.
    cat > "$BIN/herdr" <<STUB
#!/bin/sh
echo "\$CLAUDE_CONFIG_DIR \$*" >> "$CALLS"
[ -n "\$HERDR_FAKE_FAIL" ] && exit 1
mkdir -p "\$CLAUDE_CONFIG_DIR/hooks"
: > "\$CLAUDE_CONFIG_DIR/hooks/herdr-agent-state.sh"
chmod +x "\$CLAUDE_CONFIG_DIR/hooks/herdr-agent-state.sh"
STUB
    chmod +x "$BIN/herdr"

    RUNNER="$TEST_TEMP_HOME/run.sh"
    cat > "$RUNNER" <<EOF2
#!/bin/bash
export DOTFILES_FORCE_INIT=1
source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh"
source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/integrations/claude.sh"
_claude_install_herdr_hook "\$1"
EOF2
    chmod +x "$RUNNER"
}

teardown() {
    teardown_isolated_home
}

@test "installs the hook script once and is idempotent" {
    PATH="$BIN:$PATH" run "$RUNNER" "$CDIR"
    [ "$status" -eq 0 ]
    [ -x "$CDIR/hooks/herdr-agent-state.sh" ]
    PATH="$BIN:$PATH" run "$RUNNER" "$CDIR"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$CALLS")" -eq 1 ]
    grep -q "^$CDIR integration install claude" "$CALLS"
}

@test "no-op when herdr is not on PATH" {
    PATH="/usr/bin:/bin" run "$RUNNER" "$CDIR"
    [ "$status" -eq 0 ]
    [ ! -e "$CDIR/hooks/herdr-agent-state.sh" ]
}

@test "soft-fails when herdr install fails" {
    HERDR_FAKE_FAIL=1 PATH="$BIN:$PATH" run "$RUNNER" "$CDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"herdr integration install"* ]]
}
