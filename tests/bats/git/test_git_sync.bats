#!/usr/bin/env bats
# tests/bats/git/test_git_sync.bats
#
# Issue #1721 — `git sync` 전역 alias 이식.
#
# 검증 대상은 두 가지뿐이다:
#   1. SSOT(`git/.gitconfig`)에 alias 가 실제로 등록돼 있고, 그 alias 를
#      include 한 **다른 저장소**에서 스크립트가 호출된다(전역화의 핵심).
#   2. upstream 리모트가 없는 프로젝트에서 사전 가드가 안내 후 종료한다
#      (에러 스택 없음).
#
# merge/push 경로는 네트워크와 원격 상태에 의존하므로 여기서 다루지 않는다.
# 격리: 임시 저장소 + `GIT_CONFIG_GLOBAL` 로 실제 `~/.gitconfig` 를 건드리지 않는다.

load '../test_helper'

setup() {
    REAL_ROOT="${_BATS_REAL_DOTFILES_ROOT}"
    SCRIPT="${REAL_ROOT}/git/scripts/git-sync.sh"
    WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/git-sync-bats.XXXXXX")"

    printf '[include]\n\tpath = %s/git/.gitconfig\n' "$REAL_ROOT" \
        >"${WORK_DIR}/gitconfig.global"

    git init -q -b main "${WORK_DIR}/repo"
    git -C "${WORK_DIR}/repo" -c user.email=t@t -c user.name=t \
        commit -q --allow-empty --no-verify -m init
}

teardown() {
    if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
}

# 임시 저장소에서 alias 를 태워 git 을 실행한다.
_git_in_repo() {
    env GIT_CONFIG_GLOBAL="${WORK_DIR}/gitconfig.global" \
        DOTFILES_ROOT="$REAL_ROOT" \
        git -C "${WORK_DIR}/repo" "$@"
}

@test "git-sync.sh: 스크립트가 존재하고 실행 권한이 있다" {
    [ -x "$SCRIPT" ]
}

@test "git-sync.sh: SSOT .gitconfig 에 alias.sync 가 등록돼 있다" {
    run git config --file "${REAL_ROOT}/git/.gitconfig" --get alias.sync
    [ "$status" -eq 0 ]
    [[ "$output" == *"git/scripts/git-sync.sh"* ]]
}

@test "git-sync.sh: dotfiles 밖 저장소에서 alias 가 스크립트를 호출한다" {
    # `--help` 는 git 이 alias 정의 출력으로 가로채므로 `-h` 로 확인한다.
    run _git_in_repo sync -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"GIT_SYNC_EXTERNAL_REMOTE"* ]]
}

@test "git-sync.sh: upstream 리모트가 없으면 안내 후 종료한다" {
    run _git_in_repo sync
    [ "$status" -eq 1 ]
    [[ "$output" == *"'upstream' 리모트가 없습니다"* ]]
    # 에러 스택(bash 트레이스)이 새어나오지 않아야 한다.
    [[ "$output" != *"git-sync.sh: line"* ]]
}

@test "git-sync.sh: main 이 아닌 브랜치에서는 거부한다" {
    git -C "${WORK_DIR}/repo" remote add upstream "${WORK_DIR}/repo"
    git -C "${WORK_DIR}/repo" checkout -q -b feature/x

    run _git_in_repo sync
    [ "$status" -eq 1 ]
    [[ "$output" == *"'feature/x'"* ]]
}
