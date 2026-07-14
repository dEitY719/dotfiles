#!/bin/sh
# check_port_registry.sh — PORTS.md 포트 레지스트리 검증 (issue #1154)
#
# 정책:
#   - index 컬럼은 정수이며 레지스트리 안에서 유일해야 한다 (중복 → 종료 코드 1).
#   - 각 행의 backend/frontend/db(host) 포트는 decade-block 공식과 일치해야 한다:
#       backend  = 9200 + index*10
#       frontend = backend + 1
#       db(host) = backend + 2
#     (TBD) 행도 검증 대상 — 예약 블록이 공식에서 어긋나면 실패한다.
#
# 사용:
#   sh scripts/check_port_registry.sh                   # repo root 기준 PORTS.md
#   PORTS_FILE=path/to/PORTS.md sh scripts/check_port_registry.sh

set -eu

PORTS_FILE="${PORTS_FILE:-PORTS.md}"
BASE_PORT=9200

if [ ! -f "$PORTS_FILE" ]; then
    echo "check-ports: '$PORTS_FILE' 파일을 찾을 수 없습니다." >&2
    exit 2
fi

errors=0
rows=0
seen=" " # 공백 구분 index 목록 (중복 탐지용)

is_int() {
    case "$1" in
    "" | *[!0-9]*) return 1 ;;
    *) return 0 ;;
    esac
}

# 셀 앞뒤 공백 제거
trim() {
    _s="$1"
    while :; do
        case "$_s" in
        " "*) _s="${_s# }" ;;
        *" ") _s="${_s% }" ;;
        *) break ;;
        esac
    done
    printf '%s' "$_s"
}

while IFS= read -r line; do
    # 표 행만 처리 ('|' 로 시작)
    case "$line" in
    \|*) ;;
    *) continue ;;
    esac

    # '|' 로 필드 분해 (glob 방지 위해 noglob).
    # 선행 '|' 때문에 $1 은 빈 필드; 데이터 컬럼은 2..6.
    old_ifs="$IFS"
    set -f
    IFS='|'
    # shellcheck disable=SC2086
    set -- $line
    IFS="$old_ifs"
    set +f

    idx="$(trim "${2-}")"
    be="$(trim "${4-}")"
    fe="$(trim "${5-}")"
    db="$(trim "${6-}")"

    # 헤더/구분선/설명 행은 index 가 정수가 아니므로 자연히 걸러진다.
    is_int "$idx" || continue

    rows=$((rows + 1))

    # 중복 index 검사
    case "$seen" in
    *" $idx "*)
        echo "FAIL  index=$idx 가 중복됩니다." >&2
        errors=$((errors + 1))
        ;;
    *)
        seen="$seen$idx "
        ;;
    esac

    # decade-block 공식 일치 검사
    exp_be=$((BASE_PORT + idx * 10))
    exp_fe=$((exp_be + 1))
    exp_db=$((exp_be + 2))

    if is_int "$be" && [ "$be" -ne "$exp_be" ]; then
        echo "FAIL  index=$idx backend=$be, 공식값 $exp_be 와 불일치." >&2
        errors=$((errors + 1))
    fi
    if is_int "$fe" && [ "$fe" -ne "$exp_fe" ]; then
        echo "FAIL  index=$idx frontend=$fe, 공식값 $exp_fe 와 불일치." >&2
        errors=$((errors + 1))
    fi
    if is_int "$db" && [ "$db" -ne "$exp_db" ]; then
        echo "FAIL  index=$idx db=$db, 공식값 $exp_db 와 불일치." >&2
        errors=$((errors + 1))
    fi
done <"$PORTS_FILE"

echo "check-ports: rows=${rows} errors=${errors} (file: ${PORTS_FILE})"

[ "$errors" -eq 0 ] || exit 1
