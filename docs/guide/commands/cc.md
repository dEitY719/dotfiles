# cc

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/cc_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic cc --force`

## 호출

- Help 진입점: `cc-help [section|--list|--all]`
- 통합 라우팅: `my-help cc [section]`
- Alias: `cc-help`

## 요약 (cc-help)

- Usage: cc-help [section|--list|--all]
- sections
    - install: npm install -g ccusage
    - commands: ccd | ccs | ccb
    - details: cc-help <section>  (example: cc-help commands)

## 섹션

### install

- Global prefix: npm install -g ccusage --prefix=$HOME/.npm-global

### commands

- **ccd** — ccusage daily --breakdown — Token usage by model
- **ccs** — ccusage session --sort tokens — Session analysis
- **ccb** — ccusage blocks --live — Cache hit ratio (live)

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/cc.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/cc_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
