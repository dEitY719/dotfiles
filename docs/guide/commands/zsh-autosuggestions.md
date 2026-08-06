# zsh-autosuggestions

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/zsh_autosuggestions.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic zsh_autosuggestions --force`

## 호출

- Help 진입점: `zsh-autosuggestions-help [section|--list|--all]`
- 통합 라우팅: `my-help zsh_autosuggestions [section]`
- Alias: `zsh-autosuggestions-help`

## 요약 (zsh-autosuggestions-help)

- Usage: zsh-autosuggestions-help [section|--list|--all]
- sections
    - about: what is zsh-autosuggestions
    - keys: Tab | Ctrl+Right | Ctrl+F | Ctrl+A
    - how: how the suggestions work
    - example: example usage
    - env: ZSH_AUTOSUGGEST_* variables
    - strategies: history | completion | match_prev_cmd
    - customize: ~/.zshrc snippets
    - status: installation status
    - details: zsh-autosuggestions-help <section>

## 섹션

### about

- Auto-suggests commands as you type, based on your history.
- Press Tab or Ctrl+Right to accept the suggestion.

### keys

- **Key** — Action
- **Tab / Ctrl+Right** — Accept suggestion
- **Ctrl+F** — Accept next word of suggestion
- **Ctrl+A** — Accept entire suggestion
- **Up/Down Arrow** — Navigate history (overrides suggestions)

### how

- As you type, suggestions appear in gray text
- Suggestions are based on command history
- Press Tab (or configured key) to accept
- Press Esc or start typing to dismiss

### example

- Type 'work' and zsh will suggest:
- work-log list help
- work-log add SWINNOTEAM-906 -t coordination...
- work-help
- Press Tab to accept any suggestion

### env

- **Variable** — Description — Default
- **ZSH_AUTOSUGGEST_STRATEGY** — Suggestion matching strategy — history
- **ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE** — Max command length to suggest — unbounded
- **ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE** — Suggestion text color — fg=8

### strategies

- history - Suggest from command history
- completion - Suggest from completion
- match_prev_cmd - Suggest matching previous command

### customize

- Add to ~/.zshrc (before sourcing zsh-autosuggestions):
  # Accept suggestion with Tab key
  bindkey '\t' autosuggest-accept
  # Change suggestion highlight color
  export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=10'
  # Use history strategy only
  export ZSH_AUTOSUGGEST_STRATEGY=(history)

### status

- zsh-autosuggestions is not installed
  Run: install-zsh-autosuggestions

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/zsh-autosuggestions.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/zsh_autosuggestions.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
