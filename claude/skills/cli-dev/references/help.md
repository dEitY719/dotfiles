# cli-dev — Usage

## Synopsis

```
/cli-dev <REQ-CLI-id>
/cli-dev -h | --help | help
```

## Description

CLI 기능 구현 스킬. `docs/CLI-FEATURE-REQUIREMENTS.md`에 정의된
`REQ-CLI-*` 요구사항을 TDD 워크플로 (pytest + Rich + cmd2 + httpx) 로
구현한다. 새 action handler 와 매칭 테스트를 동시에 생성.

## Arguments

| Option | Description | Default |
|--------|-------------|---------|
| `<REQ-CLI-id>` | 구현할 요구사항 ID (예: `REQ-CLI-AUTH-1`) | 필수 |
| `-h` / `--help` / `help` | 본 사용법 출력 후 종료 | — |

## Workflow

1. Read requirement from `docs/CLI-FEATURE-REQUIREMENTS.md`
2. Write pytest tests first (TDD)
3. Implement action handler
4. Run tests
5. Run lint checks (`ruff check --fix` + `ruff format`)
6. Print structured verdict

## Output

성공 시 `[OK]` + 생성 파일·테스트 통과 수·다음 명령 hint.
실패 시 `[FAIL]` + 실패 단계 + 이유.

## Examples

```
/cli-dev REQ-CLI-AUTH-1
/cli-dev REQ-CLI-SURVEY-2
```

## Stop conditions

- 요구사항 ID 가 `docs/CLI-FEATURE-REQUIREMENTS.md`에 없을 때
- 어느 Step 이든 실패 시 즉시 중단 (다음 Step 진행 금지)

## See also

- `references/test-template.md` — Step 2 pytest 템플릿
- `references/action-template.md` — Step 3 action handler 템플릿
- `references/patterns.md` — 5 가지 코드 패턴 + 출력 포맷 + 명명 규칙
