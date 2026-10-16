#!/usr/bin/env bats
# tests/bats/tools/post_merge_verify_callers.bats
# The #1571 cross-file drift guard on this repo's two herdr cron dispatchers.
#
# This repo shipped the same defect twice by fixing two of the three herdr
# dispatchers (#1530 -> #1549, #1560 -> #1571). The third — the post-merge
# verification dispatch, PMV_SETTLE_SECONDS — lives in dEitY719/gh-verify-skills
# (skills/post-merge-verify/references/dispatch.sh.md) and is tested there, in
# tests/bats/gh_pr_post_merge_verify.bats. What this repo pins is the two cron
# dispatchers and their four constants. Split out of
# tests/bats/skills/gh_pr_post_merge_verify.bats when that suite moved (#2200).

load '../test_helper'

_pmv_wait_files() {
    printf '%s\n' \
        "${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/custom/issue_watcher_cron.sh" \
        "${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/custom/pr_merge_train_cron.sh"
}

_PMV_WAIT_ASSIGN='^(_IW_SETTLE_SECONDS|_PMT_SETTLE_SECONDS|PMV_SETTLE_SECONDS|_IW_START_RETRY_SLEEP|_PMT_START_RETRY_SLEEP)='

@test "1571: all four herdr wait constants exist across the two cron dispatchers" {
    local _n
    _n=$(_pmv_wait_files | xargs grep -hE "$_PMV_WAIT_ASSIGN" | wc -l)
    [ "$_n" -eq 4 ]
}

@test "1571: no herdr wait constant has drifted off 13" {
    local _bad
    _bad=$(_pmv_wait_files | xargs grep -hE "$_PMV_WAIT_ASSIGN" | grep -vE ':-13\}"$' || true)
    [ -z "$_bad" ] || fail "wait constant not defaulted to 13: ${_bad}"
}

@test "1571: every herdr wait constant stays env-overridable" {
    local _bad
    _bad=$(_pmv_wait_files | xargs grep -hE "$_PMV_WAIT_ASSIGN" |
        grep -vE '="\$\{[A-Z_]+:-13\}"$' || true)
    [ -z "$_bad" ] || fail "wait constant is not env-overridable: ${_bad}"
}

@test "1571: the cron dispatchers' wait comments still name the third site" {
    local _iw _pmt
    _iw="${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/custom/issue_watcher_cron.sh"
    _pmt="${_BATS_REAL_DOTFILES_ROOT}/shell-common/tools/custom/pr_merge_train_cron.sh"
    run grep -qF -- 'PMV_SETTLE_SECONDS' "$_iw"
    assert_success
    run grep -qF -- 'PMV_SETTLE_SECONDS' "$_pmt"
    assert_success
}
