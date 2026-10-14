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

# --- shell-state-neutral dispatchers moved to PATH executables (#2155) ---

# <script stem> <~/.local/bin name>
DISPATCHERS="gcp_scan:gcp-scan gh_audit_builtin_workflows:gh-audit-builtin-workflows ghes_mirror:ghes-mirror ai_usage:ai-usage wsl_check:wsl-check"

# Link each dispatcher the way symlinks.conf does, into a bin dir on PATH.
_link_dispatchers() {
    LINK_BIN="$TEST_TEMP_HOME/.local/bin"
    mkdir -p "$LINK_BIN"
    local pair
    for pair in $DISPATCHERS; do
        ln -s "${TOOLS_DIR}/${pair%%:*}.sh" "$LINK_BIN/${pair##*:}"
    done
}

@test "#2155 dispatchers: executable, bash -n clean, linked in symlinks.conf" {
    local pair stem conf="${DOTFILES_ROOT}/shell-common/config/symlinks.conf"
    for pair in $DISPATCHERS; do
        stem="${pair%%:*}"
        [ -x "${TOOLS_DIR}/${stem}.sh" ] || fail "${stem}.sh not executable"
        bash -n "${TOOLS_DIR}/${stem}.sh" || fail "${stem}.sh syntax"
        grep -qF "\${HOME}/.local/bin/${pair##*:}|\${DOTFILES_ROOT}/shell-common/tools/custom/${stem}.sh|" "$conf" ||
            fail "symlinks.conf row missing for ${pair##*:}"
    done
}

@test "#2155 dispatchers: --help through the ~/.local/bin link in a bare bash -c" {
    _link_dispatchers
    local pair
    for pair in $DISPATCHERS; do
        # No SHELL_COMMON / DOTFILES_ROOT: the script must find its own tree
        # through the symlink, as an AI agent's non-interactive call does.
        run env -i HOME="$HOME" PATH="$LINK_BIN:/usr/bin:/bin" TERM=dumb \
            bash -c "${pair##*:} --help"
        assert_success
        [ -n "$output" ] || fail "${pair##*:} --help printed nothing"
    done
}

@test "#2155 wsl-check: no-arg one-line summary runs non-interactively" {
    _link_dispatchers
    run env -i HOME="$HOME" PATH="$LINK_BIN:/usr/bin:/bin" TERM=dumb bash -c 'wsl-check'
    assert_success
    assert_output --partial "disk:"
}

@test "#2155 ghes_mirror wrapper still leaves the shell inside the new clone" {
    local stub="$TEST_TEMP_HOME/stub-bin"
    mkdir -p "$stub"
    printf '#!/bin/sh\ncase "$1" in clone) mkdir -p "$3" ;; branch) echo main ;; esac\nexit 0\n' >"$stub/git"
    printf '#!/bin/sh\nexit 0\n' >"$stub/gh"
    chmod +x "$stub/git" "$stub/gh"
    run_in_bash "export PATH='$stub':\$PATH DOTFILES_GHES_HOST=ghes.example.invalid
        cd '$HOME' || exit 1
        # A redirect, not a pipe: a pipe would run ghes_mirror in a subshell.
        printf 'https://github.com/o/mirrored\nhttps://ghes.example.invalid/u/mirrored\ny\n' >answers
        ghes_mirror <answers
        echo \"rc=\$? pwd=\$(pwd)\""
    assert_output --partial "Mirror complete."
    assert_output --partial "rc=0 pwd=$HOME/mirrored"
}
