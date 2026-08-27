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
#
# T9-T14 cover `_gh_host_from_url` (issue #1403) — the host read out of a
# remote URL rather than out of the PC's setup-mode.
#
# T15-T17 cover `_gh_match_known_host`'s boundary anchoring (PR #1404
# review) — a substring-only glob also matches near-miss hosts like
# `notgithub.com` or `github.com.evil.net`; these pin the rejection.

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
# T9-T14: _gh_host_from_url — host read out of the remote URL (issue #1403)
#
# `_gh_resolve_host` answers "which host does this PC default to"; this
# function answers "which host does *this remote URL* name". They can
# legitimately disagree (internal PC: origin=GHE, upstream=github.com), so
# a skill that resolved owner/repo from a URL must take GH_HOST from the
# same URL — that pairing is what makes the #1403 wrong-host query
# impossible.
# ---------------------------------------------------------------------------

@test "T9: https github.com URL -> github.com" {
    run_in_bash '_gh_host_from_url "https://github.com/dEitY719/dotfiles.git"'
    assert_success
    assert_output "github.com"
}

@test "T10: git@ GHE URL -> github.samsungds.net" {
    run_in_bash '_gh_host_from_url "git@github.samsungds.net:byoungwoo-yoon/dotfiles.git"'
    assert_success
    assert_output "github.samsungds.net"
}

@test "T11: ssh:// GHE URL -> github.samsungds.net" {
    run_in_bash '_gh_host_from_url "ssh://git@github.samsungds.net/owner/repo.git"'
    assert_success
    assert_output "github.samsungds.net"
}

@test "T12: non-github URL is rejected with exit 1" {
    run_in_bash '_gh_host_from_url "https://gitlab.com/owner/repo" 2>&1'
    assert_failure
    assert_output --partial "not a github remote"
}

@test "T13: empty URL is rejected with exit 1" {
    run_in_bash '_gh_host_from_url "" 2>&1'
    assert_failure
    assert_output --partial "empty remote URL"
}

@test "T14: URL host wins over the PC setup-mode (the #1403 invariant)" {
    # internal PC (setup-mode -> GHE) working on the pull-only github.com
    # upstream: _gh_resolve_host says GHE, but the remote URL says
    # github.com and the URL is what `gh` must be pointed at.
    echo "internal" > "$HOME/.dotfiles-setup-mode"
    run_in_bash '_gh_resolve_host; _gh_host_from_url "https://github.com/dEitY719/dotfiles.git"'
    assert_success
    assert_line --index 0 "github.samsungds.net"
    assert_line --index 1 "github.com"
}

# ---------------------------------------------------------------------------
# T15-T17: near-miss hosts (PR #1404 review, codex/agy) — a plain
# `*github.com*` substring glob also matches these; the boundary-anchored
# `_gh_match_known_host` must reject all three.
# ---------------------------------------------------------------------------

@test "T15: notgithub.com (substring near-miss) is rejected, not misread as github.com" {
    run_in_bash '_gh_host_from_url "https://notgithub.com/owner/repo.git" 2>&1'
    assert_failure
    assert_output --partial "not a github remote"
}

@test "T16: github.com.evil.net (suffix near-miss) is rejected" {
    run_in_bash '_gh_host_from_url "https://github.com.evil.net/owner/repo.git" 2>&1'
    assert_failure
    assert_output --partial "not a github remote"
}

@test "T17: notgithub.com is also rejected by _gh_parse_owner_repo_url" {
    run_in_bash '_gh_parse_owner_repo_url "https://notgithub.com/owner/repo.git" 2>&1'
    assert_failure
    assert_output --partial "not a github remote"
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

@test "zsh: _gh_host_from_url handles GHE https" {
    run_in_zsh '_gh_host_from_url "https://github.samsungds.net/owner/repo.git"'
    assert_success
    assert_output "github.samsungds.net"
}

@test "zsh: _gh_host_from_url handles git@ github.com" {
    run_in_zsh '_gh_host_from_url "git@github.com:dEitY719/dotfiles.git"'
    assert_success
    assert_output "github.com"
}

# ---------------------------------------------------------------------------
# PR #704 review (gemini-code-assist, critical) — non-interactive sourcing.
# The original gh_host.sh shipped with an interactive guard that returned 0
# before defining the helpers when the file was sourced from a non-interactive
# shell without DOTFILES_FORCE_INIT. Hooks and one-shot scripts hit this and
# saw `_gh_resolve_host: command not found`. The guard was removed because
# gh_host.sh has no file-scope side effects (CLAUDE.md only mandates the
# guard for files that produce output). This test pins the contract — the
# functions MUST be defined after a bare `. gh_host.sh` in `bash -c`.
# ---------------------------------------------------------------------------

@test "non-interactive bash -c without DOTFILES_FORCE_INIT defines the helpers" {
    run bash -c "
        unset DOTFILES_FORCE_INIT
        . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_host.sh'
        command -v _gh_resolve_host >/dev/null && echo resolve_ok
        command -v _gh_parse_owner_repo_url >/dev/null && echo parse_ok
        command -v _gh_host_from_url >/dev/null && echo host_from_url_ok
    "
    assert_success
    assert_output --partial "resolve_ok"
    assert_output --partial "parse_ok"
    assert_output --partial "host_from_url_ok"
}

# ---------------------------------------------------------------------------
# Issue #718 — disk fallback when `_dotfiles_setup_mode` function is absent.
#
# Reproduces the hook context: `claude/hooks/post-gh-pr-create.sh` sources
# only `gh_host.sh` (NOT the integrations layer that defines
# `_dotfiles_setup_mode`). Before #718 this path always returned
# `github.com`, masking `internal` PCs' GHE host and breaking the post-PR
# board-sync regex. The fix adds a `~/.dotfiles-setup-mode` file fallback,
# tested here with a clean `env -i` bash so neither the function nor any
# parent-shell env can leak in.
# ---------------------------------------------------------------------------

@test "#718: function present -> function result wins over disk (no regression)" {
    echo "external" > "$HOME/.dotfiles-setup-mode"
    # When _dotfiles_setup_mode is in scope and returns 'internal', the
    # function MUST win — even if the disk file disagrees. This pins
    # the "function-first" precedence.
    run bash --noprofile --norc -c "
        export HOME='$HOME'
        _dotfiles_setup_mode() { echo internal; }
        . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_host.sh'
        _gh_resolve_host
    "
    assert_success
    assert_output "github.samsungds.net"
}

@test "#718: function absent + setup-mode=internal on disk -> GHE (hook context)" {
    echo "internal" > "$HOME/.dotfiles-setup-mode"
    # env -i strips the parent shell so _dotfiles_setup_mode cannot leak in.
    # PATH must be preserved or `bash`/`tr` won't resolve.
    run env -i "HOME=$HOME" "PATH=$PATH" bash --noprofile --norc -c "
        . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_host.sh'
        _gh_resolve_host
    "
    assert_success
    assert_output "github.samsungds.net"
}

@test "#718: function absent + setup-mode file absent -> github.com" {
    rm -f "$HOME/.dotfiles-setup-mode"
    run env -i "HOME=$HOME" "PATH=$PATH" bash --noprofile --norc -c "
        . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_host.sh'
        _gh_resolve_host
    "
    assert_success
    assert_output "github.com"
}

# ---------------------------------------------------------------------------
# #1454 foreign-checkout guard, propagated to this file by issue #1505.
#
# Mirrors tests/bats/functions/gh_pr_review.bats — zsh is the case that
# matters: the guard reads ${BASH_SOURCE[0]}, which bash always populated but
# zsh never does, so before #1454 the zsh path self-disabled on its first
# line. The file is re-sourced explicitly rather than read off the loader's
# own pass because both loaders source with `2>/dev/null` (safe_source /
# load_category), which would swallow the very stderr under test.
# ---------------------------------------------------------------------------

_setup_foreign_home_1505() {
    FOREIGN_HOME_1505="$TEST_TEMP_HOME/foreign-home-1505"
    mkdir -p "$FOREIGN_HOME_1505/dotfiles"
    git -C "$FOREIGN_HOME_1505/dotfiles" init -q -b main
    git -C "$FOREIGN_HOME_1505/dotfiles" -c user.email=t@t -c user.name=t \
        commit --allow-empty -q -m init
    export HOME="$FOREIGN_HOME_1505"
}

@test "zsh: #1505 foreign-checkout guard warns when gh_host.sh is sourced under zsh" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not available"
    command -v git >/dev/null 2>&1 || skip "git not available"

    _setup_foreign_home_1505
    run_in_zsh '. "$SHELL_COMMON/functions/gh_host.sh"'
    assert_success
    assert_output --partial "[WARN] dotfiles: loaded from a foreign checkout"
    assert_output --partial "shell-common/functions/gh_host.sh"
}

@test "bash: #1505 foreign-checkout guard warns when gh_host.sh is sourced under bash" {
    command -v git >/dev/null 2>&1 || skip "git not available"

    _setup_foreign_home_1505
    run_in_bash '. "$SHELL_COMMON/functions/gh_host.sh"'
    assert_success
    assert_output --partial "[WARN] dotfiles: loaded from a foreign checkout"
    assert_output --partial "shell-common/functions/gh_host.sh"
}
