# zsh

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/zsh_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic zsh --force`

## 호출

- Help 진입점: `zsh-help [section|--list|--all]`
- 통합 라우팅: `my-help zsh [section]`
- Alias: `zsh-help`

## 요약 (zsh-help)

- Usage: zsh-help [section|--list|--all]
- sections
    - switch: zsh-switch | bash-switch | install-zsh
    - config: zsh-edit | zsh-reload | zsh-snippet
    - theme: zsh-themes | zsh-theme-current | zsh-theme
    - plugins: zsh-plugins | zsh-update
    - packages: install-p10k | install-fzf | install-fasd
    - themes-list: robbyrussell | powerlevel10k | agnoster
    - plugins-list: git | autosuggestions | syntax-highlighting
    - coexist: bash & zsh coexistence tips
    - tips: configuration & snippet tips
    - troubleshoot: zsh-fix-vscode | zsh-clear-p10k-caches | zsh-git-fix | p10k issues
    - status: zsh-version | zsh-info
    - details: zsh-help <section>  (example: zsh-help theme)

## 섹션

### switch

- **zsh-switch** — Switch to zsh
- **bash-switch** — Switch back to bash
- **install-zsh** — Install zsh (if not installed)

### config

- **zsh-edit** — Edit $HOME/.zshrc
- **zsh-reload** — Reload zsh config
- **zsh-snippet <name>** — Create config snippet
- **zsh-snippets** — List all snippets
- **zsh-config** — View current zsh config
- **zsh-edit-quick** — Quick edit with nano

### theme

- **zsh-themes** — List all available themes
- **zsh-theme-current** — Show current theme
- **zsh-theme <name>** — Change zsh theme

### plugins

- **zsh-plugins** — List installed plugins
- **zsh-update** — Update oh-my-zsh framework

### packages

- **install-p10k** — Install powerlevel10k theme
- **p10k-help** — VSCode terminal font setup guide
- **p10k configure** — Configure powerlevel10k
- **install-zsh-autosuggestions** — Install zsh-autosuggestions
- **install-fzf** — Install fzf (fuzzy finder)
- **install-fasd** — Install fasd (fast directory access)
- **install-ripgrep** — Install ripgrep (fast text search)
- **install-fd** — Install fd (fast file finder)
- **install-bat** — Install bat (cat with highlighting)
- **install-pet** — Install pet (command snippet manager)

### themes_list

- robbyrussell - Default clean theme
- powerlevel10k - Modern powerline theme (requires Nerd Font)
- agnoster - Git-aware theme
- minimal - Minimal and fast
- afowler - Syntax highlighting focused

### plugins_list

- git - Git aliases and functions
- zsh-autosuggestions - Command suggestions (type then use arrow)
- zsh-syntax-highlighting - Syntax highlighting as you type
- extract - Smart archive extraction (extract file.tar.gz)
- web-search - Quick web search (google 'query')

### coexist

- Both shells can coexist without conflicts
- Switch shells anytime: zsh-switch or bash-switch
- Set default: chsh -s $(which zsh) (then login again)

### tips

- Shared config: Add to shell-common/ for portable settings
- Shell-specific: Use shell-specific files for unique functions
- Use snippets: Organize $HOME/.zshrc.d/ for better management

### troubleshoot

- VS Code 터미널에서 기본 프롬프트(HOSTNAME%)만 표시될 때:
-   원인: VS Code 업데이트 후 셸 통합 캐시 불일치
-   해결: zsh-fix-vscode
- gwt spawn 직후 prompt 가 이전 디렉터리/브랜치에 frozen 일 때:
-   진단: print -lr -- $precmd_functions 에 _p9k_precmd 가 있는지 확인
-   해결: zsh-clear-p10k-caches 후 exec zsh
- gwt teardown 후 p10k 가 branch 이름을 표시하지 않을 때:
-   원인: .git/config 에 repositoryformatversion=1 잔존 (gitstatusd 오인식)
-   해결: zsh-git-fix (worktree 없는 상태에서 실행)
- p10k 프롬프트가 깨지거나 느릴 때:
-   해결: p10k configure 로 재설정

### status

- **zsh-version** — Show zsh version
- **zsh-info** — System info

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/zsh.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/zsh_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
