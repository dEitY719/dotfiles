#!/usr/bin/env bats
# tests/bats/functions/gcp.bats
# Tests for issue #697 — gcp_* family unified under the 'gcp <verb>' Type 2A
# dispatcher (docs/.ssot/command-design-pattern.md §4).
#
# Behavior under test:
#   - 'gcp' is a function (dispatcher), not the bash-only integrations version.
#   - Private sub-functions _gcp_scan/_gcp_theirs/_gcp_ours/_gcp_author/_gcp_pick
#     exist and are wired through the dispatcher.
#   - Help is reachable as 'gcp', 'gcp -h', 'gcp --help', 'gcp help',
#     'gcp help <section>', 'gcp help --list', 'gcp help --all'.
#   - The deprecated forms 'gcp_scan', 'gcp-scan', 'gcp_theirs', 'gcp_ours',
#     'gcp_author' still work as aliases routing through 'gcp <verb>'.
#   - 'gcp <unknown-verb>' returns 1 with 'Run: gcp help' hint (Type 2A §6).
#   - 'gcp <committish>' is bridged to 'gcp pick' with a deprecation warning.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# Function / alias existence
# ---------------------------------------------------------------------------

@test "bash: gcp dispatcher function exists" {
    run_in_bash 'declare -f gcp >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _gcp_scan private function exists" {
    run_in_bash 'declare -f _gcp_scan >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _gcp_theirs private function exists" {
    run_in_bash 'declare -f _gcp_theirs >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _gcp_ours private function exists" {
    run_in_bash 'declare -f _gcp_ours >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _gcp_author private function exists" {
    run_in_bash 'declare -f _gcp_author >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _gcp_pick private function exists" {
    run_in_bash 'declare -f _gcp_pick >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: gcp_help standalone help exists" {
    run_in_bash 'declare -f gcp_help >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: gcp_scan alias maps to 'gcp scan'" {
    run_in_bash 'alias gcp_scan'
    assert_success
    assert_output --partial "gcp scan"
}

@test "bash: gcp-scan alias maps to 'gcp scan'" {
    run_in_bash 'alias gcp-scan'
    assert_success
    assert_output --partial "gcp scan"
}

@test "bash: gcp_theirs alias maps to 'gcp theirs'" {
    run_in_bash 'alias gcp_theirs'
    assert_success
    assert_output --partial "gcp theirs"
}

@test "bash: gcp_ours alias maps to 'gcp ours'" {
    run_in_bash 'alias gcp_ours'
    assert_success
    assert_output --partial "gcp ours"
}

@test "bash: gcp_author alias maps to 'gcp author'" {
    run_in_bash 'alias gcp_author'
    assert_success
    assert_output --partial "gcp author"
}

@test "bash: gcp-help alias maps to gcp_help" {
    run_in_bash 'alias gcp-help'
    assert_success
    assert_output --partial "gcp_help"
}

# ---------------------------------------------------------------------------
# Help entry points
# ---------------------------------------------------------------------------

@test "help: bare 'gcp' invocation shows help (no error)" {
    run_in_bash 'gcp'
    assert_success
    assert_output --partial "Usage: gcp help"
}

@test "help: 'gcp -h' shows help" {
    run_in_bash 'gcp -h'
    assert_success
    assert_output --partial "Usage: gcp help"
}

@test "help: 'gcp --help' shows help" {
    run_in_bash 'gcp --help'
    assert_success
    assert_output --partial "Usage: gcp help"
}

@test "help: 'gcp help' shows help" {
    run_in_bash 'gcp help'
    assert_success
    assert_output --partial "Usage: gcp help"
}

@test "help: 'gcp help scan' shows section detail" {
    run_in_bash 'gcp help scan'
    assert_success
    assert_output --partial "scan"
}

@test "help: 'gcp help --list' lists sections" {
    run_in_bash 'gcp help --list'
    assert_success
    assert_output --partial "scan"
    assert_output --partial "theirs"
    assert_output --partial "ours"
    assert_output --partial "author"
    assert_output --partial "pick"
}

@test "help: summary lists all 5 verbs" {
    run_in_bash 'gcp help'
    assert_output --partial "scan"
    assert_output --partial "theirs"
    assert_output --partial "ours"
    assert_output --partial "author"
    assert_output --partial "pick"
}

# ---------------------------------------------------------------------------
# Dispatcher behavior
# ---------------------------------------------------------------------------

@test "dispatch: unknown sub-command returns error + 'Run: gcp help' hint" {
    run_in_bash 'gcp definitely-not-a-verb'
    assert_failure
    assert_output --partial "Unknown command"
    assert_output --partial "Run: gcp help"
}

@test "dispatch: 'gcp pick' (no args) prints usage and returns 1" {
    run_in_bash 'gcp pick'
    assert_failure
    assert_output --partial "gcp pick"
}

@test "dispatch: 'gcp theirs' (no args) prints usage and returns 1" {
    run_in_bash 'gcp theirs'
    assert_failure
    assert_output --partial "gcp theirs"
}

@test "dispatch: 'gcp author' (no args) prints usage and returns 1" {
    run_in_bash 'gcp author'
    assert_failure
    assert_output --partial "gcp author"
}

# ---------------------------------------------------------------------------
# Bare-form deprecation bridge: 'gcp <committish>' -> '_gcp_pick' + warning
# ---------------------------------------------------------------------------

@test "dispatch: bare committish triggers deprecation bridge" {
    # Stub `git cherry-pick` so the deprecation warning fires inside the
    # dispatcher but the actual cherry-pick is a no-op — keeps the working
    # tree clean across test runs (no leftover CHERRY_PICK_HEAD state).
    # `git rev-parse` (used by _gcp_committish_p) must still pass through to
    # the real git so the heuristic correctly classifies HEAD as commit-ish.
    run_in_bash '
        cd "$DOTFILES_ROOT"
        git() {
            if [ "$1" = "cherry-pick" ]; then
                echo "stubbed: git cherry-pick $*" >&2
                return 1
            fi
            command git "$@"
        }
        gcp "$(command git rev-parse HEAD)"
    '
    assert_output --partial "Deprecated: bare 'gcp <commit>'"
    assert_output --partial "Use: gcp pick"
}

@test "dispatch: non-committish unknown arg does NOT bridge to pick" {
    run_in_bash 'cd "$DOTFILES_ROOT" && gcp not-a-real-commit-or-verb'
    assert_failure
    assert_output --partial "Unknown command"
    refute_output --partial "Deprecated:"
}

# ---------------------------------------------------------------------------
# Loader sanity: tools/integrations/git.sh no longer defines gcp
# (would shadow the dispatcher since integrations/ loads after functions/)
# ---------------------------------------------------------------------------

@test "loader: 'gcp' resolves to the dispatcher in shell-common/functions/gcp.sh" {
    run_in_bash 'declare -f gcp | head -1'
    assert_success
    assert_output --partial "gcp"
}

@test "loader: tools/integrations/git.sh no longer declares the gcp family" {
    run grep -E '^(gcp|gcp_theirs|gcp_ours|gcp_author|_git_cherry_pick) *\(\)' \
        "${DOTFILES_ROOT}/shell-common/tools/integrations/git.sh"
    assert_failure
}
