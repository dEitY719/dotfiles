#!/bin/bash

# scripts/disable-git-crypt-local.sh: 로컬 git-crypt smudge/clean 무력화
#
# PURPOSE: Host-side 안전망 (#594). Repo 레벨에서 .gitattributes 의
# `filter=git-crypt` 항목은 이미 제거됐지만, 사용자 머신에 과거
# `filter.git-crypt.required=true` 같은 git config 가 남아있거나, 옛 워크트리
# 가 잔존하면 checkout 시 smudge filter 가 호출되어 InvalidSymbol / NBSP
# 류 손상이 재현될 수 있다. 이 스크립트는 git config 4 항목을 강제 무력화
# 한다.
#
# WHEN TO RUN: setup.sh 가 자동 호출. 수동 실행도 안전 (멱등).
#
# EXIT: 항상 0 — 실패해도 setup.sh 흐름을 막지 않는다. 결과는 ux 로그로 표면화.

# UX lib — fail-fast to stay consistent with install.sh / setup.sh.
_SCRIPT_PATH=$(cd "$(dirname "$0")" && pwd)
DOTFILES_ROOT="$(cd "$_SCRIPT_PATH/.." && pwd)"
UX_LIB="$DOTFILES_ROOT/shell-common/tools/ux_lib/ux_lib.sh"
if [ ! -f "$UX_LIB" ]; then
    echo "CRITICAL ERROR: UX library not found at $UX_LIB. Exiting." >&2
    exit 1
fi
# shellcheck source=/dev/null
. "$UX_LIB"

ux_header "Disable git-crypt smudge/clean (local)"

if ! git -C "$DOTFILES_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ux_warning "Not a git repo: $DOTFILES_ROOT — skipped"
    exit 0
fi

git -C "$DOTFILES_ROOT" config filter.git-crypt.smudge cat
git -C "$DOTFILES_ROOT" config filter.git-crypt.clean cat
git -C "$DOTFILES_ROOT" config filter.git-crypt.required false
git -C "$DOTFILES_ROOT" config diff.git-crypt.textconv cat

ux_success "filter.git-crypt.{smudge,clean,required} + diff.git-crypt.textconv neutralized"
ux_info    "Idempotent — safe to re-run on every setup.sh."

exit 0
