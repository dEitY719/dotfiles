#!/usr/bin/env bash
# aws/install-otel-managed-settings.sh — Claude Code OTel telemetry installer.
#
# Writes /etc/claude-code/managed-settings.json with internal Samsung OTLP
# endpoint + dynamic user.id (from `aws sts get-caller-identity`). Required
# preconditions:
#   1. ~/.dotfiles-setup-mode == internal   (external PCs are refused)
#   2. AWS CLI v2 installed
#   3. `aws sso login` already completed (this script does NOT log you in)
#   4. sudo authority on this machine
#
# Idempotent: identical inputs produce identical output. Re-run any time.
#
# Issue: #677 (F-8).

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths + constants
# ---------------------------------------------------------------------------
MANAGED_DIR="/etc/claude-code"
MANAGED_FILE="${MANAGED_DIR}/managed-settings.json"

OTEL_ENDPOINT_HOST="10.172.25.203"
OTEL_ENDPOINT="http://${OTEL_ENDPOINT_HOST}:80"
OTEL_LOGS_ENDPOINT="${OTEL_ENDPOINT}/v1/logs"
OTEL_METRICS_ENDPOINT="${OTEL_ENDPOINT}/v1/metrics"

BASE_RESOURCE_ATTRS="service.name=claude-code,llm.provider=bedrock,environment=prod"

NO_PROXY_VALUE="${OTEL_ENDPOINT_HOST},.samsung.com,.samsungds.net,12.0.0.0/8,10.0.0.0/8,192.0.0.0/8,172.0.0.0/8"

# ---------------------------------------------------------------------------
# ux_lib (best-effort — fall back to plain stderr when sourcing fails)
# ---------------------------------------------------------------------------
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_UX_LIB="${_SCRIPT_DIR}/../shell-common/tools/ux_lib/ux_lib.sh"
if [ -f "$_UX_LIB" ]; then
    # shellcheck source=/dev/null
    . "$_UX_LIB"
else
    ux_info()    { printf '[INFO] %s\n'    "$*"; }
    ux_success() { printf '[OK]   %s\n'    "$*"; }
    ux_warning() { printf '[WARN] %s\n'    "$*" >&2; }
    ux_error()   { printf '[ERR]  %s\n'    "$*" >&2; }
    ux_section() { printf '\n== %s ==\n'   "$*"; }
    ux_bullet()  { printf '  - %s\n'       "$*"; }
fi

die() { ux_error "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Setup-mode gate — refuse on external/public PCs
# ---------------------------------------------------------------------------
_mode_file="$HOME/.dotfiles-setup-mode"
if [ ! -f "$_mode_file" ]; then
    die "$_mode_file 없음. 먼저 ./setup.sh 로 internal 모드를 선택하세요."
fi
_mode=$(tr -d ' \t\n\r' < "$_mode_file" 2>/dev/null || echo "")
case "$_mode" in
    2|internal) ;;
    *)
        die "setup-mode='${_mode:-unset}' — install-otel-managed-settings.sh 는 internal 전용입니다."
        ;;
esac

ux_section "Claude Code OTel installer (internal mode)"

# ---------------------------------------------------------------------------
# Tool prerequisites
# ---------------------------------------------------------------------------
command -v sudo >/dev/null 2>&1 || die "sudo not found. /etc/claude-code 쓰기에 필요합니다."
command -v aws  >/dev/null 2>&1 || die "aws CLI not found. AWS CLI v2 를 먼저 설치하세요."

if ! command -v jq >/dev/null 2>&1; then
    ux_info "jq 미설치 — 자동 설치 시도"
    if command -v apt-get >/dev/null 2>&1; then
        sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y jq
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y jq
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y jq
    else
        die "지원되는 패키지 매니저(apt-get/dnf/yum) 없음. jq 를 수동 설치하세요."
    fi
    command -v jq >/dev/null 2>&1 || die "jq 설치 보고됐지만 바이너리를 못 찾음."
fi

# ---------------------------------------------------------------------------
# STS UserId (resource attribute — user.id)
# ---------------------------------------------------------------------------
CALLER_JSON="$(aws sts get-caller-identity 2>/dev/null)" \
    || die "aws sts get-caller-identity 실패. 먼저 'aws sso login' 을 실행하세요."

USER_ID_RAW="$(printf '%s' "$CALLER_JSON" | jq -r '.UserId')"
if [ "$USER_ID_RAW" = "null" ] || [ -z "$USER_ID_RAW" ]; then
    die "UserId 가 caller-identity 응답에 없음."
fi

USER_ID="${USER_ID_RAW##*:}"
if [ -z "$USER_ID" ] || [ "$USER_ID" = "$USER_ID_RAW" ]; then
    die "UserId '$USER_ID_RAW' 형식이 'ROLE_ID:user' 와 다릅니다."
fi

RESOURCE_ATTRS="${BASE_RESOURCE_ATTRS},user.id=${USER_ID}"

# ---------------------------------------------------------------------------
# Render managed-settings.json
# ---------------------------------------------------------------------------
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

jq -n \
    --arg endpoint         "$OTEL_ENDPOINT" \
    --arg logs_endpoint    "$OTEL_LOGS_ENDPOINT" \
    --arg metrics_endpoint "$OTEL_METRICS_ENDPOINT" \
    --arg attrs            "$RESOURCE_ATTRS" \
    --arg noproxy          "$NO_PROXY_VALUE" \
    '{
        env: {
            CLAUDE_CODE_ENABLE_TELEMETRY: "1",
            OTEL_METRICS_EXPORTER: "otlp",
            OTEL_LOGS_EXPORTER: "otlp",
            OTEL_EXPORTER_OTLP_PROTOCOL: "http/protobuf",
            OTEL_EXPORTER_OTLP_ENDPOINT: $endpoint,
            OTEL_EXPORTER_OTLP_LOGS_ENDPOINT: $logs_endpoint,
            OTEL_EXPORTER_OTLP_METRICS_ENDPOINT: $metrics_endpoint,
            OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE: "cumulative",
            OTEL_RESOURCE_ATTRIBUTES: $attrs,
            NO_PROXY: $noproxy,
            no_proxy: $noproxy
        }
    }' > "$TMP"

# ---------------------------------------------------------------------------
# Install to /etc/claude-code/
# ---------------------------------------------------------------------------
sudo install -d -m 0755 "$MANAGED_DIR"
sudo install -m 0644 "$TMP" "$MANAGED_FILE"

ux_success "Installed: $MANAGED_FILE"
ux_bullet "user.id = $USER_ID"
ux_bullet "endpoint = $OTEL_ENDPOINT"
echo ""
ux_info "Claude Code 를 재시작하면 OTel exporter 가 활성화됩니다."
