# ghostty

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/ghostty_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic ghostty --force`

## 호출

- Help 진입점: `ghostty-help [section|--list|--all]`
- 통합 라우팅: `my-help ghostty [section]`
- Alias: `ghostty-help`

## 요약 (ghostty-help)

- Usage: ghostty-help [section|--list|--all]
- sections
    - concept: GPU-accelerated | AppKit/GTK4 | Catppuccin
    - config: ghostty_init | ghostty_edit_config
    - symlink: ~/dotfiles/ghostty/config -> ~/.config/ghostty/config
    - settings: theme | font-family | background-opacity | quick-terminal
    - commands: +list-themes | +list-fonts | +show-config
    - related: tmux-help | zsh-help
    - details: ghostty-help <section>  (example: ghostty-help config)

## 섹션

### concept

- GPU-accelerated terminal emulator (Zig + libghostty)
- Platform-native UI on macOS (AppKit) and Linux (GTK4)
- Catppuccin Mocha/Latte theme with Hack Nerd Font Mono

### config

- **ghostty_init** — 설정 파일 symbolic link 초기화
- **ghostty_edit_config** — config 파일 편집 (symlinked)

### symlink

- Source: ~/dotfiles/ghostty/config
- Target: ~/.config/ghostty/config

### settings

- **theme** — dark:catppuccin-mocha, light:catppuccin-latte
- **font-family** — Hack Nerd Font Mono (size 14)
- **background-opacity** — 0.8 with blur radius 10
- **quick-terminal** — Cmd+` toggle, bottom position

### commands

- **ghostty +list-themes** — List all available themes
- **ghostty +list-fonts** — List available fonts
- **ghostty +show-config** — Show current configuration

### related

- Terminal multiplexer: tmux-help
- Zsh shell: zsh-help

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/ghostty.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/ghostty_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
