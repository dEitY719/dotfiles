#!/bin/bash

# =============================================================================
# run_agents_md_master_prompt.sh
# Claude Code에게 AGENTS.md 생성 요청 (비대화형)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve DOTFILES_ROOT from script location when not provided
DOTFILES_ROOT="${DOTFILES_ROOT:-${SCRIPT_DIR%/shell-common/tools/custom}}"
PROMPT_FILE="${DOTFILES_ROOT:-$HOME/dotfiles}/docs/AGENTS_md_Master_Prompt.md"

# Initialize common tools environment (ux_lib); after PROMPT_FILE so a caller's
# DOTFILES_ROOT still picks the prompt file.
# shellcheck source=init.sh
. "${SCRIPT_DIR}/init.sh" || exit 1

main() {
# 프롬프트 파일 존재 확인
if [[ ! -f "$PROMPT_FILE" ]]; then
    ux_error "Master prompt file not found: $PROMPT_FILE"
    return 1
fi

# Claude Code CLI 존재 확인
if ! command -v claude &> /dev/null; then
    ux_error "'claude' command not found. Please install Claude Code CLI."
    return 1
fi

# 현재 디렉토리 확인
CURRENT_DIR="$(pwd)"
ux_header "Generating AGENTS.md"
ux_info "Project directory: $CURRENT_DIR"

# Claude Code에 요청 전송 (비대화형)
PROMPT="Read $PROMPT_FILE and execute all the commands in it to create the AGENTS.md file system for this project at $CURRENT_DIR. Follow all the protocols and phases described in that document."

# Claude Code CLI 실행 - 단일 메시지 모드
# Claude Code CLI는 인자로 프롬프트를 받으면 비대화형으로 실행됨
if claude "$PROMPT" 2>/dev/null; then
    ux_info ""
    ux_success "AGENTS.md generation completed successfully"
    return 0
fi

# 대안: stdin 방식
if printf '%s\n' "$PROMPT" | claude 2>/dev/null; then
    ux_info ""
    ux_success "AGENTS.md generation completed successfully"
    return 0
fi

# 실패 시 안내 메시지
ux_error "Failed to execute claude command in non-interactive mode"
ux_info ""
ux_info "Please run claude manually:"
ux_bullet "cd $CURRENT_DIR"
ux_bullet "claude"
ux_info ""
ux_info "Then paste the following command:"
ux_bullet "Read $PROMPT_FILE and execute the commands."
ux_info ""
return 1
}

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "${BASH_SOURCE[0]}" ]; then
    main "$@"
fi
