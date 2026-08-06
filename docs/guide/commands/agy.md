# agy

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/agy_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic agy --force`

## 호출

- Help 진입점: `agy-help [section|--list|--all]`
- 통합 라우팅: `my-help agy [section]`
- Alias: `agy-help`

## 요약 (agy-help)

- Usage: agy-help [section|--list|--all]
- sections
    - basic: agy-version | agy-continue | agy-plan | agy-models
    - setup: agy-install | agy-uninstall
    - tips: OAuth token dir | agy install PATH conflict
    - details: agy-help <section>  (example: agy-help basic)

## 섹션

### basic

- **agy-version** — agy --version — Check version
- **agy-continue** — agy --continue — Continue recent conversation
- **agy-plan** — agy --mode plan — Run in plan mode
- **agy-models** — agy models — List available models

### setup

- **agy-install** — Install Script — Install Antigravity CLI
- **agy-uninstall** — Uninstall Script — Remove Antigravity CLI

### tips

- OAuth token stored in ~/.gemini/antigravity-cli/
- Use 'agy --help' for detailed CLI options
- Model list changes often — run 'agy models' directly rather than relying on the 'agy-models' alias
- agy install edits shell profiles; PATH SSOT is shell-common/env/path.sh
- Prefer: agy install --skip-path --skip-aliases

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/agy.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/agy_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
