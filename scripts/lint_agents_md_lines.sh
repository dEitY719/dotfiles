#!/bin/sh
# lint_agents_md_lines.sh — AGENTS.md 100줄 규칙 검사 (issue #2152)
#
# 정책 (AGENTS.md Golden Rules "100-Line Limit"):
#   - git 이 추적하는 모든 AGENTS.md 는 100줄 미만이어야 한다 → 위반 시 FAIL(exit 1).
#   - CLAUDE.md 는 규칙 대상이 아니다 — 줄 수만 참고로 출력한다.
#
# 사용 (현재 git 저장소 root 기준):
#   sh scripts/lint_agents_md_lines.sh

set -eu

LIMIT=100

# wc -l 은 마지막 줄에 개행이 없으면 한 줄 덜 센다 — awk NR 로 센다.
count_lines() {
    awk 'END { print NR }' "$1"
}

errors=0
checked=0

while IFS= read -r file; do
    [ -n "$file" ] || continue
    [ -f "$file" ] || continue
    checked=$((checked + 1))
    n="$(count_lines "$file")"
    if [ "$n" -ge "$LIMIT" ]; then
        echo "FAIL  $file — ${n}줄 (AGENTS.md 는 ${LIMIT}줄 미만이어야 합니다)." >&2
        errors=$((errors + 1))
    fi
done <<EOF
$(git ls-files '*AGENTS.md')
EOF

while IFS= read -r file; do
    [ -n "$file" ] && [ -f "$file" ] || continue
    echo "info  $file — $(count_lines "$file")줄 (규칙 대상 아님, 참고)"
done <<EOF
$(git ls-files 'CLAUDE.md' '*/CLAUDE.md')
EOF

echo "lint-agents-md: checked=${checked} errors=${errors} (limit: <${LIMIT} lines)"

[ "$errors" -eq 0 ] || exit 1
