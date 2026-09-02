#!/bin/sh
# lint_shell_common_fallback.sh — ${SHELL_COMMON} $HOME 폴백 검사 (issue #1612)
#
# 정책:
#   - 스킬 `**/*.md` 안의 소싱 지시문은 Claude Code의 Bash tool
#     (`bash --noprofile --norc`, dotfiles rc 미실행)처럼 $SHELL_COMMON 이
#     비어 있는 셸에서도 그대로 복붙 실행 가능해야 한다.
#   - 그러려면 모든 `${SHELL_COMMON}/...` 참조(functions/ 뿐 아니라 tools/ 등
#     다른 하위 경로도 포함)는 `${SHELL_COMMON:-$HOME/dotfiles/shell-common}/...`
#     폴백 관용구를 갖춰야 한다 (devx-pr-review-all/SKILL.md:116 이 기존 표준).
#   - 폴백이 빠지면 `$SHELL_COMMON` 이 비었을 때 상대경로로 대체 source 하기
#     쉬운데, 그 경로는 가드 체인과 상호작용해 함수가 조용히 안 정의되는
#     실패로 이어진다(#1612 재현 스크립트 참고) — 즉시 에러가 나는 쪽보다도
#     나쁘다.
#
# 사용 (issue #1680 이후 수동 전용):
#   CLAUDE_SKILLS_DIR=<marketplace-repo>/skills sh scripts/lint_shell_common_fallback.sh
#
# 검사 대상 스킬은 #1680 으로 15개 marketplace repo 로 옮겨갔다. dotfiles 에는
# `claude/skills/` 가 없으므로 기본값으로 실행하면 exit 2 다 — mise `lint-docs`
# 게이트에서도 그래서 빠졌다. 규칙 자체는 그대로 유효하니 워크스페이스 clone 을
# 가리켜 돌린다.

set -eu

SKILLS_DIR="${CLAUDE_SKILLS_DIR:-claude/skills}"

if [ ! -d "$SKILLS_DIR" ]; then
    echo "lint-shell-common-fallback: '$SKILLS_DIR' 디렉터리를 찾을 수 없습니다." >&2
    exit 2
fi

errors=0

fail() {
    echo "FAIL  $1" >&2
    errors=$((errors + 1))
}

# `${SHELL_COMMON}/` 를 하위 경로 무관하게 그대로 찾는다 — `${SHELL_COMMON:-...}`
# 는 여는 중괄호 바로 뒤가 `:` 이므로 이 리터럴 패턴과 매치되지 않는다.
# `find` + 파일별 grep — 형제 린터 lint_docs_filenames.sh 와 동일한 이식 가능
# 패턴이다. GNU 전용 `grep -r --include=` 는 BSD/macOS grep 에서 지원이
# 불확실해 지원 대상 플랫폼(WSL·Linux·macOS, 루트 AGENTS.md) 에서
# `mise run lint-docs` 자체가 깨질 수 있다 (PR #1614 codex 리뷰).
for file in $(find "$SKILLS_DIR" -type f -name '*.md' | sort); do
    matches=$(grep -n '${SHELL_COMMON}/' "$file" || true)
    [ -n "$matches" ] || continue
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        fail "$file:$line — \${SHELL_COMMON:-\$HOME/dotfiles/shell-common}/ 로 고치세요."
    done <<EOF
$matches
EOF
done

echo "lint-shell-common-fallback: errors=${errors} (dir: ${SKILLS_DIR})"

[ "$errors" -eq 0 ] || exit 1
