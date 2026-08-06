# gbr

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/git_branch.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic gbr --force`

## 호출

- Help 진입점: `gbr-help [section|--list|--all]`
- 통합 라우팅: `my-help gbr [section]`
- Alias: `gbr-help`

## 요약 (gbr-help)

- Usage: gbr-help [section|--list|--all]
- sections
    - teardown: gbr teardown [--force] [--keep-branch] [--discard-changes]
    - details: gbr-help <section> (example: gbr-help teardown)

## 섹션

### teardown

- **syntax** — gbr teardown [--force] [--keep-branch] [--discard-changes] — Cleanup merged feature branch
- **context** — Run from the feature branch (not main, not worktree) — Switches to main, pulls, deletes current branch
- **signal** — Detects '[gone]' upstream as PR-merged — Blocks otherwise; use --force to override
- **flags** — --force / --keep-branch / --discard-changes — Skip merge-status checks (non-destructive) / sync main only / DESTRUCTIVE overwrite of local changes

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/gbr.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/git_branch.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
