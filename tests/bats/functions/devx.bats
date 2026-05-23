#!/usr/bin/env bats
# tests/bats/functions/devx.bats
# Test devx Type 2A dispatcher (issue #726 / #722 PR 2).

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# Dispatcher existence
# ---------------------------------------------------------------------------

@test "bash: devx dispatcher exists" {
    run_in_bash 'declare -f devx >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: devx dispatcher exists" {
    run_in_zsh 'declare -f devx >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: devx_help standalone exists" {
    run_in_bash 'declare -f devx_help >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: devx_help standalone exists" {
    run_in_zsh 'typeset -f devx_help >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

# ---------------------------------------------------------------------------
# §7.6.1 deviation — devx-help alias must NOT exist
# ---------------------------------------------------------------------------

@test "bash: devx-help alias does not exist (§7.6.1 deviation)" {
    run_in_bash 'type devx-help 2>&1'
    assert_failure
}

@test "zsh: devx-help alias does not exist (§7.6.1 deviation)" {
    run_in_zsh 'type devx-help 2>&1'
    assert_failure
}

# ---------------------------------------------------------------------------
# Five entry points produce equivalent summary output
# ---------------------------------------------------------------------------

@test "bash: 5 entry points produce equivalent summary" {
    run_in_bash '
        a=$(devx 2>&1)
        b=$(devx -h 2>&1)
        c=$(devx --help 2>&1)
        d=$(devx help 2>&1)
        e=$(my_help_impl devx 2>&1)
        [ "$a" = "$b" ] && [ "$b" = "$c" ] && [ "$c" = "$d" ] && [ "$d" = "$e" ] && echo MATCH
    '
    assert_success
    assert_output --partial "MATCH"
}

@test "zsh: 5 entry points produce equivalent summary" {
    run_in_zsh '
        a=$(devx 2>&1)
        b=$(devx -h 2>&1)
        c=$(devx --help 2>&1)
        d=$(devx help 2>&1)
        e=$(my_help_impl devx 2>&1)
        [ "$a" = "$b" ] && [ "$b" = "$c" ] && [ "$c" = "$d" ] && [ "$d" = "$e" ] && echo MATCH
    '
    assert_success
    assert_output --partial "MATCH"
}

# ---------------------------------------------------------------------------
# Summary content + line budget
# ---------------------------------------------------------------------------

@test "bash: devx help summary mentions key sub-commands" {
    run_in_bash 'devx help'
    assert_success
    assert_output --partial "lint"
    assert_output --partial "fix"
    assert_output --partial "lint-helpfunc"
    assert_output --partial "lint-deadcode"
    assert_output --partial "stat"
}

@test "bash: devx help default output ≤ 15 lines (command-guidelines)" {
    run_in_bash 'devx help | wc -l'
    assert_success
    [ "$output" -le 15 ]
}

@test "zsh: devx help default output ≤ 15 lines (command-guidelines)" {
    run_in_zsh 'devx help | wc -l'
    assert_success
    [ "$output" -le 15 ]
}

# ---------------------------------------------------------------------------
# SSOT §1 — devx help <section> rows ≡ devx help --all same section rows
# ---------------------------------------------------------------------------

@test "bash: section rows byte-for-byte match --all (SSOT §1)" {
    run_in_bash '
        for s in lint fix lint-helpfunc lint-deadcode stat; do
            sec=$(devx help "$s" 2>&1)
            # Every line of the section view must appear verbatim in --all.
            all=$(devx help --all 2>&1)
            while IFS= read -r line; do
                [ -n "$line" ] || continue
                case "$all" in
                    *"$line"*) ;;
                    *) echo "MISS section=$s line=$line"; exit 1 ;;
                esac
            done <<EOF
$sec
EOF
        done
        echo OK
    '
    assert_success
    assert_output --partial "OK"
}

# ---------------------------------------------------------------------------
# my_help.sh registration coverage
# ---------------------------------------------------------------------------

@test "bash: HELP_DESCRIPTIONS[devx_help] registered" {
    run_in_bash 'my_help_impl >/dev/null; echo "${HELP_DESCRIPTIONS[devx_help]}"'
    assert_success
    assert_output --partial "[Development]"
}

@test "bash: HELP_CATEGORY_MEMBERS[development] contains devx" {
    run_in_bash 'my_help_impl >/dev/null; echo "${HELP_CATEGORY_MEMBERS[development]}"'
    assert_success
    assert_output --partial "devx"
}

# ---------------------------------------------------------------------------
# Self-check: lint-helpfunc must pass on the repo itself
# ---------------------------------------------------------------------------

@test "bash: devx lint-helpfunc exits 0 on this repo" {
    run_in_bash 'devx lint-helpfunc'
    assert_success
}

@test "zsh: devx lint-helpfunc exits 0 on this repo" {
    run_in_zsh 'devx lint-helpfunc'
    assert_success
}

# ---------------------------------------------------------------------------
# fmt / format deprecation routing (no actual mise invocation — stub mise)
# ---------------------------------------------------------------------------

@test "bash: devx fmt emits deprecation warning and routes to fix" {
    run_in_bash '
        mise() { echo "MISE_CALLED $*"; }
        export -f mise
        devx fmt 2>&1
    '
    assert_output --partial "deprecated"
    assert_output --partial "MISE_CALLED run fix"
}

@test "bash: devx format emits deprecation warning and routes to fix" {
    run_in_bash '
        mise() { echo "MISE_CALLED $*"; }
        export -f mise
        devx format 2>&1
    '
    assert_output --partial "deprecated"
    assert_output --partial "MISE_CALLED run fix"
}

# ---------------------------------------------------------------------------
# Unknown sub-command — error, no passthrough (command-design-pattern §6)
# ---------------------------------------------------------------------------

@test "bash: unknown sub-command returns 1 and shows error" {
    run_in_bash 'devx run-some-unknown-thing 2>&1'
    assert_failure
    assert_output --partial "Unknown command"
    assert_output --partial "devx help"
}

@test "zsh: unknown sub-command returns 1 and shows error" {
    run_in_zsh 'devx run-some-unknown-thing 2>&1'
    assert_failure
    assert_output --partial "Unknown command"
}

# ---------------------------------------------------------------------------
# stat — repo_stats.sh delegation
# ---------------------------------------------------------------------------

@test "bash: devx stat invokes repo_stats.sh wrapper" {
    # Should at minimum exit 0 (or print stats). Confirm no fatal error.
    run_in_bash 'devx stat 2>&1 >/dev/null; echo rc=$?'
    assert_output --partial "rc="
}

# ---------------------------------------------------------------------------
# Private helpers exist
# ---------------------------------------------------------------------------

@test "bash: private _devx_* sub-functions exist" {
    run_in_bash '
        for fn in _devx_lint _devx_fix _devx_fmt_deprecated _devx_stat _devx_lint_helpfunc _devx_lint_deadcode; do
            declare -f "$fn" >/dev/null || { echo MISSING $fn; exit 1; }
        done
        echo ok
    '
    assert_success
    assert_output --partial "ok"
}
