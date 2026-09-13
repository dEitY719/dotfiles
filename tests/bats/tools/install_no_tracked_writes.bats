#!/usr/bin/env bats
# tests/bats/tools/install_no_tracked_writes.bats
# install-* scripts must not write through the dotfiles symlinks (#1802).
#
# ~/.bashrc, ~/.zshrc and ~/.npmrc are symlinks into this repo. A write-through
# (`>>`, `npm config set`) edits a tracked file; a rename-style edit (`sed -i`)
# replaces the symlink with a plain file. The settings those installers wrote
# already live in npm/npmrc.*, zsh/zshrc and bash/main.bash, so the writes are
# removed, and install_agy.sh reverts what the upstream installer changes.

load '../test_helper'

TOOLS_DIR="${DOTFILES_ROOT}/shell-common/tools/custom"
INSTALL_AGY_SCRIPT="${TOOLS_DIR}/install_agy.sh"

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# Non-comment lines of every install*.sh, prefixed with file:line.
_install_code_lines() {
    grep -nE '.' "$TOOLS_DIR"/install*.sh | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'
}

# --- static guards -----------------------------------------------------------

@test "no install script runs npm config set prefix" {
    run bash -c "$(declare -f _install_code_lines); TOOLS_DIR='$TOOLS_DIR'; _install_code_lines | grep -E 'npm config set prefix'"
    assert_failure
}

@test "no install script appends to ~/.bashrc or ~/.zshrc" {
    run bash -c "$(declare -f _install_code_lines); TOOLS_DIR='$TOOLS_DIR'; _install_code_lines | grep -E '>>[[:space:]]*\"?(\\\$\\{?HOME\\}?|~)/\\.(bashrc|zshrc)'"
    assert_failure
}

@test "no install script runs sed -i on an rc file" {
    run bash -c "$(declare -f _install_code_lines); TOOLS_DIR='$TOOLS_DIR'; _install_code_lines | grep -E 'sed -i' | grep -E 'zshrc|bashrc'"
    assert_failure
}

@test "install_fzf: macOS shell integration does not update rc files" {
    run grep -c -- '--no-update-rc' "$TOOLS_DIR/install_fzf.sh"
    assert_success
    run grep -c 'opt/fzf/install" --all' "$TOOLS_DIR/install_fzf.sh"
    assert_failure
}

# --- install_agy.sh rc restore guard -----------------------------------------

# Commit main.bash / zshrc into a throwaway repo and symlink ~/.bashrc /
# ~/.zshrc at them, mirroring setup.sh.
_make_tracked_rc_repo() {
    local repo="$HOME/dots"
    mkdir -p "$repo"
    git -C "$repo" init -q
    printf 'bash original\n' > "$repo/main.bash"
    printf 'zsh original\n' > "$repo/zshrc"
    git -C "$repo" add main.bash zshrc
    git -C "$repo" -c user.name=t -c user.email=t@t commit -qm init
    ln -s "$repo/main.bash" "$HOME/.bashrc"
    ln -s "$repo/zshrc" "$HOME/.zshrc"
}

run_agy_guard() {
    run_sourced_tool_script "$TOOLS_DIR" "$INSTALL_AGY_SCRIPT" "
        ux_info() { printf 'INFO %s\n' \"\$*\"; }
        ux_warning() { printf 'WARN %s\n' \"\$*\"; }
        $1
    "
}

@test "agy guard: rc file clean before install is reverted after" {
    _make_tracked_rc_repo

    run_agy_guard '
        snap="$(_agy_rc_snapshot)"
        printf "export PATH=agy\n" >> "$HOME/.bashrc"
        _agy_restore_rc_files "$snap"
    '
    assert_success
    assert_output --partial "Reverted agy installer edits to $HOME/dots/main.bash"
    [ "$(cat "$HOME/dots/main.bash")" = "bash original" ]
    [ -L "$HOME/.bashrc" ]
}

@test "agy guard: rc file dirty before install is left untouched" {
    _make_tracked_rc_repo
    printf 'user edit\n' >> "$HOME/dots/zshrc"

    run_agy_guard '
        snap="$(_agy_rc_snapshot)"
        printf "export PATH=agy\n" >> "$HOME/.zshrc"
        _agy_restore_rc_files "$snap"
    '
    assert_success
    assert_output --partial "WARN"
    refute_output --partial "Reverted"
    [ "$(cat "$HOME/dots/zshrc")" = "zsh original
user edit
export PATH=agy" ]
}

@test "agy guard: rc files that are not symlinks are skipped" {
    printf 'plain\n' > "$HOME/.bashrc"

    run_agy_guard '_agy_rc_snapshot'
    assert_success
    assert_output ""
}

@test "agy main: snapshots before the installer and restores after" {
    run grep -c '_agy_rc_snapshot' "$INSTALL_AGY_SCRIPT"
    assert_success
    run grep -cE '_agy_restore_rc_files "\$' "$INSTALL_AGY_SCRIPT"
    assert_success
}
