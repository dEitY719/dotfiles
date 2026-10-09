# jetbrain

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/jetbrain_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic jetbrain --force`

## 호출

- Help 진입점: `jetbrain-help [section|--list|--all]`
- 통합 라우팅: `my-help jetbrain [section]`
- Alias: `jetbrain-help`

## 요약 (jetbrain-help)

- Usage: jetbrain-help [section|--list|--all]
- sections
    - commands: pycharm [args...]
    - config: PYCHARM_BIN | JETBRAIN_HOME
    - details: jetbrain-help <section>  (example: jetbrain-help config)

## 섹션

### commands

- **pycharm [args...]** — Launch PyCharm — Binary resolved on every call

### config

- **$PYCHARM_BIN** — Explicit binary path — Checked first
- **$JETBRAIN_HOME** — Install root (default ~/application) — Newest pycharm-*/bin/pycharm wins
- Fallback: ~/application/pycharm-2025.2.0.1/bin/pycharm

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/jetbrain.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/jetbrain_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
