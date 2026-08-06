# fasd

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/fasd.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic fasd --force`

## 호출

- Help 진입점: `fasd-help [section|--list|--all]`
- 통합 라우팅: `my-help fasd [section]`
- Alias: `fasd-help`

## 요약 (fasd-help)

- Usage: fasd-help [section|--list|--all]
- sections
    - core: z | zz | f | ff
    - ranking: frequency | recency | combined
    - patterns: z pro | z my pro | z /tmp | z -l
    - advanced: -r | -t | -e | -d
    - usecases: jump dirs | file ops | dir ops
    - tips: partial match | multiple terms | -l | -d
    - compare: cd vs z
    - integration: fzf | vim | grep | git
    - trouble: -l verify | reset history
    - related: install-fasd | fzf-help
    - details: fasd-help <section>  (example: fasd-help core)

## 섹션

### core

- **z <dir>** — Jump to recently used directory
- **zz <dir>** — Thorough search, jump to directory
- **f <file>** — Open/edit recently used file
- **ff <file>** — Thorough search, open file

### ranking

- Frequency - How often you visit (w weight)
- Recency - How recently you visited (time decay)
- Combined score determines ranking
- Most relevant items appear first

### patterns

- **z pro** — Match 'project' (partial)
- **z my pro** — Match 'my_project' (multiple terms)
- **z /tmp** — Match full path
- **z -l** — List directory frecency data

### advanced

- **z -r <dir>** — Interactive ranking (by recency)
- **z -t <dir>** — Interactive ranking (by frequency)
- **z -e <dir>** — Echo directory path without jumping
- **z -d <dir>** — Delete frecency data for directory

### usecases

- Quick directory jumping:
- z docs - Jump to most recent 'docs' directory
- z project - Navigate to project directory
- z dev src - Jump to 'dev/src' or 'src/dev'
- File operations:
- vim $(f project) - Edit file from project directory
- cat $(f config) - View config file
- ls $(zz search) - List files in search directory
- Directory operations:
- cd $(z downloads) && ls - Navigate and list files
- z -e config > path.txt - Save directory path to file
- cp file.txt $(z backup)/ - Copy to backup directory

### tips

- No exact match needed: 'z pj' may match 'project'
- Multiple patterns: 'z my config' for more specificity
- View all matches: 'z -l' to see frecency database
- Clean history: 'z -d /old/path' to remove from database
- Combine with pipes: 'z config | xargs grep pattern'

### compare

- cd - Requires full/exact path
- z - Requires only partial, fuzzy matching
- fasd learns from usage patterns over time
- No need to remember exact directory structure

### integration

- Works well with:
- fzf - Combine for interactive selection: z -i
- vim/neovim - Quick file access: :e $(f pattern)
- grep - Search in recent directories: grep -r pattern $(z proj)
- git - Navigate git repos: z my_repo && git status

### trouble

- Not jumping? 'z -l' to verify directory is recorded
- Wrong directory? Use more specific patterns
- Reset history: Remove ~/.local/share/fasd/data
- Verify installation: 'fasd --version'

### related

- Install fasd: install-fasd
- Fuzzy finder: fzf-help
- File manager: z -i (interactive mode)

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/fasd.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/fasd.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
