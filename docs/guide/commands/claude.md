# claude

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/ai_tools_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic claude --force`

## 호출

- Help 진입점: `claude-help [section|--list|--all]`
- 통합 라우팅: `my-help claude [section]`
- Alias: `claude-help`

## 요약 (claude-help)

- Usage: claude-help [section|--list|--all]
- sections
    - mcp: list | get | add | remove
    - recommended: Playwright MCP | Sequential Thinking MCP
    - setup: clinstall | ensure_jq | claude_init | claude_edit_settings
    - sandbox: /sandbox | Auto-allow | pytest, git, npm
    - config: settings.json | autoAllow | block paths | block cmds
    - statusline: time | model | project | context | cost
    - skills: claude-skills
    - plugin: claude plugin sync + restore.sh
    - details: claude-help <section>  (example: claude-help mcp)

## 섹션

### mcp

- **claude mcp list** — List installed MCP servers
- **claude mcp get <name>** — Show MCP server details
- **claude mcp add <name> ...** — Add MCP server
- **claude mcp remove <name>** — Remove MCP server

### recommended

- Playwright MCP: Web browser automation
- Install: claude mcp add playwright --transport stdio -- npx -y @playwright/mcp@latest
- Sequential Thinking MCP: Logical analysis
- Install: claude mcp add sequential-thinking --transport stdio -- npx -y @modelcontextprotocol/server-sequential-thinking

### setup

- **clinstall** — Install Claude Code CLI
- **ensure_jq** — Install jq (required for statusline)
- **claude_init** — Initialize config & skills
- **claude_edit_settings** — Edit settings.json

### sandbox

- Use in Claude conversation: /sandbox
- Select Auto-allow mode
- pytest, git, npm auto-approved

### config

- Settings file: ~/dotfiles/claude/settings.json
- Sandbox: autoAllowBashIfSandboxed
- Auto-allow: pytest, ruff, mypy, tox
- Block: .env, ~/.aws, ~/.ssh
- Block commands: rm -rf, sudo rm

### statusline

- Real-time session information in Claude Code status bar
- 🕐 Time (morning/afternoon/night emoji + YY-MM-DD HH:MM:SS)
- 🤖 Model (emoji + display name: 🐰 Haiku, 🎼 Sonnet, 🎭 Opus)
- 📁 Project (folder name + git branch with emoji)
- 📊 Context usage percentage + weekly percentage
- 💰 Session cost (Green <$5, Orange $5-20, Red >$20)

### skills

- **claude-skills** — List available Claude Code skills
- Skills location: ~/dotfiles/claude/skills/

### plugin

- **claude plugin marketplace add/remove, install/uninstall** — 자동으로 claude/plugin/*.json에 동기화됨 (hook)
- **./claude/plugin/restore.sh** — 신규 PC에서 manifest 기반 일괄 재설치 (add-only)
- **./claude/plugin/restore.sh --sync** — 양방향 sync — SSOT에 없는 잉여 로컬 항목까지 제거
- **./claude/plugin/restore.sh --dry-run** — 실행 없이 계획만 출력 (--sync와 조합 가능)
- **./claude/plugin/publish-sync.sh** — 로컬에 쌓인 manifest sync 커밋을 PR로 origin에 게시
- **./claude/plugin/publish-sync.sh --dry-run** — 게시할 diff만 출력, 변경 없음
- **./claude/plugin/reconcile.sh --check** — SSOT(installed_plugins) 대비 manifest drift 감지 (유령 엔트리 포함)
- **./claude/plugin/reconcile.sh --apply** — manifest를 SSOT 기준으로 재빌드 + 커밋 (drift 복구)
- **claude-plugin-list** — 설치된 플러그인을 마켓플레이스별로 요약 출력

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/claude.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/ai_tools_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
