#!/usr/bin/env bash
# shellcheck disable=SC2088  # ~/path literals in user-facing strings are intentional (not paths to expand)
# aws/diagnose.sh — Claude Code Linux 환경설정 진단 (사내 PC, read-only).
#
# 가이드(Claude_Linux.md) 기준으로 ./aws/setup.sh +
# ./aws/install-otel-managed-settings.sh 부트스트랩 결과를 점검한다.
# 2-5) AWS SSO 로그인 절차는 대화형이므로 제외한다.
#
# 사용:
#   ./aws/diagnose.sh           # 진단 실행
#   ./aws/diagnose.sh -h|--help # 사용법
#
# 안전성: 본 스크립트는 어떤 파일도 변경하지 않는다 (read-only).
# Issue: #677

# 복붙 실행에도 안전하도록 서브쉘로 감싼다.
(
set -uo pipefail

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
case "${1:-}" in
    -h|--help|help)
        cat <<'USAGE'
Usage: ./aws/diagnose.sh [-h|--help]

Read-only 진단. ./aws/setup.sh 와 ./aws/install-otel-managed-settings.sh
부트스트랩이 정상 완료되었는지 PASS / FAIL / WARN 으로 보고한다.

체크 항목 (가이드 절 번호):
  1-1) 프록시 인증서 (NODE_EXTRA_CA_CERTS, samsungsemi-prx.com.crt)
  1-2) Claude Code 설치 & PATH
  2-2) AWS CLI 설치
  2-3) AWS 인증서/Bedrock env (AWS_CA_BUNDLE, CLAUDE_CODE_USE_BEDROCK,
       ANTHROPIC_BEDROCK_BASE_URL, http(s)_proxy, no_proxy)
  2-4) ~/.aws/config (sso_start_url, sso_role_name, region)
  2-6) ~/.claude/settings.json (env, model, modelOverrides, awsAuthRefresh)
  2-7) /etc/claude-code/managed-settings.json (OTel telemetry)
  2-8) AWS SSO 세션 상태 (aws sts get-caller-identity)

본 스크립트는 read-only — 환경을 수정하지 않는다.
USAGE
        exit 0
        ;;
esac

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

if [ "${NO_COLOR:-}" != "" ] || [ "${TERM:-}" = "dumb" ]; then
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
fi

PASS=0
FAIL=0
WARN=0

pass()  { PASS=$((PASS+1)); printf "  ${GREEN}[PASS]${NC} %s\n" "$1"; }
fail()  { FAIL=$((FAIL+1)); printf "  ${RED}[FAIL]${NC} %s\n" "$1"; }
warn()  { WARN=$((WARN+1)); printf "  ${YELLOW}[WARN]${NC} %s\n" "$1"; }
header(){ printf "\n${CYAN}${BOLD}── %s ──${NC}\n" "$1"; }

# ---------------------------------------------------------------------------
# Setup-mode warning (diagnose 는 read-only 이므로 강제 차단 대신 경고만)
# ---------------------------------------------------------------------------
_mode_file="$HOME/.dotfiles-setup-mode"
if [ -f "$_mode_file" ]; then
    _mode_raw=$(tr -d ' \t\n\r' < "$_mode_file" 2>/dev/null || echo "")
    case "$_mode_raw" in
        2|internal) ;;
        *) printf '\n%s%sNOTE%s: setup-mode='\''%s'\'' — internal 전용 항목 일부가 FAIL 로 보고될 수 있습니다.\n' "$YELLOW" "$BOLD" "$NC" "$_mode_raw" ;;
    esac
else
    printf '\n%s%sNOTE%s: ~/.dotfiles-setup-mode 없음 — '\''./setup.sh'\'' 미수행 가능성.\n' "$YELLOW" "$BOLD" "$NC"
fi

# ---------------------------------------------------------------------------
# Dotfiles env file paths — 본 dotfiles 는 ~/.bashrc 가 아닌 별도 로컬
# env 파일(*.local.sh)로 변수를 export 한다. 진단의 "registered" 체크는
# bashrc + dotfiles env 파일 모두를 탐색해야 정확하다.
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
AWS_LOCAL_SH="${DOTFILES_DIR}/aws/aws.local.sh"
SECURITY_LOCAL_SH="${DOTFILES_DIR}/shell-common/env/security.local.sh"

# 주어진 env var 가 ~/.bashrc 또는 dotfiles env 파일에 export 되었는지 확인.
# 첫 매치된 파일 경로를 stdout 으로 돌려준다 (없으면 빈 문자열, exit 1).
_env_registered() {
    _var="$1"
    for _f in "$HOME/.bashrc" "$AWS_LOCAL_SH" "$SECURITY_LOCAL_SH"; do
        [ -f "$_f" ] || continue
        if grep -q "export ${_var}=" "$_f" 2>/dev/null; then
            printf '%s' "$_f"
            return 0
        fi
    done
    return 1
}

EXPECTED_PROXY_CERT_FINGERPRINT="MIIERTCCAy2gAwIBAgIJAPirWAe96NTFMA0GCSqGSIb3DQEBCwUA"
EXPECTED_SECDS_ROOT_FINGERPRINT="MIID8TCCAtmgAwIBAgIQeU+juUDmhZpLkbkVoaIKdDANBgkqhki"
EXPECTED_SECDS_T2ROOT_FINGERPRINT="MIID8zCCAqegAwIBAgIQNeZUTiLsarJADGKa+6XaEjBBBgkqhki"
EXPECTED_SECDS_T2ISSUING_FINGERPRINT="MIIFBzCCA7ugAwIBAgITFwAAAAeli5W0Sszy3QABAAAABzBBBgkq"

EXPECTED_CERT_PATH="/usr/local/share/ca-certificates/samsungsemi-prx.com.crt"
EXPECTED_BEDROCK_URL="https://vpce-0dd86dfd31388ddeb-tgk37vc6.bedrock-runtime.ap-northeast-2.vpce.amazonaws.com"
EXPECTED_SSO_START_URL="https://dspublic.awsapps.com/start"
EXPECTED_SSO_REGION="ap-northeast-2"
EXPECTED_SSO_ACCOUNT_ID="518692946118"
EXPECTED_REGION="ap-northeast-2"

# ============================================================
header "1-1) 프록시 인증서 생성 및 연결"
# ============================================================

# NODE_EXTRA_CA_CERTS 환경변수 확인
if [ -n "${NODE_EXTRA_CA_CERTS:-}" ]; then
  pass "NODE_EXTRA_CA_CERTS 환경변수 설정됨: ${NODE_EXTRA_CA_CERTS}"

  CERT_FILE="$NODE_EXTRA_CA_CERTS"

  # 확장자 확인
  case "$CERT_FILE" in
    *.crt) pass "인증서 확장자가 .crt" ;;
    *)     fail "인증서 확장자가 .crt가 아님 (현재: ${CERT_FILE##*.}) → .crt 확장자 필요" ;;
  esac

  # 파일 존재 확인
  if [ -f "$CERT_FILE" ]; then
    pass "인증서 파일 존재: ${CERT_FILE}"
  else
    fail "인증서 파일 없음: ${CERT_FILE}"
  fi
else
  fail "NODE_EXTRA_CA_CERTS 환경변수 미설정"
  CERT_FILE=""
fi

# bashrc 또는 dotfiles env 파일에 NODE_EXTRA_CA_CERTS 등록 여부
if _registered_in=$(_env_registered "NODE_EXTRA_CA_CERTS"); then
  pass "NODE_EXTRA_CA_CERTS 등록됨 (source: ${_registered_in})"
else
  fail "NODE_EXTRA_CA_CERTS 미등록 → shell-common/env/security.local.sh 에 export 추가 필요"
fi

# 인증서 파일 내용 점검 (NODE_EXTRA_CA_CERTS가 가리키는 파일 또는 기본 경로)
CHECK_CERT="${CERT_FILE:-$EXPECTED_CERT_PATH}"
if [ -f "$CHECK_CERT" ]; then
  CERT_CONTENT=$(cat "$CHECK_CERT")

  # BEGIN CERTIFICATE 첫 줄 깨짐 여부 확인 (vim 붙여넣기 버그)
  FIRST_BEGIN=$(grep -n "BEGIN CERTIFICATE" "$CHECK_CERT" | head -1)
  if echo "$FIRST_BEGIN" | grep -q "^[0-9]*:-----BEGIN CERTIFICATE-----$"; then
    pass "인증서 첫 줄 형식 정상 (vim 붙여넣기 깨짐 없음)"
  else
    fail "인증서 첫 줄이 깨져 있을 수 있음 → -----BEGIN CERTIFICATE----- 형식인지 확인 필요"
  fi

  # 각 인증서 포함 여부
  if echo "$CERT_CONTENT" | grep -q "$EXPECTED_PROXY_CERT_FINGERPRINT"; then
    pass "반도체 프록시 인증서 (samsungsemi-prx.com) 포함됨"
  else
    fail "반도체 프록시 인증서 (samsungsemi-prx.com) 미포함"
  fi

  if echo "$CERT_CONTENT" | grep -q "$EXPECTED_SECDS_ROOT_FINGERPRINT"; then
    pass "DS 1 Tier 루트인증서 (SECDS_ROOT_CA) 포함됨"
  else
    warn "DS 1 Tier 루트인증서 (SECDS_ROOT_CA) 미포함 (Case 2에서만 필요)"
  fi

  if echo "$CERT_CONTENT" | grep -q "$EXPECTED_SECDS_T2ROOT_FINGERPRINT"; then
    pass "DS 2 Tier 루트인증서 (SECDS-T2ROOTCA) 포함됨"
  else
    warn "DS 2 Tier 루트인증서 (SECDS-T2ROOTCA) 미포함 (Case 2에서만 필요)"
  fi

  if echo "$CERT_CONTENT" | grep -q "$EXPECTED_SECDS_T2ISSUING_FINGERPRINT"; then
    pass "DS 2 Tier 중간기관 인증서 (SECDS-T2IssuingCA) 포함됨"
  else
    warn "DS 2 Tier 중간기관 인증서 (SECDS-T2IssuingCA) 미포함 (Case 2에서만 필요)"
  fi
else
  fail "인증서 파일을 찾을 수 없음: ${CHECK_CERT}"
fi

# ============================================================
header "1-2) Claude Code 설치"
# ============================================================

if command -v claude >/dev/null 2>&1; then
  CLAUDE_PATH=$(command -v claude)
  pass "claude 명령어 사용 가능: ${CLAUDE_PATH}"
else
  fail "claude 명령어를 찾을 수 없음 → Claude Code 설치가 안 됐거나 PATH에 등록 안 됨"
fi

if echo "$PATH" | tr ':' '\n' | grep -q "$HOME/.local/bin"; then
  pass "PATH에 ~/.local/bin 포함됨"
else
  fail "PATH에 ~/.local/bin 미포함 → ~/.bashrc 또는 dotfiles 쉘 init 에 추가 필요"
fi

if _registered_in=$(_env_registered "PATH"); then
  pass "PATH 관련 export 등록됨 (source: ${_registered_in})"
elif grep -qE 'export PATH=.*\.local/bin' "$HOME/.bashrc" 2>/dev/null; then
  pass "~/.bashrc 에 ~/.local/bin PATH 등록됨"
else
  warn "~/.bashrc 에 ~/.local/bin PATH 등록 미확인 → 다른 설정파일에 있을 수 있음"
fi

# ============================================================
header "2-2) AWS CLI"
# ============================================================

if command -v aws >/dev/null 2>&1; then
  AWS_VER=$(aws --version 2>&1)
  pass "AWS CLI 설치됨: ${AWS_VER}"
else
  fail "AWS CLI 미설치 → 가이드 2-2 절차 수행 필요"
fi

# ============================================================
header "2-3) AWS 인증서 설정 (환경변수)"
# ============================================================

# AWS_CA_BUNDLE
if [ -n "${AWS_CA_BUNDLE:-}" ]; then
  pass "AWS_CA_BUNDLE 설정됨: ${AWS_CA_BUNDLE}"
  if [ -f "$AWS_CA_BUNDLE" ]; then
    pass "AWS_CA_BUNDLE 파일 존재"
  else
    fail "AWS_CA_BUNDLE 파일 없음: ${AWS_CA_BUNDLE}"
  fi
  case "$AWS_CA_BUNDLE" in
    *.crt) pass "AWS_CA_BUNDLE 확장자 .crt" ;;
    *)     fail "AWS_CA_BUNDLE 확장자가 .crt가 아님 → .crt 확장자 필요" ;;
  esac
else
  fail "AWS_CA_BUNDLE 환경변수 미설정"
fi

# CLAUDE_CODE_USE_BEDROCK
if [ "${CLAUDE_CODE_USE_BEDROCK:-}" = "1" ]; then
  pass "CLAUDE_CODE_USE_BEDROCK=1 설정됨"
else
  fail "CLAUDE_CODE_USE_BEDROCK 미설정 또는 값이 '1'이 아님 (현재: '${CLAUDE_CODE_USE_BEDROCK:-}')"
fi

# ANTHROPIC_BEDROCK_BASE_URL
if [ "${ANTHROPIC_BEDROCK_BASE_URL:-}" = "$EXPECTED_BEDROCK_URL" ]; then
  pass "ANTHROPIC_BEDROCK_BASE_URL 올바르게 설정됨"
elif [ -n "${ANTHROPIC_BEDROCK_BASE_URL:-}" ]; then
  fail "ANTHROPIC_BEDROCK_BASE_URL 값이 다름"
  printf "       기대: %s\n" "$EXPECTED_BEDROCK_URL"
  printf "       현재: %s\n" "$ANTHROPIC_BEDROCK_BASE_URL"
else
  fail "ANTHROPIC_BEDROCK_BASE_URL 미설정"
fi

# Proxy 환경변수
if [ -n "${https_proxy:-}${HTTPS_PROXY:-}" ]; then
  PROXY_VAL="${https_proxy:-${HTTPS_PROXY:-}}"
  pass "https_proxy 설정됨: ${PROXY_VAL}"
else
  fail "https_proxy / HTTPS_PROXY 미설정"
fi

if [ -n "${http_proxy:-}${HTTP_PROXY:-}" ]; then
  PROXY_VAL="${http_proxy:-${HTTP_PROXY:-}}"
  pass "http_proxy 설정됨: ${PROXY_VAL}"
else
  fail "http_proxy / HTTP_PROXY 미설정"
fi

if [ -n "${no_proxy:-}${NO_PROXY:-}" ]; then
  NO_PROXY_VAL="${no_proxy:-${NO_PROXY:-}}"
  pass "no_proxy 설정됨"

  # samsungds.net 포함 및 와일드카드 여부 확인
  if echo "$NO_PROXY_VAL" | grep -q 'samsungds\.net'; then
    if echo "$NO_PROXY_VAL" | grep -qE '\*\.?samsungds\.net'; then
      fail "no_proxy에 와일드카드(*.samsungds.net) 사용됨 → '*' 제거하고 .samsungds.net 으로 변경 필요"
    else
      pass "no_proxy에 samsungds.net 정상 포함됨"
    fi
  else
    fail "no_proxy에 samsungds.net 미포함 → .samsungds.net 추가 필요"
  fi
else
  warn "no_proxy / NO_PROXY 미설정"
fi

# bashrc 또는 dotfiles env 파일에 환경변수 등록 여부
for VAR in AWS_CA_BUNDLE CLAUDE_CODE_USE_BEDROCK ANTHROPIC_BEDROCK_BASE_URL; do
  if _registered_in=$(_env_registered "$VAR"); then
    pass "${VAR} 등록됨 (source: ${_registered_in})"
  else
    fail "${VAR} 미등록 → 영구 설정 안 됨 (aws/aws.local.sh 또는 ~/.bashrc 확인)"
  fi
done

# ============================================================
header "2-4) AWS 자격 증명 구성 (~/.aws/config)"
# ============================================================

AWS_CONFIG="$HOME/.aws/config"
if [ -f "$AWS_CONFIG" ]; then
  pass "~/.aws/config 파일 존재"

  CONFIG_CONTENT=$(cat "$AWS_CONFIG")

  # [default] 프로필 확인
  if echo "$CONFIG_CONTENT" | grep -q '^\[default\]'; then
    pass "[default] 프로필 존재"
  else
    fail "[default] 프로필 미존재 → [default] 섹션 추가 필요"
  fi

  # sso_start_url
  if echo "$CONFIG_CONTENT" | grep -q "sso_start_url.*=.*${EXPECTED_SSO_START_URL}"; then
    pass "sso_start_url 올바름"
  else
    ACTUAL=$(echo "$CONFIG_CONTENT" | grep 'sso_start_url' | head -1 | awk -F= '{print $2}' | xargs)
    if [ -n "$ACTUAL" ]; then
      fail "sso_start_url 값이 다름 (현재: ${ACTUAL}, 기대: ${EXPECTED_SSO_START_URL})"
    else
      fail "sso_start_url 미설정"
    fi
  fi

  # sso_region
  if echo "$CONFIG_CONTENT" | grep -q "sso_region.*=.*${EXPECTED_SSO_REGION}"; then
    pass "sso_region 올바름"
  else
    fail "sso_region 미설정 또는 값이 다름 (기대: ${EXPECTED_SSO_REGION})"
  fi

  # sso_account_id
  if echo "$CONFIG_CONTENT" | grep -q "sso_account_id.*=.*${EXPECTED_SSO_ACCOUNT_ID}"; then
    pass "sso_account_id 올바름"
  else
    fail "sso_account_id 미설정 또는 값이 다름 (기대: ${EXPECTED_SSO_ACCOUNT_ID})"
  fi

  # sso_role_name
  SSO_ROLE=$(echo "$CONFIG_CONTENT" | grep 'sso_role_name' | head -1 | awk -F= '{print $2}' | xargs)
  if [ -n "$SSO_ROLE" ]; then
    if [ "$SSO_ROLE" = "여기에 안내 받은 값을 붙여넣으세요 (대소문자도 구분 필수)" ]; then
      fail "sso_role_name이 가이드 예시 그대로임 → AICM 메일로 안내 받은 실제 role name으로 변경 필요"
    else
      pass "sso_role_name 설정됨: ${SSO_ROLE}"
    fi
  else
    fail "sso_role_name 미설정 → AICM 메일에서 안내 받은 role name 입력 필요"
  fi

  # region
  if echo "$CONFIG_CONTENT" | grep -q "^region.*=.*${EXPECTED_REGION}"; then
    pass "region 올바름"
  else
    fail "region 미설정 또는 값이 다름 (기대: ${EXPECTED_REGION})"
  fi
else
  fail "~/.aws/config 파일 없음 → ./aws/setup.sh 미수행"
fi

# ============================================================
header "2-6) 모델 정보 (~/.claude/settings.json / settings.local.json)"
# ============================================================

# 사용자는 settings.local.json 에 모델 매핑을 머지한다 (#677 F-7).
# settings.json 은 SSOT 로 커밋되어 있어 모델 매핑이 비어 있을 수 있다.
CLAUDE_SETTINGS_LOCAL="$HOME/.claude/settings.local.json"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
SETTINGS_FILE=""
if [ -f "$CLAUDE_SETTINGS_LOCAL" ]; then
  SETTINGS_FILE="$CLAUDE_SETTINGS_LOCAL"
  pass "~/.claude/settings.local.json 파일 존재"
elif [ -f "$CLAUDE_SETTINGS" ]; then
  SETTINGS_FILE="$CLAUDE_SETTINGS"
  warn "settings.local.json 없음 — settings.json 으로 폴백 (Bedrock 매핑은 보통 .local 에 있음)"
else
  fail "~/.claude/settings*.json 파일 없음 → ./aws/setup.sh 미수행"
fi

if [ -n "$SETTINGS_FILE" ]; then
  # JSON 유효성 검사
  if command -v jq >/dev/null 2>&1; then
    if jq empty "$SETTINGS_FILE" 2>/dev/null; then
      pass "JSON 형식 유효 (${SETTINGS_FILE})"
    else
      fail "JSON 형식 오류 (${SETTINGS_FILE}) → 문법(쉼표, 중괄호 등)을 확인하세요"
    fi

    # 양립-불가 잔존 키 확인 (#677 O-1)
    LEGACY=$(jq -r '.env // {} | keys_unsorted[] | select(test("^(ANTHROPIC_BASE_URL|ANTHROPIC_AUTH_TOKEN|ANTHROPIC_MODEL|ANTHROPIC_CUSTOM_HEADERS|NODE_TLS_REJECT_UNAUTHORIZED)$"))' "$SETTINGS_FILE" 2>/dev/null | tr '\n' ' ')
    if [ -n "$LEGACY" ]; then
      fail "Bedrock 와 양립 불가한 레거시 gateway env 키 잔존: ${LEGACY}→ ./aws/setup.sh 재실행 (자동 제거됨)"
    else
      pass "레거시 gateway env 키 없음 (Bedrock 단일 경로)"
    fi

    SETTINGS_JSON=$(jq '.' "$SETTINGS_FILE" 2>/dev/null || echo "{}")

    # Bedrock 모드는 CLAUDE_CODE_USE_BEDROCK 를 쉘 env 한 곳에서만 SSOT 로
    # 가진다 (#677 F-7.3). settings.json 에 중복 명시되어 있다면 정보로만 보고.
    USE_BR=$(echo "$SETTINGS_JSON" | jq -r '.env.CLAUDE_CODE_USE_BEDROCK // empty' 2>/dev/null)
    if [ "$USE_BR" = "1" ]; then
      pass "settings 의 env.CLAUDE_CODE_USE_BEDROCK=1 (쉘 env 와 중복이지만 안전)"
    fi

    # model 확인
    MODEL=$(echo "$SETTINGS_JSON" | jq -r '.model // empty' 2>/dev/null)
    if [ -n "$MODEL" ]; then
      pass "settings model 설정됨: ${MODEL}"
    else
      fail "settings model 미설정"
    fi

    # availableModels
    if [ "$(echo "$SETTINGS_JSON" | jq -r '.availableModels | length // 0' 2>/dev/null)" -gt 0 ] 2>/dev/null; then
      pass "settings availableModels 설정됨"
    else
      warn "settings availableModels 미설정"
    fi

    # modelOverrides
    if [ "$(echo "$SETTINGS_JSON" | jq -r '.modelOverrides | length // 0' 2>/dev/null)" -gt 0 ] 2>/dev/null; then
      pass "settings modelOverrides 설정됨"
    else
      warn "settings modelOverrides 미설정"
    fi

    # awsAuthRefresh
    AUTH_REFRESH=$(echo "$SETTINGS_JSON" | jq -r '.awsAuthRefresh // empty' 2>/dev/null)
    if [ "$AUTH_REFRESH" = "aws sso login" ]; then
      pass "settings awsAuthRefresh 올바름"
    elif [ -n "$AUTH_REFRESH" ]; then
      fail "settings awsAuthRefresh 값이 다름 (현재: ${AUTH_REFRESH}, 기대: aws sso login)"
    else
      fail "settings awsAuthRefresh 미설정"
    fi
  else
    warn "jq 미설치 → settings 내용 상세 검증 생략 (jq 설치 후 재실행 권장)"
  fi
fi

# ============================================================
header "2-7) OTel 텔레메트리 (/etc/claude-code/managed-settings.json)"
# ============================================================

MANAGED_SETTINGS="/etc/claude-code/managed-settings.json"
if [ -f "$MANAGED_SETTINGS" ]; then
  pass "managed-settings.json 파일 존재"

  if command -v jq >/dev/null 2>&1; then
    if jq empty "$MANAGED_SETTINGS" 2>/dev/null; then
      pass "managed-settings.json JSON 형식 유효"
    else
      fail "managed-settings.json JSON 형식 오류"
    fi

    MANAGED_JSON=$(jq '.' "$MANAGED_SETTINGS" 2>/dev/null || echo "{}")

    # CLAUDE_CODE_ENABLE_TELEMETRY
    TELEMETRY=$(echo "$MANAGED_JSON" | jq -r '.env.CLAUDE_CODE_ENABLE_TELEMETRY // empty' 2>/dev/null)
    if [ "$TELEMETRY" = "1" ]; then
      pass "CLAUDE_CODE_ENABLE_TELEMETRY=1 설정됨"
    else
      fail "CLAUDE_CODE_ENABLE_TELEMETRY 미설정 또는 값이 '1'이 아님"
    fi

    # OTEL_RESOURCE_ATTRIBUTES 에 user.id 포함 확인
    RESOURCE_ATTRS=$(echo "$MANAGED_JSON" | jq -r '.env.OTEL_RESOURCE_ATTRIBUTES // empty' 2>/dev/null)
    if echo "$RESOURCE_ATTRS" | grep -q "user.id="; then
      USER_ID=$(echo "$RESOURCE_ATTRS" | grep -oE 'user\.id=[^,]+' | head -1 | cut -d= -f2)
      pass "OTEL user.id 설정됨: ${USER_ID}"
    else
      fail "OTEL_RESOURCE_ATTRIBUTES 에 user.id 미포함 → ./aws/install-otel-managed-settings.sh 재실행"
    fi

    # endpoint
    OTEL_ENDPOINT=$(echo "$MANAGED_JSON" | jq -r '.env.OTEL_EXPORTER_OTLP_ENDPOINT // empty' 2>/dev/null)
    if [ -n "$OTEL_ENDPOINT" ]; then
      pass "OTEL endpoint 설정됨: ${OTEL_ENDPOINT}"
    else
      fail "OTEL endpoint 미설정"
    fi
  else
    warn "jq 미설치 → managed-settings.json 상세 검증 생략"
  fi
else
  fail "managed-settings.json 없음: ${MANAGED_SETTINGS} → ./aws/install-otel-managed-settings.sh 미수행"
fi

# ============================================================
header "2-8) AWS SSO 세션 상태"
# ============================================================

if command -v aws >/dev/null 2>&1; then
  if aws sts get-caller-identity >/dev/null 2>&1; then
    CALLER=$(aws sts get-caller-identity --output text --query 'UserId' 2>/dev/null)
    pass "AWS SSO 세션 유효 (UserId: ${CALLER})"
  else
    fail "AWS SSO 세션 만료 또는 미로그인 → aws sso login 실행 필요"
  fi
else
  warn "AWS CLI 미설치 → SSO 세션 확인 불가"
fi

# ============================================================
header "진단 결과 요약"
# ============================================================

TOTAL=$((PASS + FAIL + WARN))
printf "\n"
printf "  ${GREEN}PASS: %d${NC}  ${RED}FAIL: %d${NC}  ${YELLOW}WARN: %d${NC}  / 총 %d 항목\n" "$PASS" "$FAIL" "$WARN" "$TOTAL"
printf "\n"

if [ "$FAIL" -eq 0 ]; then
  printf '  %s%s모든 필수 항목이 정상입니다.%s\n' "$GREEN" "$BOLD" "$NC"
  exit_code=0
else
  printf '  %s%sFAIL 항목을 확인하고 가이드에 따라 수정해 주세요.%s\n' "$RED" "$BOLD" "$NC"
  printf '\n'
  printf '  %sNext:%s\n' "$BOLD" "$NC"
  printf '    1. ./aws/setup.sh                          (env / config / settings 시드 + 레거시 키 제거)\n'
  printf '    2. aws sso login                           (SSO 토큰 갱신)\n'
  printf '    3. ./aws/install-otel-managed-settings.sh  (OTel 재설치)\n'
  printf '    4. 새 쉘에서 ./aws/diagnose.sh 재실행\n'
  exit_code=1
fi
printf '\n'

exit "$exit_code"
)
