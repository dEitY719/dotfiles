# mysql

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/database_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic mysql --force`

## 호출

- Help 진입점: `mysql-help [section|--list|--all]`
- 통합 라우팅: `my-help mysql [section]`
- Alias: `mysql-help`

## 요약 (mysql-help)

- Usage: mysql-help [section|--list|--all]
- sections
    - service: mysql_list | mysql_dmc_dev | mysql_dmc_test | mysql_cmd | mysql_server
    - details: mysql-help <section>  (example: mysql-help service)

## 섹션

### service

- **mysql_list** — List configured services — Show all database connections
- **mysql_dmc_dev** — Connect to dev database — Use .my.cnf config
- **mysql_dmc_test** — Connect to test database — Use .my.cnf config
- **mysql_cmd <svc> <cmd>** — Execute SQL command — databases, tables, version, describe, status, etc.
- **mysql_server <action>** — Manage service — start, stop, restart, status, reload

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/mysql.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/database_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
