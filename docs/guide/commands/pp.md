# pp

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/pp_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic pp --force`

## 호출

- Help 진입점: `pp-help [section|--list|--all]`
- 통합 라우팅: `my-help pp [section]`
- Alias: `pp-help`

## 요약 (pp-help)

- Usage: pp-help [section|--list|--all]
- sections
    - package: pp_install | pp_install_up | pp_reqs | pp_uninstall | pp_freeze | pp_list | pp_check
    - quality: code_check | code_fix | code_type
    - test: test_pytest | test_unittest
    - docs: docs_gen
    - details: pp-help <section>  (example: pp-help quality)

## 섹션

### package

- **pp_install** — pip install — Install package
- **pp_install_up** — upgrade pip & install — Update pip first
- **pp_reqs** — pip install -r reqs — Install from file
- **pp_uninstall** — pip uninstall -y — Remove package
- **pp_freeze** — Freeze to reqs.txt — Exclude project name
- **pp_list** — pip list --outdated — Check updates
- **pp_check** — pip check — Verify deps

### quality

- **code_check** — ruff format & check — CI mode (check only)
- **code_fix** — ruff format & fix — Auto-fix issues
- **code_type** — mypy . — Type checking

### test

- **test_pytest** — pytest -q — Run pytest (fast)
- **test_unittest** — unittest discover — Run unittest

### docs

- **docs_gen** — sphinx build — Generate HTML docs

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/pp.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/pp_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
