#!/bin/bash
# /home/deity719/dotfiles/bash/app/claude.bash

# Initialize DOTFILES_BASH_DIR if not already set (for standalone execution)
if [[ -z "$DOTFILES_BASH_DIR" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/../util/init.bash"
    DOTFILES_BASH_DIR="$(init_dotfiles_bash_dir "${BASH_SOURCE[0]}")"
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

    cat <<EOF

${UX_BOLD}${UX_PRIMARY}[MCP (Model Context Protocol) 설정]${UX_RESET}

  MCP 서버 관리 명령어:

  ${UX_SUCCESS}claude mcp list${UX_RESET}              : 설치된 MCP 서버 목록
  ${UX_SUCCESS}claude mcp get <name>${UX_RESET}        : MCP 서버 상세 정보
  ${UX_SUCCESS}claude mcp add <name> ...${UX_RESET}    : MCP 서버 추가
  ${UX_SUCCESS}claude mcp remove <name>${UX_RESET}     : MCP 서버 제거

${UX_BOLD}${UX_PRIMARY}[Recommended MCP Servers]${UX_RESET}

  1. ${UX_BOLD}Playwright MCP${UX_RESET} (웹 브라우저 자동화)
     ${UX_SUCCESS}claude mcp add playwright --transport stdio -- npx -y @playwright/mcp@latest${UX_RESET}

     사용 예:
     - "playwright mcp를 사용해서 example.com에 접속해줘"
     - "playwright로 검색창에 'claude' 입력하고 스크린샷 찍어줘"

  2. ${UX_BOLD}Sequential Thinking MCP${UX_RESET} (논리적 분석)
     ${UX_SUCCESS}claude mcp add sequential-thinking --transport stdio -- npx -y @modelcontextprotocol/server-sequential-thinking${UX_RESET}

     사용 예:
     - "이 문제를 sequential-thinking으로 단계별 분석해줘"
     - "이 알고리즘의 시간복잡도를 체계적으로 분석해줘"

${UX_BOLD}${UX_PRIMARY}[설치 후 확인]${UX_RESET}

  # 설치한 MCP 서버 확인
  ${UX_SUCCESS}claude mcp list${UX_RESET}

  # 특정 MCP 서버 상태 확인
  ${UX_SUCCESS}claude mcp get playwright${UX_RESET}
  ${UX_SUCCESS}claude mcp get sequential-thinking${UX_RESET}

${UX_BOLD}${UX_PRIMARY}[Setup & Requirements]${UX_RESET}

  ${UX_SUCCESS}clinstall${UX_RESET}        : Claude Code CLI 설치
  ${UX_SUCCESS}ensure_jq${UX_RESET}        : jq 설치 여부 확인 및 자동 설치
                     (Claude Code statusline 스크립트에 필요)

${UX_BOLD}${UX_PRIMARY}[Configuration Management]${UX_RESET}

  ${UX_SUCCESS}claude_init${UX_RESET}      : Claude Code 설정 및 skills symbolic link 초기화
                     - settings.json ↔ ~/.claude/settings.json
                     - statusline-command.sh ↔ ~/.claude/statusline-command.sh
                     - skills/*.md ↔ ~/.claude/skills/*.md
  ${UX_SUCCESS}claude_edit_settings${UX_RESET} : settings.json 파일 편집 (vim)

${UX_BOLD}${UX_PRIMARY}[Workflow Patterns]${UX_RESET}

  ${UX_BOLD}1. Plan 모드 (권장 - 안전)${UX_RESET}
     ${UX_SUCCESS}claude${UX_RESET}          : Interactive 모드로 시작
                      먼저 plan을 요청하고, 승인 후 실행
                      TDD/SDD 지향 개발에 적합

     ${UX_SUCCESS}clplan${UX_RESET}          : claude 명령어 alias

  ${UX_BOLD}2. 테스트 & 린팅 작업${UX_RESET}
     ${UX_SUCCESS}cltest "요청내용"${UX_RESET} : 테스트 작성 및 실행
                      예: cltest "사용자 인증 테스트 작성해줘"
                      권한 설정으로 pytest/ruff 자동 허용

  ${UX_BOLD}3. Skip Permissions 모드 (주의)${UX_RESET}
     ${UX_SUCCESS}clskip "요청내용"${UX_RESET} : 모든 권한 프롬프트 무시
                      복잡한 리팩토링이나 보일러플레이트 생성 시
                      ⚠️  작은 범위부터 시작하고 신중하게 사용

  ${UX_BOLD}권장 워크플로우:${UX_RESET}
  - 새 기능 개발: ${UX_SUCCESS}claude${UX_RESET} (plan → 승인 → 실행)
  - 테스트 작성: ${UX_SUCCESS}cltest "테스트 작성해줘"${UX_RESET}
  - 대규모 리팩토링: ${UX_SUCCESS}clskip "리팩토링해줘"${UX_RESET} (신중하게)

${UX_BOLD}${UX_PRIMARY}[권한 관리 & Sandbox]${UX_RESET}

  ${UX_BOLD}1. Sandbox 사용법 (84% 프롬프트 감소)${UX_RESET}
     ${UX_SUCCESS}/sandbox${UX_RESET}         : Claude 대화 중에 입력
                      → Auto-allow mode 선택 (권장)
                      → pytest, git, npm 등이 자동 승인됨

     예제:
     ${UX_SUCCESS}claude${UX_RESET}
     > ${UX_SUCCESS}/sandbox${UX_RESET}
     > [Auto-allow mode 선택]
     > "테스트 작성하고 실행해줘"
     → pytest, ruff, git 명령어가 자동 실행!

  ${UX_BOLD}2. Settings.json 설정${UX_RESET}
     ${UX_SUCCESS}claude_edit_settings${UX_RESET} : 설정 파일 편집

     위치: ~/dotfiles/bash/claude/settings.json

     기본 설정 포함:
     - Sandbox 활성화 (autoAllowBashIfSandboxed: true)
     - 테스트 파일 자동 허용 (pytest, ruff, mypy, tox)
     - 민감한 파일 차단 (.env, ~/.aws, ~/.ssh)
     - 위험한 명령어 차단 (rm -rf, sudo rm)

  ${UX_BOLD}3. 설정 예제${UX_RESET}
     프로젝트별 설정: .claude/settings.json
     {
       "sandbox": { "enabled": true },
       "permissions": {
         "allow": ["Bash(pytest*)"],
         "deny": ["Read(.env)"]
       }
     }
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
    local skills_source_dir="$HOME/dotfiles/bash/claude/skills"
    local skills_target_dir="$HOME/.claude/skills"

    echo "🔧 Initializing Claude Code configuration..."

    # Create ~/.claude directory if not exists
    if [[ ! -d "$HOME/.claude" ]]; then
        echo "📁 Creating ~/.claude directory..."
        mkdir -p "$HOME/.claude"
    fi

    # Create ~/.claude/skills directory if not exists
    if [[ ! -d "$skills_target_dir" ]]; then
        echo "📁 Creating ~/.claude/skills directory..."
        mkdir -p "$skills_target_dir"
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

    # Handle skills directory
    echo ""
    echo "📚 Setting up Claude Code skills..."
    local skill_count=0
    if [[ -d "$skills_source_dir" ]]; then
        for skill_file in "$skills_source_dir"/*.md; do
            if [[ -f "$skill_file" ]]; then
                local skill_name=$(basename "$skill_file")
                local skill_target="$skills_target_dir/$skill_name"

                if [[ -L "$skill_target" ]]; then
                    echo "  ✅ $skill_name (already linked)"
                elif [[ -f "$skill_target" ]]; then
                    echo "  ⚠️  $skill_name exists as regular file"
                    echo "     Backing up to $skill_name.backup..."
                    mv "$skill_target" "$skill_target.backup"
                    ln -s "$skill_file" "$skill_target"
                    echo "  ✅ $skill_name (linked)"
                else
                    ln -s "$skill_file" "$skill_target"
                    echo "  ✅ $skill_name (linked)"
                fi
                ((skill_count++))
            fi
        done

        if [[ $skill_count -eq 0 ]]; then
            echo "  ℹ️  No skill files found in $skills_source_dir"
        else
            echo "  📊 Total: $skill_count skill(s) linked"
        fi
    else
        echo "  ⚠️  Skills source directory not found: $skills_source_dir"
    fi

    echo ""
    echo "✨ Claude Code configuration initialization complete!"
    echo ""
    echo "📍 Configuration files:"
    ls -la "$settings_target" "$statusline_target" 2>/dev/null | grep -v "^total"

    echo ""
    echo "📍 Skills:"
    if [[ -d "$skills_target_dir" ]]; then
        ls -la "$skills_target_dir"/*.md 2>/dev/null | grep -v "^total" || echo "  (no skills found)"
    fi
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

# (5) Claude Code workflow aliases
# Plan 모드: Interactive 모드로 시작 (권장)
alias clplan='claude'

# 테스트 작성 및 실행
cltest() {
    if [[ -z "$1" ]]; then
        echo "사용법: cltest \"요청내용\""
        echo "예: cltest \"사용자 인증 테스트 작성해줘\""
        return 1
    fi
    claude -p "$1"
}

# Skip permissions 모드 (주의해서 사용)
clskip() {
    if [[ -z "$1" ]]; then
        echo "사용법: clskip \"요청내용\""
        echo "예: clskip \"이 모듈을 리팩토링해줘\""
        echo ""
        echo "⚠️  주의: 모든 권한 프롬프트를 무시합니다."
        echo "   작은 범위부터 시작하고 신중하게 사용하세요."
        return 1
    fi

    echo "⚠️  Skip permissions 모드로 실행합니다..."
    echo "   요청: $1"
    echo ""
    claude --dangerously-skip-permissions -p "$1"
}
