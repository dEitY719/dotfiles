#!/usr/bin/env bats
# tests/bats/integrations/claude_statusline_cost.bats
#
# claude/statusline-command.sh internal-mode cost segment (#1966): the usage
# API URL and employee ID come from the gitignored
# shell-common/env/internal.local.sh (fake values only here), read by the
# script itself — not from the caller's shell env. Either value missing => the
# segment is omitted silently (exit 0, no stderr, no curl).
#
# The script is copied into a throwaway tree so the test can own
# shell-common/env/internal.local.sh without touching the repo checkout.

load '../test_helper'

setup() {
    setup_isolated_home
    ISO="$TEST_TEMP_HOME/df"
    mkdir -p "$ISO/claude" "$ISO/shell-common/util" "$ISO/shell-common/env" \
        "$TEST_TEMP_HOME/bin" "$TEST_TEMP_HOME/tmp"
    cp "$DOTFILES_ROOT/claude/statusline-command.sh" "$DOTFILES_ROOT/claude/statusline-tokens.sh" "$ISO/claude/"
    cp "$DOTFILES_ROOT/shell-common/util/setup_mode_read.sh" "$ISO/shell-common/util/"
    STATUSLINE="$ISO/claude/statusline-command.sh"
    LOCAL_SH="$ISO/shell-common/env/internal.local.sh"
    CURL_LOG="$TEST_TEMP_HOME/curl.log"
    CACHE="$TEST_TEMP_HOME/tmp/.claude_bedrock_cost_cache"
    # curl stub: record the URL, answer with a fixed cost.
    cat >"$TEST_TEMP_HOME/bin/curl" <<EOF
#!/bin/sh
for a; do u="\$a"; done
printf '%s\n' "\$u" >>"$CURL_LOG"
printf '{"latest_cost": 12.5}'
EOF
    chmod +x "$TEST_TEMP_HOME/bin/curl"
    export PATH="$TEST_TEMP_HOME/bin:$PATH" TMPDIR="$TEST_TEMP_HOME/tmp"
    export CLAUDE_STATUSLINE_SKIP_FCITX=1
    unset DOTFILES_CLAUDE_USAGE_API_URL DOTFILES_CLAUDE_USAGE_ID
    echo internal >"$HOME/.dotfiles-setup-mode"
}

teardown() {
    teardown_isolated_home
}

_write_local() {
    cat >"$LOCAL_SH" <<'EOF'
export DOTFILES_CLAUDE_USAGE_API_URL="https://usage.example.invalid/"
export DOTFILES_CLAUDE_USAGE_ID="EMP00000"
EOF
}

_fresh_cache() { printf '%s\n%s\n' "$(date +%s)" "12.5" >"$CACHE"; }

@test "statusline cost: values from internal.local.sh render the cost segment" {
    _write_local
    _fresh_cache
    _render_plain '{}'
    assert_success
    assert_output --partial '$12.5 / $175'
}

@test "statusline cost: stale cache refreshes via the URL built from internal.local.sh" {
    _write_local
    printf '%s\n%s\n' 1 "12.5" >"$CACHE"
    _render '{}'
    assert_success
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [ -s "$CURL_LOG" ] && break
        sleep 0.2
    done
    [ "$(cat "$CURL_LOG")" = "https://usage.example.invalid/?id=EMP00000" ]
}

@test "statusline cost: missing internal.local.sh omits segment, no stderr, no curl" {
    _fresh_cache
    run bash -c "printf '{}' | bash '$STATUSLINE' 2>&1 >/dev/null"
    assert_success
    assert_output ''
    _render_plain '{}'
    assert_success
    refute_output --partial '/ $175'
    [ ! -e "$CURL_LOG" ]
}

@test "statusline cost: only one of the two values set omits segment" {
    printf 'export DOTFILES_CLAUDE_USAGE_API_URL="https://usage.example.invalid/"\n' >"$LOCAL_SH"
    _fresh_cache
    _render_plain '{}'
    assert_success
    refute_output --partial '/ $175'
}

@test "statusline cost: public mode ignores internal.local.sh" {
    _write_local
    _fresh_cache
    echo public >"$HOME/.dotfiles-setup-mode"
    _render_plain '{}'
    assert_success
    refute_output --partial '/ $175'
}

@test "settings.local.json.example: env values are placeholders only" {
    run jq -r '.env.ANTHROPIC_BASE_URL' "$DOTFILES_ROOT/claude/settings.local.json.example"
    assert_success
    assert_output --regexp '^https?://[a-z.-]*\.example\.invalid(/|$)'
}
