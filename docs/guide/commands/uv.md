# uv

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/package_managers_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic uv --force`

## 호출

- Help 진입점: `uv-help [section|--list|--all]`
- 통합 라우팅: `my-help uv [section]`
- Alias: `uv-help`

## 요약 (uv-help)

- Usage: uv-help [section|--list|--all]
- sections
    - sync: uvs | uvu | uvd | uv-install
    - lock: uvk | uvl | uvc | uvr
    - maintenance: uvcheck
    - recipes: --all-extras | backend dev | frontend dev
    - details: uv-help <section>  (example: uv-help recipes)

## 섹션

### sync

- **uvs** — uv sync — Sync env & prune (Prod)
- **uvu** — uv sync --upgrade — Upgrade deps
- **uvd** — uv sync --dev — Dev install
- **uv-install** — install script — Install UV tool

### lock

- **uvk** — uv lock — Refresh lockfile
- **uvl** — uv pip list — List packages
- **uvc** — uv pip compile — Export requirements
- **uvr** — uv pip sync — Sync from reqs

### maintenance

- **uvcheck** — uv pip check — Verify env

### recipes

- Install all extras: uv pip sync --all-extras
- Backend dev:      uv pip sync --extra backend --extra dev
- Frontend dev:     uv pip sync --extra frontend --extra dev

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/uv.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/package_managers_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
