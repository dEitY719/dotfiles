#!/usr/bin/env bats
# tests/bats/tools/install_no_tracked_writes.bats
# No shell script may write through the dotfiles symlinks (#1802) or pipe a
# remote installer straight into a shell (#1801).
#
# ~/.bashrc, ~/.zshrc and ~/.npmrc are symlinks into this repo. A write-through
# (`>>`, `npm config set`) edits a tracked file; a rename-style edit (`sed -i`,
# `mv`) replaces the symlink with a plain file. And `curl ... | sh` reports the
# exit code of `sh`, so a failed download runs empty input and "succeeds" --
# lib/install_helpers.sh::run_remote_installer downloads first instead.
#
# Scope is the whole repo, not just install*.sh: the same bugs turned up in
# shell-common/functions/zsh.sh, bash/setup.sh, hermes/setup.sh and
# integrations/bun.sh (#1807).

load '../test_helper'

TOOLS_DIR="${DOTFILES_ROOT}/shell-common/tools/custom"
INSTALL_AGY_SCRIPT="${TOOLS_DIR}/install_agy.sh"

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# --- static guards -----------------------------------------------------------

# Every repo *.sh line that actually executes something, prefixed file:line.
# Skipped because they are data rather than execution: tests/ (this file's own
# patterns would match themselves), comments, `: <<'DOC'` help blocks,
# arguments of the ux_*/echo/printf output functions (help text that documents
# an upstream installer is intentional), and quoted assignments holding a
# command string for display (unquoted ones stay in scope, so a
# `X=$(curl ... | bash)` still trips the guards).
_repo_code_lines() {
    find "$DOTFILES_ROOT" -name '*.sh' \
        -not -path '*/.git/*' -not -path "${DOTFILES_ROOT}/tests/*" -print0 |
        xargs -0 awk '
            FNR == 1 { doc = "" }
            doc != "" { if ($0 == doc) doc = ""; next }
            /^[[:space:]]*:[[:space:]]*<</ {
                doc = $0
                sub(/^[[:space:]]*:[[:space:]]*<<-?[[:space:]]*/, "", doc)
                gsub(/["'"'"']/, "", doc)
            }
            { print FILENAME ":" FNR ":" $0 }
        ' |
        grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' |
        grep -vE '^[^:]+:[0-9]+:[[:space:]]*(ux_(bullet(_sub)?|info|error|warning|success)|echo|printf)[[:space:]]' |
        grep -vE '^[^:]+:[0-9]+:[[:space:]]*[A-Za-z_][A-Za-z0-9_]*="'
}

# Fail, listing the offenders, if any executable line matches the ERE in $1.
_refute_code_pattern() {
    local hits
    hits="$(_repo_code_lines | grep -E "$1")" || return 0
    printf 'violating lines:\n%s\n' "$hits"
    return 1
}

@test "no script pipes a remote installer into a shell" {
    run _refute_code_pattern '(curl|wget)[^|]*\|[[:space:]]*(sh|bash)|(sh|bash) -c "\$\((curl|wget)'
    assert_success
}

@test "no script runs npm config set prefix" {
    run _refute_code_pattern 'npm config set prefix'
    assert_success
}

@test "no script appends to a symlinked rc file" {
    run _refute_code_pattern '>>[[:space:]]*"?(\$\{?HOME\}?|~)/\.(bashrc|zshrc|npmrc|bash_profile)'
    assert_success
}

@test "no script runs sed -i on a symlinked rc file" {
    run _refute_code_pattern 'sed -i[^[:space:]]*[[:space:]].*(/\.(bashrc|zshrc|npmrc)|\$\{?(bashrc|zshrc|npmrc|rc|rc_file|rcfile)\}?([^A-Za-z0-9_]|$))'
    assert_success
}

@test "no script mv/cp-renames onto a symlinked rc file" {
    run _refute_code_pattern '(mv|cp)[[:space:]].*[[:space:]]"?(\$\{?HOME\}?|~)/\.(bashrc|zshrc|npmrc|bash_profile)"?[[:space:]]*$|(mv|cp)[[:space:]]+[^|]*[[:space:]]"\$\{?(zshrc|bashrc|npmrc)\}?"[[:space:]]*$'
    assert_success
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

@test "agy guard: ~/.bash_profile is snapshotted too" {
    _make_tracked_rc_repo
    rm "$HOME/.bashrc" "$HOME/.zshrc"
    ln -s "$HOME/dots/main.bash" "$HOME/.bash_profile"

    run_agy_guard '
        snap="$(_agy_rc_snapshot)"
        printf "export PATH=agy\n" >> "$HOME/.bash_profile"
        _agy_restore_rc_files "$snap"
    '
    assert_success
    assert_output --partial "Reverted agy installer edits to $HOME/dots/main.bash"
    [ "$(cat "$HOME/dots/main.bash")" = "bash original" ]
    [ -L "$HOME/.bash_profile" ]
}

@test "agy main: snapshots before the installer and restores after" {
    run grep -c '_agy_rc_snapshot' "$INSTALL_AGY_SCRIPT"
    assert_success
    run grep -cE '_agy_restore_rc_files "\$' "$INSTALL_AGY_SCRIPT"
    assert_success
}
