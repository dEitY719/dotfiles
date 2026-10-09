#!/usr/bin/env bats
# tests/bats/tools/check_proxy_mode.bats
# check_proxy.sh validates the proxy env against the setup mode through the
# single proxy rule _dotfiles_setup_mode_proxy (util/setup_mode_read.sh), the
# same predicate util/setup_mode.sh uses to clean inherited proxies.

load '../test_helper'

TOOLS_DIR="${DOTFILES_ROOT}/shell-common/tools/custom"

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# ux_* stubs: DOTFILES_TEST_MODE makes init.sh return before loading ux_lib.
run_proxy_env_check() {
    run_sourced_tool_script "$TOOLS_DIR" "$TOOLS_DIR/check_proxy.sh" "
        for f in ux_header ux_section ux_bullet ux_info ux_success ux_warning ux_error; do
            eval \"\$f() { printf '%s\\n' \\\"\\\$*\\\"; }\"
        done
        $1
        check_proxy_env
    "
}

@test "external mode + inherited proxy -> ISSUE DETECTED (forbidden)" {
    printf 'external\r\n' >"$HOME/.dotfiles-setup-mode"
    run_proxy_env_check 'export http_proxy=http://127.0.0.1:3128'
    assert_output --partial "ISSUE DETECTED: Proxy is set but should not be (Mode external)"
}

@test "legacy 2 (internal) without proxy -> expects proxy (required)" {
    printf '2\n' >"$HOME/.dotfiles-setup-mode"
    run_proxy_env_check 'unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY'
    assert_output --partial "No proxy set but internal mode expects proxy"
}

@test "public mode without proxy -> no issue" {
    printf 'public\n' >"$HOME/.dotfiles-setup-mode"
    run_proxy_env_check 'unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY'
    refute_output --partial "ISSUE DETECTED"
    refute_output --partial "expects proxy"
}
