#!/usr/bin/env bats
# tests/bats/integrations/docker_apt_word_split.bats
# Regression for #1952: docker bulk-cleanup functions must pass each ID as a
# separate argument in bash AND zsh, and appa_list must sort/dedupe the whole
# deb + deb-src listing. docker is a stub that logs argv; nothing real runs.

load '../test_helper'

setup() {
    setup_isolated_home
    STUB_BIN="$TEST_TEMP_HOME/bin"
    DOCKER_LOG="$TEST_TEMP_HOME/docker.log"
    mkdir -p "$STUB_BIN"
    cat >"$STUB_BIN/docker" <<'EOF'
#!/bin/sh
case "$1 $2" in
    "ps -q" | "ps -aq" | "images -f" | "volume ls")
        [ -n "${STUB_EMPTY-}" ] || printf 'aaa\nbbb\nccc\n'
        exit 0
        ;;
esac
printf 'argc=%s argv=%s\n' "$#" "$*" >>"$DOCKER_LOG"
EOF
    chmod +x "$STUB_BIN/docker"
}

teardown() {
    teardown_isolated_home
}

# $1 = bash|zsh, $2 = command line run after sourcing ux_lib + the integration
_run_sh() {
    local _sh="$1" _flag="--norc"
    [ "$_sh" = zsh ] && _flag="-f"
    run "$_sh" "$_flag" -c "
        export PATH='$STUB_BIN':\"\$PATH\" DOCKER_LOG='$DOCKER_LOG' DOTFILES_FORCE_INIT=1 TERM=dumb
        . '$SHELL_COMMON/tools/ux_lib/ux_lib.sh'
        . '$SHELL_COMMON/tools/integrations/docker.sh'
        . '$SHELL_COMMON/tools/integrations/apt.sh'
        $2
    "
}

_assert_split() {
    _run_sh "$1" "$2"
    assert_success
    run cat "$DOCKER_LOG"
    assert_output "argc=$3 argv=$4 aaa bbb ccc"
}

@test "bash: dstopall passes 3 IDs as 3 args" { _assert_split bash dstopall 4 stop; }
@test "zsh: dstopall passes 3 IDs as 3 args" { _assert_split zsh dstopall 4 stop; }
@test "bash: drmall passes 3 IDs as 3 args" { _assert_split bash drmall 4 rm; }
@test "zsh: drmall passes 3 IDs as 3 args" { _assert_split zsh drmall 4 rm; }
@test "bash: drm_dangling passes 3 IDs as 3 args" { _assert_split bash drm_dangling 4 rmi; }
@test "zsh: drm_dangling passes 3 IDs as 3 args" { _assert_split zsh drm_dangling 4 rmi; }
@test "bash: dvol_rm_dangling passes 3 IDs as 3 args" { _assert_split bash dvol_rm_dangling 5 "volume rm"; }
@test "zsh: dvol_rm_dangling passes 3 IDs as 3 args" { _assert_split zsh dvol_rm_dangling 5 "volume rm"; }

@test "bash+zsh: empty ID list is a no-op (no docker call)" {
    local _sh _fn
    for _sh in bash zsh; do
        for _fn in dstopall drmall drm_dangling dvol_rm_dangling; do
            _run_sh "$_sh" "STUB_EMPTY=1 $_fn"
            assert_success
        done
    done
    [ ! -e "$DOCKER_LOG" ]
}

@test "bash+zsh: appa_list lists deb and deb-src lines sorted and deduplicated" {
    local _dir="$TEST_TEMP_HOME/sources.list.d" _sh
    mkdir -p "$_dir"
    printf '%s\n' 'deb-src http://ppa.launchpad.net/b/ppa/ubuntu jammy main' \
        'deb http://ppa.launchpad.net/b/ppa/ubuntu jammy main' '# deb http://commented/out jammy main' \
        >"$_dir/b.list"
    printf '%s\n' 'deb http://ppa.launchpad.net/a/ppa/ubuntu jammy main' \
        'deb http://ppa.launchpad.net/b/ppa/ubuntu jammy main' >"$_dir/a.list"
    for _sh in bash zsh; do
        _run_sh "$_sh" "APT_SOURCES_LIST_DIR='$_dir' appa_list | grep '^deb'"
        assert_success
        assert_output "deb http://ppa.launchpad.net/a/ppa/ubuntu jammy main
deb http://ppa.launchpad.net/b/ppa/ubuntu jammy main
deb-src http://ppa.launchpad.net/b/ppa/ubuntu jammy main"
    done
}

@test "bash+zsh: appa_list with no .list files succeeds with no entries" {
    local _sh
    for _sh in bash zsh; do
        _run_sh "$_sh" "APT_SOURCES_LIST_DIR='$TEST_TEMP_HOME/none' appa_list | grep -c '^deb'"
        assert_output "0"
    done
}
