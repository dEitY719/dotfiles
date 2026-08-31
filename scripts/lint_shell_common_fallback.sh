#!/bin/sh
# lint_shell_common_fallback.sh — ${SHELL_COMMON} $HOME 폴백 검사 (issue #1612)
#
# 정책:
#   - `claude/skills/**/*.md` 안의 소싱 지시문은 Claude Code의 Bash tool
#     (`bash --noprofile --norc`, dotfiles rc 미실행)처럼 $SHELL_COMMON 이
#     비어 있는 셸에서도 그대로 복붙 실행 가능해야 한다.
#   - 그러려면 모든 `${SHELL_COMMON}/...` 참조(`functions/`, `tools/` 등 하위
#     경로 무관)는 `${SHELL_COMMON:-$HOME/dotfiles/shell-common}/...` 폴백
#     관용구를 갖춰야 한다 (devx-pr-review-all/SKILL.md:116 이 기존 표준).
#   - 폴백이 빠지면 `$SHELL_COMMON` 이 비었을 때 상대경로로 대체 source 하기
#     쉬운데, 그 경로는 가드 체인과 상호작용해 함수가 조용히 안 정의되는
#     실패로 이어진다(#1612 재현 스크립트 참고) — 즉시 에러가 나는 쪽보다도
#     나쁘다.
#
# 사용:
#   sh scripts/lint_shell_common_fallback.sh
#   CLAUDE_SKILLS_DIR=path/to/skills sh scripts/lint_shell_common_fallback.sh

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
matches=$(grep -rn '${SHELL_COMMON}/' "$SKILLS_DIR" --include='*.md' || true)

if [ -n "$matches" ]; then
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        fail "$line — \${SHELL_COMMON:-\$HOME/dotfiles/shell-common}/ 로 고치세요."
    done <<EOF
$matches
EOF
fi

echo "lint-shell-common-fallback: errors=${errors} (dir: ${SKILLS_DIR})"

[ "$errors" -eq 0 ] || exit 1
