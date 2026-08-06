# claude-plugins

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/claude_plugins_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic claude_plugins --force`

## 호출

- Help 진입점: `claude-plugins-help [section|--list|--all]`
- 통합 라우팅: `my-help claude_plugins [section]`
- Alias: `claude-plugins-help`

## 요약 (claude-plugins-help)

- Usage: claude-plugins-help [section|--list|--all]
- sections
    - commands: open_claude_plugins | list-plugins | claude-plugin-list | init-plugins-docs | sync-plugins-structure
    - view: view-plugin-info | generate-plugin-doc-ko | create-plugin-structure-ko
    - examples: quick examples for create-plugin-ko
    - ai-tools: claude | agy | codex
    - workflow: recommended workflow
    - structure: plugin and docs directory layout
    - git: git integration & mount details
    - details: claude-plugins-help <section>

## 섹션

### commands

- open_claude_plugins  - Open marketplace plugins directory in VSCode
- list-plugins         - List all available marketplaces and their skills
- claude-plugin-list   - List installed plugins grouped by marketplace (SSOT: installed_plugins.json)
- init-plugins-docs    - Initialize Korean documentation directory structure
- sync-plugins-structure - Create directory structure mirroring plugins organization

### view

- view-plugin-info <plugin-name>
-   Usage: view-plugin-info algorithmic-art
- generate-plugin-doc-ko <source-file> <output-file> [ai-tool]
-   Default Claude: generate-plugin-doc-ko file.md output_KO.md
-   agy: generate-plugin-doc-ko file.md output_KO.md agy
- create-plugin-structure-ko <marketplace> <plugin-path> [ai-tool]
-   Default: create-plugin-structure-ko <marketplace> <path/to/file.md>
-   agy: create-plugin-structure-ko <marketplace> <path/to/file.md> agy

### examples

- 1. Generate with default AI (Claude):
-    create-plugin-ko claude-code-workflows plugins/code-refactoring/agents/code-reviewer.md
- 2. Generate with agy:
-    create-plugin-ko claude-code-workflows plugins/code-refactoring/agents/code-reviewer.md agy
- 3. Change default AI tool for session:
-    export CLAUDE_DOC_GENERATOR=codex
-    create-plugin-ko claude-code-workflows plugins/code-refactoring/agents/code-reviewer.md
- 4. Review the generated file:
-    code ~/.claude/docs/marketplaces/claude-code-workflows/plugins/code-refactoring/agents/code-reviewer_KO.md
- 5. Commit to git:
-    cd ~/dotfiles && git add claude/docs/ && git commit -m 'docs: Add Korean summary'

### ai_tools

- claude - Anthropic Claude (default)
- agy - Antigravity CLI
- codex - OpenAI Codex
- Any CLI tool accepting -p or --prompt flag

### workflow

- 1. init-plugins-docs - Initialize docs directory (first time only)
- 2. open_claude_plugins - Review plugin files in VSCode
- 3. create-plugin-ko <marketplace> <path> - Generate Korean summary
- 4. Edit & customize generated *_KO.md file
- 5. Add personal notes to README.md
- 6. git add && git commit - Save to dotfiles repository

### structure

- Plugins (read-only marketplace):
- $HOME/.claude/plugins/marketplaces/[marketplace]/plugins/[plugin-name]/agents/[agent].md
- Documentation (git-tracked, mounted):
- $HOME/.claude/docs/marketplaces/[marketplace]/plugins/[plugin-name]/agents/
-   ├── [agent]_KO.md    (Korean summary, auto-generated)
-   └── README.md         (Learning notes, manual)

### git

- All documentation is symlinked to the SSOT and automatically git-tracked:
- User location: ~/.claude/docs (directory symlink, #575)
- Git source: ~/dotfiles/claude/docs
- Changes are version-controlled and shareable across machines

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/claude-plugins.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/claude_plugins_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
