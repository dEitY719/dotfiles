#!/bin/bash
# claude/tools/register-drift-hook.sh — F-7b (#1364), relocated by #2097.
#
# Internal-PC only. The live ~/.claude/settings.json there is owned by
# `gateway-cli setup`; dotfiles' only stake in it is the SessionStart hook
# claude/hooks/session-start-settings-drift.sh, which heals .hooks/.statusLine.
# Claude Code only runs a hook registered in the live file, so if something
# wipes live .hooks the hook can never heal itself. This script re-inserts
# exactly that one registration and touches nothing else.
#
# Called by claude/setup.sh (internal branch). Safe to run by hand. Idempotent.
# External/public PCs: no-op (mode gate below).
#
# bash (not /bin/sh): ux_lib references $BASH_VERSION.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=../../shell-common/tools/ux_lib/ux_lib.sh
. "${DOTFILES_DIR}/shell-common/tools/ux_lib/ux_lib.sh"
# Backup primitives SSOT (#806): fixed-suffix, latest-only backups.
# shellcheck source=../../shell-common/lib/dotfiles_backup.sh
. "${DOTFILES_DIR}/shell-common/lib/dotfiles_backup.sh"
# shellcheck source=../../shell-common/util/setup_mode_read.sh
. "${DOTFILES_DIR}/shell-common/util/setup_mode_read.sh"

[ "$(_dotfiles_setup_mode)" = "internal" ] || exit 0

# _reregister_session_start_drift_hook — F-7b (issue #1364).
#
# 부트스트랩 단일 실패점 해소: session-start-settings-drift.sh 는 live 파일의
# .hooks/.statusLine drift 를 자동 복구하지만, Claude Code 가 그 훅을 호출하려면
# 훅이 live `.hooks.SessionStart` 에 등록돼 있어야 한다. 외부 요인이 live
# `.hooks` 를 통째로 날리면 훅의 등록도 함께 사라져 훅이 스스로를 되살릴 수
# 없다. 그 한 항목만 여기서 되돌린다.
#
# 안전 장치:
#   - jq 없음 / SSOT 없음 / live 파일 없음 / live 가 symlink → 조용히 no-op.
#     특히 파일을 새로 만들지 않는다 (생성 소유자는 gateway-cli). symlink
#     레이아웃은 그 symlink 를 만든 쪽 소유 — 훅 자신의 heal 경로와 동일 규칙.
#   - 훅 커맨드 문자열은 하드코딩하지 않고 SSOT 에서 jq 로 읽는다. 그래야
#     비표준 체크아웃 경로에서도 맞는 문자열이 들어간다.
#   - 이미 등록돼 있으면 파일을 열어보기만 하고 쓰지 않는다 (조용한 no-op).
#   - 쓰기 전 dotfiles_backup_copy 로 백업 (#806 고정 suffix, latest-only).
#     suffix 는 훅 자신의 `.pre-drift-heal.backup` 과 겹치지 않게 분리한다.
#   - mktemp → jq → mv 순서라 중간 실패가 live 파일을 반쯤 쓴 상태로 남기지
#     않는다. 실패 시 백업은 남긴다 (훅과 동일 규칙).
#   - 어떤 경로로도 0 을 반환한다 — 호출자(claude/setup.sh)의 나머지 단계를
#     이 부가 점검이 날려버리면 안 된다.
_reregister_session_start_drift_hook() {
    _rr_live="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
    _rr_ssot="${DOTFILES_DIR}/claude/settings.json"
    _rr_suffix=".pre-sessionstart-hook-reg.backup"

    if ! command -v jq >/dev/null 2>&1; then
        ux_warning "jq 미설치 — SessionStart drift-heal 훅 등록 점검 건너뜀 (#1364)"
        return 0
    fi
    if [ ! -f "$_rr_ssot" ]; then
        ux_warning "dotfiles SSOT 없음: $_rr_ssot — 훅 등록 점검 건너뜀 (#1364)"
        return 0
    fi
    # live 파일이 없으면 만들지 않는다 (조용히 skip — 생성 소유자는 gateway-cli).
    [ -f "$_rr_live" ] || return 0
    # symlink 면 손대지 않는다 — 그 레이아웃은 심링크를 만든 쪽 소유. 조용히
    # skip하지 않고 알린다: 재실행이 아무 효과가 없는 유일한 분기이기 때문이다
    # (PR #1366 코덱스 리뷰 지적).
    if [ -L "$_rr_live" ]; then
        ux_warning "live settings.json 이 symlink 입니다 — SessionStart 훅 등록 점검 건너뜀 (#1364)"
        ux_bullet "  symlink 레이아웃은 만든 쪽 소유라 여기서 건드리지 않습니다."
        ux_bullet "  복구: symlink 제거 후 gateway-cli setup 재실행"
        return 0
    fi
    jq empty "$_rr_live" >/dev/null 2>&1 || {
        ux_warning "live settings.json JSON 파싱 실패 — 훅 등록 점검 건너뜀: $_rr_live"
        return 0
    }

    # SSOT 에서 훅 커맨드 문자열을 그대로 읽어온다 (하드코딩 금지).
    _rr_cmd=$(jq -r '
        [ .hooks.SessionStart[]?.hooks[]?.command
          | select(type == "string")
          | select(endswith("session-start-settings-drift.sh")) ][0] // ""
    ' "$_rr_ssot" 2>/dev/null) || _rr_cmd=""
    if [ -z "$_rr_cmd" ]; then
        ux_warning "SSOT 에 session-start-settings-drift.sh 훅 정의가 없음 — 등록 생략 (#1364)"
        return 0
    fi

    # 이미 등록돼 있으면 조용히 끝낸다 (정상 경로 = 무출력).
    # jq 변수 ($cmd) 는 --arg 주입 — shell 변수 아님.
    # shellcheck disable=SC2016
    if jq -e --arg cmd "$_rr_cmd" \
        'any(.hooks.SessionStart[]?.hooks[]?.command; . == $cmd)' \
        "$_rr_live" >/dev/null 2>&1; then
        return 0
    fi

    _rr_backup=$(dotfiles_backup_copy "$_rr_live" "$_rr_suffix") || {
        ux_error "settings.json 백업 실패 — SessionStart 훅 등록 중단: $_rr_live"
        return 0
    }
    chmod 0600 "$_rr_backup" 2>/dev/null || true

    _rr_tmp=$(mktemp "${_rr_live}.XXXXXX" 2>/dev/null) || {
        ux_error "임시 파일 생성 실패 — SessionStart 훅 등록 중단 (백업 보존: $_rr_backup)"
        return 0
    }

    # `.hooks` / `.hooks.SessionStart` 의 모든 부재 단계는 jq path assignment
    # 가 알아서 autovivify 하므로 별도 `// {}` 없이 한 프로그램으로 처리된다.
    # 이미 등록된 경우는 위 already-registered 가드가 먼저 return 하므로 여기
    # 도달했다는 것 자체가 $cmd 가 아직 없다는 뜻이다 — 그래서 append 만 하고
    # 존재 여부를 다시 검사하지 않는다. 다른 키는 값이 그대로 보존된다 (jq 가
    # 문서를 재직렬화하므로 공백/키 순서만 정규화됨).
    # shellcheck disable=SC2016
    if jq --arg cmd "$_rr_cmd" \
            '.hooks.SessionStart = (
               (.hooks.SessionStart // []) + [{"hooks":[{"type":"command","command":$cmd}]}]
             )' \
            "$_rr_live" >"$_rr_tmp" 2>/dev/null &&
        [ -s "$_rr_tmp" ] &&
        chmod 0600 "$_rr_tmp" 2>/dev/null &&
        mv -f "$_rr_tmp" "$_rr_live" 2>/dev/null; then
        ux_warning "settings.json 에 SessionStart drift-heal 훅 자동 등록 완료 (#1364)"
        ux_bullet "  hook: $_rr_cmd"
        ux_bullet "  backup: $_rr_backup"
        ux_bullet "  .hooks.SessionStart 외 어떤 키도 변경하지 않았습니다."
        ux_bullet "  Claude Code 를 재시작하면 drift 자동 복구가 다시 동작합니다."
    else
        rm -f "$_rr_tmp"
        ux_error "settings.json 갱신 실패 — 백업 보존: $_rr_backup"
    fi
    return 0
}

_reregister_session_start_drift_hook
