# llm-wiki

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/llm_wiki_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic llm_wiki --force`

## 호출

- Help 진입점: `llm-wiki-help [section|--list|--all]`
- 통합 라우팅: `my-help llm_wiki [section]`
- Alias: `llm-wiki-help`

## 요약 (llm-wiki-help)

- Usage: llm-wiki-help [section|--list|--all]
- vault 커맨드 (.claude/commands/)
    - /ingest [파일]: 99-Inbox 소스 1건 PARA 분류·이동 + 00-wiki 융합 (인자 없으면 큐 나열)
    - /query {질문}: 위키 근거 답변 (근거 없으면 없다고 선언)
    - /lint: 기계+판단 검사 보고서 (자동 수정 안 함)
    - /theme {주제}: 새 추적 테마 개설 + 기존 페이지 근거 수집
    - /archive {경로}: 40-Archive 로 이동 + 위키 링크 재작성 (이동은 이것만)
- 클립 스킬 (vault 밖)
    - /pkm:obsidian-web-clip <url>: 99-Inbox/Web/
    - /pkm:obsidian-session-clip: 99-Inbox/ai-session/
- flow: 클립 -> 99-Inbox -> /ingest -> 00-wiki · index.md · log.md
    - details: llm-wiki-help <section>  (sections: commands clip flow related)

## 섹션

### commands

- **/ingest [파일]** — 99-Inbox 소스 1건을 PARA 로 분류·이동하고 00-wiki 에 융합. 인자 없으면 큐 나열
- **/query {질문}** — 위키에 근거한 답변. 근거가 없으면 없다고 선언
- **/lint** — 기계 검사 + 판단 검사 보고서. 자동 수정하지 않음
- **/theme {주제}** — 새 추적 테마 개설 + 기존 페이지에서 근거 수집
- **/archive {경로}** — PARA 문서를 40-Archive 로 이동 + 위키 링크 재작성. 이동은 이 커맨드로만

### clip

- **/pkm:obsidian-web-clip <url>** — URL 을 99-Inbox/Web/ 에 클립
- **/pkm:obsidian-session-clip** — AI 세션을 99-Inbox/ai-session/ 에 클립
- 두 클리퍼는 Inbox 까지만 넣는다. 이후는 /ingest 담당

### flow

- 클립 (web-clip / session-clip) -> 99-Inbox -> /ingest -> 00-wiki · index.md · log.md

### related

- 원본 SSOT: obsidian-para AGENTS.md §4, .claude/commands/*.md, docs/guide/commands.md
- 커맨드 목록이 바뀌면 이 토픽도 수동 갱신 (자동 동기화 없음)
- 그래프: graphify-help

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/llm-wiki.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/llm_wiki_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
