# ripgrep

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/ripgrep.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic ripgrep --force`

## 호출

- Help 진입점: `ripgrep-help [section|--list|--all]`
- 통합 라우팅: `my-help ripgrep [section]`
- Alias: `ripgrep-help`

## 요약 (ripgrep-help)

- Usage: ripgrep-help [section|--list|--all]
- sections
    - concept: fast | gitignore | parallel | binary-safe
    - basic: pattern | path | file
    - case: smart | -i | -S
    - pattern: regex | -F | -w | -x
    - output: -n | -c | -l | -o
    - filter: -t | -T | --type-list | -g
    - scope: -u | -uu | -j 1
    - context: -B | -A | -C
    - examples | compare | fzf | config | trouble | related
    - details: ripgrep-help <section>  (example: ripgrep-help basic)

## 섹션

### concept

- Rust-based grep replacement - much faster than grep
- Respects .gitignore automatically - avoids unwanted files
- Automatic parallelization - uses all available CPU cores
- Handles binary files gracefully

### basic

- **rg 'pattern'** — Search for pattern in current directory
- **rg 'pattern' /path** — Search in specific directory
- **rg 'pattern' file.txt** — Search in specific file

### case

- **rg 'pattern'** — Smart case (sensitive if pattern has uppercase)
- **rg -i 'pattern'** — Case-insensitive search
- **rg -S 'pattern'** — Case-sensitive (always)

### pattern

- **rg 'regex'** — Regular expression search (default)
- **rg -F 'literal'** — Literal string search (no regex)
- **rg -w 'word'** — Match whole words only
- **rg -x 'line'** — Match entire lines only

### output

- **rg -n 'pattern'** — Show line numbers (default)
- **rg -c 'pattern'** — Count matches per file
- **rg -l 'pattern'** — List filenames only
- **rg -o 'pattern'** — Show only matches, not whole lines

### filter

- **rg 'pattern' -t py** — Search in Python files only
- **rg 'pattern' -T py** — Exclude Python files
- **rg 'pattern' --type-list** — Show all available file types
- **rg 'pattern' -g '*.py'** — Glob pattern filtering

### scope

- **rg 'pattern'** — Search respecting .gitignore (default)
- **rg -u 'pattern'** — Skip .gitignore (search hidden/ignored)
- **rg -uu 'pattern'** — Skip .gitignore and .ignore files
- **rg -j 1 'pattern'** — Single-threaded search

### context

- **rg -B 3 'pattern'** — Show 3 lines before match
- **rg -A 3 'pattern'** — Show 3 lines after match
- **rg -C 3 'pattern'** — Show 3 lines before and after

### examples

- Search in specific file type:
- rg 'TODO' -t py - Find TODO comments in Python files
- rg 'import' -t js src/ - Find imports in JavaScript source
- Search with context:
- rg -C 2 'function' - See function definitions with context
- rg -B 5 'error' - Show error messages with preceding context
- Counting and statistics:
- rg -c 'pattern' | sort -t: -k2 -rn - Count occurrences by file
- rg 'pattern' -c --sort=count - Show most frequent matches
- Replace with sed integration:
- rg 'old' -l | xargs sed -i 's/old/new/g' - Replace in all matched files
- rg 'pattern' --files-with-matches | xargs -I {} sh -c 'echo {}; rg pattern {}'

### compare

- grep: Standard but slow, easy regex syntax
- rg: Much faster (50-100x), auto .gitignore support
- rg: Better output formatting, sensible defaults
- rg: No need for -r flag for recursion

### fzf

- rg 'pattern' | fzf - Interactive result selection
- vim $(rg -l 'pattern' | fzf) - Open matched file in vim
- rg --files | fzf - Find file then search in it

### config

- Create ~/.ripgreprc for default options:
- --color=auto - Always colorize output
- --max-columns=200 - Truncate long lines
- --smart-case - Smart case sensitivity

### trouble

- Not finding files? Use -u to skip .gitignore
- Slow search? Use -j 1 to disable parallelization
- Too much output? Use -l to list files only, or -c to count

### related

- Install ripgrep: install-ripgrep
- Fuzzy finder: fzf-help
- Fast find: fd-help
- File viewer: bat-help

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/ripgrep.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/ripgrep.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
