#!/usr/bin/env bats
# tests/bats/integrations/docker_denv_menu.bats
# Regression for #1990: denv with no argument must pass the running container
# names to ux_menu as arguments (not stdin) and exec into the chosen one, in
# bash and zsh. docker is a stub that logs argv; ux_menu runs its fallback path
# with the choice fed on stdin.

load '../test_helper'

setup() {
    setup_isolated_home
    STUB_BIN="$TEST_TEMP_HOME/bin"
    DOCKER_LOG="$TEST_TEMP_HOME/docker.log"
    mkdir -p "$STUB_BIN"
    cat >"$STUB_BIN/docker" <<'STUB'
#!/bin/sh
if [ "$1" = ps ]; then
    [ -n "${STUB_EMPTY-}" ] || printf 'web\ndb\ncache\n'
    exit 0
fi
printf 'argc=%s argv=%s\n' "$#" "$*" >>"$DOCKER_LOG"
STUB
    chmod +x "$STUB_BIN/docker"
}

teardown() {
    teardown_isolated_home
}

# $1 = bash|zsh, $2 = stdin fed to ux_menu's fallback, $3 = extra prelude
_run_denv() {
    local _flag="--norc"
    [ "$1" = zsh ] && _flag="-f"
    run "$1" "$_flag" -c "
        export PATH='$STUB_BIN':\"\$PATH\" DOCKER_LOG='$DOCKER_LOG' DOTFILES_FORCE_INIT=1 TERM=dumb
        . '$SHELL_COMMON/tools/ux_lib/ux_lib.sh'
        . '$SHELL_COMMON/tools/integrations/docker.sh'
        python3() { return 1; }
        $3
        printf '$2' | denv
    "
}

@test "bash+zsh: denv menu lists 3 containers and execs into the chosen one" {
    local _sh
    for _sh in bash zsh; do
        rm -f "$DOCKER_LOG"
        _run_denv "$_sh" '2\n'
        assert_success
        assert_output --partial '1) web'
        assert_output --partial '3) cache'
        run cat "$DOCKER_LOG"
        assert_output "argc=3 argv=exec db env"
    done
}

@test "bash+zsh: denv passes containers to ux_menu as separate args" {
    local _sh
    for _sh in bash zsh; do
        _run_denv "$_sh" '' 'ux_menu() { shift; printf "%s|" "$@" >"$DOCKER_LOG.menu"; echo 0; }'
        assert_success
        run cat "$DOCKER_LOG.menu"
        assert_output "web|db|cache|"
    done
}

@test "bash+zsh: cancel and no containers make no docker exec" {
    local _sh
    for _sh in bash zsh; do
        _run_denv "$_sh" '0\n'
        assert_success
        _run_denv "$_sh" '' 'export STUB_EMPTY=1'
        assert_failure
        assert_output --partial 'No running containers found.'
    done
    [ ! -e "$DOCKER_LOG" ]
}
