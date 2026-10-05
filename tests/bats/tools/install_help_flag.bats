#!/usr/bin/env bats
# tests/bats/tools/install_help_flag.bats
# tools/custom install/util scripts: -h/--help print usage, exit 0 and call no
# external tool (#1913, #1923). Before: install_python cleared the screen and
# took -h as a Python version, install-ollama as an offline file, install_herdr
# ignored it and installed, make_jira used it as the week, repo_stats exited 1.

load '../test_helper'

setup() {
    setup_isolated_home
    STUB_DIR="$HOME/stub-bin"
    CALL_LOG="$HOME/calls.log"
    mkdir -p "$STUB_DIR"
    : >"$CALL_LOG"
    # Every tool a script would touch logs its call and fails instead of running.
    local tool
    for tool in sudo apt-get git pyenv curl wget ollama tar zstd npm node \
        claude; do
        printf '#!/bin/sh\necho "%s $*" >>"%s"\nexit 1\n' "$tool" "$CALL_LOG" >"$STUB_DIR/$tool"
        chmod +x "$STUB_DIR/$tool"
    done
    # clear must succeed: install_python runs under set -e.
    printf '#!/bin/sh\necho "clear $*" >>"%s"\n' "$CALL_LOG" >"$STUB_DIR/clear"
    chmod +x "$STUB_DIR/clear"
}

teardown() {
    teardown_isolated_home
}

_run_script() {
    local name="$1"
    shift
    # Real ux_lib (init.sh returns before loading it under test mode).
    run env -u DOTFILES_TEST_MODE PATH="$STUB_DIR:$PATH" HOME="$HOME" \
        TERM=dumb bash "${SHELL_COMMON}/tools/custom/${name}.sh" "$@"
}

@test "install/util scripts -h|--help: usage, exit 0, no external tool called" {
    local name flag
    for name in install_python install-ollama install_herdr make_jira repo_stats; do
        for flag in -h --help; do
            _run_script "$name" "$flag"
            assert_success
            assert_output --partial "Usage"
        done
    done
    for flag in -h --help; do
        _run_script install_notion_mcp "$flag"
        assert_success
        assert_output --partial "Notion MCP Installation Help"
    done
    run cat "$CALL_LOG"
    assert_output ""
}

@test "install_python without flag still clears and asks to proceed" {
    _run_script install_python <<<"n"
    assert_success
    assert_output --partial "Using default versions"
    assert_output --partial "Installation cancelled"
    run cat "$CALL_LOG"
    assert_output "clear "
}

@test "install_herdr without flag still runs the installer" {
    _run_script install_herdr
    assert_failure
    assert_output --partial "herdr install failed"
    run grep -c '^curl ' "$CALL_LOG"
    assert_output "1"
}

@test "install-ollama without flag still checks the installed ollama" {
    _run_script install-ollama
    run cat "$CALL_LOG"
    assert_line "ollama --version"
}

@test "make_jira without flag still builds the current-week report" {
    _run_script make_jira
    assert_failure
    assert_output --partial "Jira Report"
    assert_output --partial "work_log.txt not found"
}

@test "repo_stats and install_notion_mcp keep their argument errors" {
    _run_script repo_stats "$HOME/missing"
    assert_failure 1
    assert_output --partial "is not a directory"
    _run_script install_notion_mcp bogus
    assert_failure 1
    assert_output --partial "Unknown action: bogus"
}
