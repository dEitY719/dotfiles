# bat

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/bat_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic bat --force`

## 호출

- Help 진입점: `bat-help [section|--list|--all]`
- 통합 라우팅: `my-help bat [section]`
- Alias: `bat-help`

## 요약 (bat-help)

- Usage: bat-help [section|--list|--all]
- sections
    - concept: cat replacement | syntax highlighting | git integration
    - basic: bat file | piped | multiple
    - lines: -n | -r 5:10 | -r 5: | -r :10
    - language: -l | --list-languages | --theme | --list-themes
    - display: --plain | --color | --style
    - git: shows changes (green/red)
    - advanced: -A | -t | --tabs | -H
    - config: ~/.config/bat/config defaults
    - related: install-bat | ripgrep-help | fd-help | fzf-help
    - details: bat-help <section>  (example: bat-help basic)

## 섹션

### concept

- Cat replacement with syntax highlighting
- Supports 200+ languages and file formats
- Git integration - shows file changes in color
- Automatic language detection from filename

### basic

- **bat file.txt** — View file with syntax highlighting
- **cat file.txt | bat** — View piped content
- **bat file.txt file2.txt** — View multiple files

### lines

- **bat -n file.txt** — Show line numbers
- **bat -r 5:10 file.txt** — Show lines 5-10
- **bat -r 5: file.txt** — Show from line 5 to end
- **bat -r :10 file.txt** — Show first 10 lines

### language

- **bat -l python file.py** — Specify language explicitly
- **bat --list-languages** — Show all supported languages
- **bat --theme Monokai file.txt** — Use different color theme
- **bat --list-themes** — Show all available themes

### display

- **bat --plain file.txt** — Plain output (no decorations)
- **bat --color=never file.txt** — Disable colors
- **bat --color=always file.txt** — Force colors
- **bat --style=numbers file.txt** — Show only line numbers

### git

- **bat file.txt** — Shows git changes (green/red lines)

### advanced

- **bat -A file.txt** — Show invisible characters
- **bat -t file.txt** — Show tabs as visual indicators
- **bat --tabs 4 file.txt** — Set tab width to 4 spaces
- **bat -H file.txt** — Highlight specific lines

### config

- Create ~/.config/bat/config for default options:
- --theme=Monokai Extended - Set default theme
- --style=numbers - Always show line numbers
- --tabs=4 - Set tab width
- --paging=auto - Auto pagination

### related

- Install bat: install-bat
- Text search: ripgrep-help
- File finder: fd-help
- Fuzzy finder: fzf-help

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/bat.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/bat_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
