#!/usr/bin/env bash
# claude/skills/devx-session-close/lib/check-artifacts.sh
#
# C-3 (F-5) — 세션이 남긴 임시 산출물 감사. 세 갈래를 본다.
#
#   1. scratchpad 잔재      — --scratchpad 로 받은 디렉터리에 남은 파일
#   2. 버려진 예약 파일     — 0 바이트 untracked 파일. 이름만 잡아두고
#                             내용을 못 채운 채 턴이 끊긴 흔적이므로,
#                             단순 나열이 아니라 별도 분류로 제시한다.
#   3. 미정리 임시 파일     — *.tmp *.bak *.orig *.rej *.swp *~ 등
#                             untracked 인 편집/병합 부산물
#
# 세 갈래 모두 디스크에 남아 다음 세션이 이어받을 수 있으므로 NOTE 이며
# BLOCKED 를 만들지 않는다 (F-7).
#
# NF-1 read-only — 찾은 파일을 지우지도 옮기지도 않는다. 정리 여부는
# 사람이 결정한다.
#
# Usage:
#   check-artifacts.sh [--scratchpad <dir>] [repo-path...]
# Exit 0 = 정상(잔재 유무 무관), 2 = 검사 대상 0개(NF-6).

set -uo pipefail

_cra_lib_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
. "${_cra_lib_dir}/_repo_common.sh"

# 편집/병합 부산물로 취급할 이름 글롭. shell-common/functions/file_cleanup.sh
# 의 CLEANUP_DEFAULT_PATTERNS 와는 목적이 다르다 — 그쪽은 사람이 opt-in 으로
# 지우는 "백업/구버전 파일" 목록(del_file 용, bash 배열)이고, 여기는 세션이
# 끊기며 남는 "편집기·병합 도구가 흘린 임시 산출물"만 read-only 로 잡는다.
# 둘을 하나로 합치면 서로 다른 의도의 글롭이 뒤섞인다.
RESERVED_GLOBS='*.tmp *.bak *.orig *.rej *.swp *~'
NOTE_COUNT=0
SCRATCHPAD=""

usage() {
    cat <<'EOF'
check-artifacts.sh — devx:session-close 의 C-3 임시 산출물 감사 (read-only)

Usage:
  check-artifacts.sh [--scratchpad <dir>] [repo-path...]

Options:
  --scratchpad <dir>   이 세션의 scratchpad 디렉터리 (생략 가능)
  -h, --help, help     이 도움말

저장소마다 0 바이트 untracked 파일(버려진 예약 파일)과 untracked 임시
파일을 찾고, scratchpad 잔재를 셈한 뒤 VERDICT 줄 하나를 남긴다.
찾기만 하고 아무것도 정리하지 않는다.

Exit: 0 = 정상, 2 = 검사 대상 0개.
EOF
}

note() {
    printf 'NOTE: %s\n' "$1"
    NOTE_COUNT=$((NOTE_COUNT + 1))
}

pass() {
    printf 'PASS: %s\n' "$1"
}

warn() {
    printf 'WARN: %s\n' "$1"
}

# is_reserved_name <basename> — 편집/병합 부산물 이름이면 0.
is_reserved_name() {
    _irn_base="$1"
    for _irn_glob in $RESERVED_GLOBS; do
        # shellcheck disable=SC2254  # 글롭으로 쓰려고 일부러 따옴표를 뺀다
        case "$_irn_base" in
            $_irn_glob) return 0 ;;
        esac
    done
    return 1
}

check_scratchpad() {
    _cs_dir="$1"
    if [ ! -d "$_cs_dir" ]; then
        warn "scratchpad 경로가 없다 — 건너뜀: ${_cs_dir}"
        return 0
    fi
    _cs_files=$(find "$_cs_dir" -type f 2>/dev/null)
    _cs_count=$(printf '%s\n' "$_cs_files" | grep -c . || true)
    if [ "${_cs_count:-0}" -gt 0 ]; then
        note "scratchpad 잔재 ${_cs_count}건: ${_cs_dir}"
        printf '%s\n' "$_cs_files" | sed -n '1,10p' | sed 's/^/    /'
    else
        pass "scratchpad 잔재 없음: ${_cs_dir}"
    fi
}

check_repo_artifacts() {
    _cra_repo="$1"

    if ! resolve_repo "$_cra_repo"; then
        return 0
    fi
    _cra_top="$_RC_TOP"
    printf 'REPO: %s\n' "$_cra_top"

    _cra_empty=""
    _cra_temp=""
    while IFS= read -r _cra_rel; do
        [ -n "$_cra_rel" ] || continue
        _cra_abs="${_cra_top}/${_cra_rel}"
        [ -f "$_cra_abs" ] || continue
        if [ ! -s "$_cra_abs" ]; then
            _cra_empty="${_cra_empty}${_cra_rel}
"
            continue
        fi
        if is_reserved_name "${_cra_rel##*/}"; then
            _cra_temp="${_cra_temp}${_cra_rel}
"
        fi
    done <<EOF
$(git -C "$_cra_repo" ls-files --others --exclude-standard 2>/dev/null)
EOF

    if [ -n "$_cra_empty" ]; then
        _cra_n=$(printf '%s' "$_cra_empty" | grep -c . || true)
        note "${_cra_top}: 버려진 예약 파일 ${_cra_n}건 — 0 바이트 untracked 파일이다. 이름만 잡고 내용을 못 채운 채 끊긴 흔적이므로 채우거나 정리할지 판단하라"
        printf '%s' "$_cra_empty" | sed 's/^/    /'
    else
        pass "${_cra_top}: 버려진 예약 파일 없음"
    fi

    if [ -n "$_cra_temp" ]; then
        _cra_n=$(printf '%s' "$_cra_temp" | grep -c . || true)
        note "${_cra_top}: 미정리 임시 파일 ${_cra_n}건"
        printf '%s' "$_cra_temp" | sed 's/^/    /'
    else
        pass "${_cra_top}: 미정리 임시 파일 없음"
    fi
}

main() {
    case "${1:-}" in
        -h | --help | help)
            usage
            return 0
            ;;
    esac

    repos=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --scratchpad)
                if [ "$#" -lt 2 ]; then
                    printf '--scratchpad 에 경로 인자가 없다\n' >&2
                    usage >&2
                    return 1
                fi
                SCRATCHPAD="$2"
                shift 2
                ;;
            --scratchpad=*)
                SCRATCHPAD="${1#--scratchpad=}"
                shift
                ;;
            --)
                shift
                break
                ;;
            -*)
                printf '알 수 없는 옵션: %s\n' "$1" >&2
                usage >&2
                return 1
                ;;
            *)
                repos="${repos}${1}
"
                shift
                ;;
        esac
    done
    while [ "$#" -gt 0 ]; do
        repos="${repos}${1}
"
        shift
    done

    if [ -z "$SCRATCHPAD" ] && [ -z "$repos" ]; then
        printf '검사 대상 없음 — 검사할 저장소도 scratchpad 도 0개다 (NF-6)\n'
        printf '\nVERDICT: NO-TARGET\n'
        return 2
    fi

    [ -n "$SCRATCHPAD" ] && check_scratchpad "$SCRATCHPAD"

    while IFS= read -r repo; do
        [ -n "$repo" ] || continue
        check_repo_artifacts "$repo"
    done <<EOF
$repos
EOF

    printf '\n'
    if [ "$NOTE_COUNT" -eq 0 ]; then
        printf 'VERDICT: OK\n'
    else
        printf 'VERDICT: NOTE (%d)\n' "$NOTE_COUNT"
    fi
    return 0
}

main "$@"
