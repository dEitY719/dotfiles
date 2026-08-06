# du

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/system_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic du --force`

## 호출

- Help 진입점: `du-help [section|--list|--all]`
- 통합 라우팅: `my-help du [section]`
- Alias: `du-help`

## 요약 (du-help)

- Usage: du-help [section|--list|--all]
- sections
    - commands: dus | dud | dsql | dubig
    - tips: -h means human-readable (K, M, G)
    - details: du-help <section>  (example: du-help commands)

## 섹션

### commands

- **dus** — du -sh . — Current dir summary
- **dud** — du -sh * — Subdir summary (sorted)
- **dsql** — du .sql — SQL dump sizes
- **dubig** — du top 10 — Top 10 largest items

### tips

- Tip: -h option means 'human-readable' (K, M, G)

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/du.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/system_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
