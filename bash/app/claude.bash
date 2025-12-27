#!/bin/bash
# /home/deity719/dotfiles/bash/app/claude.bash

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
    # Color definitions
    local bold blue green reset
    bold=$(tput bold 2>/dev/null || echo "")
    blue=$(tput setaf 4 2>/dev/null || echo "")
    green=$(tput setaf 2 2>/dev/null || echo "")
    reset=$(tput sgr0 2>/dev/null || echo "")

    cat <<EOF

${bold}${blue}[MCP (Model Context Protocol) 설정]${reset}

  MCP 서버 관리 명령어:

  ${green}claude mcp list${reset}              : 설치된 MCP 서버 목록
  ${green}claude mcp get <name>${reset}        : MCP 서버 상세 정보
  ${green}claude mcp add <name> ...${reset}    : MCP 서버 추가
  ${green}claude mcp remove <name>${reset}     : MCP 서버 제거

${bold}${blue}[Recommended MCP Servers]${reset}

  1. ${bold}Playwright MCP${reset} (웹 브라우저 자동화)
     ${green}claude mcp add playwright --transport stdio -- npx -y @playwright/mcp@latest${reset}

     사용 예:
     - "playwright mcp를 사용해서 example.com에 접속해줘"
     - "playwright로 검색창에 'claude' 입력하고 스크린샷 찍어줘"

  2. ${bold}Sequential Thinking MCP${reset} (논리적 분석)
     ${green}claude mcp add sequential-thinking --transport stdio -- npx -y @modelcontextprotocol/server-sequential-thinking${reset}

     사용 예:
     - "이 문제를 sequential-thinking으로 단계별 분석해줘"
     - "이 알고리즘의 시간복잡도를 체계적으로 분석해줘"

${bold}${blue}[설치 후 확인]${reset}

  # 설치한 MCP 서버 확인
  ${green}claude mcp list${reset}

  # 특정 MCP 서버 상태 확인
  ${green}claude mcp get playwright${reset}
  ${green}claude mcp get sequential-thinking${reset}

${bold}${blue}[Setup & Requirements]${reset}

  ${green}clinstall${reset}        : Claude Code CLI 설치
  ${green}ensure_jq${reset}        : jq 설치 여부 확인 및 자동 설치
                     (Claude Code statusline 스크립트에 필요)

${bold}${blue}[Settings Management]${reset}

  ${green}claude_init${reset}      : Claude Code 설정 파일 symbolic link 초기화
                     (dotfiles/bash/claude/settings.json ↔ ~/.claude/settings.json)
  ${green}claude_edit_settings${reset} : settings.json 파일 편집 (vim)
EOF
}

# (2) jq 설치 확인 및 설치
ensure_jq() {
    if command -v jq &>/dev/null; then
        # jq already installed - silent pass
        return 0
    else
        echo "⚠️  jq is not installed. Installing..."
        if command -v apt-get &>/dev/null; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v brew &>/dev/null; then
            brew install jq
        elif command -v yum &>/dev/null; then
            sudo yum install -y jq
        else
            echo "❌ Cannot determine package manager. Please install jq manually."
            echo "   For Ubuntu/Debian: sudo apt-get install jq"
            echo "   For macOS: brew install jq"
            echo "   For CentOS/RHEL: sudo yum install jq"
            return 1
        fi

        if command -v jq &>/dev/null; then
            echo "✅ jq installed successfully"
            jq --version
            return 0
        else
            echo "❌ Failed to install jq"
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

    echo "🔧 Initializing Claude Code settings..."

    # Create ~/.claude directory if not exists
    if [[ ! -d "$HOME/.claude" ]]; then
        echo "📁 Creating ~/.claude directory..."
        mkdir -p "$HOME/.claude"
    fi

    # Handle settings.json
    if [[ -L "$settings_target" ]]; then
        echo "✅ settings.json symbolic link already exists"
    elif [[ -f "$settings_target" ]]; then
        echo "⚠️  settings.json exists as regular file"
        echo "   Backing up to settings.json.backup..."
        mv "$settings_target" "$settings_target.backup"
        ln -s "$settings_source" "$settings_target"
        echo "✅ Created symbolic link for settings.json"
    else
        ln -s "$settings_source" "$settings_target"
        echo "✅ Created symbolic link for settings.json"
    fi

    # Handle statusline-command.sh
    if [[ -L "$statusline_target" ]]; then
        echo "✅ statusline-command.sh symbolic link already exists"
    elif [[ -f "$statusline_target" ]]; then
        echo "⚠️  statusline-command.sh exists as regular file"
        echo "   Backing up to statusline-command.sh.backup..."
        mv "$statusline_target" "$statusline_target.backup"
        ln -s "$statusline_source" "$statusline_target"
        echo "✅ Created symbolic link for statusline-command.sh"
    else
        ln -s "$statusline_source" "$statusline_target"
        echo "✅ Created symbolic link for statusline-command.sh"
    fi

    echo ""
    echo "✨ Claude Code settings initialization complete!"
    echo ""
    echo "📍 Symbolic links:"
    ls -la "$settings_target" "$statusline_target" 2>/dev/null | grep -v "^total"
}

# (4) Claude Code settings.json 편집
claude_edit_settings() {
    local settings_file="$HOME/dotfiles/bash/claude/settings.json"

    if [[ ! -f "$settings_file" ]]; then
        echo "❌ Settings file not found: $settings_file"
        return 1
    fi

    echo "📝 Editing Claude Code settings..."
    echo "   File: $settings_file"
    echo ""

    ${EDITOR:-vim} "$settings_file"

    echo ""
    echo "✅ Settings file edited"
    echo "   Changes will take effect immediately (settings.json is symlinked)"
}
