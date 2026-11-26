#!/usr/bin/env bats
# tests/bats/setup/setup_isolated_home.bats
# Issue #2469 — setup_isolated_home must drop host leaks that survive a HOME
# swap: an exported GH_HOST and the developer's real ~/.opencode/bin on PATH.

load '../test_helper'

teardown() {
    teardown_isolated_home
}

@test "setup_isolated_home unsets GH_HOST and strips the real ~/.opencode/bin from PATH" {
    export GH_HOST=github.com
    local oc="$_BATS_REAL_HOME/.opencode/bin"
    export PATH="$oc:/usr/bin:$oc:$oc/:$oc:$oc/sub:/bin:$oc/"
    setup_isolated_home
    [ -z "${GH_HOST+x}" ]
    [ "$PATH" = "/usr/bin:$oc/sub:/bin" ]
}
