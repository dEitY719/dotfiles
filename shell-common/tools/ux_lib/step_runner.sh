#!/bin/sh
# shellcheck shell=bash
# (shebang per shell-common hook rule; the file is bash-only and only sourced)
# shellcheck disable=SC2034  # STEP_* are read by callers and by the hint/digest callbacks
#
# shell-common/tools/ux_lib/step_runner.sh: summary-mode step runner (#2126)
#
# One line per step; warnings/failures get detail + a fix hint; full
# sub-command output goes to a log file. Shared by ./setup.sh and
# scripts/update-skills.sh (skills-sync) so both print the same contract.
#
# bash only, explicit source only — never auto-sourced (no interactive guard:
# its callers are non-interactive scripts). Needs ux_lib.sh (sourced below
# when the caller has not loaded it yet).
#
# API
#   step_init <log-prefix> <verbose>   verbose=1 streams everything; else log
#                                      to ${TMPDIR:-/tmp}/<prefix>-<ts>.log
#                                      (unwritable -> verbose fallback + warning)
#   step_run <label> <critical|optional> <cmd...>
#                                      critical failure -> exit 1;
#                                      optional failure -> recorded, return 0
#   step_summary <name>                final tally line(s); removes $STEP_OUT
#
# Knobs (set by the caller)
#   STEP_NAME        abort message subject   (default: "작업")
#   STEP_RERUN       re-run command for non-script steps (default: "")
#   STEP_HINT_FN     on failure: "$STEP_HINT_FN" "<label>" prints extra hints
#   STEP_DIGEST_FN   on clean success: "$STEP_DIGEST_FN" "<label>" may set
#                    STEP_DIGEST from $STEP_OUT -> "✅ <label> (<t>s) — <digest>"
#   STEP_LOG_ALWAYS  1 (default) prints the log path in the summary even when
#                    all green; 0 prints it only on warnings/failures and
#                    deletes an all-green log
#
# State (read by the caller)
#   STEP_LOG STEP_OUT STEP_VERBOSE STEP_TOTAL STEP_WARNED[] STEP_FAILED[]
#   STEP_LAST_RC     exit code of the most recent step_run

if ! command -v ux_success >/dev/null 2>&1; then
    # shellcheck source=ux_lib.sh
    source "$(dirname "${BASH_SOURCE[0]}")/ux_lib.sh"
fi

STEP_VERBOSE="${STEP_VERBOSE:-0}"
STEP_LOG="${STEP_LOG:-/dev/null}"
STEP_OUT="${STEP_OUT:-/dev/null}"
STEP_NAME="${STEP_NAME:-작업}"
STEP_RERUN="${STEP_RERUN:-}"
STEP_HINT_FN="${STEP_HINT_FN:-}"
STEP_DIGEST_FN="${STEP_DIGEST_FN:-}"
STEP_LOG_ALWAYS="${STEP_LOG_ALWAYS:-1}"
STEP_DIGEST=""
STEP_LAST_RC=0
STEP_TOTAL=0
STEP_WARNED=()
STEP_FAILED=()

# Deciseconds since epoch into _STEP_NOW_DS (bash 5 EPOCHREALTIME; whole seconds otherwise).
_step_now_ds() {
    local t="${EPOCHREALTIME:-$SECONDS.0}" f
    t="${t/,/.}"
    f="${t#*.}"
    _STEP_NOW_DS=$((${t%.*} * 10 + ${f:0:1}))
}

step_init() {
    local prefix="$1"
    STEP_VERBOSE="${2:-0}"
    STEP_LOG=/dev/null
    STEP_OUT=/dev/null
    if [ "$STEP_VERBOSE" = 1 ]; then
        return 0
    fi
    STEP_LOG="${TMPDIR:-/tmp}/${prefix}-$(date +%Y%m%d-%H%M%S).log"
    if ! { : >"$STEP_LOG"; } 2>/dev/null; then
        ux_warning "로그 파일을 만들 수 없음 ($STEP_LOG) — 전체 출력 모드로 전환합니다"
        STEP_VERBOSE=1
        STEP_LOG=/dev/null
        return 0
    fi
    STEP_OUT="${STEP_LOG}.step"
}

# step_run <label> <critical|optional> <cmd...>
step_run() {
    local label="$1" level="$2" rc=0 t0 dt d miss="" warns suffix=""
    shift 2
    STEP_TOTAL=$((STEP_TOTAL + 1))
    _step_now_ds
    t0=$_STEP_NOW_DS
    : >"$STEP_OUT"
    if [ "${1#*/}" != "$1" ] && [ ! -x "$1" ]; then
        rc=127
        miss="스크립트가 없거나 실행 권한이 없음: $1"
    elif [ "$STEP_VERBOSE" = 1 ]; then
        "$@" || rc=$?
    else
        "$@" >"$STEP_OUT" 2>&1 || rc=$?
    fi
    STEP_LAST_RC=$rc
    {
        ux_info "=== [$label] $* (exit $rc) ==="
        cat "$STEP_OUT"
    } >>"$STEP_LOG" 2>&1
    _step_now_ds
    d=$((_STEP_NOW_DS - t0))
    dt="$((d / 10)).$((d % 10))s"

    if [ "$rc" -eq 0 ]; then
        warns=$(grep -E '⚠|❌|^WARN:|^ERR:' "$STEP_OUT" || true)
        if [ -z "$warns" ]; then
            STEP_DIGEST=""
            if [ -n "$STEP_DIGEST_FN" ]; then "$STEP_DIGEST_FN" "$label" || STEP_DIGEST=""; fi
            if [ -n "$STEP_DIGEST" ]; then suffix=" — $STEP_DIGEST"; fi
            ux_success "$label ($dt)$suffix"
            return 0
        fi
        ux_warning "$label ($dt) — 경고 $(grep -c . <<<"$warns")줄"
        while IFS= read -r line; do
            ux_bullet_sub "${line#"${line%%[![:space:]]*}"}"
        done < <(head -n 10 <<<"$warns")
        STEP_WARNED+=("$label")
        return 0
    fi

    {
        ux_error "$label 실패 [$level] (exit $rc, $dt)"
        if [ -n "$miss" ]; then ux_bullet_sub "$miss"; fi
        if [ -s "$STEP_OUT" ]; then
            ux_bullet "로그 마지막 20줄:"
            while IFS= read -r line; do ux_bullet_sub "$line"; done < <(tail -n 20 "$STEP_OUT")
        fi
        ux_bullet "조치:"
        if [ "${1#*/}" != "$1" ]; then
            ux_bullet_sub "상세 재현: bash -x $1"
        elif [ -n "$STEP_RERUN" ]; then
            ux_bullet_sub "상세 재현: $STEP_RERUN -v"
        fi
        if [ -n "$STEP_HINT_FN" ]; then "$STEP_HINT_FN" "$label" || true; fi
        if [ "$STEP_LOG" != /dev/null ]; then ux_bullet_sub "전체 로그: $STEP_LOG"; fi
    } >&2
    if [ "$level" = critical ]; then
        ux_error "critical 스텝 '$label' 실패 — $STEP_NAME 을 중단합니다. 위 조치 후 ${STEP_RERUN:-$STEP_NAME} 를 다시 실행하세요."
        exit 1
    fi
    STEP_FAILED+=("$label")
}

# step_summary <name>
step_summary() {
    local name="$1" ok=$((STEP_TOTAL - ${#STEP_WARNED[@]} - ${#STEP_FAILED[@]}))
    if [ "$STEP_OUT" != /dev/null ]; then rm -f "$STEP_OUT"; fi
    ux_info ""
    if [ "$ok" -eq "$STEP_TOTAL" ]; then
        ux_success "$name 완료: ${STEP_TOTAL}개 스텝 모두 정상"
        if [ "$STEP_LOG_ALWAYS" != 1 ] && [ "$STEP_LOG" != /dev/null ]; then
            rm -f "$STEP_LOG"
            return 0
        fi
    else
        ux_warning "$name 완료(확인 필요): 총 ${STEP_TOTAL} / 성공 ${ok} / 경고 ${#STEP_WARNED[@]} / 실패 ${#STEP_FAILED[@]}"
        if [ ${#STEP_WARNED[@]} -gt 0 ]; then ux_warning "경고 스텝: ${STEP_WARNED[*]}"; fi
        if [ ${#STEP_FAILED[@]} -gt 0 ]; then ux_error "실패 스텝(optional): ${STEP_FAILED[*]}"; fi
    fi
    if [ "$STEP_LOG" != /dev/null ]; then ux_info "전체 로그: $STEP_LOG"; fi
}
