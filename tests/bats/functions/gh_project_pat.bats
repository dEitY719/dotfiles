#!/usr/bin/env bats
# tests/bats/functions/gh_project_pat.bats
# gh-project-pat dispatcher + help (issue #2064). The helper's PAT/stdin
# contract is covered in tests/integration/test_gh_project_pat.py; here a gh
# stub on PATH proves the shell layer wires guide/set/status without writes.

load '../test_helper'

setup() {
    setup_isolated_home
    STUB_BIN="$TEST_TEMP_HOME/stubbin"
    GH_LOG="$TEST_TEMP_HOME/gh.log"
    mkdir -p "$STUB_BIN"
    cat >"$STUB_BIN/gh" <<'GH'
#!/bin/sh
printf 'GH_HOST=%s %s\n' "${GH_HOST-}" "$*" >>"$GH_LOG"
case "$*" in
    "api --hostname "*" user") echo '{"login":"me"}' ;;
    "api --hostname "*"user/repos"*"page=1")
        echo '[{"name":"a-skills","full_name":"me/a-skills","private":true},{"name":"misc","full_name":"me/misc","private":false},{"name":"b-skills","full_name":"me/b-skills","private":false}]' ;;
    "secret list --repo me/a-skills"*) echo '[{"name":"PROJECT_BOARD_PAT"}]' ;;
    "secret list --repo me/b-skills"*) echo '[]' ;;
    "secret set"*) exit 0 ;;
    *) echo "unexpected: $*" >&2; exit 1 ;;
esac
GH
    chmod +x "$STUB_BIN/gh"
    export GH_LOG
    export PATH="$STUB_BIN:$PATH"
}

teardown() {
    teardown_isolated_home
}

_run() {
    if [ "$1" = bash ]; then
        run_in_bash "$2"
    else
        run_in_zsh "$2"
    fi
}

@test "functions and aliases are defined (bash + zsh)" {
    for sh in bash zsh; do
        _run "$sh" 'type gh_project_pat >/dev/null && type gh_project_pat_help >/dev/null && alias gh-project-pat && alias gh-project-pat-help'
        assert_success
    done
}

@test "help shows guide/set/status in both shells" {
    for sh in bash zsh; do
        _run "$sh" 'gh_project_pat_help'
        assert_success
        assert_output --partial "guide"
        assert_output --partial "set"
        assert_output --partial "status"
        _run "$sh" 'gh_project_pat --help'
        assert_success
        assert_output --partial "gh-project-pat"
    done
}

@test "guide prints host URL, classic menu path and scopes" {
    for sh in bash zsh; do
        _run "$sh" 'gh_project_pat guide --host ghe.example.com'
        assert_success
        assert_output --partial "https://ghe.example.com/settings/tokens/new"
        assert_output --partial "Tokens (classic)"
        assert_output --partial "skills-plugins-board"
        assert_output --partial "project"
        assert_output --partial "repo"
        assert_output --partial "fine-grained"
    done
    [ ! -s "$GH_LOG" ]
}

@test "guide without --host uses the resolved host" {
    _run bash 'gh_project_pat guide'
    assert_success
    assert_output --partial "https://github.com/settings/tokens/new"
}

@test "set dry-run lists targets and never writes (bash + zsh)" {
    for sh in bash zsh; do
        : >"$GH_LOG"
        _run "$sh" 'gh_project_pat set --host ghe.example.com; echo "rc=$?"'
        assert_output --partial "me/a-skills"
        assert_output --partial "me/b-skills"
        refute_output --partial "me/misc"
        assert_output --partial "rc=0"
        assert_output --partial "dry-run"
        run grep -c "secret set" "$GH_LOG"
        assert_output "0"
        run grep -vc "^GH_HOST=ghe.example.com " "$GH_LOG"
        assert_output "0"
    done
}

@test "set with explicit repo under emulate -L sh caller" {
    _run zsh 'f() { emulate -L sh; gh_project_pat set --host github.com --owner me --repo me/x --repo me/y; echo "rc=$?"; }; f'
    assert_output --partial "me/x"
    assert_output --partial "me/y"
    assert_output --partial "rc=0"
}

@test "bad input exits 2" {
    for args in "frobnicate" "set --host github.com --apply --dry-run" \
        "set --host github.com --owner me --repo other/x" \
        "set --host github.com --repo me/x --repo-pattern '*'" \
        "set --host github.com --bogus" "guide --bogus" "guide --host ''"; do
        _run bash "gh_project_pat $args; echo \"rc=\$?\""
        assert_output --partial "rc=2"
    done
}

@test "set --apply without a TTY exits 1 before any write" {
    command -v setsid >/dev/null || skip "setsid unavailable"
    run setsid bash --noprofile --norc -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}' SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_FORCE_INIT=1 DOTFILES_TEST_MODE=1 DOTFILES_ROOT_NO_CANONICALIZE=1
        export HOME='${HOME}' TERM=dumb
        source '${DOTFILES_ROOT}/bash/main.bash'
        gh_project_pat set --host github.com --apply </dev/null
        echo \"rc=\$?\"
    "
    assert_output --partial "TTY"
    assert_output --partial "rc=1"
    run grep -c "secret set" "$GH_LOG"
    assert_output "0"
}

@test "status counts present and missing, exit 1" {
    for sh in bash zsh; do
        _run "$sh" 'gh_project_pat status --host github.com; echo "rc=$?"'
        assert_output --partial "me/a-skills"
        assert_output --partial "me/b-skills"
        assert_output --partial "present 1"
        assert_output --partial "missing 1"
        assert_output --partial "rc=1"
    done
    run grep -c "secret set" "$GH_LOG"
    assert_output "0"
}

@test "my-help discovers the topic and /func registry" {
    for sh in bash zsh; do
        _run "$sh" 'my_help_impl gh_project_pat'
        assert_success
        assert_output --partial "gh-project-pat"
        _run "$sh" '_my_help_function_index'
        assert_output --partial "gh_project_pat"
        assert_output --partial "functions/gh_project_pat.sh"
    done
}
