#!/usr/bin/env bats
# tests/bats/tools/docker_configure_proxy_mkdir.bats
# Regression coverage for issue #1308 — locks the PR #1307 fix of issue #1305.
#
# main() used to create the systemd drop-in directory like this:
#     sudo mkdir -p "$drop_in_dir"
#     if [ $? -ne 0 ]; then ...            # $? already clobbered by `local`
# so a failing mkdir was never detected. The step now lives in
# docker_proxy_create_dropin_dir(), which branches on `sudo mkdir -p` directly.
#
# `sudo` is a PATH-injected mock binary (same pattern as
# tests/bats/skills/gh_label_bootstrap.bats) — no privileged call is ever made.

load '../test_helper'

TOOLS_DIR="${DOTFILES_ROOT}/shell-common/tools/custom"
DOCKER_PROXY_SCRIPT="${TOOLS_DIR}/docker_configure_proxy.sh"

setup() {
    setup_isolated_home

    MOCK_BIN="${TEST_TEMP_HOME}/mock-bin"
    MOCK_LOG="${TEST_TEMP_HOME}/mock-sudo.log"
    TARGET_DIR="${TEST_TEMP_HOME}/systemd/docker.service.d"
    mkdir -p "$MOCK_BIN"
    : >"$MOCK_LOG"

    cat >"${MOCK_BIN}/sudo" <<'EOF'
#!/usr/bin/env bash
# Mock sudo: log the delegated command, then either fail or run it unprivileged.
printf '%s\n' "$*" >>"${MOCK_SUDO_LOG}"

if [ "${MOCK_SUDO_FAIL:-0}" = "1" ]; then
    exit 1
fi

exec "$@"
EOF
    chmod +x "${MOCK_BIN}/sudo"

    export MOCK_SUDO_LOG="$MOCK_LOG"
    export MOCK_SUDO_FAIL=0
    export PATH="${MOCK_BIN}:${PATH}"
}

teardown() {
    teardown_isolated_home
}

# Source docker_configure_proxy.sh and call the extracted step, via the
# shared run_sourced_tool_script helper (tests/bats/test_helper.bash).
#
# $1 = extra statement appended to the ux_success double (e.g. "return 1")
run_create_dropin_dir() {
    local ux_success_tail="${1:-return 0}"

    run_sourced_tool_script "$TOOLS_DIR" "$DOCKER_PROXY_SCRIPT" "
        ux_success() { printf 'OK: %s\n' \"\$1\"; ${ux_success_tail}; }
        ux_error() { printf 'ERR: %s\n' \"\$1\" >&2; }
        if docker_proxy_create_dropin_dir '${TARGET_DIR}'; then
            printf 'rc=0\n'
        else
            printf 'rc=1\n'
        fi
    "
}

# --- the actual PR #1307 regression -----------------------------------------

@test "docker_proxy_create_dropin_dir: failing sudo mkdir is reported and returns 1" {
    MOCK_SUDO_FAIL=1 run_create_dropin_dir
    assert_success # the driver itself completes; the function's rc is printed
    assert_output --partial "ERR: Failed to create directory: ${TARGET_DIR}"
    assert_output --partial "rc=1"
    refute_output --partial "OK:"
    [ ! -d "$TARGET_DIR" ]
}

@test "docker_proxy_create_dropin_dir: delegates exactly 'mkdir -p <dir>' to sudo" {
    MOCK_SUDO_FAIL=1 run_create_dropin_dir
    run grep -Fx "mkdir -p ${TARGET_DIR}" "$MOCK_LOG"
    assert_success
}

# --- success path ------------------------------------------------------------

@test "docker_proxy_create_dropin_dir: successful sudo mkdir creates the dir and returns 0" {
    run_create_dropin_dir
    assert_output --partial "OK: Directory created: ${TARGET_DIR}"
    assert_output --partial "rc=0"
    refute_output --partial "ERR:"
    [ -d "$TARGET_DIR" ]
}

@test "docker_proxy_create_dropin_dir: failing ux_success does not turn success into failure" {
    # Same class of bug as the work_log fix: the reporting side effect must not
    # decide the step's exit status (hence the explicit `return 0`).
    run_create_dropin_dir "return 1"
    assert_output --partial "rc=0"
    [ -d "$TARGET_DIR" ]
}

# --- structural guard --------------------------------------------------------

@test "docker_configure_proxy.sh no longer inspects \$? after the mkdir step" {
    if grep -nE '^[[:space:]]*if \[ \$\? -ne 0 \]' "$DOCKER_PROXY_SCRIPT"; then
        echo "docker_configure_proxy.sh reintroduced the late '\$?' check"
        return 1
    fi
}
