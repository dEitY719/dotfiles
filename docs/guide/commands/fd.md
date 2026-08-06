# fd

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/fd.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic fd --force`

## 호출

- Help 진입점: `fd-help [section|--list|--all]`
- 통합 라우팅: `my-help fd [section]`
- Alias: `fd-help`

## 요약 (fd-help)

- Usage: fd-help [section|--list|--all]
- sections
    - concept: fast | gitignore | smart-case | colored
    - basic: pattern | path | regex
    - type: -t f | -t d | -t l | -t x
    - case: smart | -s | -i
    - extension: -e | -x
    - depth: -d 1 | -d 2 | -d 3
    - scope: -u | -H | --exclude
    - exec: -0 | -x
    - examples | compare | fzf | ripgrep | trouble | related
    - details: fd-help <section>  (example: fd-help basic)

## 섹션

### concept

- Rust-based find replacement - much faster than find
- Respects .gitignore automatically - avoids unwanted files
- Smart case sensitivity - case-insensitive unless pattern has uppercase
- Intuitive syntax - simpler than find command
- Colored output for better readability

### basic

- **fd 'pattern'** — Find files/directories matching pattern
- **fd 'pattern' /path** — Search in specific directory
- **fd '^file$'** — Regex pattern search

### type

- **fd -t f 'pattern'** — Find files only
- **fd -t d 'pattern'** — Find directories only
- **fd -t l 'pattern'** — Find symlinks only
- **fd -t x 'pattern'** — Find executable files only

### case

- **fd 'pattern'** — Smart case (case-insensitive by default)
- **fd -s 'pattern'** — Case-sensitive search
- **fd -i 'pattern'** — Case-insensitive (explicit)

### extension

- **fd -e .txt** — Find all .txt files
- **fd -e .py 'test'** — Find .py files matching pattern
- **fd -x 'name'** — Find executable files

### depth

- **fd -d 1 'pattern'** — Search only in current directory
- **fd -d 2 'pattern'** — Search up to 2 levels deep
- **fd -d 3 'pattern'** — Search up to 3 levels deep

### scope

- **fd 'pattern'** — Respects .gitignore (default)
- **fd -u 'pattern'** — Skip .gitignore (search ignored files)
- **fd -H 'pattern'** — Show hidden files/directories
- **fd --exclude 'dir' 'pattern'** — Exclude specific directory

### exec

- **fd -0 'pattern'** — NUL character separator (for xargs)
- **fd -x CMD 'pattern'** — Execute command for each result
- **fd -x echo '{}' 'pattern'** — Display full path of matches

### examples

- Finding specific file types:
- fd -e .py - Find all Python files
- fd -t f 'test' - Find all test files
- fd -t d 'node_modules' - Find all node_modules directories
- Finding without .gitignore:
- fd -u '.git' - Find all .git directories (including hidden)
- fd -H -t f '.env' - Find .env files (hidden)
- Integration with other tools:
- fd -e .rs | xargs wc -l - Count lines in all Rust files
- fd -x file {} - Determine file type of all results
- fd -x grep 'TODO' {} - Search for TODO in matched files
- Finding within depth limits:
- fd -d 1 '.*' - Find all files/dirs in current directory only
- fd -d 2 'src' - Find src directories up to 2 levels deep

### compare

- find: Standard but slow, complex syntax
- fd: Much faster (10-100x), simpler syntax, auto .gitignore support
- find: Full control, can be used in scripts
- fd: Better defaults, more intuitive

### fzf

- fd | fzf - Interactive file selection
- vim $(fd -e .txt | fzf) - Open selected file in vim
- fd --type f | fzf --preview 'cat {}' - Preview files

### ripgrep

- fd -e .py | xargs rg 'pattern' - Search pattern in Python files
- fd -t f | xargs grep -l 'TODO' - Find files with TODO comments

### trouble

- Case sensitivity issues? Use smart case or -s/-i flags
- Hidden files not showing? Use -H flag
- Gitignore being respected? Use -u to override
- Command too slow? Try limiting depth with -d flag

### related

- Install fd: install-fd
- Text search: ripgrep-help
- Fuzzy finder: fzf-help
- Directory access: fasd-help

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/fd.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/fd.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
