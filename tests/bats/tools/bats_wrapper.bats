#!/usr/bin/env bats
# tests/bats/tools/bats_wrapper.bats
# Tests for shell-common/tools/custom/bats.sh — the ~/.local/bin/bats wrapper
# around the vendored bats-core (issue #2361).

load '../test_helper'

WRAPPER="${DOTFILES_ROOT}/shell-common/tools/custom/bats.sh"

setup() {
    setup_isolated_home
    LINK_BIN="${TEST_TEMP_HOME}/.local/bin"
    mkdir -p "$LINK_BIN"
    ln -s "$WRAPPER" "${LINK_BIN}/bats"
    WORK="${TEST_TEMP_HOME}/work"
    mkdir -p "$WORK"
}

teardown() {
    teardown_isolated_home
}

# A bare environment: no DOTFILES_ROOT, no BATS_LIB_PATH, only the link dir
# and the system dirs on PATH — what an agent's `bash -c` call gets.
_bare() {
    run env -i HOME="$HOME" PATH="${LINK_BIN}:/usr/bin:/bin" TERM=dumb "$@"
}

@test "#2361 packaging: executable, bash -n clean, linked in symlinks.conf" {
    [ -x "$WRAPPER" ] || fail "bats.sh not executable"
    bash -n "$WRAPPER" || fail "bats.sh syntax"
    grep -qF '${HOME}/.local/bin/bats|${DOTFILES_ROOT}/shell-common/tools/custom/bats.sh|' \
        "${DOTFILES_ROOT}/shell-common/config/symlinks.conf" ||
        fail "symlinks.conf row missing for bats"
}

@test "#2361 bats --version works through the link with a minimal PATH" {
    _bare bash -c 'command -v bats && bats --version'
    assert_success
    assert_line --index 0 "${LINK_BIN}/bats"
    assert_output --partial "Bats "
}

@test "#2361 a .bats file in any directory loads bats-support/bats-assert" {
    cat >"${WORK}/libs.bats" <<'EOF'
setup() {
    bats_load_library bats-support
    bats_load_library bats-assert
}
@test "assert_equal from the vendored bats-assert" {
    assert_equal "$((1 + 1))" 2
}
EOF
    cd "$WORK"
    _bare bats libs.bats
    assert_success
    assert_output --partial "ok 1 assert_equal from the vendored bats-assert"
}

@test "#2361 an existing BATS_LIB_PATH is kept after the vendored lib dir" {
    cat >"${WORK}/env.bats" <<EOF
@test "lib path" {
    [ "\$BATS_LIB_PATH" = "${DOTFILES_ROOT}/tests/bats/lib:/opt/extra" ]
}
EOF
    run env -i HOME="$HOME" PATH="${LINK_BIN}:/usr/bin:/bin" TERM=dumb \
        BATS_LIB_PATH=/opt/extra bats "${WORK}/env.bats"
    assert_success
}

@test "#2361 a missing vendored bats-core prints the searched path and fails" {
    # A copy of the wrapper in a tree with no tests/bats/lib stands in for a
    # checkout whose submodules were never initialised.
    local fake="${TEST_TEMP_HOME}/fake-dotfiles"
    mkdir -p "${fake}/shell-common/tools/custom"
    cp "$WRAPPER" "${fake}/shell-common/tools/custom/bats.sh"
    ln -sf "${fake}/shell-common/tools/custom/bats.sh" "${LINK_BIN}/bats"
    _bare bats --version
    assert_failure 1
    assert_output --partial "${fake}/tests/bats/lib/bats-core/bin/bats"
}
