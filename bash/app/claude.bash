#!/bin/bash
# /home/deity719/dotfiles/bash/app/claude.bash

# Initialize DOTFILES_BASH_DIR if not already set (for standalone execution)
if [[ -z "$DOTFILES_BASH_DIR" ]]; then
    _SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
    source "$(dirname "$_SCRIPT_PATH")/../util/init.bash"
    DOTFILES_BASH_DIR="$(init_dotfiles_bash_dir "$_SCRIPT_PATH")"
    export DOTFILES_BASH_DIR
fi

#### ✅ 1. 이미 쓰고 계신 `~/.npm-global` 경로 활용
# 아까 `gemini-cli` 설치에서 전역 경로가 `~/.npm-global/bin` 으로 잡혀 있었죠.
# npm install -g @anthropic-ai/claude-code --prefix=$HOME/.npm-global
# 이후 PATH에 `~/.npm-global/bin` 이 잡혀 있어야 합니다.

#### ✅ 2. 혹은 `nvm` 사용 (더 깔끔한 방법)
# * `nvm` 은 Node.js 버전을 사용자 홈 디렉토리에 설치해 주고, npm 전역 패키지도 같은 홈 경로에 저장합니다.
# * root 권한이 필요 없고, 여러 Node.js 버전을 쉽게 관리할 수 있어요.

# ```bash
# # nvm 설치
# curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
# source ~/.bashrc   # 또는 ~/.zshrc

# # Node 설치 (예: 20버전)
# nvm install 20
# nvm use 20

# # 이제 다시 설치
# npm install -g @anthropic-ai/claude-code
# ```

# (1) Claude Code 도움말
claudehelp() {
    # Load UX library
    source "${DOTFILES_BASH_DIR}/ux_lib/ux_lib.bash"

    ux_header "Claude Code - MCP & Workflow Guide"

    ux_section "MCP (Model Context Protocol) Commands"
    ux_table_row "claude mcp list" "List installed MCP servers" ""
    ux_table_row "claude mcp get <name>" "Show MCP server details" ""
    ux_table_row "claude mcp add <name> ..." "Add MCP server" ""
    ux_table_row "claude mcp remove <name>" "Remove MCP server" ""
    echo ""

    ux_section "Recommended MCP Servers"
    ux_bullet "Playwright MCP: Web browser automation"
    echo "  Install: ${UX_SUCCESS}claude mcp add playwright --transport stdio -- npx -y @playwright/mcp@latest${UX_RESET}"
    ux_bullet "Sequential Thinking MCP: Logical analysis"
    echo "  Install: ${UX_SUCCESS}claude mcp add sequential-thinking --transport stdio -- npx -y @modelcontextprotocol/server-sequential-thinking${UX_RESET}"
    echo ""

    ux_section "Setup & Requirements"
    ux_table_row "clinstall" "Install Claude Code CLI" ""
    ux_table_row "ensure_jq" "Install jq (required for statusline)" ""
    ux_table_row "claude_init" "Initialize config & skills" ""
    ux_table_row "claude_edit_settings" "Edit settings.json" ""
    echo ""

    ux_section "Workflow Patterns"
    ux_bullet "Plan mode (recommended): ${UX_SUCCESS}claude${UX_RESET} → plan → approve → execute"
    ux_bullet "Test workflow: ${UX_SUCCESS}cltest \"test description\"${UX_RESET}}"
    ux_bullet "Skip permissions (caution): ${UX_SUCCESS}clskip \"request\"${UX_RESET}"
    echo ""

    ux_section "Sandbox Mode"
    ux_info "Use in Claude conversation: ${UX_SUCCESS}/sandbox${UX_RESET}"
    ux_bullet "Select Auto-allow mode"
    ux_bullet "pytest, git, npm auto-approved"
    echo ""

    ux_section "Configuration"
    ux_info "Settings file: ~/dotfiles/bash/claude/settings.json"
    ux_bullet "Sandbox: autoAllowBashIfSandboxed"
    ux_bullet "Auto-allow: pytest, ruff, mypy, tox"
    ux_bullet "Block: .env, ~/.aws, ~/.ssh"
    ux_bullet "Block commands: rm -rf, sudo rm"
    echo ""
}

# (2) jq 설치 확인 및 설치
ensure_jq() {
    if command -v jq &>/dev/null; then
        # jq already installed - silent pass
        return 0
    else
        ux_warning "jq is not installed. Installing..."
        if command -v apt-get &>/dev/null; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v brew &>/dev/null; then
            brew install jq
        elif command -v yum &>/dev/null; then
            sudo yum install -y jq
        else
            ux_error "Cannot determine package manager. Please install jq manually."
            ux_bullet "Ubuntu/Debian: ${UX_BOLD}sudo apt-get install jq${UX_RESET}"
            ux_bullet "macOS: ${UX_BOLD}brew install jq${UX_RESET}"
            ux_bullet "CentOS/RHEL: ${UX_BOLD}sudo yum install jq${UX_RESET}"
            return 1
        fi

        if command -v jq &>/dev/null; then
            ux_success "jq installed successfully"
            jq --version
            return 0
        else
            ux_error "Failed to install jq"
            return 1
        fi
    fi
}

# Auto-call ensure_jq when this file is sourced
ensure_jq

# Claude Code CLI 설치 스크립트
clinstall() {
    bash "$HOME/dotfiles/mytool/install-claude.sh"
}

# (3) Claude Code 설정 파일 symbolic link 초기화
claude_init() {
    local settings_source="$HOME/dotfiles/bash/claude/settings.json"
    local settings_target="$HOME/.claude/settings.json"
    local statusline_source="$HOME/dotfiles/bash/claude/statusline-command.sh"
    local statusline_target="$HOME/.claude/statusline-command.sh"
    local skills_source_dir="$HOME/dotfiles/bash/claude/skills"
    local skills_target_dir="$HOME/.claude/skills"

    ux_info "Initializing Claude Code configuration..."
    echo ""

    # Create ~/.claude directory if not exists
    if [[ ! -d "$HOME/.claude" ]]; then
        ux_info "Creating ~/.claude directory..."
        mkdir -p "$HOME/.claude"
    fi

    # Create ~/.claude/skills directory if not exists
    if [[ ! -d "$skills_target_dir" ]]; then
        ux_info "Creating ~/.claude/skills directory..."
        mkdir -p "$skills_target_dir"
    fi

    # Handle settings.json
    ux_section "Settings Configuration"
    if [[ -L "$settings_target" ]]; then
        ux_success "settings.json symbolic link already exists"
    elif [[ -f "$settings_target" ]]; then
        ux_warning "settings.json exists as regular file"
        ux_info "Backing up to settings.json.backup..."
        mv "$settings_target" "$settings_target.backup"
        ln -s "$settings_source" "$settings_target"
        ux_success "Created symbolic link for settings.json"
    else
        ln -s "$settings_source" "$settings_target"
        ux_success "Created symbolic link for settings.json"
    fi
    echo ""

    # Handle statusline-command.sh
    ux_section "Statusline Configuration"
    if [[ -L "$statusline_target" ]]; then
        ux_success "statusline-command.sh symbolic link already exists"
    elif [[ -f "$statusline_target" ]]; then
        ux_warning "statusline-command.sh exists as regular file"
        ux_info "Backing up to statusline-command.sh.backup..."
        mv "$statusline_target" "$statusline_target.backup"
        ln -s "$statusline_source" "$statusline_target"
        ux_success "Created symbolic link for statusline-command.sh"
    else
        ln -s "$statusline_source" "$statusline_target"
        ux_success "Created symbolic link for statusline-command.sh"
    fi
    echo ""

    # Handle skills directory
    ux_section "Claude Code Skills"
    local skill_count=0
    if [[ -d "$skills_source_dir" ]]; then
        for skill_file in "$skills_source_dir"/*.md; do
            if [[ -f "$skill_file" ]]; then
                local skill_name
                skill_name="$(basename "$skill_file")"
                local skill_target="$skills_target_dir/$skill_name"

                if [[ -L "$skill_target" ]]; then
                    ux_success "$skill_name (already linked)"
                elif [[ -f "$skill_target" ]]; then
                    ux_warning "$skill_name exists as regular file"
                    ux_info "Backing up to $skill_name.backup..."
                    mv "$skill_target" "$skill_target.backup"
                    ln -s "$skill_file" "$skill_target"
                    ux_success "$skill_name (linked)"
                else
                    ln -s "$skill_file" "$skill_target"
                    ux_success "$skill_name (linked)"
                fi
                ((skill_count++))
            fi
        done

        if [[ $skill_count -eq 0 ]]; then
            ux_info "No skill files found in $skills_source_dir"
        else
            ux_success "Total: $skill_count skill(s) linked"
        fi
    else
        ux_warning "Skills source directory not found: $skills_source_dir"
    fi
    echo ""

    ux_header "Claude Code Initialization Complete"
    echo ""

    ux_section "Configuration Files"
    local config_target
    for config_target in "$settings_target" "$statusline_target"; do
        if [[ -e "$config_target" ]]; then
            ls -la -- "$config_target"
        fi
    done
    echo ""

    ux_section "Skills"
    if [[ -d "$skills_target_dir" ]]; then
        local linked_skill_found=0
        local skill_target_file
        for skill_target_file in "$skills_target_dir"/*.md; do
            if [[ -e "$skill_target_file" ]]; then
                ls -la -- "$skill_target_file"
                linked_skill_found=1
            fi
        done
        if [[ $linked_skill_found -eq 0 ]]; then
            ux_info "(no skills found)"
        fi
    fi
}

# (4) Claude Code settings.json 편집
claude_edit_settings() {
    local settings_file="$HOME/dotfiles/bash/claude/settings.json"

    if [[ ! -f "$settings_file" ]]; then
        ux_error "Settings file not found: $settings_file"
        return 1
    fi

    ux_header "Claude Code Settings"
    ux_info "File: $settings_file"
    echo ""

    ${EDITOR:-vim} "$settings_file"

    echo ""
    ux_success "Settings file edited"
    ux_info "Changes will take effect immediately (settings.json is symlinked)"
}

# (5) Claude Code workflow aliases
# Plan 모드: Interactive 모드로 시작 (권장)
alias clplan='claude'

# 테스트 작성 및 실행
cltest() {
    if [[ -z "$1" ]]; then
        ux_header "cltest"
        ux_usage "cltest" "\"request\"" "Run Claude with prompt for test writing"
        ux_bullet "Example: ${UX_INFO}cltest \"사용자 인증 테스트 작성해줘\"${UX_RESET}"
        return 1
    fi
    claude -p "$1"
}

# Skip permissions 모드 (주의해서 사용)
clskip() {
    if [[ -z "$1" ]]; then
        ux_header "clskip"
        ux_usage "clskip" "\"request\"" "Run Claude skipping permission prompts (caution)"
        ux_bullet "Example: ${UX_INFO}clskip \"이 모듈을 리팩토링해줘\"${UX_RESET}"
        echo ""
        ux_warning "모든 권한 프롬프트를 무시합니다"
        ux_bullet "작은 범위부터 시작하고 신중하게 사용하세요"
        return 1
    fi

    ux_warning "Skip permissions 모드로 실행합니다"
    ux_info "요청: $1"
    echo ""
    claude --dangerously-skip-permissions -p "$1"
}
