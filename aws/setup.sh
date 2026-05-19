#!/bin/bash
# aws/setup.sh — Internal-PC AWS Bedrock + Claude bootstrap (issue #677, #687).
#
# Idempotent: re-runs preserve user edits to aws.local.sh / ~/.aws/config
# / ~/.claude/settings.json (real file, NOT symlink in internal mode).
#
# #687 fix: Claude Code 의 settings.json ↔ settings.local.json 사이에서
# .env 객체 deep-merge 가 사용자 환경에서 실제로 적용되지 않는 사례가 확인
# 됐다 (ANTHROPIC_DEFAULT_SONNET_MODEL 미반영 → 400 invalid model). 그래서
# 사내 모드 한정으로 ~/.claude/settings.json 자체를 dotfiles SSOT
# (claude/settings.json) + Bedrock 오버레이 (claude/settings.bedrock-overlay.example)
# 를 jq deep-merge 한 실파일로 시드한다. 외부 PC 는 영향 없음 — symlink
# 그대로 유지 (claude/setup.sh 외부 분기).
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

ux_section "AWS Bedrock bootstrap (internal mode)"

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

# _merge_claude_settings_json <base> <overlay> <target>
# Internal-mode 한정: ~/.claude/settings.json 을 dotfiles SSOT (base) +
# Bedrock 오버레이 (overlay) 의 jq deep-merge 결과 실파일로 시드한다.
# 외부 PC 의 symlink 디자인은 claude/setup.sh 외부 분기에서 유지된다.
#
# 머지 우선순위 (낮음 → 높음): base < overlay < existing_real
#   - base: dotfiles 가 commit 한 모든 PC 공용 키 (hooks/statusLine/...)
#   - overlay: 사내 모드 한정 Bedrock 모델 매핑 (model/availableModels/...)
#   - existing_real: 사용자가 ~/.claude/settings.json 을 직접 편집한 경우
#     해당 변경을 보존 (overlay 보다 우선). 단 legacy gateway env 키는
#     머지 전 strip 된다 (Bedrock 와 양립 불가, #677 O-1).
#
# Symlink 처리 (#687): target 이 dotfiles base 를 가리키는 symlink 면 풀고
# 실파일로 전환한다. 이는 claude/setup.sh 의 external 분기 호환을 위해
# 일단 symlink 가 생성된 뒤 사내 분기에서 다시 풀어내는 흐름이 아니라,
# claude/setup.sh 의 internal 분기 자체가 settings.json 처리를 위임한
# 결과다 — claude/setup.sh:internal 은 settings.json symlink 를 만들지 않는다.
# 그래도 과거 설치(symlink) 에서 #687 로 마이그레이션하는 사용자를 위한
# fallback 으로 symlink 자동 변환을 남겨둔다.
_merge_claude_settings_json() {
    _base="$1"
    _overlay="$2"
    _tgt="$3"

    if [ ! -f "$_base" ]; then
        ux_error "Base settings missing: $_base"
        return 1
    fi
    if [ ! -f "$_overlay" ]; then
        ux_error "Overlay template missing: $_overlay"
        return 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        ux_warning "jq 미설치 — settings.json 자동 머지 건너뜀."
        ux_bullet "다음 두 파일을 수동으로 머지해 ~/.claude/settings.json 에 작성하세요:"
        ux_bullet "  base   : $_base"
        ux_bullet "  overlay: $_overlay"
        return 0
    fi

    _tgt_dir="$(dirname "$_tgt")"
    [ -d "$_tgt_dir" ] || mkdir -p "$_tgt_dir"

    # symlink → 실파일 전환 (#687 마이그레이션 fallback). symlink 가 가리키는
    # 내용은 보존되어야 하므로 cp -L 로 실파일 복사 후 symlink 자체를 제거한다.
    if [ -L "$_tgt" ]; then
        _link_dst=$(readlink "$_tgt")
        ux_warning "기존 ~/.claude/settings.json 이 symlink (→ $_link_dst). 실파일로 전환합니다 (#687)."
        _tmp_resolved=$(mktemp)
        cp -L "$_tgt" "$_tmp_resolved"
        rm -f "$_tgt"
        mv "$_tmp_resolved" "$_tgt"
        chmod 0600 "$_tgt"
    fi

    if [ ! -f "$_tgt" ]; then
        # First-time create — base * overlay (existing 없음). _comment 제거.
        _tmp_new=$(mktemp)
        if jq -s '(.[0]) * (.[1] | del(._comment?))' "$_base" "$_overlay" > "$_tmp_new"; then
            mv "$_tmp_new" "$_tgt"
            chmod 0600 "$_tgt"
            ux_success "Created: $_tgt (base + overlay)"
        else
            ux_error "jq merge failed — check JSON in $_base / $_overlay"
            rm -f "$_tmp_new"
            return 1
        fi
        return 0
    fi

    # Legacy 사내 게이트웨이 env 키 검출 (Bedrock 와 양립 불가, #677 O-1).
    # 키 이름 기반이라 host rebrand (a2g → cloud.dtgpt) 에 강건.
    _gateway_keys=$(jq -r '
        .env // {}
        | keys_unsorted[]
        | select(test("^(ANTHROPIC_BASE_URL|ANTHROPIC_AUTH_TOKEN|ANTHROPIC_MODEL|ANTHROPIC_CUSTOM_HEADERS|NODE_TLS_REJECT_UNAUTHORIZED)$"))
    ' "$_tgt" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')

    if [ -n "$_gateway_keys" ]; then
        ux_warning "Legacy gateway env keys detected — Bedrock 와 양립 불가 (#677 O-1):"
        ux_bullet "  $_gateway_keys"
        ux_bullet "머지 중 위 키들을 제거합니다. 원본은 백업 파일에 보존됩니다."
    fi

    # Deep merge: base * overlay * (existing - legacy gateway keys).
    # 사용자 편집이 가장 우선 — 사내 PC 에서 ~/.claude/settings.json 을 직접
    # 손대지 않는 게 정상이지만, 손댄 경우 보존된다. _comment 는 머지에서 항상 제거.
    _tmp_merged=$(mktemp)
    if jq -s '
        def _strip_gateway:
            if .env then
                .env |= del(
                    .ANTHROPIC_BASE_URL,
                    .ANTHROPIC_AUTH_TOKEN,
                    .ANTHROPIC_MODEL,
                    .ANTHROPIC_CUSTOM_HEADERS,
                    .NODE_TLS_REJECT_UNAUTHORIZED
                )
            else .
            end;
        (.[0])                          as $base
        | (.[1] | del(._comment?))      as $overlay
        | (.[2] | _strip_gateway)       as $existing
        | $base * $overlay * $existing
    ' "$_base" "$_overlay" "$_tgt" > "$_tmp_merged"; then
        if cmp -s "$_tgt" "$_tmp_merged"; then
            rm -f "$_tmp_merged"
            ux_success "Preserved (already up to date): $_tgt"
        else
            _backup="${_tgt}.bedrock-merge-backup.$(date +%Y%m%d%H%M%S)"
            mv "$_tgt" "$_backup"
            mv "$_tmp_merged" "$_tgt"
            chmod 0600 "$_tgt"
            ux_success "Merged Bedrock keys into: $_tgt"
            ux_bullet "Backup: $_backup"
        fi
    else
        ux_error "jq merge failed — check JSON in $_base / $_overlay / $_tgt"
        rm -f "$_tmp_merged"
        return 1
    fi
}

# 자동 archive (#687, 보강): 옛 머지 결과인 ~/.claude/settings.local.json 은
# 이제 사용되지 않는다. Claude Code 의 settings.local.json deep-merge 가
# 사용자 환경에서 신뢰 불가하므로 모든 키는 settings.json 으로 통합됐다.
# 사용자가 잊어도 회귀하지 않도록 mv 로 timestamp suffix 백업까지 자동 수행
# (#688 codex / #686 Opus-personal 권고). 백업 파일은 보존되므로 복구 가능.
_archive_legacy_settings_local() {
    _legacy="$HOME/.claude/settings.local.json"
    [ -f "$_legacy" ] || return 0
    _legacy_bak="${_legacy}.deprecated-687.$(date +%Y%m%d%H%M%S)"
    if mv "$_legacy" "$_legacy_bak"; then
        ux_success "Archived legacy settings.local.json (#687):"
        ux_bullet "  $_legacy"
        ux_bullet "  → $_legacy_bak"
        ux_bullet "Claude Code 의 deep-merge 가 사용자 환경에서 신뢰 불가하므로 본 파일은 더 이상 사용되지 않습니다."
    else
        ux_warning "settings.local.json archive 실패: $_legacy"
        ux_bullet "수동 처리: mv \"$_legacy\" \"$_legacy_bak\""
    fi
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
# F-7: ~/.claude/settings.json — base + Bedrock overlay deep-merge (#687)
# ---------------------------------------------------------------------------
_merge_claude_settings_json \
    "${DOTFILES_DIR}/claude/settings.json" \
    "${DOTFILES_DIR}/claude/settings.bedrock-overlay.example" \
    "$HOME/.claude/settings.json"

_archive_legacy_settings_local

# ---------------------------------------------------------------------------
# F-8: OTel installer guidance (do NOT auto-run — needs sudo + sso login)
# ---------------------------------------------------------------------------
echo ""
ux_section "Next steps (run manually)"
ux_bullet "1. aws sso login"
ux_bullet "2. ./aws/install-otel-managed-settings.sh   (sudo password once)"
ux_bullet "3. claude   (재시작 후 availableModels 확인)"
echo ""
ux_info "Walkthrough: aws/README.md"
