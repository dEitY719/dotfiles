# psql

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/database_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic psql --force`

## 호출

- Help 진입점: `psql-help [section|--list|--all]`
- 통합 라우팅: `my-help psql [section]`
- Alias: `psql-help`

## 요약 (psql-help)

- Usage: psql-help [section|--list|--all]
- sections
    - primary: psql_list | psql_bootstrap | psql_sync | psql_add | psql_del
    - lowlevel: psql_db | psql_user
    - details: psql-help <section>  (example: psql-help primary)

## 섹션

### primary

- **psql_list** — List Services — Show all configured connections
- **psql_bootstrap** — Create New — Full Setup: Create DB, User, Grant & Save
- **psql_sync** — Sync DBs — Scan server and add existing DBs to config
- **psql_add** — Add Link — Manually add a shortcut for existing DB
- **psql_del** — Remove — Remove service (and optionally drop DB)

### lowlevel

- **psql_db** — DB Ops — list, create, delete, grant
- **psql_user** — User Ops — list, create, attr, passwd, delete

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/psql.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/database_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
