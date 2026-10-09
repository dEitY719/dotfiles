# register

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/register_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic register --force`

## 호출

- Help 진입점: `register-help [section|--list|--all]`
- 통합 라우팅: `my-help register [section]`
- Alias: `register-help`

## 요약 (register-help)

- Usage: register-help [section|--list|--all]
- sections
    - topic: function ending with _help
    - description: _register_help <name>_help "<desc>" [category]
    - category: 3rd argument of the same _register_help row
    - details: register-help <section>  (example: register-help topic)

## 섹션

### topic

- Create a function ending with: _help
- Example: mytool_help() { ... }

### description

- Add a row in my_help.sh: _register_help mytool_help "[Development] ..." development

### category

- The row's 3rd argument appends mytool to that category (omit it to stay uncategorized)
- Then reload your shell (source ~/.bashrc or ~/.zshrc)

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/register.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/register_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
