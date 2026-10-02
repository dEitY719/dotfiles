#!/usr/bin/env bats
# tests/bats/functions/graphify_setup.bats
# Coverage for graphify-setup (shell-common/functions/graphify_setup.sh -> tools/custom/graphify_setup.sh):
# the .gitignore entry is added once, and the per-project graphify steps run
# in the target directory. `graphify` is stubbed on PATH and logs its calls.

load '../test_helper'

setup() {
    setup_isolated_home
    STUB_BIN="$(mktemp -d)"
    export PATH="${STUB_BIN}:/usr/bin:/bin"
    printf '#!/bin/sh\necho "$PWD: $*" >> "%s/calls"\n' "$STUB_BIN" > "${STUB_BIN}/graphify"
    chmod +x "${STUB_BIN}/graphify"
    PROJECT="$HOME/proj"
    mkdir -p "$PROJECT"
    git -C "$PROJECT" init -q
}

teardown() {
    teardown_isolated_home
    rm -rf "$STUB_BIN"
}

_run_setup() {
    run bash -c ". '${SHELL_COMMON}/functions/graphify_setup.sh'; graphify_setup \"\$1\"" _ "$1"
}

@test "graphify-setup: ignores graphify-out once and runs project steps in the target dir" {
    printf 'node_modules' > "$PROJECT/.gitignore"
    _run_setup "$PROJECT"
    assert_success
    _run_setup "$PROJECT"
    assert_success
    assert_output --partial "graphify-out/ already ignored"
    [ "$(cat "$PROJECT/.gitignore")" = "$(printf 'node_modules\ngraphify-out/')" ]
    grep -q "^${PROJECT}: claude install$" "${STUB_BIN}/calls"
    grep -q "^${PROJECT}: update \.$" "${STUB_BIN}/calls"
}

@test "graphify-setup: existing graph is not rebuilt" {
    mkdir -p "$PROJECT/graphify-out"
    touch "$PROJECT/graphify-out/graph.json"
    _run_setup "$PROJECT"
    assert_success
    ! grep -q "update" "${STUB_BIN}/calls"
}

@test "graphify-setup: missing directory fails" {
    _run_setup "$HOME/nope"
    assert_failure
    assert_output --partial "No such directory"
}
