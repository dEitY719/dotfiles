#!/usr/bin/env bats
# tests/bats/functions/setup_mode.bats
# Coverage for shell-common/util/setup_mode.sh's `_apply_setup_mode_config`.
#
# Issue #1051: the proxy-cleanup `case` only matched the legacy numeric
# mode values (1/2/3). Since #703, shell-common/setup.sh writes the
# string values (`internal`/`external`/`public`) to
# ~/.dotfiles-setup-mode, so `external`/`public` PCs silently kept any
# WSL2-inherited proxy env vars. gh_host.sh (#703) already migrated to
# dual string/numeric support; this file was the one left behind.

load '../test_helper'

setup() {
    setup_isolated_home
    export http_proxy="http://127.0.0.1:8080"
    export https_proxy="http://127.0.0.1:8080"
    export all_proxy="http://127.0.0.1:8080"
    export ALL_PROXY="http://127.0.0.1:8080"
}

teardown() {
    teardown_isolated_home
}

@test "mode=external clears proxy vars" {
    echo "external" > "$HOME/.dotfiles-setup-mode"
    run_in_bash '_apply_setup_mode_config; echo "[${http_proxy}][${all_proxy}][${ALL_PROXY}]"'
    assert_success
    assert_output "[][][]"
}

@test "mode=public clears proxy vars" {
    echo "public" > "$HOME/.dotfiles-setup-mode"
    run_in_bash '_apply_setup_mode_config; echo "[${http_proxy}][${all_proxy}][${ALL_PROXY}]"'
    assert_success
    assert_output "[][][]"
}

@test "mode=internal leaves proxy vars untouched" {
    echo "internal" > "$HOME/.dotfiles-setup-mode"
    run_in_bash '_apply_setup_mode_config; echo "[${http_proxy}]"'
    assert_success
    assert_output "[http://127.0.0.1:8080]"
}

@test "legacy mode=1 (public) clears proxy vars" {
    echo "1" > "$HOME/.dotfiles-setup-mode"
    run_in_bash '_apply_setup_mode_config; echo "[${http_proxy}]"'
    assert_success
    assert_output "[]"
}

@test "legacy mode=3 (external) clears proxy vars" {
    echo "3" > "$HOME/.dotfiles-setup-mode"
    run_in_bash '_apply_setup_mode_config; echo "[${http_proxy}]"'
    assert_success
    assert_output "[]"
}

@test "legacy mode=2 (internal) leaves proxy vars untouched" {
    echo "2" > "$HOME/.dotfiles-setup-mode"
    run_in_bash '_apply_setup_mode_config; echo "[${http_proxy}]"'
    assert_success
    assert_output "[http://127.0.0.1:8080]"
}

@test "missing setup-mode file leaves proxy vars untouched" {
    rm -f "$HOME/.dotfiles-setup-mode"
    run_in_bash '_apply_setup_mode_config; echo "[${http_proxy}]"'
    assert_success
    assert_output "[http://127.0.0.1:8080]"
}

@test "zsh: mode=external clears proxy vars" {
    if ! command -v zsh >/dev/null 2>&1; then
        skip "zsh is not installed"
    fi
    echo "external" > "$HOME/.dotfiles-setup-mode"
    run_in_zsh '_apply_setup_mode_config; echo "[${http_proxy}]"'
    assert_success
    assert_output "[]"
}

# --- _dotfiles_setup_mode SSOT (#1810) ---------------------------------------
#
# Issue #1810: ~/.dotfiles-setup-mode was parsed independently in 16 places.
# Half of them compared against "internal" without translating the legacy
# numeric values, and half read the file with a bare `cat`, so a CRLF-saved
# file or a stray space silently failed every equality check. Both classes are
# now one function in shell-common/util/setup_mode_read.sh.

# Source ONLY the SSOT file (no shell init) and echo the canonical mode.
_run_setup_mode_read() {
    run bash --noprofile --norc -c "
        export HOME='${HOME}'
        . '${DOTFILES_ROOT}/shell-common/util/setup_mode_read.sh'
        _dotfiles_setup_mode
    "
}

@test "_dotfiles_setup_mode: legacy numeric 2 maps to internal" {
    printf '2\n' > "$HOME/.dotfiles-setup-mode"
    _run_setup_mode_read
    assert_success
    assert_output "internal"
}

@test "_dotfiles_setup_mode: symbolic internal stays internal" {
    printf 'internal\n' > "$HOME/.dotfiles-setup-mode"
    _run_setup_mode_read
    assert_success
    assert_output "internal"
}

@test "_dotfiles_setup_mode: surrounding whitespace is stripped" {
    printf '  internal  \n' > "$HOME/.dotfiles-setup-mode"
    _run_setup_mode_read
    assert_success
    assert_output "internal"
}

@test "_dotfiles_setup_mode: CRLF line ending is stripped" {
    printf 'internal\r\n' > "$HOME/.dotfiles-setup-mode"
    _run_setup_mode_read
    assert_success
    assert_output "internal"
}

@test "_dotfiles_setup_mode: missing file yields empty string" {
    rm -f "$HOME/.dotfiles-setup-mode"
    _run_setup_mode_read
    assert_success
    assert_output ""
}

# --- static guard: nobody re-reads the file raw ------------------------------

# Every repo *.sh line that actually executes something, prefixed file:line.
# Same awk/grep approach as tests/bats/tools/install_no_tracked_writes.bats,
# minus that file's `X="..."` filter: the #1810 bugs looked exactly like
# `MODE="$(cat ~/.dotfiles-setup-mode)"`, so quoted assignments must stay in
# scope here. tests/, comments, `: <<'DOC'` help blocks and ux_*/echo/printf
# arguments are data rather than execution, so they are skipped.
_setup_mode_code_lines() {
    find "$DOTFILES_ROOT" -name '*.sh' \
        -not -path '*/.git/*' -not -path "${DOTFILES_ROOT}/tests/*" -print0 |
        xargs -0 awk '
            FNR == 1 { doc = "" }
            doc != "" { if ($0 == doc) doc = ""; next }
            /^[[:space:]]*:[[:space:]]*<</ {
                doc = $0
                sub(/^[[:space:]]*:[[:space:]]*<<-?[[:space:]]*/, "", doc)
                gsub(/["'"'"']/, "", doc)
            }
            { print FILENAME ":" FNR ":" $0 }
        ' |
        grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' |
        grep -vE '^[^:]+:[0-9]+:[[:space:]]*(ux_(bullet(_sub)?|info|error|warning|success)|echo|printf)[[:space:]]'
}

# Raw (non-normalising) reads of ~/.dotfiles-setup-mode: a `cat` of the literal
# path or of a *setup_mode_file*/*mode_file* variable, or a `<` redirect of the
# literal path. Lines that strip CR/whitespace themselves are compliant, as are
# the SSOT itself and the one documented exception below.
_setup_mode_raw_reads() {
    _setup_mode_code_lines |
        grep -E "cat[^|]*\.dotfiles-setup-mode|cat[[:space:]]+\"?\\\$\{?[A-Za-z_]*(setup_)?mode_file|<[[:space:]]*\"?\\\$\{?HOME\}?/\.dotfiles-setup-mode" |
        grep -v "tr -d" |
        grep -v '/shell-common/util/setup_mode_read.sh:' |
        grep -v '/shell-common/functions/setup_mode_help.sh:'
}

@test "guard: no script reads ~/.dotfiles-setup-mode without normalising it" {
    local hits
    hits="$(_setup_mode_raw_reads)" || return 0
    if [ -n "$hits" ]; then
        printf 'raw ~/.dotfiles-setup-mode reads (use _dotfiles_setup_mode):\n%s\n' "$hits"
        return 1
    fi
}

# get_setup_mode() in setup_mode_help.sh is a *diagnostic* that must echo the
# file verbatim — showing the user what is actually on disk is its whole job.
# It is the only allowlisted raw reader, so pin that it stays one file.
@test "guard: setup_mode_help.sh is the only allowlisted raw reader" {
    run grep -c 'cat "\$setup_mode_file"' "${DOTFILES_ROOT}/shell-common/functions/setup_mode_help.sh"
    assert_success
    assert_output "1"
}
