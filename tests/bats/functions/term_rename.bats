#!/usr/bin/env bats
# tests/bats/functions/term_rename.bats
# Test term-rename VSCode tab-rename helper.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# Existence + alias
# ---------------------------------------------------------------------------

@test "bash: term_rename function exists" {
    run_in_bash 'declare -f term_rename >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: term-rename alias points at term_rename" {
    run_in_bash 'alias term-rename | grep -q term_rename && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: term_rename function exists" {
    run_in_zsh 'whence -w term_rename | grep -q ": function" && echo ok'
    assert_success
    assert_output --partial "ok"
}

# ---------------------------------------------------------------------------
# Core OSC emit
# ---------------------------------------------------------------------------

@test "bash: term_rename foo emits exact OSC 0 sequence" {
    run_in_bash 'term_rename foo'
    assert_success
    # 8 bytes: ESC ] 0 ; f o o BEL
    expected=$'\e]0;foo\a'
    [ "$output" = "$expected" ]
}

@test "bash: term_rename with no args fails" {
    run_in_bash 'term_rename'
    assert_failure
}

@test "bash: term_rename --unknown fails" {
    run_in_bash 'term_rename --bogus 2>/dev/null'
    assert_failure
}

@test "bash: term_rename -h shows help (success)" {
    run_in_bash 'term_rename -h'
    assert_success
    assert_output --partial "term-rename"
}

# ---------------------------------------------------------------------------
# Sanitize: ESC / BEL / newline / NUL stripped
# ---------------------------------------------------------------------------

@test "bash: term_rename strips ESC/BEL injection" {
    # Input: ESC ] 0 ; evil BEL space name  → after sanitize → ]0;evil name
    # Output OSC payload: ESC ]0; + sanitized + BEL
    run_in_bash $'term_rename $\'\\e]0;evil\\a name\''
    assert_success
    expected=$'\e]0;]0;evil name\a'
    [ "$output" = "$expected" ]
}

@test "bash: term_rename rejects all-control name (empty after sanitize)" {
    run_in_bash $'term_rename $\'\\e\\a\\n\' 2>/dev/null'
    assert_failure
}

# ---------------------------------------------------------------------------
# --persist installs hook and stores name
# ---------------------------------------------------------------------------

@test "bash: --persist installs PROMPT_COMMAND hook and stores name" {
    run_in_bash '
        PROMPT_COMMAND=""
        term_rename --persist bar >/dev/null
        case "$PROMPT_COMMAND" in
            *_term_rename_persist*) printf "hook=ok\n" ;;
            *)                       printf "hook=missing\n" ;;
        esac
        printf "name=%s\n" "${_TERM_RENAME_PERSIST_NAME-}"
    '
    assert_success
    assert_output --partial "hook=ok"
    assert_output --partial "name=bar"
}

@test "bash: --clear removes hook and unsets name" {
    run_in_bash '
        PROMPT_COMMAND=""
        term_rename --persist baz >/dev/null
        term_rename --clear >/dev/null
        case "$PROMPT_COMMAND" in
            *_term_rename_persist*) printf "hook=stuck\n" ;;
            *)                       printf "hook=cleared\n" ;;
        esac
        printf "name=%s\n" "${_TERM_RENAME_PERSIST_NAME-}"
    '
    assert_success
    assert_output --partial "hook=cleared"
    assert_output --partial "name="
}

@test "bash: --persist twice does not duplicate the hook" {
    run_in_bash '
        PROMPT_COMMAND=""
        term_rename --persist a >/dev/null
        term_rename --persist a >/dev/null
        # count occurrences of the hook name
        count=$(printf "%s" "$PROMPT_COMMAND" | grep -o _term_rename_persist | wc -l)
        printf "count=%s\n" "$count"
    '
    assert_success
    assert_output --partial "count=1"
}

@test "bash: --persist with no name fails" {
    run_in_bash 'term_rename --persist 2>/dev/null'
    assert_failure
}

@test "zsh: --persist installs precmd_functions hook" {
    run_in_zsh '
        precmd_functions=()
        term_rename --persist zz >/dev/null
        if [[ ${precmd_functions[(I)_term_rename_persist]} -ne 0 ]]; then
            print "hook=ok"
        else
            print "hook=missing"
        fi
        print "name=${_TERM_RENAME_PERSIST_NAME-}"
    '
    assert_success
    assert_output --partial "hook=ok"
    assert_output --partial "name=zz"
}

@test "zsh: --clear removes precmd_functions hook" {
    run_in_zsh '
        precmd_functions=()
        term_rename --persist zz >/dev/null
        term_rename --clear >/dev/null
        if [[ ${precmd_functions[(I)_term_rename_persist]} -ne 0 ]]; then
            print "hook=stuck"
        else
            print "hook=cleared"
        fi
    '
    assert_success
    assert_output --partial "hook=cleared"
}
