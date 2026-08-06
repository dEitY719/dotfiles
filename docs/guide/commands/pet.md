# pet

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/pet.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic pet --force`

## 호출

- Help 진입점: `pet-help [section|--list|--all]`
- 통합 라우팅: `my-help pet [section]`
- Alias: `pet-help`

## 요약 (pet-help)

- Usage: pet-help [section|--list|--all]
- sections
    - concept: snippet manager | search/exec | TOML
    - core: pet new | search | list | edit | version
    - structure: description | command | tags
    - create: pet new (interactive)
    - search: pet search | grep
    - examples: file | git | docker | system
    - fzf | config | storage | workflow | tips | compare | advantages
    - related: install-pet | fzf-help | ripgrep-help | zsh-help
    - details: pet-help <section>  (example: pet-help core)

## 섹션

### concept

- Store and recall frequently used commands
- Interactive search and execution
- Snippets stored as TOML configuration
- Built-in editor support for managing snippets
- Integrates with shell for easy access

### core

- **pet new** — Create a new snippet interactively
- **pet search** — Search and execute snippet
- **pet list** — List all stored snippets
- **pet edit** — Edit snippets in text editor
- **pet version** — Show pet version

### structure

- Each snippet contains:
- description - What the snippet does
- command - The actual command to execute
- tags - Keywords for searching (optional)

### create

- Interactive creation:
- pet new - Opens editor to create snippet
- Prompts for: description, command, tags
- Example: 'Find large files' -> 'find . -size +100M'

### search

- **pet search** — Interactive search (fzf integration)
- **pet search 'find'** — Search by description/command
- **pet list | grep 'find'** — Grep search results

### examples

- File Operations:
- find large files: find . -size +100M
- recursive search: grep -r 'pattern' .
- count lines: find . -name '*.rs' | xargs wc -l
- Git Operations:
- undo last commit: git reset --soft HEAD~1
- delete local branch: git branch -d branch_name
- prune remote branches: git remote prune origin
- Docker Operations:
- remove dangling images: docker rmi $(docker images -f dangling=true -q)
- clean all: docker system prune -a
- view logs: docker logs --follow container_name
- System Commands:
- disk usage: du -sh * | sort -h
- find and delete: find . -name '.DS_Store' -delete
- monitor processes: watch -n 1 'ps aux | grep pattern'

### fzf

- pet integrates with fzf for interactive search
- Fuzzy match snippets by description or command
- Preview snippet before execution
- Execute directly from search results

### config

- Location: ~/.config/pet/config.toml
- Editor integration:
- editor = 'vim' - Set preferred editor
- selector = 'fzf' - Use fzf for selection
- pager = 'less' - Set pager for output

### storage

- Location: ~/.config/pet/snippets.toml
- Text format (TOML) - easy to edit manually
- Portable - copy between systems
- Versionable - track with git

### workflow

- Regular workflow:
- Execute a command frequently: pet new
- Need to use it later: pet search
- Found a better version: pet edit
- Integration with other tools:
- Copy snippet command: pet search | xargs echo
- Share snippets: Upload ~/.config/pet/snippets.toml
- Backup snippets: cp ~/.config/pet/snippets.toml backup/

### tips

- Create aliases for frequently used snippets: alias myfunc='pet search'
- Document complex commands as snippets instead of comments
- Use tags to organize snippets by category
- Combine with fzf for fuzzy search experience
- Backup snippets regularly - they're valuable

### compare

- bash history: Unorganized, easy to lose
- pet: Organized, searchable, persistent
- Man pages: Complex to read
- pet: Simple description + example

### advantages

- Simpler than writing scripts for one-off commands
- Better than trying to remember complex commands
- Easier than searching through bash history
- Portable configuration files
- Built-in editor for easy management

### related

- Install pet: install-pet
- Interactive search: fzf-help
- Text search: ripgrep-help
- Zsh shell: zsh-help

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/pet.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/pet.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
