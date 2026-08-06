# dir

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/system_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic dir --force`

## 호출

- Help 진입점: `dir-help [section|--list|--all]`
- 통합 라우팅: `my-help dir [section]`
- Alias: `dir-help`

## 요약 (dir-help)

- Usage: dir-help [section|--list|--all]
- sections
    - core: cd-dot | cd-down | cd-work
    - windows: cd-wdocu | cd-wobsidian | cd-wdown | cd-wpicture | cd-tilnote | cd-obsidian
    - para: mkpara | cd-para | cd-project | cd-area | cd-vault | cd-resource | cd-archive
    - copy: cp_wdown
    - details: dir-help <section>  (example: dir-help para)

## 섹션

### core

- **Command** — Destination — Purpose
- **cd-dot** — $DOTFILES_ROOT — Dotfiles repository root
- **cd-down** — $HOME/downloads — Downloads folder
- **cd-work** — $HOME/workspace — Workspace root

### windows

- **Command** — Destination — Purpose
- **cd-wdocu** — Windows Documents — Access Windows documents
- **cd-wobsidian** — Windows Obsidian — Obsidian vault location
- **cd-wdown** — Windows Downloads — Quick access to downloads
- **cd-wpicture** — Windows Pictures — Photo library
- **cd-tilnote** — Obsidian TilNote — TilNote vault
- **cd-obsidian** — Obsidian vault — Default vault in WSL

### para

- **Command** — Destination — Purpose
- **mkpara** — para/{archive,area,project,resource} — Create PARA directories
- **cd-para** — $HOME/para — PARA root
- **cd-project** — $HOME/para/project — Projects workspace
- **cd-area** — $HOME/para/area — Areas of responsibility
- **cd-vault** — $HOME/para/area/vault — Vault under Areas
- **cd-resource** — $HOME/para/resource — Reference materials
- **cd-archive** — $HOME/para/archive — Archived items

### copy

- **Command** — Usage — Purpose
- **cp_wdown** — cp_wdown [options] <file...> — Copy from Windows Downloads into WSL (run -h for details)

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/dir.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/system_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
