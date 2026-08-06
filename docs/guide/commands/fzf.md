# fzf

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/fzf.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic fzf --force`

## 호출

- Help 진입점: `fzf-help [section|--list|--all]`
- 통합 라우팅: `my-help fzf [section]`
- Alias: `fzf-help`

## 요약 (fzf-help)

- Usage: fzf-help [section|--list|--all]
- sections
    - core: Ctrl+T | Ctrl+R | Alt+C
    - nav: Tab | Shift+Tab | Ctrl+K | Ctrl+J | PgUp | PgDn
    - edit: Ctrl+W | Ctrl+U | Ctrl+A | Ctrl+E | Backspace
    - select: Ctrl+A | Ctrl+D | Ctrl+X
    - actions: Enter | Esc | Ctrl+V | Ctrl+L
    - preview: ? | > | <
    - examples: file | history | process | git
    - tips: type | ^ | ! | ' | Tab
    - config: FZF_DEFAULT_OPTS | FZF_DEFAULT_COMMAND
    - details: fzf-help <section>  (example: fzf-help core)

## 섹션

### core

- **Ctrl+T** — Insert selected file(s) into command line
- **Ctrl+R** — Search and insert command from history
- **Alt+C** — Change to selected directory

### nav

- **Tab** — Toggle selection (multi-select mode)
- **Shift+Tab** — Toggle selection (reverse)
- **Ctrl+K** — Move cursor up
- **Ctrl+J** — Move cursor down
- **Page Up** — Scroll up
- **Page Down** — Scroll down

### edit

- **Ctrl+W** — Delete word backward
- **Ctrl+U** — Clear line
- **Ctrl+A** — Move to beginning of line
- **Ctrl+E** — Move to end of line
- **Backspace** — Delete character

### select

- **Ctrl+A** — Select all items
- **Ctrl+D** — Deselect all items
- **Ctrl+X** — Toggle all selections

### actions

- **Enter** — Confirm selection(s)
- **Esc/Ctrl+C** — Abort (no selection)
- **Ctrl+V** — Toggle preview window
- **Ctrl+L** — Toggle layout

### preview

- **?** — Show/hide help
- **>** — Toggle info on the right
- **<** — Toggle info on the left

### examples

- File selection:
- vim $(fzf) - Open file in vim
- cat $(fzf) - Display file contents
- cd $(dirname $(fzf)) - Navigate to file's directory
- Command history:
- Press Ctrl+R to search command history interactively
- Process selection:
- kill -9 $(pgrep -f process | fzf)
- Git integration:
- git checkout $(git branch | fzf)
- git log --oneline | fzf

### tips

- Type to filter: Just start typing to narrow down results
- Regex matching: Use ^pattern to match from start
- Inverse match: Use !pattern to exclude matches
- Exact match: Use 'pattern for exact string match
- Multi-select: Use Tab to select multiple items

### config

- Customize fzf with environment variables:
- FZF_DEFAULT_OPTS - Default options
- FZF_DEFAULT_COMMAND - Default command
- FZF_CTRL_T_COMMAND - Ctrl+T command
- FZF_CTRL_R_OPTS - Ctrl+R options
- FZF_ALT_C_COMMAND - Alt+C command
- Example: Add to ~/.bashrc or ~/.zshrc
- export FZF_DEFAULT_OPTS='--multi --preview "head -20 {}"'

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/fzf.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/fzf.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
