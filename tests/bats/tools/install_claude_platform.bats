#!/usr/bin/env bats
# tests/bats/tools/install_claude_platform.bats
# Static routing check for issue #1308 (PR #1307 / issue #1305).
#
# PR #1307 dropped the unreachable `linux-gnu*` arm from the OSTYPE case in
# install_claude.sh — `linux*` already matched it, so it was dead code, not a
# behaviour change. The dispatch now lives in install_claude_platform_branch(),
# a pure classifier, so the equivalence is verifiable without running the
# installer: `linux-gnu` must route exactly like `linux`.

load '../test_helper'

TOOLS_DIR="${DOTFILES_ROOT}/shell-common/tools/custom"
INSTALL_CLAUDE_SCRIPT="${TOOLS_DIR}/install_claude.sh"

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# Source install_claude.sh and classify each argument, one token per line, via
# the shared run_sourced_tool_script / quote_args helpers (test_helper.bash).
classify() {
    local args_q
    args_q="$(quote_args "$@")"

    run_sourced_tool_script "$TOOLS_DIR" "$INSTALL_CLAUDE_SCRIPT" "
        for ostype in${args_q}; do
            install_claude_platform_branch \"\$ostype\"
        done
    "
}

# --- the equivalence PR #1307 relied on -------------------------------------

@test "install_claude_platform_branch: linux-gnu routes identically to linux" {
    classify linux-gnu
    assert_success
    local linux_gnu_branch="$output"

    classify linux
    assert_success
    assert_output "$linux_gnu_branch"
    assert_output "unix"
}

# --- full classification table ----------------------------------------------

@test "install_claude_platform_branch: unix-family OSTYPE values all route to unix" {
    classify darwin23 darwin linux linux-gnu linux-musl freebsd14
    assert_success
    assert_output "unix
unix
unix
unix
unix
unix"
}

@test "install_claude_platform_branch: windows shells route to windows" {
    classify msys msys2 win32 cygwin
    assert_success
    assert_output "windows
windows
windows
windows"
}

@test "install_claude_platform_branch: unknown OSTYPE routes to unsupported" {
    classify solaris2.11 "" aix
    assert_success
    assert_output "unsupported
unsupported
unsupported"
}

# --- structural guard: main() consumes the classifier -----------------------

@test "install_claude.sh main() dispatches on install_claude_platform_branch" {
    run grep -Fq 'case "$(install_claude_platform_branch "$OSTYPE")" in' "$INSTALL_CLAUDE_SCRIPT"
    assert_success
}
