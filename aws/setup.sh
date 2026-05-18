#!/bin/bash
# aws/setup.sh — Internal-PC AWS Bedrock + Claude bootstrap (issue #677).
#
# Idempotent: re-runs preserve user edits to aws.local.sh / ~/.aws/config
# / ~/.claude/settings.local.json.
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

# _merge_claude_settings_local <template> <target>
# Idempotent jq merge: adds template keys missing from target, preserves
# existing user values. Detects the Samsung a2g gateway block and warns
# instead of merging (Bedrock + a2g are mutually exclusive — issue #677 O-1).
_merge_claude_settings_local() {
    _tpl="$1"
    _tgt="$2"

    if [ ! -f "$_tpl" ]; then
        ux_error "Template missing: $_tpl"
        return 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        ux_warning "jq 미설치 — settings.local.json 자동 머지 건너뜀."
        ux_bullet "수동으로 다음 파일 내용을 ~/.claude/settings.local.json 에 머지하세요:"
        ux_bullet "  $_tpl"
        return 0
    fi

    _tgt_dir="$(dirname "$_tgt")"
    [ -d "$_tgt_dir" ] || mkdir -p "$_tgt_dir"

    if [ ! -f "$_tgt" ]; then
        # First-time create — drop the _comment scaffolding field so the
        # live file stays clean.
        jq 'del(._comment)' "$_tpl" > "$_tgt"
        chmod 0600 "$_tgt"
        ux_success "Created: $_tgt"
        return 0
    fi

    # Detect Samsung a2g gateway block — mutually exclusive with Bedrock.
    _has_a2g=$(jq -r '.env.ANTHROPIC_BASE_URL // ""' "$_tgt" 2>/dev/null \
        | grep -c "a2g\.samsungds\.net" 2>/dev/null || true)
    if [ "${_has_a2g:-0}" != "0" ]; then
        ux_warning "Detected Samsung a2g gateway env in $_tgt"
        ux_warning "Bedrock 경로와 a2g 게이트웨이 경로는 양립 불가합니다 (#677 O-1)."
        ux_warning "자동 머지를 건너뜁니다. 한 경로만 남기고 수동 정리하세요."
        ux_bullet "Bedrock 으로 단일화하려면 settings.local.json 의 env.ANTHROPIC_*"
        ux_bullet "키들을 제거한 뒤 ./aws/setup.sh 를 재실행하세요."
        return 0
    fi

    # Merge: target wins on conflicts (preserve user edits). Template keys
    # only fill gaps. _comment is dropped during the merge.
    #
    # Atomicity: render to a temp file, compare with the live target via
    # cmp -s, and only when contents differ do we mv the live file aside
    # as a timestamped backup and mv the new file into place. This avoids
    # accumulating identical backups on every idempotent re-run, and the
    # final mv is atomic on POSIX (same-filesystem rename).
    _tmp_merged=$(mktemp)
    if jq -s '
        (.[0] | del(._comment?)) as $tpl
        | (.[1]) as $cur
        | $tpl * $cur
    ' "$_tpl" "$_tgt" > "$_tmp_merged"; then
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
        ux_error "jq merge failed — check syntax in $_tgt"
        rm -f "$_tmp_merged"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# F-1: shell env (aws.local.sh)
# ---------------------------------------------------------------------------
_seed_file \
    "${DOTFILES_DIR}/aws/aws.local.example" \
    "${DOTFILES_DIR}/aws/aws.local.sh" \
    0600

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
# F-7: ~/.claude/settings.local.json — model mapping merge
# ---------------------------------------------------------------------------
_merge_claude_settings_local \
    "${DOTFILES_DIR}/claude/settings.local.bedrock.example" \
    "$HOME/.claude/settings.local.json"

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
