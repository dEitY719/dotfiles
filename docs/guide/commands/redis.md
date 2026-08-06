# redis

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/database_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic redis --force`

## 호출

- Help 진입점: `redis-help [section|--list|--all]`
- 통합 라우팅: `my-help redis [section]`
- Alias: `redis-help`

## 요약 (redis-help)

- Usage: redis-help [section|--list|--all]
- sections
    - commands: server-ctl | ping | info | monitor | dbsize | keys | flush | config-get | slowlog | clients | memory | install-redis
    - env: REDISCLI_AUTH | REDIS_DEFAULT_HOST | REDIS_DEFAULT_PORT
    - details: redis-help <section>  (example: redis-help commands)

## 섹션

### commands

- **redis-server-ctl <action>** — Manage service — start, stop, restart, status
- **redis-ping** — Health check — PING/PONG test
- **redis-info [section]** — Server info — server, memory, clients, etc.
- **redis-monitor** — Live monitor — Real-time command stream
- **redis-dbsize** — Key count — Current DB key count
- **redis-keys [pattern] [limit]** — Scan keys — SCAN with glob pattern (default: 20)
- **redis-flush <db|all>** — Flush data — Clear current DB or all DBs
- **redis-config-get <param>** — Config value — Get runtime config
- **redis-slowlog [count]** — Slow queries — Recent slow log entries
- **redis-clients** — Client list — Connected clients info
- **redis-memory** — Memory stats — Memory usage details
- **install-redis** — Install Redis — Interactive installer for WSL

### env

- **REDISCLI_AUTH** — Password — Auto-auth for all commands
- **REDIS_DEFAULT_HOST** — Server host — Default: 127.0.0.1
- **REDIS_DEFAULT_PORT** — Server port — Default: 6379

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/redis.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/database_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
