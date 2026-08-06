# gc

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/gc_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic gc --force`

## 호출

- Help 진입점: `gc-help [section|--list|--all]`
- 통합 라우팅: `my-help gc [section]`
- Alias: `gc-help`

## 요약 (gc-help)

- Usage: gc-help [section|--list|--all]
- sections
    - basic: gc | gca
    - options: --amend | --no-verify | --signoff
    - details: gc-help <section>  (example: gc-help basic)

## 섹션

### basic

- **gc** — git commit -m — Commit with message
- **gca** — git commit --amend — Amend last commit

### options

- **--amend** — git commit --amend — Modify last commit
- **--no-verify** — git commit --no-verify — Skip pre-commit hooks (use sparingly)
- **--signoff** — git commit -s — Add Signed-off-by trailer

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/gc.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/gc_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
