# codex

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/ai_tools_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic codex --force`

## 호출

- Help 진입점: `codex-help [section|--list|--all]`
- 통합 라우팅: `my-help codex [section]`
- Alias: `codex-help`

## 요약 (codex-help)

- Usage: codex-help [section|--list|--all]
- sections
    - basic: codex | codex-help | official help | codex-version | codex-yolo
    - setup: codex-install | codex-uninstall | codex-status | codex-skills-sync | auto sync
    - interactive: codex | codex prompt
    - tips: config dir | auth | auto sync env vars
    - details: codex-help <section>  (example: codex-help setup)

## 섹션

### basic

- **codex** — codex — Base command
- **codex-help** — codex-help — Show dotfiles codex commands
- **Official help** — codex help | --help | -h — Show CLI help
- **codex-version** — codex --version — Check version
- **codex-yolo** — codex --dangerously-bypass-approvals-and-sandbox — Bypass guardrails

### setup

- **codex-install** — Install Script — Install Codex CLI
- **codex-uninstall** — Uninstall Script — Remove Codex CLI
- **codex-status** — Status Check — Show installation status
- **codex-skills-sync** — Skills Sync — Sync skills symlinks
- **Auto skill sync** — Enabled by default — Before codex command

### interactive

- **codex** — codex — Start interactive
- **codex prompt** — codex prompt — Run with prompt

### tips

- Config: ~/.codex/ or ~/.config/codex/
- Auth: Use 'codex' to authenticate
- Auto sync: before codex command + prompt cycle
- Disable auto sync: export CODEX_SKILLS_AUTO_SYNC=0
- Verbose auto sync: export CODEX_SKILLS_AUTO_SYNC_VERBOSE=1
- Auto sync interval(sec): export CODEX_SKILLS_AUTO_SYNC_INTERVAL=5

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/codex.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/ai_tools_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
