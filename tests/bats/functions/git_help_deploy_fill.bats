#!/usr/bin/env bats
# tests/bats/functions/git_help_deploy_fill.bats
# git-help deploy/release/rollback auto-fill placeholders from the cwd repo.

load '../test_helper'

setup() {
    setup_isolated_home
    REPO="${HOME}/app"
    mkdir -p "${REPO}/.github/workflows"
    touch "${REPO}/.github/workflows/ci.yml" \
        "${REPO}/.github/workflows/dev-deploy.yml" \
        "${REPO}/.github/workflows/prod-deploy.yml"
    git -C "$REPO" init -q
    git -C "$REPO" remote add origin git@ghe.example.net:org/app.git
    git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
    git -C "$REPO" tag v1.1.0
    git -C "$REPO" tag v1.10.0
}

teardown() {
    teardown_isolated_home
}

@test "bash: rollback fills workflow, repo coord and previous tag" {
    run_in_bash "cd '${REPO}' && git_help rollback"
    assert_success
    assert_output --partial "gh workflow run prod-deploy.yml --repo ghe.example.net/org/app -f ref=v1.1.0"
}

@test "zsh: deploy fills dev workflow and repo coord" {
    run_in_zsh "cd '${REPO}' && git_help deploy"
    assert_success
    assert_output --partial "gh workflow run dev-deploy.yml --repo ghe.example.net/org/app -f ref=main"
}

@test "bash: ambiguous workflow keeps placeholder" {
    touch "${REPO}/.github/workflows/prod-deploy-canary.yml"
    run_in_bash "cd '${REPO}' && git_help release"
    assert_success
    assert_output --partial "gh workflow run <PROD_WORKFLOW> --repo ghe.example.net/org/app"
}

@test "bash: DOTFILES_HELP_STATIC keeps every placeholder" {
    run_in_bash "cd '${REPO}' && DOTFILES_HELP_STATIC=1 git_help rollback"
    assert_success
    assert_output --partial "gh workflow run <PROD_WORKFLOW> --repo <REPO_COORD> -f ref=<PREV_TAG>"
}

@test "bash: outside a git repo keeps placeholders" {
    run_in_bash "cd '${HOME}' && git_help deploy"
    assert_success
    assert_output --partial "gh workflow run <DEV_WORKFLOW> --repo <REPO_COORD>"
}
