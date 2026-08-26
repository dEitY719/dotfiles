#!/bin/sh
# lint_changelog_fragments.sh — changelog fragment 포맷 검사 (issue #1471)
#
# 정책 (수집기 계약과 1:1 대응 — my-share `scripts/report_range.py`):
#   - 파일명은 `<YYYY-MM-DD>-<issue>.md`. 날짜를 파일명이 들고 있으므로
#     fragment 안에는 날짜 헤더가 필요 없다 — 중복 헤더 클래스가 원천 차단된다.
#   - fragment 안에 마크다운 헤더(`#`)를 두지 않는다. 수집기는 `#` 로 시작하는
#     줄을 조용히 버리므로, 헤더를 쓰면 항목이 소리 없이 사라진다.
#   - 비어 있지 않은 모든 줄이 항목이다. 따라서 한 줄 = 한 항목(`- ` 로 시작)이며,
#     산문 줄을 섞으면 그대로 보고서에 실린다.
#   - 빈 파일은 수집기가 통째로 무시한다 — 항목 증발이므로 FAIL.
#
# 사용:
#   sh scripts/lint_changelog_fragments.sh                    # repo root 기준
#   CHANGELOG_FRAGMENT_DIR=path/to/changelog.d sh scripts/lint_changelog_fragments.sh

set -eu

FRAGMENT_DIR="${CHANGELOG_FRAGMENT_DIR:-docs/public/changelog.d}"

# 디렉터리가 없으면 검사 대상이 없다 — 조용한 no-op (다른 저장소/부분 체크아웃).
[ -d "$FRAGMENT_DIR" ] || exit 0

errors=0

fail() {
    echo "FAIL  $1" >&2
    errors=$((errors + 1))
}

# 파일명 규칙: <YYYY-MM-DD>-<issue>.md
is_valid_name() {
    case "$1" in
    *.md) ;;
    *) return 1 ;;
    esac
    _stem="${1%.md}"
    case "$_stem" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*) ;;
    *) return 1 ;;
    esac
    _issue="${_stem#????-??-??-}"
    case "$_issue" in
    "" | *[!0-9]*) return 1 ;;
    esac
    return 0
}

# 선행 공백/탭 제거 (POSIX 파라미터 확장 — grep/sed 포크 없이).
lstrip() {
    _lead="${1%%[! 	]*}"
    printf '%s' "${1#"$_lead"}"
}

for file in "$FRAGMENT_DIR"/*; do
    # glob 미매치(빈 디렉터리) 또는 하위 디렉터리는 건너뛴다.
    [ -f "$file" ] || continue

    if ! is_valid_name "$(basename "$file")"; then
        fail "$file — 파일명이 <YYYY-MM-DD>-<issue>.md 형식이 아닙니다."
        continue
    fi

    bullets=0
    lineno=0
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        stripped="$(lstrip "$line")"

        # 공백만 있는 줄은 수집기가 버리므로 항목이 아니다 — 허용.
        [ -n "$stripped" ] || continue

        case "$stripped" in
        \#*)
            fail "$file:$lineno — 마크다운 헤더는 fragment 안에 둘 수 없습니다 (날짜는 파일명이 갖습니다)."
            ;;
        "- "*)
            bullets=$((bullets + 1))
            ;;
        *)
            fail "$file:$lineno — 항목은 '- ' 로 시작해야 합니다: $stripped"
            ;;
        esac
    done <"$file"

    if [ "$bullets" -eq 0 ]; then
        fail "$file — 내용이 비어 있습니다 (수집기가 통째로 무시합니다)."
    fi
done

echo "lint-changelog-fragments: errors=${errors} (dir: ${FRAGMENT_DIR})"

[ "$errors" -eq 0 ] || exit 1
