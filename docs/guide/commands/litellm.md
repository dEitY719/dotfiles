# litellm

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/ai_tools_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic litellm --force`

## 호출

- Help 진입점: `litellm-help [section|--list|--all]`
- 통합 라우팅: `my-help litellm [section]`
- Alias: `litellm-help`, `llm-help`

## 요약 (litellm-help)

- Usage: litellm-help [section|--list|--all]
- sections
    - basic: llm-start | llm-stop | llm-restart | llm-status | llm-models | llm-test
    - info: Path | URL | Key
    - details: litellm-help <section>  (example: litellm-help basic)

## 섹션

### basic

- **llm-start** — Start Stack — docker compose up
- **llm-stop** — Stop Stack — docker compose down
- **llm-restart** — Restart — Stop & Start
- **llm-status** — Status — Check health & models
- **llm-models** — List Models — Show loaded models
- **llm-test** — Test Model — Run basic prompt

### info

- **Path** — 
- **URL** — 
- **Key** — 

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/litellm.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/ai_tools_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
