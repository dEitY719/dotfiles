#!/usr/bin/env bats
# tests/bats/git/test_prepare_commit_msg.bats
#
# JIRA key extraction for git/hooks/prepare-commit-msg: JIRA_PATTERN from
# git/config/prepare-commit-msg-rules.sh against branch names (moved from
# git/tests/test-prepare-commit-msg.sh, #2163).

load '../test_helper'

setup() {
    # shellcheck source=../../../git/config/prepare-commit-msg-rules.sh
    source "${DOTFILES_ROOT}/git/config/prepare-commit-msg-rules.sh"
}

# jira_key_of <branch> — prints the key JIRA_PATTERN extracts, or nothing.
jira_key_of() {
    if [[ "$1" =~ $JIRA_PATTERN ]]; then
        printf '%s\n' "${BASH_REMATCH[0]}"
    fi
}

@test "feature/SWINNOTEAM-906-user-profile -> [SWINNOTEAM-906]" {
    run jira_key_of "feature/SWINNOTEAM-906-user-profile"
    assert_success
    assert_output "SWINNOTEAM-906"
}

@test "feature/SWINNOTEAM-906-add-auth -> [SWINNOTEAM-906]" {
    run jira_key_of "feature/SWINNOTEAM-906-add-auth"
    assert_success
    assert_output "SWINNOTEAM-906"
}

@test "bugfix/PROJ-245-login-bug -> [PROJ-245]" {
    run jira_key_of "bugfix/PROJ-245-login-bug"
    assert_success
    assert_output "PROJ-245"
}

@test "hotfix/JIRA-1-urgent-fix -> [JIRA-1]" {
    run jira_key_of "hotfix/JIRA-1-urgent-fix"
    assert_success
    assert_output "JIRA-1"
}

@test "bugfix/ABC-999-test-case -> [ABC-999]" {
    run jira_key_of "bugfix/ABC-999-test-case"
    assert_success
    assert_output "ABC-999"
}

@test "feature/user-profile -> (no key)" {
    run jira_key_of "feature/user-profile"
    assert_success
    assert_output ""
}

@test "bugfix/refactor-auth -> (no key)" {
    run jira_key_of "bugfix/refactor-auth"
    assert_success
    assert_output ""
}

@test "hotfix/urgent-fix -> (no key)" {
    run jira_key_of "hotfix/urgent-fix"
    assert_success
    assert_output ""
}

@test "feature/simple-name -> (no key)" {
    run jira_key_of "feature/simple-name"
    assert_success
    assert_output ""
}

@test "develop -> (no key)" {
    run jira_key_of "develop"
    assert_success
    assert_output ""
}

@test "main -> (no key)" {
    run jira_key_of "main"
    assert_success
    assert_output ""
}

@test "feature/PROJ-10-x -> [PROJ-10]" {
    run jira_key_of "feature/PROJ-10-x"
    assert_success
    assert_output "PROJ-10"
}

@test "feature/VERYLONGKEY-999-test -> [VERYLONGKEY-999]" {
    run jira_key_of "feature/VERYLONGKEY-999-test"
    assert_success
    assert_output "VERYLONGKEY-999"
}
