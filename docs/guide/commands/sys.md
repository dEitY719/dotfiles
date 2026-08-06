# sys

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/system_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic sys --force`

## 호출

- Help 진입점: `sys-help [section|--list|--all]`
- 통합 라우팅: `my-help sys [section]`
- Alias: `sys-help`

## 요약 (sys-help)

- Usage: sys-help [section|--list|--all]
- sections
    - process: psgrep | psg | kill9 | psa
    - network: ports | myip | localip | ping | check-network | ssh-help
    - monitoring: top | meminfo | cpuinfo | diskusage
    - apt: update | upgrade | remove | auto-remove
    - logs: logs | error | auth
    - details: sys-help <section>  (example: sys-help network)

## 섹션

### process

- **psgrep** — ps aux | grep <pattern> — Find process by pattern
- **psg** — ps aux | grep — Find process
- **kill9** — kill -9 — Force kill
- **psa** — ps aux — List all processes

### network

- **ports** — ss -tulanp — Show open ports
- **myip** — curl ipecho.net — Public IP
- **localip** — hostname -I — Local IP
- **ping** — ping -c 5 — Ping (5 times)
- **check-network** — check-network — Internet connectivity diagnostics
- **ssh-help** — ssh-help — SSH hosts and examples

### monitoring

- **top** — htop — Process monitor
- **meminfo** — free -m — Memory usage
- **cpuinfo** — lscpu — CPU info
- **diskusage** — df -h — Disk usage

### apt

- **update** — apt update — Update lists
- **upgrade** — apt upgrade — Upgrade packages
- **remove** — apt remove — Remove package
- **auto-remove** — apt autoremove — Remove unused

### logs

- **logs** — syslog — System logs
- **error** — error.log — Error logs
- **auth** — auth.log — Auth logs

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/sys.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/system_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
