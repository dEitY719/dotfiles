#!/usr/bin/env bats
# tests/bats/functions/internal_hosts.bats
# #1944: ghes_mirror / git_ssh_check read the GHES host from DOTFILES_GHES_HOST
# (shell-common/env/internal.local.sh) instead of a tracked literal. With the
# variable set they must issue the same commands as before; unset, they warn.
# Only fake placeholder hosts appear here.

load '../test_helper'

setup() {
    setup_isolated_home
    STUB_BIN="$HOME/stub-bin"
    STUB_LOG="$HOME/stub.log"
    mkdir -p "$STUB_BIN" "$HOME/.ssh"
    : >"$HOME/.ssh/id_ed25519"
    : >"$HOME/.ssh/id_ed25519.pub"
    printf '#!/bin/sh\necho "256 SHA256:x %s/.ssh/id_ed25519 (ED25519)"\n' "$HOME" >"$STUB_BIN/ssh-add"
    printf '#!/bin/sh\necho "ssh $*" >>"%s"\nexit 0\n' "$STUB_LOG" >"$STUB_BIN/ssh"
    printf '#!/bin/sh\necho "gh $*" >>"%s"\necho mirror-user\n' "$STUB_LOG" >"$STUB_BIN/gh"
    chmod +x "$STUB_BIN"/*
}

teardown() {
    teardown_isolated_home
}

@test "git_ssh_check: DOTFILES_GHES_HOST set -> ssh -T git@<host>" {
    run_in_bash "export PATH='$STUB_BIN':\$PATH DOTFILES_GHES_HOST=ghes.example.invalid; git_ssh_check"
    assert_success
    assert_output --partial "All SSH checks passed"
    run cat "$STUB_LOG"
    assert_output "ssh -T git@ghes.example.invalid"
}

@test "git_ssh_check: DOTFILES_GHES_HOST unset -> warn, no ssh call, rc 1" {
    run_in_bash "export PATH='$STUB_BIN':\$PATH; unset DOTFILES_GHES_HOST; git_ssh_check"
    assert_failure
    assert_output --partial "DOTFILES_GHES_HOST not set"
    [ ! -e "$STUB_LOG" ]
}

@test "ghes_mirror: DOTFILES_GHES_HOST set -> default GHES URL from gh api login" {
    run_in_bash "export PATH='$STUB_BIN':\$PATH DOTFILES_GHES_HOST=ghes.example.invalid
        printf '\n\nn\n' | ghes_mirror"
    assert_success
    assert_output --partial "https://ghes.example.invalid/mirror-user/visuals-skills"
    assert_output --partial "Aborted."
    run cat "$STUB_LOG"
    assert_output "gh api --hostname ghes.example.invalid user --jq .login"
}

@test "ghes_mirror: DOTFILES_GHES_HOST unset -> warn, empty URL rejected" {
    run_in_bash "export PATH='$STUB_BIN':\$PATH; unset DOTFILES_GHES_HOST
        printf '\n\n' | ghes_mirror"
    assert_failure
    assert_output --partial "DOTFILES_GHES_HOST not set"
    assert_output --partial "GHES repo URL is required."
    [ ! -e "$STUB_LOG" ]
}
