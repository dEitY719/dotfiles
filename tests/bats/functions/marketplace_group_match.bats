#!/usr/bin/env bats
# tests/bats/functions/marketplace_group_match.bats
# `csm list <plugin>` exact-match and `csm list --all` summary (issue #2258).
#
# The plugin filter is matched as a fixed whole line (grep -qxF), so a filter
# with regex metacharacters must not match a different plugin name, and the
# --all overview must name the marketplace count instead of a dangling
# "skills across".

load '../test_helper'

setup() {
    setup_isolated_home
    command -v jq >/dev/null 2>&1 || skip "jq not available"
    MANIFEST="${HOME}/.claude/plugins/marketplaces/.skills-manifest.json"
    mkdir -p "${MANIFEST%/*}"
    cat >"$MANIFEST" <<'JSON'
{"version":"1.0","total_skills":3,"skills":[
 {"name":"s1","description":"d","license":"MIT","path":"/p","category":"pl","marketplace":"m1","plugin":"pl"},
 {"name":"s2","description":"d","license":"MIT","path":"/p","category":"pl.*x","marketplace":"m1","plugin":"pl.*x"},
 {"name":"s3","description":"d","license":"MIT","path":"/p","category":"pl","marketplace":"m2","plugin":"pl"}
]}
JSON
}

teardown() {
    teardown_isolated_home
}

_csm() {
    run bash -c "
        export DOTFILES_FORCE_INIT=1 HOME='${HOME}'
        source '${SHELL_COMMON}/tools/ux_lib/ux_lib.sh'
        source '${SHELL_COMMON}/functions/marketplace.sh'
        $1
    "
}

@test "exact plugin name matches" {
    _csm "_claude_skills_marketplace_group pl"
    assert_success
    assert_output --partial "Plugin: pl"
    assert_output --partial "Skills (2)"
}

@test "regex metacharacters in the filter do not match another plugin" {
    _csm "_claude_skills_marketplace_group 'pl.*'"
    assert_failure
    assert_output --partial "No exact match for plugin"
    refute_output --partial "Plugin: pl.*x"
}

@test "list --all names the marketplace count" {
    _csm "_claude_skills_marketplace_list --all"
    assert_success
    assert_output --partial "Total: 3 skills across 2 marketplaces"
}
