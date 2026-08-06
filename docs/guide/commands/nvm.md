# nvm

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/nvm_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic nvm --force`

## 호출

- Help 진입점: `nvm-help [section|--list|--all]`
- 통합 라우팅: `my-help nvm [section]`
- Alias: `nvm-help`

## 요약 (nvm-help)

- Usage: nvm-help [section|--list|--all]
- sections
    - commands: nvm-install
    - usage: nvm install --lts | nvm use --lts | nvm ls
    - details: nvm-help <section>  (example: nvm-help usage)

## 섹션

### commands

- **nvm-install** — Install Script — Install NVM & Node LTS

### usage

- nvm install --lts  : Install latest LTS Node
- nvm use --lts      : Use latest LTS Node
- nvm ls             : List installed versions

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/nvm.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/nvm_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
