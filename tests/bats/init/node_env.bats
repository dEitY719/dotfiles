#!/usr/bin/env bats
# tests/bats/init/node_env.bats
# Issue #2093 — shell-common/env/node.sh makes Node.js trust the OS CA store
# (TLS-intercepting proxy PCs) without overriding a value the user pre-set.

load '../test_helper'

_source_node() {
    run env -u NODE_USE_SYSTEM_CA DOTFILES_FORCE_INIT=1 "$@" \
        bash -c ". '${SHELL_COMMON}/env/node.sh'; printf '%s' \"\$NODE_USE_SYSTEM_CA\""
}

@test "node.sh: exports NODE_USE_SYSTEM_CA=1 by default" {
    _source_node
    assert_success
    assert_output "1"
}

@test "node.sh: keeps a pre-set NODE_USE_SYSTEM_CA value" {
    _source_node NODE_USE_SYSTEM_CA=0
    assert_success
    assert_output "0"
}

@test "node.sh: the export reaches child processes" {
    run env -u NODE_USE_SYSTEM_CA DOTFILES_FORCE_INIT=1 \
        bash -c ". '${SHELL_COMMON}/env/node.sh'; sh -c 'printf %s \"\$NODE_USE_SYSTEM_CA\"'"
    assert_success
    assert_output "1"
}
