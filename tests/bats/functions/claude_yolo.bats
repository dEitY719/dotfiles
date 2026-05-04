#!/usr/bin/env bats
# tests/bats/functions/claude_yolo.bats
# Test claude_yolo function: exists, alias maps correctly, and the
# main-branch auto-switch behavior works. Uses a PATH-prepended shim
# so `command claude ...` hits a fake binary that records the
# current branch instead of invoking the real claude CLI.

load '../test_helper'

setup() {
    setup_isolated_home
    _install_claude_shim
    _setup_fake_repo_on_main
    # Multi-account dispatcher (issue #287) requires the account directory
    # to exist. These tests cover the default (personal) path.
    mkdir -p "$HOME/.claude-personal"
}

teardown() {
    teardown_isolated_home
}

# Install a fake `claude` binary into a dir we prepend to PATH. It
# records the branch at invocation time into $MARKER, so tests can
# assert what branch `claude_yolo` actually handed control to.
_install_claude_shim() {
    export STUB_BIN="$TEST_TEMP_HOME/bin"
    export MARKER="$TEST_TEMP_HOME/marker"
    mkdir -p "$STUB_BIN"
    cat > "$STUB_BIN/claude" <<'SH'
#!/usr/bin/env bash
git symbolic-ref --short HEAD 2>/dev/null > "$MARKER" || echo "no-branch" > "$MARKER"
SH
    chmod +x "$STUB_BIN/claude"
    export PATH="$STUB_BIN:$PATH"
}

_setup_fake_repo_on_main() {
    export REPO="$TEST_TEMP_HOME/repo"
    export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test \
           GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test

    git init -q --initial-branch=main "$REPO"
    (
        cd "$REPO"
        echo seed > seed.txt
        git add seed.txt
        git commit -q -m seed
    )
}

# Run claude_yolo in bash with the shim on PATH and CWD at a given path.
_run_yolo_bash() {
    local cwd="$1"
    shift
    run bash --noprofile --norc -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        export SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_FORCE_INIT=1
        export DOTFILES_TEST_MODE=1
        export HOME='${HOME}'
        export TERM=dumb
        export PATH='${PATH}'
        export MARKER='${MARKER}'
        $*
        source '${DOTFILES_ROOT}/bash/main.bash'
        cd '${cwd}'
        claude_yolo
    "
}

# --- function and alias wiring ---

@test "bash: claude_yolo function exists" {
    run_in_bash 'declare -f claude_yolo >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: claude-yolo alias maps to claude_yolo" {
    run_in_bash 'alias claude-yolo'
    assert_success
    assert_output --partial "claude_yolo"
}

@test "zsh: claude_yolo function exists" {
    run_in_zsh 'declare -f claude_yolo >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: claude-yolo alias maps to claude_yolo" {
    run_in_zsh 'alias claude-yolo'
    assert_success
    assert_output --partial "claude_yolo"
}

# --- auto-switch behavior ---

@test "bash: claude_yolo on main auto-switches to scratch/* then invokes claude" {
    _run_yolo_bash "$REPO"
    assert_success
    run cat "$MARKER"
    assert_output --regexp '^scratch/[0-9]{4}-[0-9]{6}$'
}

@test "bash: claude_yolo on main with CLAUDE_YOLO_STAY=1 stays on main" {
    _run_yolo_bash "$REPO" "export CLAUDE_YOLO_STAY=1"
    assert_success
    run cat "$MARKER"
    assert_output "main"
}

@test "bash: claude_yolo on feature branch passes through without switching" {
    git -C "$REPO" switch -q -c feat/demo
    _run_yolo_bash "$REPO"
    assert_success
    run cat "$MARKER"
    assert_output "feat/demo"
}

@test "bash: claude_yolo outside a git repo passes through" {
    local non_repo="$TEST_TEMP_HOME/plain"
    mkdir -p "$non_repo"
    _run_yolo_bash "$non_repo"
    assert_success
    run cat "$MARKER"
    assert_output "no-branch"
}
