#!/usr/bin/env bats
# tests/bats/functions/herdr_agent_lookup_readonly.bats
# NF-2 read-only guard for shell-common/lib/herdr_agent_lookup.sh, the
# "which herdr agent sits on this worktree?" SSOT (#1569).
#
# #2200: these two @tests came from tests/bats/skills/gh_pr_merge_herdr_notify.bats.
# The hint itself (gh-pr:merge Step 4) moved to the gh-pr-skills repo with its
# tests, but its read-only guarantee is only as strong as this file it sources,
# so the guard on this file stays next to it.

load '../test_helper'

LIB="${_BATS_REAL_DOTFILES_ROOT}/shell-common/lib/herdr_agent_lookup.sh"

@test "herdr lookup (NF-2): the SSOT contains no state-changing invocation" {
    [ -r "$LIB" ]
    run bash -c "grep -n -e 'tab close' -e 'worktree remove' -e 'agent start' -e 'tab create' '$LIB'"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "herdr lookup (NF-2): every herdr call in the SSOT's code is the read-only agent list" {
    # Comment lines are dropped: the rationale legitimately says things like
    # "herdr could not be asked".
    run bash -c "grep -v '^[[:space:]]*#' '$LIB' | grep -oE 'herdr [a-z]+ [a-z]+' | sort -u"
    assert_output 'herdr agent list'
}
