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

# changelog.d 가 유일한 changelog 소스이므로 디렉터리 부재는 "검사할 게 없음"이
# 아니라 소스 전체가 사라진 상태다 — 조용히 통과하면 lint-docs 가 초록인 채로
# changelog 를 잃는다 (PR #1475 codex). 형제 린터 lint_docs_filenames.sh 와
# 같은 rc 2 를 쓴다: 1(=위반 발견)과 구별되는 "검사 대상 자체가 없음".
if [ ! -d "$FRAGMENT_DIR" ]; then
    echo "lint-changelog-fragments: '$FRAGMENT_DIR' 디렉터리를 찾을 수 없습니다." >&2
    exit 2
fi

errors=0

fail() {
    echo "FAIL  $1" >&2
    errors=$((errors + 1))
}

# 파일명 규칙: <YYYY-MM-DD>-<issue>.md
is_valid_name() {
    # 날짜 프리픽스 + 숫자로 시작하는 issue + .md 를 한 패턴으로 거른다.
    case "$1" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9]*.md) ;;
    *) return 1 ;;
    esac
    # issue 부분이 전부 숫자인지 (`1a.b` 같은 잔여 케이스) 확인한다.
    _stem="${1%.md}"
    case "${_stem#????-??-??-}" in
    *[!0-9]*) return 1 ;;
    esac
}

for file in "$FRAGMENT_DIR"/*; do
    # glob 미매치(빈 디렉터리) 또는 하위 디렉터리는 건너뛴다.
    [ -f "$file" ] || continue

    if ! is_valid_name "${file##*/}"; then
        fail "$file — 파일명이 <YYYY-MM-DD>-<issue>.md 형식이 아닙니다."
        continue
    fi

    bullets=0
    lineno=0
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))

        # 공백만 있는 줄은 수집기가 버리므로 항목이 아니다 — 허용.
        # (선행 공백/탭 제거는 POSIX 파라미터 확장 — 줄당 포크 없이.)
        _lead="${line%%[! 	]*}"
        [ -n "${line#"$_lead"}" ] || continue

        # 아래 검사는 stripped 가 아니라 **원본 줄**을 본다: 들여쓴
        # `  - 하위 불릿` 은 CLAUDE.md 가 금지하는 형식인데, 선행 공백을
        # 지우고 보면 정상 항목과 구별되지 않는다.
        case "$line" in
        \#*)
            fail "$file:$lineno — 마크다운 헤더는 fragment 안에 둘 수 없습니다 (날짜는 파일명이 갖습니다)."
            ;;
        "- 변경: "*)
            # 문서가 강제한다고 말하는 형식은 `- 변경: **요약**` 이다.
            # `- ` 로만 검사하면 계약과 구현이 어긋난다 (PR #1475 codex).
            _rest="${line#- 변경: }"
            case "$_rest" in
            '**'*) _rest="${_rest#'**'}" ;;
            *) _rest="" ;;
            esac
            case "$_rest" in
            *'**'*) bullets=$((bullets + 1)) ;;
            *) fail "$file:$lineno — 요약은 \`**\` 로 강조해야 합니다 ('- 변경: **요약**'): $line" ;;
            esac
            ;;
        *)
            fail "$file:$lineno — 항목은 '- 변경: **요약**' 형식이어야 합니다: $line"
            ;;
        esac
    done <"$file"

    if [ "$bullets" -eq 0 ]; then
        fail "$file — 내용이 비어 있습니다 (수집기가 통째로 무시합니다)."
    fi
done

echo "lint-changelog-fragments: errors=${errors} (dir: ${FRAGMENT_DIR})"

[ "$errors" -eq 0 ] || exit 1
