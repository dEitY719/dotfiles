#!/usr/bin/env bats
# tests/bats/functions/devx_pr_verify_live_serving_identity.bats
# devx_pr_verify_live_serving_identity (#1859). Fixture: a PR REBASE-merged, so
# its head SHA F was rewritten to F' on main and F is not an ancestor of main.

load '../test_helper'

setup() {
    setup_isolated_home
    export DOTFILES_FORCE_INIT=1
    # shellcheck disable=SC1090
    source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/devx_pr_verify_live_serving_identity.sh"

    R="$TEST_TEMP_HOME/repo"
    git init -q -b main "$R"
    echo base >"$R/a"; _g add -A; _g commit -qm base
    BASE=$(_g rev-parse HEAD)
    _g checkout -qb feature
    echo 'useSyncExternalStore' >"$R/modal.tsx"; _g add -A; _g commit -qm feature
    HEAD_OID=$(_g rev-parse HEAD)
    _g checkout -q main
    echo other >"$R/b"; _g add -A; _g commit -qm other
    _g cherry-pick "$HEAD_OID" >/dev/null
    MERGE_OID=$(_g rev-parse HEAD)

    MERGED=$(jq -n --arg m "$MERGE_OID" --arg h "$HEAD_OID" \
        '{state:"MERGED",mergeCommit:{oid:$m},headRefOid:$h}')
    OPEN=$(jq -n --arg h "$HEAD_OID" '{state:"OPEN",mergeCommit:null,headRefOid:$h}')

    printf 'export function M(){ useSyncExternalStore() }\n' >"$TEST_TEMP_HOME/served.js"
    SERVED="file://$TEST_TEMP_HOME/served.js"
}

teardown() {
    teardown_isolated_home
}

_g() { git -C "$R" -c user.email=t@t -c user.name=t "$@"; }
_si() { printf '%s' "$1" | devx_pr_verify_live_serving_identity "${@:2}" 2>&1; }

@test "target line uses mergeCommit" {
    run _si "$MERGED"
    assert_success
    assert_output "TARGET_SHA=$MERGE_OID (source=mergeCommit, state=MERGED)"
}

@test "mergeCommit on rewritten main -> verified" {
    run _si "$MERGED" "$R"
    assert_output --partial "SERVING_IDENTITY=verified"
}

@test "headRefOid on rewritten main -> mismatch" {
    run _si "$(jq -n --arg h "$HEAD_OID" '{state:"MERGED",mergeCommit:null,headRefOid:$h}')" "$R"
    assert_output --partial "SERVING_IDENTITY=mismatch"
    assert_output --partial "do not claim the feature is absent"
}

@test "unmerged PR falls back to headRefOid" {
    _g checkout -q feature
    run _si "$OPEN" "$R"
    assert_output --partial "TARGET_SHA=$HEAD_OID (source=headRefOid, state=OPEN)"
    assert_output --partial "SERVING_IDENTITY=verified"
}

@test "stale checkout -> mismatch with lag" {
    _g checkout -q "$BASE"
    run _si "$MERGED" "$R"
    assert_output --partial "@ $BASE (behind by 2 commits)"
    assert_output --partial "SERVING_IDENTITY=mismatch"
}

@test "sha mismatch + content match -> WARN, unverified" {
    run _si "$(jq -n --arg h "$HEAD_OID" '{state:"MERGED",mergeCommit:null,headRefOid:$h}')" "$R" \
        --content-url "$SERVED" --symbol useSyncExternalStore
    assert_output --partial "[WARN] SHA 불일치, 내용 일치"
    assert_output --partial "SERVING_IDENTITY=unverified"
}

@test "content absent -> mismatch naming the symbol" {
    run _si "$(jq -n --arg h "$HEAD_OID" '{state:"MERGED",mergeCommit:null,headRefOid:$h}')" "$R" \
        --content-url "$SERVED" --symbol useSyncExternalStore --symbol NotThere
    assert_output --partial "absent from $SERVED: NotThere"
    assert_output --partial "SERVING_IDENTITY=mismatch"
}

@test "--symbol glob characters match literally" {
    run _si "$(jq -n --arg h "$HEAD_OID" '{state:"MERGED",mergeCommit:null,headRefOid:$h}')" "$R" \
        --content-url "$SERVED" --symbol 'use*Store'
    assert_output --partial "SERVING_IDENTITY=mismatch"
}

@test "non-git serving root -> unverified" {
    run _si "$MERGED" "$TEST_TEMP_HOME"
    assert_output --partial "SERVING_IDENTITY=unverified"
}

@test "no sha in stdin -> exit 2" {
    run _si '{}'
    assert_failure 2
}
