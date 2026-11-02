#!/bin/bash

# scripts/remove-git-crypt-local-config.sh: 로컬 git-crypt 설정 섹션 삭제 (임시)
#
# PURPOSE: 이 저장소는 git-crypt 를 쓰지 않는다 (#594, #2345). 예전 setup.sh 가
# `.git/config` 에 다시 써 넣던 `filter.git-crypt.*` / `diff.git-crypt.*` 섹션이
# 각 PC 에 남아 있으면 worktree 도구가 git-crypt 사용 중으로 오판한다 (#2340).
# 이 스크립트는 두 섹션을 삭제한다. 없는 섹션은 정상으로 취급한다.
#
# WHEN TO RUN: setup.sh 가 자동 호출. 수동 실행도 안전 (멱등).
#
# DELETE WHEN: docs/.ssot/pc-environment.md 의 PC 5대 모두에서
#   git -C ~/dotfiles config --get-regexp 'git-crypt'
# 출력이 비면, 이 스크립트와 setup.sh 의 호출 스텝을 함께 지운다.
#
# EXIT: 항상 0 — 실패해도 setup.sh 흐름을 막지 않는다. 결과는 ux 로그로 표면화.

# UX lib — fail-fast to stay consistent with setup.sh.
_SCRIPT_PATH=$(cd "$(dirname "$0")" && pwd)
DOTFILES_ROOT="$(cd "$_SCRIPT_PATH/.." && pwd)"
UX_LIB="$DOTFILES_ROOT/shell-common/tools/ux_lib/ux_lib.sh"
if [ ! -f "$UX_LIB" ]; then
    echo "CRITICAL ERROR: UX library not found at $UX_LIB. Exiting." >&2
    exit 1
fi
# shellcheck source=/dev/null
. "$UX_LIB"

ux_header "Remove git-crypt config (local)"

if ! git -C "$DOTFILES_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ux_warning "Not a git repo: $DOTFILES_ROOT — skipped"
    exit 0
fi

git -C "$DOTFILES_ROOT" config --local --remove-section filter.git-crypt 2>/dev/null || :
git -C "$DOTFILES_ROOT" config --local --remove-section diff.git-crypt 2>/dev/null || :

if git -C "$DOTFILES_ROOT" config --local --get-regexp '^(filter|diff)\.git-crypt\.' >/dev/null 2>&1; then
    ux_warning "git-crypt config still set — remove by hand: git -C \"$DOTFILES_ROOT\" config --remove-section filter.git-crypt"
else
    ux_success "No git-crypt sections in local config"
fi

exit 0
