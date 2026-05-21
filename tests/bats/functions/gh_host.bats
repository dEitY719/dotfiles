#!/usr/bin/env bats
# tests/bats/functions/gh_host.bats
# Coverage for shell-common/functions/gh_host.sh introduced in issue #703.
#
# T1-T4 cover `_gh_resolve_host`'s mode → host mapping (with `internal`
# being the only one that routes to GHE; everything else stays on
# `github.com` to preserve external/public/missing-file regression-zero).
#
# T5-T8 cover `_gh_parse_owner_repo_url` across both hosts and the
# common URL shapes (https://, git@host:, plus a non-github rejection).

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# T1-T4: _gh_resolve_host — mode-to-host mapping
# ---------------------------------------------------------------------------

@test "T1: _dotfiles_setup_mode=internal -> github.samsungds.net" {
    echo "internal" > "$HOME/.dotfiles-setup-mode"
    run_in_bash '_gh_resolve_host'
    assert_success
    assert_output "github.samsungds.net"
}

@test "T2: _dotfiles_setup_mode=external -> github.com" {
    echo "external" > "$HOME/.dotfiles-setup-mode"
    run_in_bash '_gh_resolve_host'
    assert_success
    assert_output "github.com"
}

@test "T3: _dotfiles_setup_mode=public -> github.com" {
    echo "public" > "$HOME/.dotfiles-setup-mode"
    run_in_bash '_gh_resolve_host'
    assert_success
    assert_output "github.com"
}

@test "T4: setup-mode file missing -> github.com (fallback)" {
    # No setup-mode file in $HOME — fresh install.
    run_in_bash '_gh_resolve_host'
    assert_success
    assert_output "github.com"
}

# ---------------------------------------------------------------------------
# T5-T8: _gh_parse_owner_repo_url — URL parser
# ---------------------------------------------------------------------------

@test "T5: https github.com URL -> owner/repo" {
    run_in_bash '_gh_parse_owner_repo_url "https://github.com/dEitY719/dotfiles.git"'
    assert_success
    assert_output "dEitY719/dotfiles"
}

@test "T6: https GHE URL -> owner/repo" {
    run_in_bash '_gh_parse_owner_repo_url "https://github.samsungds.net/byoungwoo-yoon/dotfiles.git"'
    assert_success
    assert_output "byoungwoo-yoon/dotfiles"
}

@test "T7: git@host: GHE URL -> owner/repo" {
    run_in_bash '_gh_parse_owner_repo_url "git@github.samsungds.net:byoungwoo-yoon/dotfiles.git"'
    assert_success
    assert_output "byoungwoo-yoon/dotfiles"
}

@test "T8: non-github URL is rejected with exit 1" {
    run_in_bash '_gh_parse_owner_repo_url "https://gitlab.com/owner/repo" 2>&1'
    assert_failure
    assert_output --partial "not a github remote"
}

# ---------------------------------------------------------------------------
# Extra coverage for url shapes that the issue lists in the design doc
# ---------------------------------------------------------------------------

@test "T5b: ssh:// github.com URL -> owner/repo" {
    run_in_bash '_gh_parse_owner_repo_url "ssh://git@github.com/dEitY719/dotfiles.git"'
    assert_success
    assert_output "dEitY719/dotfiles"
}

@test "T6b: git@github.com: URL -> owner/repo" {
    run_in_bash '_gh_parse_owner_repo_url "git@github.com:dEitY719/dotfiles.git"'
    assert_success
    assert_output "dEitY719/dotfiles"
}

@test "empty URL is rejected with exit 1" {
    run_in_bash '_gh_parse_owner_repo_url "" 2>&1'
    assert_failure
    assert_output --partial "empty remote URL"
}

@test "github URL without owner/repo suffix is rejected" {
    run_in_bash '_gh_parse_owner_repo_url "https://github.com/" 2>&1'
    assert_failure
    assert_output --partial "Could not parse owner/repo"
}

# ---------------------------------------------------------------------------
# zsh coverage — the helper must work in both shells (POSIX compliance)
# ---------------------------------------------------------------------------

@test "zsh: _gh_resolve_host returns github.com by default" {
    run_in_zsh '_gh_resolve_host'
    assert_success
    assert_output "github.com"
}

@test "zsh: _gh_resolve_host respects internal mode" {
    echo "internal" > "$HOME/.dotfiles-setup-mode"
    run_in_zsh '_gh_resolve_host'
    assert_success
    assert_output "github.samsungds.net"
}

@test "zsh: _gh_parse_owner_repo_url handles GHE https" {
    run_in_zsh '_gh_parse_owner_repo_url "https://github.samsungds.net/owner/repo.git"'
    assert_success
    assert_output "owner/repo"
}
