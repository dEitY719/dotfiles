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
#   - F-1   aws/aws.local.sh   시드 (없을 때만) + AWS_CA_BUNDLE sanity 경고
#   - F-6   ~/.aws/config      시드 (없을 때만)
#   - F-7b  live settings.json 의 .hooks.SessionStart 에 drift-heal 훅
#           '자신의 등록' 한 항목만 재삽입 (#1364, 아래 참조)
# gateway-cli 는 AWS SSO 프로필/CA bundle 을 만들지 않으므로 앞의 두 개는 계속
# dotfiles 소유다. F-7b 를 제외하면 이 스크립트는 그 외 어떤 Claude 설정
# 파일/키도 쓰지 않는다.
#
# SSOT 갱신 경로 대체 (중요): 예전에는 이 스크립트만이 dotfiles SSOT
# (claude/settings.json) 의 .hooks / .statusLine 변경을 사내 PC live 파일로
# 다시 실어 나르는 유일한 통로였다. 그 역할은 이제 SessionStart 훅
# `claude/hooks/session-start-settings-drift.sh` 가 맡는다 — 사내 모드에서
# .hooks / .statusLine drift 를 감지하면 그 두 키만 live 파일에 in-place
# 자동 복구하고, gateway-cli 소유 키는 건드리지 않는다.
#
# 그 위임에는 부트스트랩 구멍이 하나 있다 (#1364): Claude Code 는 live 파일의
# .hooks.SessionStart 에 등록된 훅만 호출한다. 그러므로 외부 요인(gateway-cli
# 재설정, 손편집)이 live .hooks 를 통째로 날리면 훅 자신의 등록도 함께
# 사라지고, 훅은 영원히 호출되지 않아 스스로를 복구할 수 없다 — 단일 실패점.
# F-7b 가 정확히 그 한 항목만 되살린다. 이것은 위 삭제의 되돌림이 아니라
# 좁게 도려낸 예외다 (#687 식 deep-merge 재도입 아님).
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

# Backup primitives SSOT (#806): fixed-suffix, latest-only backups. Used by
# F-7b below. Defines functions only — no output at source time.
# shellcheck source=../shell-common/functions/dotfiles_backup.sh
. "${DOTFILES_DIR}/shell-common/functions/dotfiles_backup.sh"

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
# The old merge helper and the settings.local.json archiver were deleted
# outright. The single remaining settings.json write is F-7b (#1364) — the
# drift-heal hook's OWN .hooks.SessionStart registration, which nothing else
# can restore once it is gone. Everything else about settings.json is a no-op.
# ---------------------------------------------------------------------------
ux_warning "DEPRECATED: aws/setup.sh 는 더 이상 ~/.claude/settings.json 을 머지하지 않습니다 (2026-08-18)."
ux_bullet "사내 PC live settings.json 소유자: gateway-cli (조직 LLM Gateway 전환 도구)"
ux_bullet "  재시드/점검: gateway-cli setup  /  gateway-cli verify"
ux_bullet "dotfiles SSOT (claude/settings.json) 의 .hooks / .statusLine 변경은"
ux_bullet "  SessionStart 훅 claude/hooks/session-start-settings-drift.sh 가"
ux_bullet "  사내 모드에서 자동 복구합니다 — 평소엔 이 스크립트 재실행이 불필요합니다."
ux_bullet "예외 하나 (#1364): 그 훅 '자신의 등록' 만은 이 스크립트가 책임집니다."
ux_bullet "  live .hooks.SessionStart 에서 훅 항목이 사라지면 훅은 호출조차 되지"
ux_bullet "  않아 스스로 복구 못 합니다 — 그때 그 한 항목만 여기서 되살립니다."
ux_bullet "claude/settings.bedrock-overlay.example 도 함께 deprecated (참조용 보존)."
ux_info "이 스크립트가 지금도 하는 일: aws/aws.local.sh + ~/.aws/config 시드,"
ux_info "  그리고 위 SessionStart 훅 등록 1건 점검/복구 (#1364)."

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
#
# F-7b (#1364, 아래 함수) 는 그 삭제의 되돌림이 아니라 좁게 도려낸 예외다 —
# 스코프 경계(F-7 과 무엇이 다른지)는 파일 상단 주석과 함수 docstring 참조.
# ---------------------------------------------------------------------------

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
#   - 어떤 경로로도 0 을 반환한다 — `set -e` 아래에서 AWS 시드 결과나 이후
#     안내 출력을 이 부가 점검이 날려버리면 안 된다.
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
    # live 파일이 없으면 만들지 않는다 / symlink 면 손대지 않는다.
    [ -f "$_rr_live" ] || return 0
    [ ! -L "$_rr_live" ] || return 0
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
