# cli

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/cli_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic cli --force`

## 호출

- Help 진입점: `cli-help [section|--list|--all]`
- 통합 라우팅: `my-help cli [section]`
- Alias: `cli-help`

## 요약 (cli-help)

- Usage: cli-help [section|--list|--all]
- sections
    - repos: dotfiles | FinRx | dmc-playground
    - urls: DEV | TEST | PROD
    - finrx: run_fr_cli
    - dmc: run_bes | run_tbes | run_pbes | run_api_cli | run_db_cli
    - smt: run_smt | run_tsmt | run_psmt
    - tips: project root | uv venv | no --reload in prod
    - details: cli-help <section>  (example: cli-help repos)

## 섹션

### repos

- **dotfiles** — ✨
- **FinRx** — 💰
- **dmc-playground** — 📚

### urls

- **DEV** —  (port ) — smithery-playground
- **TEST** —  (port ) — smithery-playground
- **PROD** —  (port ) — smithery-playground

### finrx

- **run_fr_cli** — python ./src/ticker_library/cli/cli.py — Run CLI

### dmc

- **run_bes** — Backend dev server (reload) — DEV: 
- **run_tbes** — Backend test server (reload) — TEST: 
- **run_pbes** — Backend prod server (no reload) — PROD: 
- **run_api_cli [URL]** — API CLI (default: DEV) — Query/test API
- **run_db_cli [URL]** — DB CLI (default: DEV) — Query/test database

### smt

- **run_smt** — Dev server (reload) — URL: 
- **run_tsmt** — Test server (reload) — URL: 
- **run_psmt** — Prod server (no reload) — URL: 

### tips

- Run from project root (current: )
- Recommend uv/pyproject-based venv (uvs/uvd)
- Never use --reload in production

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/cli.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/cli_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
