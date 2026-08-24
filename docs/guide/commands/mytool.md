# mytool

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/mytool_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic mytool --force`

## 호출

- Help 진입점: `mytool-help [section|--list|--all]`
- 통합 라우팅: `my-help mytool [section]`
- Alias: `mytool-help`

## 요약 (mytool-help)

- Usage: mytool-help [section|--list|--all]
- sections
    - tools: list all .sh files in shell-common/tools/custom/
    - usage: how to run custom tools
    - details: mytool-help <section>  (example: mytool-help tools)

## 섹션

### tools

- Executable utility scripts in ~/dotfiles/shell-common/tools/custom
- **Tool** — Description
- **analyze_bash_scripts** — Scan a directory of bash files and emit a Markdown summar...
- **check_apt** — Comprehensive APT sources configuration diagnostic script
- **check_cargo** — Comprehensive Cargo configuration diagnostic script
- **check_network** — Comprehensive internet connectivity diagnostic script
- **check_npm** — Comprehensive npm configuration diagnostic script
- **check_nuget** — Comprehensive NuGet configuration diagnostic script
- **check_pip** — Comprehensive pip configuration diagnostic script
- **check_proxy** — Comprehensive proxy diagnostic script
- **check_rpm** — Comprehensive RPM/YUM repository configuration diagnostic...
- **check_ssh** — SSH key setup and diagnostics for SSAI project (WSL envir...
- **check_uv** — Comprehensive uv configuration diagnostic script
- **check_ux_consistency** — Check UX consistency across all bash files
- **cp_wdown** — Copy files from Windows "Downloads" to WSL ~/downloads wi...
- **delete_claude** — Claude Code CLI Uninstall Script
- **demo_ux** — Interactive demo of UX library features
- **devx** — This script exists so `devx` can be run as a standalone c...
- **docker_configure_proxy** — Docker Proxy 설정 스크립트 (대화형)
- **enable_docker** — Docker 서비스 자동 시작 설정 (systemd) - 대화형
- **ensure-ollama-deps** — Ollama Dependency Installer
- **ensure_jq** — Ensure jq is installed (dependency checker)
- **gen_command_docs** — Generate one markdown reference doc per user-facing comma...
- **get_hw_info** — Display comprehensive hardware information
- **gpu_status** — 목적: WSL2 특성상 컨테이너 내 nvidia-smi 사용...
- **hook_check** — Git Hook Configuration Diagnostic Tool
- **init** — Centralized initialization for all custom tools scripts.
- **install-ollama** — WSL Environment: Ollama Binary Installation Script
- **install_agy** — Antigravity CLI (agy) 설치 스크립트 (대화형)
- **install_bat** — Install and configure bat (cat replacement with syntax hi...
- **install_claude** — Claude Code CLI Install Script
- **install_codex** — Codex CLI 설치 스크립트 (대화형)
- **install_docker** — WSL Docker 설치 스크립트 (대화형)
- **install_fasd** — Install and configure fasd (fast access to directories an...
- **install_fd** — Install and configure fd (fast file search tool)
- **install_fzf** — Install and configure fzf (fuzzy finder) for bash and zsh
- **install_git_lfs** — Install and initialize Git LFS (Ubuntu/Debian)
- **install_notion_mcp** — Install and configure Notion MCP (Model Context Protocol)...
- **install_npm** — Node.js & npm 설치 스크립트 (대화형)
- **install_nvm** — NVM (Node Version Manager) Install Script
- **install_opencode** — OpenCode CLI Installation Script (Interactive)
- **install_p10k** — Install and configure powerlevel10k theme for zsh
- **install_pet** — Install and configure pet (command snippet manager)
- **install_postgresql** — PostgreSQL 서버 설치 스크립트 (대화형)
- **install_python** — Pyenv & Python Install Script
- **install_redis** — Redis server installer for WSL/Ubuntu (interactive)
- **install_ripgrep** — Install and configure ripgrep (fast text search tool)
- **install_uv** — UV Install Script
- **install_zsh** — Zsh Install Script
- **install_zsh_autosuggestions** — Install and configure zsh-autosuggestions
- **issue_watcher_cron** — issue-watcher 5분 주기 감시 사이클 — 1회 tick ...
- **make_confluence** — Transform a technical markdown document into a Confluence...
- **make_jira** — Simple version handling both:
- **mirror-pages-activate** — Activates GitHub Pages on the GHE origin repo and replace...
- **open_in_windows_chrome** — Open links in the Windows-side Chrome from WSL (#1408).
- **repo_stats** — Initialize common tools environment
- **run_agents_md_master_prompt** — Claude Code에게 AGENTS.md 생성 요청 (비대화형)
- **set_locale** — This script sets up the en_US.UTF-8 locale to resolve "ma...
- **setup_crt** — CA Certificate Setup Script
- **setup_gpg_cache** — GPG agent 캐싱 설정 스크립트 (편의성 향상)
- **skill_loader** — Standalone skill loader utility for programmatic access
- **symlink-manager** — Symbolic Link Manager for Dotfiles
- **uninstall_agy** — Antigravity CLI (agy) 제거 스크립트 (대화형)
- **uninstall_codex** — Codex CLI 제거 스크립트 (대화형)
- **uninstall_docker** — WSL Docker 제거 스크립트 (대화형)
- **uninstall_npm** — Node.js & npm 제거 스크립트 (대화형)
- **work_log** — Companion to post-commit hook for tracking non-developmen...
- Total: 65 custom tools available
- Location: ~/dotfiles/shell-common/tools/custom

### usage

- Run a tool directly: ${SHELL_COMMON}/tools/custom/tool-name.sh
- Or add to PATH for direct execution: tool-name.sh

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/mytool.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/mytool_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
