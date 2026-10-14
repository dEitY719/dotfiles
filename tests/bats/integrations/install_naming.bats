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
    " </dev/null
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
docker.sh docker-install dinstall install_docker
docker.sh docker_uninstall duninstall uninstall_docker
docker.sh docker-uninstall duninstall uninstall_docker
postgresql.sh postgresql_install pinstall install_postgresql
postgresql.sh postgresql-install pinstall install_postgresql
npm.sh npm_install npminstall install_npm
npm.sh npm_uninstall npmuninstall uninstall_npm
EOF
    done
}

# Every function in git.sh's shared block, each pre-aliased the way an
# oh-my-zsh-style plugin could: zsh must still define them all.
_GIT_SHARED_FUNCS="gf git_rm_cached gupa gupdel glub gset git_lfs_install git_lfs_track"

@test "git.sh shared functions load in zsh over same-named aliases, prompt block stays bash-only" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
    run zsh -f -c "
        for f in $_GIT_SHARED_FUNCS; do alias \$f='echo shadowed'; done
        alias gsw='git switch'
        DOTFILES_FORCE_INIT=1
        . '$SHELL_COMMON/tools/integrations/git.sh'
        whence -w $_GIT_SHARED_FUNCS gsw
        whence -w _short_pwd || echo 'no _short_pwd'
        alias git-lfs-install glfs
    " </dev/null
    [ "$status" -eq 0 ]
    for f in $_GIT_SHARED_FUNCS; do
        [[ "$output" == *"$f: function"* ]] || { echo "$f not a function: $output"; false; }
    done
    [[ "$output" == *"gsw: alias"* ]]
    [[ "$output" == *"no _short_pwd"* ]]
    [[ "$output" == *"git-lfs-install=git_lfs_install"* ]]
}

@test "git.sh loads the prompt block and gsw in bash" {
    run bash --norc -c "
        DOTFILES_FORCE_INIT=1 PROMPT_COMMAND=
        . '$SHELL_COMMON/tools/integrations/git.sh'
        type -t gsw _short_pwd __git_ps1 gf
        printf 'PC=%s\n' \"\$PROMPT_COMMAND\"
        case \"\$PS1\" in *_CACHED_SHORT_PWD*) echo ps1-ok ;; esac
    " </dev/null
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c '^function$')" -eq 4 ]
    [[ "$output" == *"PC=_update_prompt_cache"* ]]
    [[ "$output" == *"ps1-ok"* ]]
}
