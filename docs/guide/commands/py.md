# py

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/py_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic py --force`

## 호출

- Help 진입점: `py-help [section|--list|--all]`
- 통합 라우팅: `my-help py [section]`
- Alias: `py-help`

## 요약 (py-help)

- Usage: py-help [section|--list|--all]
- sections
    - commands: cv | av | ev | rv | dv
    - setup: install-py | uninstall-py
    - details: py-help <section>  (example: py-help commands)

## 섹션

### commands

- **create-venv (cv)** — python -m venv .venv — Create venv
- **act-venv (av)** — . .venv/bin/activate — Activate
- **echo-venv (ev)** — echo $VIRTUAL_ENV — Show path
- **rm-venv (rv)** — rm -rf .venv — Delete venv
- **deact-venv (dv)** — . deactivate — Deactivate

### setup

- **install-py [version...]** — Install Script — Install default or specific Python versions
- **uninstall-py <version>** — pyenv uninstall — Remove a specific Python version

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/py.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/py_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
