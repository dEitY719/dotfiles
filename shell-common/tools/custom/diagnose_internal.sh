#!/bin/bash
# shell-common/tools/custom/diagnose_internal.sh
# 사내(internal) PC read-only 진단 — 프록시 CA, claude/PATH, 프록시 env, settings.json (#2099)
# shellcheck disable=SC2088  # ~/path literals in user-facing strings are intentional
#
# #2097 로 지운 aws/diagnose.sh 중 AWS 와 무관한 항목만 되살렸다: 프록시 CA,
# claude 설치/PATH, 프록시 env, ~/.claude/settings.json 의 .hooks/.statusLine
# SSOT 일치. internal 모드가 아니면 안내만 하고 exit 0. 어떤 파일도 쓰지 않는다.
#
# 사용: bash shell-common/tools/custom/diagnose_internal.sh [-h|--help]

# init.sh 는 DOTFILES_TEST_MODE=1 에서 ux_lib 로드 전에 return 하므로 직접 보충한다.
_di_dir="$(cd "$(dirname "$0")" && pwd)"
source "$_di_dir/init.sh" || exit 1
DOTFILES_ROOT="${_di_dir%/shell-common/tools/custom}"
type ux_header >/dev/null 2>&1 || . "$DOTFILES_ROOT/shell-common/tools/ux_lib/ux_lib.sh"
# shellcheck source=../../util/setup_mode_read.sh
. "$DOTFILES_ROOT/shell-common/util/setup_mode_read.sh"

diagnose_internal_help() {
    ux_usage "diagnose_internal.sh" "[-h|--help]" "사내(internal) PC 진단 — read-only, PASS / FAIL / WARN 으로 보고한다."
    ux_bullet "1) 프록시 인증서 (NODE_EXTRA_CA_CERTS, 사내 프록시 CA 포함 여부)"
    ux_bullet "2) Claude Code 설치 & PATH (~/.local/bin)"
    ux_bullet "3) 프록시 env (http(s)_proxy, no_proxy 사내 도메인)"
    ux_bullet "4) ~/.claude/settings.json JSON 유효성 + .hooks/.statusLine SSOT 일치"
    ux_bullet "사내 기대값: shell-common/env/internal.local.sh (미설정 항목은 WARN)"
    ux_bullet "internal 모드가 아니면 아무것도 검사하지 않고 exit 0"
}

PASS=0
FAIL=0
WARN=0
pass() {
    PASS=$((PASS + 1))
    ux_success "[PASS] $1"
}
fail() {
    FAIL=$((FAIL + 1))
    ux_error "[FAIL] $1" 2>&1
}
warn() {
    WARN=$((WARN + 1))
    ux_warning "[WARN] $1"
}

SECURITY_LOCAL_SH="$DOTFILES_ROOT/shell-common/env/security.local.sh"
INTERNAL_LOCAL_SH="$DOTFILES_ROOT/shell-common/env/internal.local.sh"

# 변수가 ~/.bashrc 또는 security.local.sh 에 export 되어 있으면 그 경로를 출력.
_env_registered() {
    local _f
    for _f in "$HOME/.bashrc" "$SECURITY_LOCAL_SH"; do
        [ -f "$_f" ] || continue
        if grep -q "export $1=" "$_f" 2>/dev/null; then
            printf '%s' "$_f"
            return 0
        fi
    done
    return 1
}

main() {
    case "${1:-}" in
        -h | --help | help)
            diagnose_internal_help
            return 0
            ;;
    esac

    _mode=$(_dotfiles_setup_mode)
    if [ "$_mode" != "internal" ]; then
        ux_info "setup-mode='${_mode:-none}' — internal 모드 전용 진단이라 건너뜁니다."
        return 0
    fi

    # 사내 기대값은 공개 repo 에 두지 않는다 (#1966) — gitignored internal.local.sh.
    if [ -z "${DOTFILES_SKIP_LOCAL_ENV-}" ] && [ -f "$INTERNAL_LOCAL_SH" ]; then
        # shellcheck source=/dev/null
        . "$INTERNAL_LOCAL_SH"
    fi
    _proxy_fp="${DOTFILES_PROXY_CA_FINGERPRINT:-}"
    _extra_fps="${DOTFILES_EXTRA_CA_FINGERPRINTS:-}"
    _domain="${DOTFILES_INTERNAL_DOMAIN:-}"
    _unset_hint="internal.local.sh 미설정 → 비교 생략"

    ux_section "1) 프록시 인증서 (NODE_EXTRA_CA_CERTS)"
    CERT_FILE="${NODE_EXTRA_CA_CERTS:-}"
    if [ -n "$CERT_FILE" ]; then
        pass "NODE_EXTRA_CA_CERTS 설정됨: $CERT_FILE"
        case "$CERT_FILE" in
            *.crt) pass "인증서 확장자가 .crt" ;;
            *) fail "인증서 확장자가 .crt 가 아님 (현재: ${CERT_FILE##*.})" ;;
        esac
    else
        fail "NODE_EXTRA_CA_CERTS 미설정"
    fi
    if _src=$(_env_registered NODE_EXTRA_CA_CERTS); then
        pass "NODE_EXTRA_CA_CERTS 등록됨 (source: $_src)"
    else
        fail "NODE_EXTRA_CA_CERTS 미등록 → shell-common/env/security.local.sh 에 export 추가"
    fi
    CHECK_CERT="${CERT_FILE:-${SSL_CERT_FILE:-}}"
    if [ -n "$CHECK_CERT" ] && [ -f "$CHECK_CERT" ]; then
        # vim 붙여넣기로 첫 BEGIN 줄이 깨지는 사고 감지 (끝 공백은 허용).
        if grep -m1 "BEGIN CERTIFICATE" "$CHECK_CERT" | grep -qE '^-----BEGIN CERTIFICATE-----[[:space:]]*$'; then
            pass "인증서 첫 줄 형식 정상"
        else
            fail "인증서 첫 줄이 깨져 있을 수 있음 → -----BEGIN CERTIFICATE----- 형식 확인"
        fi
        if [ -z "$_proxy_fp" ]; then
            warn "사내 프록시 인증서 포함 여부: $_unset_hint"
        elif grep -q "$_proxy_fp" "$CHECK_CERT"; then
            pass "사내 프록시 인증서 포함됨"
        else
            fail "사내 프록시 인증서 미포함"
        fi
        _n=0
        for _fp in $_extra_fps; do
            _n=$((_n + 1))
            if grep -q "$_fp" "$CHECK_CERT"; then
                pass "추가 사내 CA 인증서 #$_n 포함됨"
            else
                warn "추가 사내 CA 인증서 #$_n 미포함"
            fi
        done
    else
        fail "인증서 파일을 찾을 수 없음: ${CHECK_CERT:-(없음)}"
    fi

    ux_section "2) Claude Code 설치 & PATH"
    if command -v claude >/dev/null 2>&1; then
        pass "claude 명령어 사용 가능: $(command -v claude)"
    else
        fail "claude 명령어 없음 → 설치 또는 PATH 확인"
    fi
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) pass "PATH 에 ~/.local/bin 포함됨" ;;
        *) fail "PATH 에 ~/.local/bin 미포함" ;;
    esac

    ux_section "3) 프록시 env"
    if [ -n "${https_proxy:-}${HTTPS_PROXY:-}" ]; then
        pass "https_proxy 설정됨: ${https_proxy:-$HTTPS_PROXY}"
    else
        fail "https_proxy / HTTPS_PROXY 미설정"
    fi
    if [ -n "${http_proxy:-}${HTTP_PROXY:-}" ]; then
        pass "http_proxy 설정됨: ${http_proxy:-$HTTP_PROXY}"
    else
        fail "http_proxy / HTTP_PROXY 미설정"
    fi
    _no_proxy="${no_proxy:-${NO_PROXY:-}}"
    if [ -z "$_no_proxy" ]; then
        warn "no_proxy / NO_PROXY 미설정"
    elif [ -z "$_domain" ]; then
        pass "no_proxy 설정됨"
        warn "no_proxy 사내 도메인: $_unset_hint"
    else
        pass "no_proxy 설정됨"
        _dom_re=$(printf '%s' "$_domain" | sed 's/\./\\./g')
        if ! printf '%s' "$_no_proxy" | grep -q "$_dom_re"; then
            fail "no_proxy 에 $_domain 미포함 → .$_domain 추가"
        elif printf '%s' "$_no_proxy" | grep -qE "\\*\\.?$_dom_re"; then
            fail "no_proxy 에 와일드카드(*.$_domain) 사용됨 → .$_domain 으로 변경"
        else
            pass "no_proxy 에 $_domain 포함됨"
        fi
    fi

    ux_section "4) ~/.claude/settings.json"
    # session-start-settings-drift.sh 훅과 같은 LIVE 경로 해석 (CLAUDE_CONFIG_DIR 우선).
    SETTINGS_FILE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
    _ssot="$DOTFILES_ROOT/claude/settings.json"
    _fix_hint="./setup.sh 재실행(claude/tools/register-drift-hook.sh 가 훅 등록 복구) 후 새 세션 시작"
    if [ ! -f "$SETTINGS_FILE" ]; then
        fail "$SETTINGS_FILE 없음 → gateway-cli setup 미수행"
    elif ! command -v jq >/dev/null 2>&1; then
        warn "jq 미설치 → settings.json 검증 생략"
    else
        if [ -L "$SETTINGS_FILE" ]; then
            fail "settings.json 이 symlink → 제거 후 gateway-cli setup 재실행"
        else
            pass "settings.json 실파일 존재"
        fi
        if jq empty "$SETTINGS_FILE" 2>/dev/null; then
            pass "JSON 형식 유효 ($SETTINGS_FILE)"
        else
            fail "JSON 형식 오류 ($SETTINGS_FILE)"
        fi
        if [ -f "$_ssot" ]; then
            # 비교 기준(jq -S -c)은 session-start-settings-drift.sh 와 동일.
            if [ "$(jq -S -c '.hooks // {}' "$_ssot" 2>/dev/null)" = "$(jq -S -c '.hooks // {}' "$SETTINGS_FILE" 2>/dev/null)" ]; then
                pass ".hooks 가 dotfiles SSOT 와 일치"
            else
                fail ".hooks 가 dotfiles SSOT 와 다름 → $_fix_hint"
            fi
            if [ "$(jq -S -c '.statusLine // null' "$_ssot" 2>/dev/null)" = "$(jq -S -c '.statusLine // null' "$SETTINGS_FILE" 2>/dev/null)" ]; then
                pass ".statusLine 이 dotfiles SSOT 와 일치"
            else
                fail ".statusLine 이 dotfiles SSOT 와 다름 → $_fix_hint"
            fi
        else
            warn "dotfiles SSOT 없음: $_ssot → .hooks/.statusLine 비교 생략"
        fi
        ux_info "auth/env/모델 설정은 gateway-cli 영역 → 'gateway-cli verify' 로 확인"
    fi

    ux_section "결과"
    ux_info "PASS: $PASS  FAIL: $FAIL  WARN: $WARN"
    if [ "$FAIL" -gt 0 ]; then
        ux_error "FAIL 항목을 확인하세요." 2>&1
        return 1
    fi
    ux_success "모든 필수 항목이 정상입니다."
}

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "${BASH_SOURCE[0]}" ]; then
    main "$@"
    exit $?
fi
