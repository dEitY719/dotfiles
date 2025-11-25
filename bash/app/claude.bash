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
    cat <<-'EOF'

[Claude Code Quick Commands]

  /help      : Claude Code 도움말
  /feedback  : 기능 요청 및 버그 리포트
  /doctor    : 시스템 상태 진단

[MCP (Model Context Protocol) 설정]

  MCP 서버 관리 명령어:

  claude mcp list              : 설치된 MCP 서버 목록
  claude mcp get <name>        : MCP 서버 상세 정보
  claude mcp add <name> ...    : MCP 서버 추가
  claude mcp remove <name>     : MCP 서버 제거

[Recommended MCP Servers]

  1. Playwright MCP (웹 브라우저 자동화)
     claude mcp add playwright --transport stdio -- npx -y @playwright/mcp@latest

     사용 예:
     - "playwright mcp를 사용해서 example.com에 접속해줘"
     - "playwright로 검색창에 'claude' 입력하고 스크린샷 찍어줘"

  2. Sequential Thinking MCP (논리적 분석)
     claude mcp add sequential-thinking --transport stdio -- npx -y @modelcontextprotocol/server-sequential-thinking

     사용 예:
     - "이 문제를 sequential-thinking으로 단계별 분석해줘"
     - "이 알고리즘의 시간복잡도를 체계적으로 분석해줘"

[설치 후 확인]

  # 설치한 MCP 서버 확인
  claude mcp list

  # 특정 MCP 서버 상태 확인
  claude mcp get playwright
  claude mcp get sequential-thinking

[Setup & Requirements]

  ensure_jq        : jq 설치 여부 확인 및 자동 설치
                     (Claude Code statusline 스크립트에 필요)

  사용 예:
  - ensure_jq      : jq 설치 확인 및 필요시 자동 설치

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
