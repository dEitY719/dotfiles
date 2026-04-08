#!/usr/bin/env bats
# tests/bats/tools/custom_tools.bats
# Validate custom tool scripts: syntax, shebang, and executability.

load '../test_helper'

TOOLS_DIR="${DOTFILES_ROOT}/shell-common/tools/custom"

# Scripts that are sourced (not executed directly) — exempt from +x check
SOURCED_SCRIPTS="init.sh"

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# --- syntax validation (bash -n) for all tool scripts ---

@test "all custom tools pass bash syntax check" {
    local failed=()
    for script in "${TOOLS_DIR}"/*.sh; do
        [ -f "$script" ] || continue
        if ! bash -n "$script" 2>/dev/null; then
            failed+=("$(basename "$script")")
        fi
    done
    if [ ${#failed[@]} -gt 0 ]; then
        echo "Syntax errors in: ${failed[*]}"
        return 1
    fi
}

@test "all custom tools have bash shebang" {
    local failed=()
    for script in "${TOOLS_DIR}"/*.sh; do
        [ -f "$script" ] || continue
        local first_line
        first_line="$(head -1 "$script")"
        case "$first_line" in
            "#!/bin/bash"|"#!/usr/bin/env bash") ;;
            *) failed+=("$(basename "$script"): $first_line") ;;
        esac
    done
    if [ ${#failed[@]} -gt 0 ]; then
        printf "Bad shebang:\n"
        printf "  %s\n" "${failed[@]}"
        return 1
    fi
}

# --- check_network dry-run ---

@test "check_network help mode exits successfully" {
    run bash -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        export SHELL_COMMON='${SHELL_COMMON}'
        export HOME='${HOME}'
        bash '${TOOLS_DIR}/check_network.sh' help
    "
    assert_success
}

# --- individual syntax checks for check_* tools ---

@test "check_apt passes syntax check" {
    run bash -n "${TOOLS_DIR}/check_apt.sh"
    assert_success
}

@test "check_uv passes syntax check" {
    run bash -n "${TOOLS_DIR}/check_uv.sh"
    assert_success
}

@test "check_cargo passes syntax check" {
    run bash -n "${TOOLS_DIR}/check_cargo.sh"
    assert_success
}

@test "check_npm passes syntax check" {
    run bash -n "${TOOLS_DIR}/check_npm.sh"
    assert_success
}

@test "check_nuget passes syntax check" {
    run bash -n "${TOOLS_DIR}/check_nuget.sh"
    assert_success
}

@test "check_rpm passes syntax check" {
    run bash -n "${TOOLS_DIR}/check_rpm.sh"
    assert_success
}

@test "check_pip passes syntax check" {
    run bash -n "${TOOLS_DIR}/check_pip.sh"
    assert_success
}

@test "check_proxy passes syntax check" {
    run bash -n "${TOOLS_DIR}/check_proxy.sh"
    assert_success
}

@test "check_network passes syntax check" {
    run bash -n "${TOOLS_DIR}/check_network.sh"
    assert_success
}
