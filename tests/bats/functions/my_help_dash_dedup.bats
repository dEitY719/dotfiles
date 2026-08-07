#!/usr/bin/env bats
# tests/bats/functions/my_help_dash_dedup.bats
# Regression coverage for issue #1287 — `my-help find` listed every topic twice.
#
# Root cause: the help adapter defined the dash-form name (git-help) as a real
# zsh *function* wrapping the underscore form (git_help). Both landed in
# ${(k)functions}, so _get_help_functions returned each topic twice and
# _my_help_enumerate_topic_names — which normalizes both spellings to dash form
# — emitted duplicates into the fzf candidate stream.
#
# T1-T3 pin the invariant: dash-form is an alias, never a second function.
# T4-T6 pin the user-visible symptom: no duplicate rows reach fzf.
# T7-T9 pin that the fix did not break dash-form callability, including the
#       three topics (git/gwt/gbr) whose _help_std_wrap_one special case the
#       fix removed.
# T10-T11 pin bash parity — bash was never affected and must stay unchanged.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# T1-T3: dash-form must not exist as a real function in zsh
# ---------------------------------------------------------------------------

@test "T1: zsh defines no topic dash-form as a real function" {
    # zsh ships its own `_run-help`; the leading underscore keeps it out of the
    # topic namespace, so only unprefixed <topic>-help names are a regression.
    run_in_zsh 'print -rl -- ${(k)functions} | grep -cE "^[a-z0-9][a-z0-9_]*-help$" || true'
    assert_success
    assert_output "0"
}

@test "T2: zsh resolves git-help as an alias, not a function" {
    run_in_zsh 'whence -w git-help'
    assert_success
    assert_output --partial "alias"

    run_in_zsh 'alias git-help'
    assert_success
    assert_output "git-help=git_help"
}

@test "T3: zsh keeps git_help itself a real function" {
    run_in_zsh 'whence -w git_help'
    assert_success
    assert_output "git_help: function"
}

# ---------------------------------------------------------------------------
# T4-T6: the user-visible bug — duplicate rows in the fzf candidate stream
# ---------------------------------------------------------------------------

@test "T4: zsh enumerates each help topic exactly once" {
    run_in_zsh '_my_help_enumerate_topic_names | LC_ALL=C sort | uniq -d | wc -l'
    assert_success
    assert_output "0"
}

@test "T5: zsh emits each fzf topic candidate exactly once" {
    # Filter on the record-type field: the same stream also carries alias-index
    # rows, where one name legitimately repeats when two files define it
    # differently (see my_help_alias_index.bats T2b). Only topic rows are
    # covered by this regression.
    run_in_zsh '_my_help_search_candidates | awk -F"\t" "\$3==\"topic\"{print \$1}" | LC_ALL=C sort | uniq -d | wc -l'
    assert_success
    assert_output "0"

    run_in_zsh '_my_help_search_candidates | awk -F"\t" "\$3==\"topic\"" | wc -l'
    assert_success
    [ "$output" -gt 50 ]
}

@test "T6: zsh topic count equals its deduplicated count" {
    run_in_zsh '_my_help_enumerate_topic_names | wc -l'
    assert_success
    local total="$output"
    [ "$total" -gt 50 ]

    run_in_zsh '_my_help_enumerate_topic_names | LC_ALL=C sort -u | wc -l'
    assert_success
    assert_output "$total"
}

# ---------------------------------------------------------------------------
# T7-T9: dash-form stays callable; the removed git/gwt/gbr special case
#        did not take anything else with it
# ---------------------------------------------------------------------------

@test "T7: zsh still runs dash-form topics non-interactively" {
    # zsh expands aliases at parse time, so a bare `git-help` inside a `zsh -c`
    # string never sees the alias — the command_not_found_handler shim in
    # my_help.sh routes it back to git_help. That path is what makes an
    # alias-only dash form safe.
    run_in_zsh 'git-help --list'
    assert_success
    assert_output --partial "sections"
}

@test "T8: zsh still runs gwt-help and gbr-help after the special case removal" {
    run_in_zsh 'gwt-help'
    assert_success
    assert_output --partial "sections"

    run_in_zsh 'gbr-help'
    assert_success
    assert_output --partial "sections"
}

@test "T9: git/gwt/gbr stay unwrapped by the adapter" {
    # They are guideline-compliant (each has a paired _<topic>_help_summary), so
    # _help_std_wrap_one must still skip cloning them into _help_std_orig_*.
    # This is the second thing the deleted special case used to guarantee.
    run_in_zsh 'print -rl -- ${(k)functions} | grep -cE "^_help_std_orig_(git|gwt|gbr)_help$" || true'
    assert_success
    assert_output "0"
}

# ---------------------------------------------------------------------------
# T10-T11: bash parity — unchanged by the fix
# ---------------------------------------------------------------------------

@test "T10: bash enumerates each help topic exactly once" {
    run_in_bash '_my_help_enumerate_topic_names | LC_ALL=C sort | uniq -d | wc -l'
    assert_success
    assert_output "0"
}

@test "T11: bash keeps the dash-form alias pointing at the underscore helper" {
    run_in_bash 'alias git-help'
    assert_success
    assert_output "alias git-help='git_help'"
}
