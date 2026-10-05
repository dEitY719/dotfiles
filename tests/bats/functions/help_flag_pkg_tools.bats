#!/usr/bin/env bats
# tests/bats/functions/help_flag_pkg_tools.bats
# -h/--help on the apt/npm/pyenv/litellm/opencode/ollama integration commands
# prints help, exits 0 and runs nothing (#1918, follow-up of #1880).
# Every external tool they call is stubbed to append to CALL_LOG, so a
# missing guard shows up as a non-empty log instead of a real apt/pyenv/ollama
# action. Excluded passthroughs: ollama_cmd, ollama_logs (forward "$@").

load '../test_helper'

setup() {
    setup_isolated_home
    STUB_DIR="$TEST_TEMP_HOME/stub-bin"
    CALL_LOG="$TEST_TEMP_HOME/calls.log"
    mkdir -p "$STUB_DIR"
    : >"$CALL_LOG"
    local t
    for t in sudo apt-get apt-cache dpkg add-apt-repository npm pyenv \
        ollama docker opencode curl bash; do
        printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >>"%s"\nexit 0\n' \
            "$t" "$CALL_LOG" >"$STUB_DIR/$t"
        chmod +x "$STUB_DIR/$t"
    done
}

teardown() {
    teardown_isolated_home
}

# Stubs go on PATH only after main.{bash,zsh} has loaded, so `bash` itself is
# stubbed for py_install (which execs `bash install_python.sh "$@"`).
_run_all() {
    local runner="$1" fn flag cmds=""
    for fn in appa_remove ollama_rm py_uninstall py_install appa_add adep \
        ardep afiles awhich ainfo npm_info npm_search litellm_test opentest \
        ollama_models ollama_pull ollama_show ollama_run ollama_prompt; do
        for flag in -h --help; do
            cmds="$cmds $fn $flag >/dev/null || { echo FAIL:$fn:$flag; exit 1; };"
        done
    done
    "$runner" "export PATH='$STUB_DIR':\"\$PATH\"; $cmds echo ALL_OK"
}

@test "pkg/model tools -h|--help: exit 0, no external call (bash)" {
    _run_all run_in_bash
    assert_success
    assert_output --partial ALL_OK
    [ ! -s "$CALL_LOG" ] || fail "side effects: $(cat "$CALL_LOG")"
}

@test "pkg/model tools -h|--help: exit 0, no external call (zsh)" {
    _run_all run_in_zsh
    assert_success
    assert_output --partial ALL_OK
    [ ! -s "$CALL_LOG" ] || fail "side effects: $(cat "$CALL_LOG")"
}

@test "destructive commands -h print their help section" {
    run_in_bash "appa_remove -h; ollama_rm --help; py_uninstall -h"
    assert_success
    assert_output --partial "appa_remove"
    assert_output --partial "ollama-rm"
    assert_output --partial "uninstall-py"
}

@test "stubs catch an unguarded call (sanity)" {
    run_in_bash "export PATH='$STUB_DIR':\"\$PATH\"; appa_remove ppa:x/y"
    grep -q 'add-apt-repository --remove ppa:x/y' "$CALL_LOG"
}
