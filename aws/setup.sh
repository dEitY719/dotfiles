#!/bin/bash
# aws/setup.sh — Internal-PC AWS SSO/CLI seeding.
#
# ┌───────────────────────────────────────────────────────────────────────────┐
# │ DEPRECATED (2026-08-18): settings.json 소유권 이관 — gateway-cli           │
# └───────────────────────────────────────────────────────────────────────────┘
#
# 2026-08-18 부터 사내 (System LSI사업부) PC 의 live ~/.claude/settings.json 은
# 조직 공식 도구인 `gateway-cli setup` (LLM Gateway 전환, gateway-migration
# Claude Code 플러그인의 shell-start hook 이 설치) 이 소유한다. gateway-cli 가
# apiKeyHelper / awsCredentialExport / awsAuthRefresh / cleanupPeriodDays /
# env.* 를 직접 써 넣으므로, dotfiles 가 같은 파일을 "SSOT + Bedrock 오버레이
# jq deep-merge 결과" 로 다시 덮어쓰면 두 소유자가 서로를 지우는 왕복이 된다.
#
# 그래서 이 스크립트의 settings.json 관련 동작은 전부 제거됐다:
#   - F-7  ~/.claude/settings.json base+overlay deep-merge  → 삭제 (#687 종료)
#   - 부수  ~/.claude/settings.local.json 자동 archive        → 삭제
#     (#924 이후 settings.local.json 은 개인 override 의 정식 슬롯이므로
#      치워버리는 동작 자체가 유해해졌다)
# `claude/settings.bedrock-overlay.example` 도 함께 deprecated — 히스토리/
# 롤백 참조용으로만 남긴다.
#
# 남는 책임 (gateway-cli 와 겹치지 않는, 순수 AWS CLI 영역):
#   - F-1  aws/aws.local.sh   시드 (없을 때만) + AWS_CA_BUNDLE sanity 경고
#   - F-6  ~/.aws/config      시드 (없을 때만)
# gateway-cli 는 AWS SSO 프로필/CA bundle 을 만들지 않으므로 이 두 개는 계속
# dotfiles 소유다. 이 스크립트는 그 외 어떤 Claude 설정 파일도 쓰지 않는다.
#
# SSOT 갱신 경로 대체 (중요): 예전에는 이 스크립트만이 dotfiles SSOT
# (claude/settings.json) 의 .hooks / .statusLine 변경을 사내 PC live 파일로
# 다시 실어 나르는 유일한 통로였다. 그 역할은 이제 SessionStart 훅
# `claude/hooks/session-start-settings-drift.sh` 가 맡는다 — 사내 모드에서
# .hooks / .statusLine drift 를 감지하면 그 두 키만 live 파일에 in-place
# 자동 복구하고, gateway-cli 소유 키는 건드리지 않는다.
#
# Idempotent: re-runs preserve user edits to aws.local.sh / ~/.aws/config.
#
# External/public PCs: this script is a no-op (mode gate at top).
#
# bash (not /bin/sh) so we can safely source shell-common/tools/ux_lib/ux_lib.sh
# — the library references $BASH_VERSION which trips `set -u` under dash.

set -e

# ---------------------------------------------------------------------------
# Locate dotfiles root + load ux_lib
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../shell-common/tools/ux_lib/ux_lib.sh
. "${DOTFILES_DIR}/shell-common/tools/ux_lib/ux_lib.sh"

# ---------------------------------------------------------------------------
# Setup-mode gate. _dotfiles_setup_mode is defined inside the heavy
# shell-common/tools/integrations/claude.sh file; inlining the minimal
# canonicalisation here keeps aws/setup.sh standalone and avoids pulling
# in unrelated Claude account-resolver code (issue #677 O-3 deferred).
# ---------------------------------------------------------------------------
_aws_setup_mode() {
    _f="$HOME/.dotfiles-setup-mode"
    [ -f "$_f" ] || { echo ""; return 0; }
    _raw=$(tr -d ' \t\n\r' < "$_f" 2>/dev/null)
    case "$_raw" in
        1|public)   echo "public" ;;
        2|internal) echo "internal" ;;
        3|external) echo "external" ;;
        *)          echo "$_raw" ;;
    esac
}

_mode=$(_aws_setup_mode)
if [ "$_mode" != "internal" ]; then
    ux_info "aws/setup.sh: setup-mode='${_mode:-unset}' — skip (internal-only)"
    exit 0
fi

ux_section "AWS SSO/CLI seeding (internal mode)"

# ---------------------------------------------------------------------------
# Deprecation guard (2026-08-18). Runs BEFORE any file work so a user who
# invokes this script expecting the old #687 settings.json merge learns
# immediately that the merge is gone and who owns the file now.
#
# This is a hard no-op for settings.json — not a warn-then-continue. The
# merge helper and the settings.local.json archiver were deleted outright,
# so there is no code path left in this file that opens ~/.claude/settings*.
# ---------------------------------------------------------------------------
ux_warning "DEPRECATED: aws/setup.sh 는 더 이상 ~/.claude/settings.json 을 쓰지 않습니다 (2026-08-18)."
ux_bullet "사내 PC live settings.json 소유자: gateway-cli (조직 LLM Gateway 전환 도구)"
ux_bullet "  재시드/점검: gateway-cli setup  /  gateway-cli verify"
ux_bullet "dotfiles SSOT (claude/settings.json) 의 .hooks / .statusLine 변경은"
ux_bullet "  SessionStart 훅 claude/hooks/session-start-settings-drift.sh 가"
ux_bullet "  사내 모드에서 자동 복구합니다 — 이 스크립트 재실행이 필요 없습니다."
ux_bullet "claude/settings.bedrock-overlay.example 도 함께 deprecated (참조용 보존)."
ux_info "이 스크립트가 지금도 하는 일: aws/aws.local.sh + ~/.aws/config 시드뿐."

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
# _seed_file <src> <dst> <mode> — copy src to dst only when dst is absent,
# then chmod. Preserves user edits on re-runs.
_seed_file() {
    _src="$1"
    _dst="$2"
    _mode="$3"

    if [ ! -f "$_src" ]; then
        ux_error "Template missing: $_src"
        return 1
    fi

    if [ -f "$_dst" ]; then
        ux_success "Preserved (already exists): $_dst"
        return 0
    fi

    _dst_dir="$(dirname "$_dst")"
    [ -d "$_dst_dir" ] || mkdir -p "$_dst_dir"
    cp "$_src" "$_dst"
    chmod "$_mode" "$_dst"
    ux_success "Created: $_dst (mode $_mode)"
}

# ---------------------------------------------------------------------------
# F-1: shell env (aws.local.sh)
# ---------------------------------------------------------------------------
_seed_file \
    "${DOTFILES_DIR}/aws/aws.local.example" \
    "${DOTFILES_DIR}/aws/aws.local.sh" \
    0600

# Sanity: AWS_CA_BUNDLE 가 가리키는 파일이 실제로 존재하는지. 기존 사용자가
# 옛 템플릿 경로(/usr/local/share/ca-certificates/samsungsemi-prx.com.crt)를
# 그대로 들고 있고 호스트엔 그 파일이 없는 경우, aws CLI TLS 자체가 실패한다.
# _seed_file 는 사용자 편집을 보존하므로 자동 교체 대신 경고만 띄운다.
_aws_local="${DOTFILES_DIR}/aws/aws.local.sh"
if [ -f "$_aws_local" ]; then
    # sub() over -F= to handle paths containing '=' or trailing comments;
    # the -n guard below stays so an empty parse never false-fires.
    _ca_path=$(awk '
        /^export AWS_CA_BUNDLE=/ {
            sub(/^export AWS_CA_BUNDLE=/, "")
            sub(/[[:space:]]*#.*/, "")
            print
            exit
        }
    ' "$_aws_local" | tr -d '"' | tr -d "'")
    if [ -n "$_ca_path" ] && [ ! -f "$_ca_path" ]; then
        ux_warning "AWS_CA_BUNDLE 가 가리키는 파일이 존재하지 않음: $_ca_path"
        ux_bullet "NODE_EXTRA_CA_CERTS (보통 /etc/ssl/certs/ca-certificates.crt)"
        ux_bullet "와 동일 경로로 교체 권장:"
        ux_bullet "  sed -i 's|^export AWS_CA_BUNDLE=.*|export AWS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt|' aws/aws.local.sh"
    fi
fi

# ---------------------------------------------------------------------------
# F-6: ~/.aws/config — prefer aws-config.local override when present
# ---------------------------------------------------------------------------
[ -d "$HOME/.aws" ] || { mkdir -p "$HOME/.aws"; chmod 0700 "$HOME/.aws"; }
if [ -f "${DOTFILES_DIR}/aws/aws-config.local" ]; then
    _seed_file \
        "${DOTFILES_DIR}/aws/aws-config.local" \
        "$HOME/.aws/config" \
        0600
else
    _seed_file \
        "${DOTFILES_DIR}/aws/aws-config.example" \
        "$HOME/.aws/config" \
        0600
fi

# ---------------------------------------------------------------------------
# F-7 (REMOVED 2026-08-18): ~/.claude/settings.json base + Bedrock overlay
# deep-merge. gateway-cli 가 그 파일의 소유자가 됐으므로 여기서 아무것도 하지
# 않는다. 위 deprecation guard 가 사용자에게 이미 안내했다. 함수 자체
# (_merge_claude_settings_json / _archive_legacy_settings_local) 도 dead code
# 로 남기지 않고 삭제했다 — 남겨두면 다음 사람이 다시 배선할 유혹이 된다.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# F-8: OTel installer guidance (do NOT auto-run — needs sudo + sso login)
# ---------------------------------------------------------------------------
echo ""
ux_section "Next steps (run manually)"
ux_bullet "1. aws sso login"
ux_bullet "2. gateway-cli setup && gateway-cli verify   (live settings.json 소유자)"
ux_bullet "3. ./aws/install-otel-managed-settings.sh   (sudo password once)"
ux_bullet "4. claude   (재시작 후 모델 목록 확인)"
echo ""
ux_info "Walkthrough: aws/README.md"
