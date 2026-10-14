#!/bin/sh
# lint_docs_status.sh — docs front-matter status 필수 + approved 문서 stale 경로 경고 (issue #2152)
#
# 정책 (docs/AGENTS.md "문서 메타데이터·파일명 규칙"):
#   (a) docs/requirement/, docs/feature/, docs/adr/ 하위 *.md (README.md/AGENTS.md 제외)는
#       YAML front-matter `status: draft|review|approved|deprecated|needs-review` 필수
#       → 없거나 값이 틀리면 FAIL(exit 1).
#   (b) `status: approved` 문서(위 범위 + docs/.ssot/*.md)의 본문 백틱 경로 중
#       저장소 상대경로로 해석되는 것(첫 경로 성분이 git 추적 대상)이 git ls-files 에
#       없으면 WARN — 경로 추출 오탐 비용이 커서 FAIL 로 올리지 않는다.
#
# 사용 (현재 git 저장소 root 기준):
#   sh scripts/lint_docs_status.sh

set -eu

# 저장소 root 기준으로 동작하고(하위 디렉터리에서 실행해도 조용히 통과하지 않게), 비ASCII 경로를 따옴표로 감싸지 않는다.
cd "$(git rev-parse --show-toplevel)"
git() { command git -c core.quotepath=false "$@"; }

STATUS_DIRS="docs/requirement docs/feature docs/adr"
VALID_STATUSES="draft review approved deprecated needs-review"

errors=0
warnings=0

# front-matter(첫 줄 `---` ~ 다음 `---`) 안의 status 값. 없으면 빈 문자열.
front_matter_status() {
    awk '
        { sub(/\r$/, "") }
        NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; next }
        /^---[[:space:]]*$/ { exit }
        /^status:/ { sub(/^status:[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); gsub(/^["\047]|["\047]$/, ""); print; exit }
    ' "$1"
}

is_valid_status() {
    for _s in $VALID_STATUSES; do
        [ "$1" = "$_s" ] && return 0
    done
    return 1
}

# 첫 경로 성분이 추적되는 최상위 항목인가 — 다른 저장소의 경로(references/x.md 등) 오탐 차단.
TRACKED="$(git ls-files)"
TOP_LEVEL="$(printf '%s\n' "$TRACKED" | cut -d/ -f1 | sort -u)"

# 백틱 span 중 경로처럼 생긴 것만 뽑아 `:줄번호` 꼬리를 떼고 출력한다.
extract_paths() {
    grep -o '`[^`]*`' "$1" | tr -d '`' | while IFS= read -r p; do
        case "$p" in
        */*) ;;
        *) continue ;;
        esac
        case "$p" in
        *[[:space:]]* | *[*?{}\<\>\$~]* | *\[* | /* | -* | .* | http*) continue ;;
        esac
        printf '%s\n' "${p%%:*}"
    done | sort -u
}

check_stale_paths() {
    _doc="$1"
    for _p in $(extract_paths "$_doc"); do
        _top="${_p%%/*}"
        printf '%s\n' "$TOP_LEVEL" | grep -qxF "$_top" || continue
        # 파일 또는 디렉터리(접두)로 추적되는지 — 경로마다 git 을 띄우지 않고 캐시한 목록을 쓴다.
        if printf '%s\n' "$TRACKED" | awk -v p="${_p%/}" '$0 == p || index($0, p "/") == 1 { f = 1; exit } END { exit !f }'; then
            continue
        fi
        echo "warn  $_doc — stale path \`$_p\` (git ls-files 에 없음, status: approved)"
        warnings=$((warnings + 1))
    done
}

for file in $(git ls-files -- $STATUS_DIRS | grep '\.md$' || true); do
    case "$(basename "$file")" in
    README.md | AGENTS.md) continue ;;
    esac
    status="$(front_matter_status "$file")"
    if [ -z "$status" ]; then
        echo "FAIL  $file — front-matter \`status:\` 가 없습니다." >&2
        errors=$((errors + 1))
        continue
    fi
    if ! is_valid_status "$status"; then
        echo "FAIL  $file — 잘못된 status '$status' (허용: $VALID_STATUSES)." >&2
        errors=$((errors + 1))
        continue
    fi
    if [ "$status" = approved ]; then
        check_stale_paths "$file"
    fi
done

for file in $(git ls-files -- 'docs/.ssot/*.md'); do
    if [ "$(front_matter_status "$file")" = approved ]; then
        check_stale_paths "$file"
    fi
done

echo "lint-docs-status: errors=${errors} warnings=${warnings} (status required: ${STATUS_DIRS})"

[ "$errors" -eq 0 ] || exit 1
