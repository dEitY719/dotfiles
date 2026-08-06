# ssh

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/security_ssh_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic ssh --force`

## 호출

- Help 진입점: `ssh-help [section|--list|--all]`
- 통합 라우팅: `my-help ssh [section]`
- Alias: `ssh-help`

## 요약 (ssh-help)

- Usage: ssh-help [section|--list|--all]
- sections
    - ssh: ssh <host> | ssh <host> <cmd>
    - scp: pull | push
    - hosts: registered hosts in ~/.ssh/config
    - config: ~/.ssh/config -> dotfiles/ssh/config
    - details: ssh-help <section>  (example: ssh-help hosts)

## 섹션

### ssh

- **ssh <host>** — ssh ssai-dev — Connect to server
- **ssh <host> <cmd>** — ssh ssai-dev 'ls /home' — Run remote command

### scp

- **pull** — scp <host>:<src> <dst> — Download from server
- **push** — scp <src> <host>:<dst> — Upload to server

### hosts

- github.samsungds.net
- Replica-Gerrit
- github.com
- ssai-*
- server-ssai-*
- ssai-dev
- ssai-ops
- server-ssai-ops-*
- ssai-ops
- server-ssai-ops-devops
- server-ssai-ops-jiravis
- server-ssai-ops-bwyoon

### config

- **config file** — ~/.ssh/config → dotfiles/ssh/config — Managed by dotfiles

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/ssh.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/security_ssh_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
