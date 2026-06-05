#!/usr/bin/env bats
# tests/bats/functions/sync_to_deploy.bats
# Coverage for shell-common/tools/integrations/sync_to_deploy.sh.
# shellcheck disable=SC2016

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

_sync_fixture_base() {
    FIXTURE_DIR="$TEST_TEMP_HOME/sync-to-deploy"
    ORIGIN_BARE="$FIXTURE_DIR/origin.git"
    UPSTREAM_BARE="$FIXTURE_DIR/upstream.git"
    SEED_REPO="$FIXTURE_DIR/seed"
    WORK_REPO="$FIXTURE_DIR/work"

    mkdir -p "$FIXTURE_DIR"
    git init -q --bare --initial-branch=main "$ORIGIN_BARE"
    git init -q --bare --initial-branch=main "$UPSTREAM_BARE"
    git init -q --initial-branch=main "$SEED_REPO"

    (
        cd "$SEED_REPO" || exit 1
        git config user.email "test@example.invalid"
        git config user.name "bats"
        git config core.hooksPath /dev/null
        printf 'base\n' >app.txt
        git add app.txt
        git commit -q -m "base"
        git remote add origin "$ORIGIN_BARE"
        git remote add upstream "$UPSTREAM_BARE"
        git push -q origin main
        git push -q origin main:dev-server
        git push -q upstream main
    )
}

_sync_fixture_success() {
    _sync_fixture_base
    (
        cd "$SEED_REPO" || exit 1
        printf 'upstream\n' >>app.txt
        git commit -q -am "upstream change"
        git push -q upstream main
    )
    git clone -q "$ORIGIN_BARE" "$WORK_REPO"
    (
        cd "$WORK_REPO" || exit 1
        git config user.email "test@example.invalid"
        git config user.name "bats"
        git config core.hooksPath /dev/null
        git remote add upstream "$UPSTREAM_BARE"
    )
}

_sync_fixture_conflict() {
    _sync_fixture_base
    (
        cd "$SEED_REPO" || exit 1
        printf 'origin change\n' >app.txt
        git commit -q -am "origin change"
        git push -q origin main
        git checkout -q -B upstream-work HEAD~1
        printf 'upstream change\n' >app.txt
        git commit -q -am "upstream change"
        git push -q upstream upstream-work:main
    )
    git clone -q "$ORIGIN_BARE" "$WORK_REPO"
    (
        cd "$WORK_REPO" || exit 1
        git config user.email "test@example.invalid"
        git config user.name "bats"
        git config core.hooksPath /dev/null
        git remote add upstream "$UPSTREAM_BARE"
    )
}

_run_sync_in_bash() {
    local snippet="$1"
    run bash --noprofile --norc -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        export SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_FORCE_INIT=1
        export DOTFILES_TEST_MODE=1
        export HOME='${HOME}'
        export TERM=dumb
        cd '${WORK_REPO}' || exit 99
        . '${DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh'
        . '${DOTFILES_ROOT}/shell-common/tools/integrations/sync_to_deploy.sh'
        ${snippet}
    "
}

@test "bash: sync_to_deploy function exists after main load" {
    run_in_bash 'declare -f sync_to_deploy >/dev/null && alias sync-to-deploy >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: sync_to_deploy function exists after main load" {
    run_in_zsh 'typeset -f sync_to_deploy >/dev/null && alias sync-to-deploy >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: sync_to_deploy_help is registered under devops" {
    run_in_bash 'my_help_impl >/dev/null; echo "${HELP_CATEGORY_MEMBERS[devops]}"; echo "${HELP_DESCRIPTIONS[sync_to_deploy_help]}"'
    assert_success
    assert_output --partial "sync_to_deploy"
    assert_output --partial "Merge internal/external main branches"
}

@test "success: merges upstream main and pushes deploy branch" {
    _sync_fixture_success

    _run_sync_in_bash '
        sync_to_deploy dev-server >/tmp/sync-to-deploy-success.out 2>&1
        sync_rc=$?
        remote_subject=$(git --git-dir="'"$ORIGIN_BARE"'" log --format=%s -1 dev-server)
        current_branch=$(git symbolic-ref --short HEAD)
        tmp_exists=no
        git show-ref --verify --quiet refs/heads/sync-to-deploy-tmp && tmp_exists=yes
        printf "sync_rc=%s\nremote_subject=%s\ncurrent_branch=%s\ntmp_exists=%s\n" "$sync_rc" "$remote_subject" "$current_branch" "$tmp_exists"
    '

    assert_success
    assert_output --partial "sync_rc=0"
    assert_output --partial "remote_subject=upstream change"
    assert_output --partial "current_branch=main"
    assert_output --partial "tmp_exists=no"
}

@test "dirty worktree: stops before checkout" {
    _sync_fixture_success
    printf 'dirty\n' >>"$WORK_REPO/app.txt"

    _run_sync_in_bash '
        if sync_to_deploy dev-server >/tmp/sync-to-deploy-dirty.out 2>&1; then
            sync_result=unexpected_success
        else
            sync_result=dirty_guard
        fi
        current_branch=$(git symbolic-ref --short HEAD)
        remote_subject=$(git --git-dir="'"$ORIGIN_BARE"'" log --format=%s -1 dev-server)
        printf "sync_result=%s\ncurrent_branch=%s\nremote_subject=%s\n" "$sync_result" "$current_branch" "$remote_subject"
    '

    assert_success
    assert_output --partial "sync_result=dirty_guard"
    assert_output --partial "current_branch=main"
    assert_output --partial "remote_subject=base"
}

@test "conflict: preserves temporary branch and merge state without pushing" {
    _sync_fixture_conflict

    _run_sync_in_bash '
        if sync_to_deploy dev-server >/tmp/sync-to-deploy-conflict.out 2>&1; then
            sync_result=unexpected_success
        else
            sync_result=conflict_detected
        fi
        current_branch=$(git symbolic-ref --short HEAD)
        tmp_exists=no
        git show-ref --verify --quiet refs/heads/sync-to-deploy-tmp && tmp_exists=yes
        merge_head=no
        test -f .git/MERGE_HEAD && merge_head=yes
        remote_subject=$(git --git-dir="'"$ORIGIN_BARE"'" log --format=%s -1 dev-server)
        printf "sync_result=%s\ncurrent_branch=%s\ntmp_exists=%s\nmerge_head=%s\nremote_subject=%s\n" "$sync_result" "$current_branch" "$tmp_exists" "$merge_head" "$remote_subject"
    '

    assert_success
    assert_output --partial "sync_result=conflict_detected"
    assert_output --partial "current_branch=sync-to-deploy-tmp"
    assert_output --partial "tmp_exists=yes"
    assert_output --partial "merge_head=yes"
    assert_output --partial "remote_subject=base"
}
