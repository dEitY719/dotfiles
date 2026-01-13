#!/usr/bin/env bash

# =============================================================================
# run_agents_md_master_prompt.sh
# Claude Code에게 AGENTS.md 생성 요청 (비대화형)
# =============================================================================

set -euo pipefail

# Source UX library for consistent styling
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UX_LIB_PATH="${SCRIPT_DIR}/../ux_lib/ux_lib.sh"
if [[ -f "$UX_LIB_PATH" ]]; then
    source "$UX_LIB_PATH"
fi

# Resolve DOTFILES_ROOT from script location when not provided
DOTFILES_ROOT="${DOTFILES_ROOT:-${SCRIPT_DIR%/shell-common/tools/custom}}"
PROMPT_FILE="${DOTFILES_ROOT:-$HOME/dotfiles}/docs/AGENTS_md_Master_Prompt.md"

# 프롬프트 파일 존재 확인
if [[ ! -f "$PROMPT_FILE" ]]; then
    [[ -n "${UX_ERROR+x}" ]] && ux_error "Master prompt file not found: $PROMPT_FILE" || echo "Error: Master prompt file not found: $PROMPT_FILE" >&2
    exit 1
fi

# Claude Code CLI 존재 확인
if ! command -v claude &> /dev/null; then
    [[ -n "${UX_ERROR+x}" ]] && ux_error "'claude' command not found. Please install Claude Code CLI." || echo "Error: 'claude' command not found. Please install Claude Code CLI." >&2
    exit 1
fi

# 현재 디렉토리 확인
CURRENT_DIR="$(pwd)"
[[ -n "${UX_INFO+x}" ]] && ux_header "Generating AGENTS.md" || echo "Generating AGENTS.md for project: $CURRENT_DIR"
[[ -n "${UX_INFO+x}" ]] && ux_info "Project directory: $CURRENT_DIR" || echo ""

# Claude Code에 요청 전송 (비대화형)
PROMPT="Read $PROMPT_FILE and execute all the commands in it to create the AGENTS.md file system for this project at $CURRENT_DIR. Follow all the protocols and phases described in that document."

# Claude Code CLI 실행 - 단일 메시지 모드
# Claude Code CLI는 인자로 프롬프트를 받으면 비대화형으로 실행됨
if claude "$PROMPT" 2>/dev/null; then
    echo ""
    [[ -n "${UX_SUCCESS+x}" ]] && ux_success "AGENTS.md generation completed successfully" || echo "✓ AGENTS.md generation completed successfully"
    exit 0
fi

# 대안: stdin 방식
if echo "$PROMPT" | claude 2>/dev/null; then
    echo ""
    [[ -n "${UX_SUCCESS+x}" ]] && ux_success "AGENTS.md generation completed successfully" || echo "✓ AGENTS.md generation completed successfully"
    exit 0
fi

# 실패 시 안내 메시지
[[ -n "${UX_ERROR+x}" ]] && ux_error "Failed to execute claude command in non-interactive mode" || echo "Error: Failed to execute claude command in non-interactive mode." >&2
echo ""
[[ -n "${UX_INFO+x}" ]] && ux_info "Please run claude manually:" || echo "Please run claude manually:"
echo "  cd $CURRENT_DIR"
echo "  claude"
echo ""
[[ -n "${UX_INFO+x}" ]] && ux_info "Then paste the following command:" || echo "Then paste the following command:"
echo "  Read $PROMPT_FILE and execute the commands."
echo ""
exit 1
