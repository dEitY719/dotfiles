#!/usr/bin/env bats
# tests/bats/git/test_hooks_global_local_ci.bats
#
# Warn-only local CI in the global pre-push wrapper (git/global-hooks/
# lib/local-ci.sh). The wrapper finds scripts/ci.sh relative to its own real
# path, so each test copies git/global-hooks into a fake dotfiles tree whose
# scripts/ci.sh is a stub recording its argv and exiting $STUB_CI_RC.

load '../test_helper'
load 'hook_test_env'
load 'hook_cases'

setup() {
    hook_test_setup
    unset CI_LOCAL_SKIP CI_LOCAL_OWNERS CI_LOCAL_TIMEOUT
    FAKE="$TEST_TEMP_HOME/fake-dotfiles"
    mkdir -p "$FAKE/git" "$FAKE/scripts"
    cp -R "${DOTFILES_ROOT}/git/global-hooks" "$FAKE/git/"
    cat >"$FAKE/scripts/ci.sh" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >"$TEST_TEMP_HOME/ci.calls"
echo 'FAIL  bats: stub suite'
exit \${STUB_CI_RC:-0}
EOF
    GLOBAL_HOOKS_DIR="$FAKE/git/global-hooks"
    REPO="$TEST_TEMP_HOME/repo"
    make_plain_repo "$REPO"
    SHA=$(git -C "$REPO" rev-parse HEAD)
    REFS="refs/heads/main $SHA refs/heads/main $ZERO_SHA"
}

teardown() {
    hook_test_teardown
}

# push <url> [hook-exit-code]: run the wrapper with a recording project hook.
push() {
    install_recording_project_hook "$REPO" pre-push "${2:-0}"
    run_global_hook "$REPO" pre-push origin "$1" <<<"$REFS"
}

@test "local-ci: allowlisted owner (ssh) runs ci.sh on the pushed sha, no --post" {
    push "git@github.com:dEitY719/x.git"
    [ "$(cat "$TEST_TEMP_HOME/ci.calls")" = "--repo $REPO --sha $SHA" ]
    grep -q "DELEGATED:origin git@github.com:dEitY719/x.git" "$REPO/.delegated"
}

@test "local-ci: owner match is case-insensitive over https and GHES hosts" {
    push "https://github.example.com/deity719/x.git"
    [ -f "$TEST_TEMP_HOME/ci.calls" ]
}

@test "local-ci: ssh:// URL with user and port is parsed" {
    push "ssh://git@ghes.internal:2222/dEitY719/x.git"
    [ -f "$TEST_TEMP_HOME/ci.calls" ]
}

@test "local-ci: other owner does nothing at all" {
    push "git@github.com:dev404/x.git"
    [ ! -e "$TEST_TEMP_HOME/ci.calls" ]
    [[ "$WRAPPER_OUT" != *"local CI"* ]]
    grep -q "DELEGATED" "$REPO/.delegated"
}

@test "local-ci: CI_LOCAL_OWNERS extends the allowlist (comma or space)" {
    CI_LOCAL_OWNERS="foo, dev404 bar" push "https://github.com/dev404/x"
    [ -f "$TEST_TEMP_HOME/ci.calls" ]
}

@test "local-ci: ci.sh failure only warns, exit code stays 0" {
    STUB_CI_RC=1 push "git@github.com:dEitY719/x.git"
    [[ "$WRAPPER_OUT" == *"WARNING: local CI failed"* ]]
    [[ "$WRAPPER_OUT" == *"FAIL  bats: stub suite"* ]]
    [[ "$WRAPPER_OUT" == *"--post"* ]]
}

@test "local-ci: missing ci.sh only warns" {
    rm "$FAKE/scripts/ci.sh"
    push "git@github.com:dEitY719/x.git"
    [[ "$WRAPPER_OUT" == *"not found"* ]]
}

@test "local-ci: CI_LOCAL_SKIP=1 skips" {
    CI_LOCAL_SKIP=1 push "git@github.com:dEitY719/x.git"
    [ ! -e "$TEST_TEMP_HOME/ci.calls" ]
}

@test "local-ci: branch deletion only is skipped" {
    REFS="(delete) $ZERO_SHA refs/heads/old $SHA"
    push "git@github.com:dEitY719/x.git"
    [ ! -e "$TEST_TEMP_HOME/ci.calls" ]
}

@test "local-ci: delegate failure keeps its exit code and skips ci.sh" {
    run push "git@github.com:dEitY719/x.git" 3
    [ "$status" -eq 3 ]
    [ ! -e "$TEST_TEMP_HOME/ci.calls" ]
}

@test "local-ci: project hook still receives the buffered stdin" {
    install_stdin_recording_project_hook "$REPO" pre-push
    run_global_hook "$REPO" pre-push origin "git@github.com:dEitY719/x.git" <<<"$REFS"
    grep -qx "STDIN:$REFS" "$REPO/.delegated"
}

@test "local-ci: timeout guard stops a hanging ci.sh without blocking" {
    printf '#!/bin/bash\nsleep 30\n' >"$FAKE/scripts/ci.sh"
    CI_LOCAL_TIMEOUT=1 push "git@github.com:dEitY719/x.git"
    [[ "$WRAPPER_OUT" == *"timed out"* ]]
}
