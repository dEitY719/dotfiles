#!/usr/bin/env bats
# tests/bats/tools/work_log_field_validation.bats
# Regression coverage for issue #1308 — locks the PR #1307 fix of issue #1305.
#
# work_log_add_interactive() used to validate each of its four fields with
#   value=$(validate_x "$input") && { ux_success ...; } || { value=""; }
# With that form, a non-zero exit from the SUCCESS branch itself (ux_success)
# made bash fall through to the || branch and wipe an already-validated value.
# The shared logic now lives in work_log_prompt_validate(), which decides
# purely on the validator's exit status. These tests pin that behaviour down:
# the ux_success side effect must never influence the produced value or the rc.

load '../test_helper'

TOOLS_DIR="${DOTFILES_ROOT}/shell-common/tools/custom"
WORK_LOG_SCRIPT="${TOOLS_DIR}/work_log.sh"

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# Source work_log.sh (never auto-sourced, so it is loaded by path), install
# ux_* doubles, call work_log_prompt_validate and print the resulting rc plus
# the out-var value.
#
# Usage: run_prompt_validate <ux_success_tail> <preset_value> <validate args...>
#   ux_success_tail  extra statement appended to the ux_success double
#                    (e.g. "return 1" to simulate a failing success side effect)
#   preset_value     value the out var holds before the call
#   validate args    everything after the out var name (validator, input, ...)
#
# The out var is always named `field`. ux_success/ux_error are overridden AFTER
# sourcing so they replace the real ux_lib implementations.
run_prompt_validate() {
    local ux_success_tail="$1"
    shift
    local preset_q
    preset_q="$(printf '%q' "$1")"
    shift

    local args_q="" arg
    for arg in "$@"; do
        args_q+=" $(printf '%q' "$arg")"
    done

    run bash -c "
        export HOME='${HOME}'
        export TERM=dumb
        source '${WORK_LOG_SCRIPT}'
        ux_success() { printf 'OK: %s\n' \"\$1\"; ${ux_success_tail}; }
        ux_error() { printf 'ERR: %s\n' \"\$1\" >&2; }
        field=${preset_q}
        if work_log_prompt_validate field${args_q}; then
            printf 'rc=0 value=[%s]\n' \"\$field\"
        else
            printf 'rc=1 value=[%s]\n' \"\$field\"
        fi
    "
}

# --- the actual PR #1307 regression -----------------------------------------

@test "work_log_prompt_validate: failing ux_success does not discard a valid value" {
    # ux_success returns 1 unconditionally. The old '&& { } || { }' form would
    # have run the failure branch and reset the value to "".
    run_prompt_validate "return 1" "" \
        validate_jira_key "swinnoteam-903" "Jira key: " "Invalid Jira key format"
    assert_success
    assert_output --partial "rc=0 value=[SWINNOTEAM-903]"
    refute_output --partial "ERR:"
}

@test "work_log_prompt_validate: failing ux_success does not overwrite an earlier valid value" {
    # Same hazard seen from the loop's angle: a previously accepted value must
    # survive a failing success side effect instead of being reset to "".
    run_prompt_validate "return 1" "STALE-1" \
        validate_type "meeting" "Type: " "Invalid type"
    assert_success
    assert_output --partial "rc=0 value=[meeting]"
}

# --- happy path (ux_success healthy) ----------------------------------------

@test "work_log_prompt_validate: valid input yields the normalized value and reports it" {
    run_prompt_validate "return 0" "" \
        validate_jira_key "[proj-245]" "Jira key: " "Invalid Jira key format"
    assert_success
    assert_output --partial "OK: Jira key: PROJ-245"
    assert_output --partial "rc=0 value=[PROJ-245]"
}

@test "work_log_prompt_validate: optional suffix is appended to the success label only" {
    # Time: the label reads "2.5h" while the stored value stays "2.5".
    run_prompt_validate "return 0" "" \
        validate_time "2.5h" "Time: " "Invalid time format" "h"
    assert_success
    assert_output --partial "OK: Time: 2.5h"
    assert_output --partial "rc=0 value=[2.5]"
}

# --- failure path: value is reset, error reported ---------------------------

@test "work_log_prompt_validate: invalid input reports the error and produces no value" {
    run_prompt_validate "return 0" "" \
        validate_category "NotACategory" "Category: " "Invalid category"
    assert_success
    assert_output --partial "ERR: Invalid category"
    assert_output --partial "rc=1 value=[]"
    refute_output --partial "OK:"
}

@test "work_log_prompt_validate: invalid input resets a previously held value" {
    # "이전 값이 리셋되는지" — the while-loops depend on the out var going back
    # to "" so the prompt repeats instead of accepting stale input.
    run_prompt_validate "return 0" "SWINNOTEAM-903" \
        validate_jira_key "not a key" "Jira key: " "Invalid Jira key format"
    assert_success
    assert_output --partial "ERR: Invalid Jira key format"
    assert_output --partial "rc=1 value=[]"
}

# --- structural guards against reintroducing the anti-pattern ---------------

@test "work_log_add_interactive routes all four fields through the shared helper" {
    run grep -c 'work_log_prompt_validate [a-z_]* validate_' "$WORK_LOG_SCRIPT"
    assert_success
    assert_output "4"
}

@test "work_log.sh has no executable '&& { ... }' success-branch anti-pattern" {
    if grep -nE '^[[:space:]]*[^#[:space:]].*\) && \{' "$WORK_LOG_SCRIPT"; then
        echo "work_log.sh reintroduced the 'cmd && { ... } || { ... }' pattern"
        return 1
    fi
}
