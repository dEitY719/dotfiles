#!/bin/sh
# shell-common/tools/codex.sh
# Codex CLI - utilities and workflow helpers
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# Installation & Setup Guide
# ═══════════════════════════════════════════════════════════════

# 1) npm 전역 설치
#    npm config set prefix '~/.npm-global'
#    bash shell-common/tools/custom/install_codex.sh
#    또는 수동 설치:
#    npm install -g <codex-package-name>
#
# 2) API 키 또는 웹 로그인 인증
#    설정 파일 또는 환경 변수로 인증 필요
#    ~/.env 파일에 저장하거나, codex 명령어로 직접 인증

# ═══════════════════════════════════════════════════════════════
# Essential Command Aliases
# ═══════════════════════════════════════════════════════════════

alias cx='codex'                    # Basic command
alias cxhelp='codex --help'         # Show help
alias cxver='codex --version'       # Show version
alias codex-yolo='codex --dangerously-bypass-approvals-and-sandbox'
alias cxsync='cxskills_sync'        # Sync skills symlinks

# ═══════════════════════════════════════════════════════════════
# Codex Skills Sync
# ═══════════════════════════════════════════════════════════════

cxskills_sync() {
    local src="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/skills"
    local dst="$HOME/.codex/skills"
    local added=0
    local removed=0
    local name link

    ux_header "Codex Skills Sync"

    if [ ! -d "$dst" ]; then
        ux_warning "Target directory not found: $dst"
        return 1
    fi

    # Remove broken symlinks
    while read -r link; do
        if [ -L "$link" ] && [ ! -e "$link" ]; then
            name=$(basename "$link")
            rm "$link"
            ux_warning "Removed: $name"
            removed=$((removed + 1))
        fi
    done <<EOF
$(find "$dst" -maxdepth 1 -type l)
EOF

    # Add missing symlinks for each skill directory
    for dir in "$src"/*/; do
        name=$(basename "$dir")
        if [ ! -e "$dst/$name" ]; then
            ln -s "$dir" "$dst/$name"
            ux_success "Added: $name"
            added=$((added + 1))
        fi
    done

    echo ""
    ux_table_row "Added"   "$added"   ""
    ux_table_row "Removed" "$removed" ""
}

# ═══════════════════════════════════════════════════════════════
# Codex Installation
# ═══════════════════════════════════════════════════════════════

cxinstall() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_codex.sh"
}

# ═══════════════════════════════════════════════════════════════
# Codex Uninstallation
# ═══════════════════════════════════════════════════════════════

cxuninstall() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/uninstall_codex.sh"
}

# ═══════════════════════════════════════════════════════════════
# Codex Status Check
# ═══════════════════════════════════════════════════════════════

cxstatus() {
    ux_header "Codex Status"

    if command -v codex > /dev/null 2>&1; then
        ux_success "Codex installed"
        ux_table_row "Version" "$(codex --version 2>/dev/null || echo 'unknown')" ""
        ux_table_row "Location" "$(which codex)" ""
    else
        ux_warning "Codex not found"
        ux_info "To install: bash shell-common/tools/custom/install_codex.sh"
        return 1
    fi

    echo ""
    ux_section "npm Global Packages"
    if ! npm list -g --depth=0 | grep -i codex > /dev/null 2>&1; then
        echo "  (No codex packages found)"
    fi
}
