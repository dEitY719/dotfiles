#!/usr/bin/env bats
# tests/bats/functions/help_flag_git_claude.bats
# -h/--help on the git/claude integration commands prints help, exits 0 and
# has no side effects (#1917, follow-up of #1880). gupdel used to treat "-h"
# as a remote name and claude_accounts_unlink as a skill symlink name.

load '../test_helper'

setup() {
    setup_isolated_home
    # Stubs record any call that would reach the network / an installer.
    STUB_LOG="$HOME/stub.log"
    mkdir -p "$HOME/bin"
    for c in claude sudo; do
        printf '#!/bin/sh\necho "%s $*" >>"%s"\n' "$c" "$STUB_LOG" >"$HOME/bin/$c"
        chmod +x "$HOME/bin/$c"
    done
    # Throwaway repo: remote origin, one staged file.
    REPO="$HOME/repo"
    git init -q "$REPO"
    git -C "$REPO" remote add origin https://example.invalid/r.git
    printf 'x\n' >"$REPO/f.txt"
    git -C "$REPO" add f.txt
    # Account skills dir holding symlinks literally named -h / --help.
    mkdir -p "$HOME/.claude-personal/skills"
    ln -s /nonexistent "$HOME/.claude-personal/skills/-h"
    ln -s /nonexistent "$HOME/.claude-personal/skills/--help"
}

teardown() {
    teardown_isolated_home
}

@test "git/claude commands -h|--help: help, exit 0, no side effects (bash + zsh)" {
    local runner flag fn git_fns
    # integrations/git.sh is bash-only ([ -n "$BASH" ] || return 0).
    git_fns="gsw gf git_rm_cached gupa gupdel glub gset git_lfs_install git_lfs_track"
    for runner in run_in_bash run_in_zsh; do
        [ "$runner" = run_in_bash ] || git_fns=""
        for fn in $git_fns cltest clskip claude_accounts_rollback claude_accounts_repair \
            claude_accounts_link claude_accounts_unlink; do
            for flag in -h --help; do
                "$runner" "export PATH='$HOME/bin':\$PATH; cd '$REPO' && $fn $flag"
                assert_success
                [ -n "$output" ]
            done
        done
    done
    [ ! -e "$STUB_LOG" ]
    [ "$(git -C "$REPO" remote)" = "origin" ]
    [ "$(git -C "$REPO" diff --cached --name-only)" = "f.txt" ]
    [ ! -e "$REPO/.gitattributes" ]
    [ -L "$HOME/.claude-personal/skills/-h" ]
    [ -L "$HOME/.claude-personal/skills/--help" ]
    [ ! -e "$HOME/.claude" ]
}

@test "cltest / clskip with no argument still print usage and return 1" {
    local fn
    for fn in cltest clskip; do
        run_in_bash "$fn"
        assert_failure
        assert_output --partial "$fn"
    done
}
