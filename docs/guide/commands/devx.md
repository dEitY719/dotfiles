# devx

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/devx_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic devx --force`

## 호출

- Help 진입점: `devx-help [section|--list|--all]`
- 통합 라우팅: `my-help devx [section]`

## 요약 (devx-help)

- Usage: devx help [section|--list|--all]
- sections
    - lint           devx lint                  mise run lint (read-only)
    - fix            devx fix                   mise run fix  (mutating)
    - lint-helpfunc  devx lint-helpfunc         help-function registration check
    - lint-deadcode  devx lint-deadcode         unused _internal function check
    - stat           devx stat                  repo statistics (repo_stats.sh)
    - details        devx help <section> (example: devx help fix)

## 섹션

### lint

- **syntax** — devx lint — Run mise run lint (read-only)
- **scope** — ruff check + ruff format --check + mypy + shellcheck + shfmt -d — All language gates
- **behavior** — No file mutations — Safe for CI / pre-commit

### fix

- **syntax** — devx fix — Run mise run fix (mutating)
- **scope** — ruff check --fix + ruff format + shfmt -w — Python + Shell auto-fix
- **deprecated** — devx fmt / devx format — Routed to fix with a one-time warning

### lint_helpfunc

- **syntax** — devx lint-helpfunc — Audit help-function registration
- **checks** — Every public *_help in shell-common/functions/ — Must appear in HELP_DESCRIPTIONS
- **exit** — 0 = all registered, 1 = unregistered helpers found — Pre-commit gate candidate

### lint_deadcode

- **syntax** — devx lint-deadcode — Find unused _internal functions
- **checks** — ^_<name>() definitions in shell-common/functions/ — 1 ref = likely dead code
- **exit** — 0 = all in use, 1 = unused detected — Cleanup hint, not a hard gate

### stat

- **syntax** — devx stat [args] — Run shell-common/tools/custom/repo_stats.sh
- **behavior** — Args passed through to repo_stats.sh — See repo_stats.sh -h for details

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/devx.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/devx_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
