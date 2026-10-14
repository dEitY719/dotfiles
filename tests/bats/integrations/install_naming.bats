#!/usr/bin/env bats
# tests/bats/integrations/install_naming.bats
# #2148: install/uninstall functions are <tool>_install/<tool>_uninstall, and
# the legacy names stay callable as aliases. Each call runs a stub installer
# (SHELL_COMMON points at a fake tools/custom), so nothing real is installed.

load '../test_helper'

setup() {
    setup_isolated_home
    FAKE_SC="$TEST_TEMP_HOME/sc"
    mkdir -p "$FAKE_SC/tools/custom"
    for s in install_claude install_docker uninstall_docker install_postgresql install_npm uninstall_npm; do
        printf '#!/bin/sh\necho "ran %s"\n' "$s" >"$FAKE_SC/tools/custom/$s.sh"
    done
}

teardown() {
    teardown_isolated_home
}

# $1 = bash|zsh, $2 = integration file, $3 = command name to call
_call() {
    local _sh="$1" _flag="--norc" _pre="shopt -s expand_aliases"
    [ "$_sh" = zsh ] && _flag="-f" && _pre=":"
    run "$_sh" "$_flag" -c "
        export DOTFILES_FORCE_INIT=1 TERM=dumb
        $_pre
        . '$SHELL_COMMON/tools/ux_lib/ux_lib.sh'
        . '$SHELL_COMMON/tools/integrations/$2'
        SHELL_COMMON='$FAKE_SC'
        eval '$3'
    "
}

@test "new names and legacy aliases run the same installer (bash + zsh)" {
    for sh in bash zsh; do
        command -v "$sh" >/dev/null 2>&1 || continue
        while read -r file new legacy script; do
            _call "$sh" "$file" "$new"
            [ "$status" -eq 0 ] || { echo "$sh $new: $output"; false; }
            [ "$output" = "ran $script" ] || { echo "$sh $new: $output"; false; }
            _call "$sh" "$file" "$legacy"
            [ "$status" -eq 0 ] || { echo "$sh $legacy: $output"; false; }
            [ "$output" = "ran $script" ] || { echo "$sh $legacy: $output"; false; }
        done <<'EOF'
claude.sh claude_install clinstall install_claude
claude.sh claude-install clinstall install_claude
docker.sh docker_install dinstall install_docker
docker.sh docker_uninstall duninstall uninstall_docker
postgresql.sh postgresql_install pinstall install_postgresql
npm.sh npm_install npminstall install_npm
npm.sh npm_uninstall npmuninstall uninstall_npm
EOF
    done
}

@test "git.sh shared functions load in zsh, prompt block stays bash-only" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
    run zsh -f -c "
        alias gsw='git switch' gf='git fetch'
        DOTFILES_FORCE_INIT=1
        . '$SHELL_COMMON/tools/integrations/git.sh'
        whence -w git_lfs_install gf gset _short_pwd gsw
    "
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
    [[ "$output" == *"git_lfs_install: function"* ]]
    [[ "$output" == *"gf: function"* ]]
    [[ "$output" == *"gset: function"* ]]
    [[ "$output" == *"_short_pwd: none"* ]]
    [[ "$output" == *"gsw: alias"* ]]
}
