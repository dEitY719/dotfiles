#!/bin/bash

# scripts/flush-transfer.sh: transfer/ 전달물 비우기 (삭제 → 커밋 → push)
#
# PURPOSE: PC 간 1회성 전달용 `transfer/` 디렉토리를 다른 PC에서 참고한 뒤
# 흔적을 지운다. transfer/ 내 모든 파일을 git 에서 제거하고 커밋·push 한다.
#
# WHEN TO RUN: 전달 브랜치(예: chore/avatar-transfer)를 checkout 해 파일을
# 참고한 직후. 멱등하지 않다 — 한 번 비우면 더 지울 것이 없다.
#
# EXIT: 0 성공 / 1 저장소 밖·transfer 없음·git 실패.

set -euo pipefail

# 저장소 루트 (scripts/ 의 부모)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

TRANSFER_DIR="transfer"

# 가드: git 저장소 안인지
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "✗ git 저장소가 아닙니다: $ROOT" >&2
    exit 1
fi

# 가드: transfer/ 가 존재하고 추적 파일이 있는지
if [ ! -d "$TRANSFER_DIR" ] || [ -z "$(git ls-files "$TRANSFER_DIR")" ]; then
    echo "✓ 지울 전달물이 없습니다 ($TRANSFER_DIR/ 비었거나 없음). 종료."
    exit 0
fi

BRANCH="$(git branch --show-current)"
echo "▶ 브랜치 '$BRANCH' 에서 $TRANSFER_DIR/ 전달물을 비웁니다:"
git ls-files "$TRANSFER_DIR" | sed 's/^/    - /'

# 1) 삭제 (디렉토리째 추적 해제)
git rm -r --quiet "$TRANSFER_DIR"

# 2) 커밋
git commit -m "chore(transfer): $TRANSFER_DIR/ 전달물 비우기 (참고 완료)"

# 3) push (현재 브랜치 upstream)
echo "▶ push: origin/$BRANCH"
git push origin "HEAD:$BRANCH"

echo "✓ 완료 — $TRANSFER_DIR/ 제거·커밋·push 됨."
echo "  (전달 브랜치 자체를 지우려면: git switch main && git branch -D $BRANCH && git push origin --delete $BRANCH)"
