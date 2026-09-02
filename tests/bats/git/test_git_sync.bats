#!/usr/bin/env bats
# tests/bats/git/test_git_sync.bats
#
# Issue #1721 — `git sync` 전역 alias 이식.
#
# 두 층을 검증한다:
#   1. 정적 사실 — SSOT(`git/.gitconfig`)에 alias 가 등록돼 있고, 그 alias 를
#      include 한 **다른 저장소**에서 스크립트가 호출된다(전역화의 핵심).
#      경로에 공백이 있어도 alias 가 깨지지 않는다.
#   2. 오케스트레이션 — fetch → origin merge → upstream merge → push 와
#      멱등 재개를, 로컬 bare 저장소를 origin/upstream 으로 세워 네트워크 없이 돈다.
#
# 격리: 임시 저장소 + `GIT_CONFIG_GLOBAL` 로 실제 `~/.gitconfig` 를 건드리지 않고,
#   core.hooksPath 를 빈 디렉터리로 덮어 개발자의 실제 git 훅이 끼어들지 못하게 한다.
#   커밋 신원은 GIT_AUTHOR_*/GIT_COMMITTER_* 로 고정해 개발자 신원을 상속하지 않는다.

load '../test_helper'

setup() {
    REAL_ROOT="${_BATS_REAL_DOTFILES_ROOT}"
    SCRIPT="${REAL_ROOT}/git/scripts/git-sync.sh"
    WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/git-sync-bats.XXXXXX")"

    mkdir -p "${WORK_DIR}/no-hooks"
    _write_global_config "${WORK_DIR}/gitconfig.global" "${REAL_ROOT}/git/.gitconfig"
    export GIT_CONFIG_GLOBAL="${WORK_DIR}/gitconfig.global"

    # 픽스처·스크립트가 만드는 모든 커밋의 신원 고정(개발자 신원 비상속).
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t
    export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

    git init -q -b main "${WORK_DIR}/repo"
    git -C "${WORK_DIR}/repo" -c user.email=t@t -c user.name=t \
        commit -q --allow-empty --no-verify -m init
}

teardown() {
    if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
}

# <출력 파일> <include 대상 .gitconfig> — SSOT 를 include 한 뒤 훅 경로만 무력화한다.
# (include 뒤에 온 값이 이긴다.)
_write_global_config() {
    printf '[include]\n\tpath = %s\n[core]\n\thooksPath = %s/no-hooks\n' \
        "$2" "$WORK_DIR" >"$1"
}

# 임시 저장소에서 alias 를 태워 git 을 실행한다.
_git_in_repo() {
    env DOTFILES_ROOT="$REAL_ROOT" git -C "${WORK_DIR}/repo" "$@"
}

# 픽스처용 로컬 git (alias 없이 직접 실행).
_repo() {
    git -C "${WORK_DIR}/repo" "$@"
}

# origin/upstream 을 로컬 bare 저장소로 세우고 init 커밋을 양쪽에 심는다.
_seed_remotes() {
    git init --bare -q -b main "${WORK_DIR}/origin.git"
    git init --bare -q -b main "${WORK_DIR}/upstream.git"
    _repo remote add origin "${WORK_DIR}/origin.git"
    _repo remote add upstream "${WORK_DIR}/upstream.git"
    _repo push -q origin main
    _repo push -q upstream main
}

# <bare 저장소> <파일> <내용> — 임시 클론을 거쳐 원격에 커밋 1개를 추가한다.
_commit_to_remote() {
    local clone="${WORK_DIR}/clone.$$.${RANDOM}"
    git clone -q "$1" "$clone"
    printf '%s\n' "$3" >"${clone}/$2"
    git -C "$clone" add "$2"
    git -C "$clone" commit -q --no-verify -m "remote: $2"
    git -C "$clone" push -q origin main
    rm -rf "$clone"
}

# <파일> <내용> — 로컬 저장소에 커밋 1개를 추가한다.
_commit_local() {
    printf '%s\n' "$2" >"${WORK_DIR}/repo/$1"
    _repo add "$1"
    _repo commit -q --no-verify -m "local: $1"
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
    _repo remote add upstream "${WORK_DIR}/repo"
    _repo checkout -q -b feature/x

    run _git_in_repo sync
    [ "$status" -eq 1 ]
    [[ "$output" == *"'feature/x'"* ]]
}

# ── 회귀: alias 경로에 공백이 있어도 깨지지 않는다 (Fix 1) ──
@test "git-sync.sh: dotfiles 경로에 공백이 있어도 alias 가 동작한다" {
    local spaced="${WORK_DIR}/dot files"
    mkdir -p "$spaced"
    cp -r "${REAL_ROOT}/git" "${spaced}/git"

    _write_global_config "${WORK_DIR}/gitconfig.spaced" "${spaced}/git/.gitconfig"

    run env GIT_CONFIG_GLOBAL="${WORK_DIR}/gitconfig.spaced" \
        DOTFILES_ROOT="$spaced" git -C "${WORK_DIR}/repo" sync -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"GIT_SYNC_EXTERNAL_REMOTE"* ]]
}

# ── 오케스트레이션 ──
@test "git-sync.sh: origin·upstream 을 흡수하고 origin 으로 push 한다" {
    _seed_remotes
    _commit_to_remote "${WORK_DIR}/origin.git" o.txt origin-side
    _commit_to_remote "${WORK_DIR}/upstream.git" u.txt upstream-side

    run _git_in_repo sync
    [ "$status" -eq 0 ]
    [[ "$output" == *"git sync 완료"* ]]

    # 로컬 main 이 두 원격의 고유 커밋을 모두 담았다.
    [ -f "${WORK_DIR}/repo/o.txt" ]
    [ -f "${WORK_DIR}/repo/u.txt" ]
    # origin bare 도 같은 tip 으로 전진했다.
    [ "$(_repo rev-parse main)" = "$(git -C "${WORK_DIR}/origin.git" rev-parse main)" ]
}

@test "git-sync.sh: origin/main 을 upstream/main 보다 먼저 병합한다" {
    _seed_remotes
    _commit_to_remote "${WORK_DIR}/origin.git" o.txt origin-side
    _commit_to_remote "${WORK_DIR}/upstream.git" u.txt upstream-side

    run _git_in_repo sync
    [ "$status" -eq 0 ]

    local merges
    merges=$(printf '%s\n' "$output" | sed -n 's/^  \$ git merge --no-edit //p')
    [ "$(printf '%s\n' "$merges" | sed -n 1p)" = "origin/main" ]
    [ "$(printf '%s\n' "$merges" | sed -n 2p)" = "upstream/main" ]
}

@test "git-sync.sh: 지점 A 충돌 시 abort 없이 멈추고 안내한다" {
    _seed_remotes
    _commit_to_remote "${WORK_DIR}/origin.git" c.txt origin-side
    _commit_local c.txt local-side

    run _git_in_repo sync
    [ "$status" -eq 1 ]
    [[ "$output" == *"merge conflict (지점 A)"* ]]
    [[ "$output" == *"충돌 마커"* ]]
    # merge --abort 하지 않음 = 해결분 보존(멱등 재개의 핵심).
    [ -f "${WORK_DIR}/repo/.git/MERGE_HEAD" ]
    grep -q '<<<<<<<' "${WORK_DIR}/repo/c.txt"
}

@test "git-sync.sh: 충돌 해결 후 재실행하면 이어서 완료한다" {
    _seed_remotes
    _commit_to_remote "${WORK_DIR}/origin.git" c.txt origin-side
    _commit_to_remote "${WORK_DIR}/upstream.git" u.txt upstream-side
    _commit_local c.txt local-side

    run _git_in_repo sync
    [ "$status" -eq 1 ]
    [ -f "${WORK_DIR}/repo/.git/MERGE_HEAD" ]

    printf 'resolved\n' >"${WORK_DIR}/repo/c.txt"
    _repo add c.txt

    run _git_in_repo sync
    [ "$status" -eq 0 ]
    [[ "$output" == *"이전 merge 재개 감지"* ]]
    [[ "$output" == *"git sync 완료"* ]]
    [ ! -f "${WORK_DIR}/repo/.git/MERGE_HEAD" ]
    [ -f "${WORK_DIR}/repo/u.txt" ]
    [ "$(_repo rev-parse main)" = "$(git -C "${WORK_DIR}/origin.git" rev-parse main)" ]
}

@test "git-sync.sh: 충돌이 안 풀린 채 재실행하면 거부한다" {
    _seed_remotes
    _commit_to_remote "${WORK_DIR}/origin.git" c.txt origin-side
    _commit_local c.txt local-side

    run _git_in_repo sync
    [ "$status" -eq 1 ]

    # 마커를 남긴 채 git add 만 한 상태 — 스테이징 내용으로 잡아내야 한다.
    _repo add c.txt

    run _git_in_repo sync
    [ "$status" -eq 1 ]
    [[ "$output" == *"아직 해결되지 않은 충돌"* ]]
}

# ── 회귀: 충돌이 아닌 merge 실패에 충돌 안내를 하지 않는다 (Fix 2) ──
@test "git-sync.sh: merge 가 시작조차 못하면 충돌 안내를 하지 않는다" {
    _seed_remotes
    _commit_to_remote "${WORK_DIR}/origin.git" o.txt origin-side
    # 병합이 덮어쓸 untracked 파일 — git 은 병합을 시작하지 않고 거부한다.
    printf 'untracked\n' >"${WORK_DIR}/repo/o.txt"

    run _git_in_repo sync
    [ "$status" -eq 1 ]
    [[ "$output" == *"병합이 시작되지도 못했습니다"* ]]
    [[ "$output" == *"o.txt"* ]]
    # 쓸 수 없는 충돌 안내가 나오면 안 된다.
    [[ "$output" != *"충돌 마커"* ]]
    [[ "$output" != *"merge conflict"* ]]
    [ ! -f "${WORK_DIR}/repo/.git/MERGE_HEAD" ]
}

# ── 회귀: url 이 여러 개인 리모트를 "없음"으로 오판하지 않는다 (Fix 4) ──
@test "git-sync.sh: upstream 에 url 이 여러 개여도 존재로 인식한다" {
    _seed_remotes
    # `git config --get` 은 값이 여러 개면 git 버전에 따라 exit 2 이거나 마지막 값만
    # 돌려준다 — 존재 확인의 정확한 API 는 `git remote get-url`.
    _repo remote set-url --add upstream "${WORK_DIR}/origin.git"

    run _git_in_repo sync
    [ "$status" -eq 0 ]
    [[ "$output" != *"리모트가 없습니다"* ]]
}
