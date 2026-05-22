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

# ---------------------------------------------------------------------------
# #907 regression: caller under `emulate -L sh` must not truncate
# precmd_functions. Without the in-eval `emulate -L zsh` guard, the
# `${(@)arr:#PAT}` filter and `${arr[@]}` expansion collapse to the array's
# first element under sh emulation, dropping `_p9k_precmd` and freezing the
# prompt. Root cause for #907 (`gwt spawn --launch` race re-classified as a
# term_rename array-mutation bug, not a p10k init race).
# ---------------------------------------------------------------------------

@test "zsh: --persist under emulate -L sh keeps other precmd hooks" {
    run_in_zsh '
        # Seed a realistic multi-hook array, then mimic git_worktree_spawn:
        # call term_rename --persist from a function with `emulate -L sh`.
        precmd_functions=(_p9k_do_nothing _omz_async_request omz_termsupport_precmd _p9k_precmd)
        before_count=${#precmd_functions[@]}
        simulated_gwt() {
            emulate -L sh
            term_rename --persist xx >/dev/null
        }
        simulated_gwt
        after_count=${#precmd_functions[@]}
        # Original 4 hooks must survive + _term_rename_persist appended = 5.
        print "before=${before_count}"
        print "after=${after_count}"
        if [[ ${precmd_functions[(I)_p9k_precmd]} -ne 0 ]]; then
            print "p9k_precmd=present"
        else
            print "p9k_precmd=MISSING"
        fi
        if [[ ${precmd_functions[(I)_term_rename_persist]} -ne 0 ]]; then
            print "term_hook=present"
        else
            print "term_hook=MISSING"
        fi
    '
    assert_success
    assert_output --partial "before=4"
    assert_output --partial "after=5"
    assert_output --partial "p9k_precmd=present"
    assert_output --partial "term_hook=present"
}

@test "zsh: --clear under emulate -L sh keeps other precmd hooks" {
    run_in_zsh '
        precmd_functions=(_p9k_do_nothing _omz_async_request _p9k_precmd)
        term_rename --persist yy >/dev/null   # append _term_rename_persist
        simulated_gwt() {
            emulate -L sh
            term_rename --clear >/dev/null
        }
        simulated_gwt
        after_count=${#precmd_functions[@]}
        print "after=${after_count}"
        if [[ ${precmd_functions[(I)_p9k_precmd]} -ne 0 ]]; then
            print "p9k_precmd=present"
        else
            print "p9k_precmd=MISSING"
        fi
        if [[ ${precmd_functions[(I)_term_rename_persist]} -ne 0 ]]; then
            print "term_hook=stuck"
        else
            print "term_hook=cleared"
        fi
    '
    assert_success
    assert_output --partial "after=3"
    assert_output --partial "p9k_precmd=present"
    assert_output --partial "term_hook=cleared"
}

@test "zsh: --persist under emulate -L sh stores name globally" {
    # _term_rename_set_persist_name also goes through an eval under the
    # caller's emulation; verify the assignment lands in the global scope
    # and survives function return.
    run_in_zsh '
        precmd_functions=()
        unset _TERM_RENAME_PERSIST_NAME
        simulated_gwt() {
            emulate -L sh
            term_rename --persist abc >/dev/null
        }
        simulated_gwt
        print "name=${_TERM_RENAME_PERSIST_NAME-MISSING}"
    '
    assert_success
    assert_output --partial "name=abc"
}
