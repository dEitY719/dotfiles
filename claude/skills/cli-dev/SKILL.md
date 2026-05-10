---
name: cli-dev
description: >-
  CLI feature development skill. Implements CLI commands that wrap backend API
  endpoints. Follows TDD workflow with pytest, Rich console formatting, and
  session management. Use when implementing REQ-CLI-* requirements.
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# CLI Feature Development

## Help

If args is `-h`/`--help`/`help`, read `references/help.md` verbatim and stop.

## Role

You are the CLI Development Specialist. Implement CLI commands that wrap
backend API endpoints for developer testing. Use TDD (pytest), Rich for
console output, manage session state through `CLIContext`.

## Trigger Scenarios

"REQ-CLI-AUTH-1 구현해", "CLI 에 survey schema 명령어 추가", "auth login 만들어" 등 — `REQ-CLI-*` 구현 요청 전반.

## Tech Stack & Project Layout

cmd2 · rich · httpx · pytest+unittest.mock. 코드: `src/cli/{main,context,client}.py` + `src/cli/actions/<domain>.py`. 테스트: `tests/cli/test_<domain>_actions.py`.

## Arguments

| Option | Description | Default |
|--------|-------------|---------|
| `<REQ-CLI-id>` | 구현할 요구사항 ID (예: `REQ-CLI-AUTH-1`) | 필수 |
| `-h` / `--help` / `help` | `references/help.md` 출력 후 종료 | — |

## Workflow (stop on first failure — 어느 Step 이든 실패 시 즉시 중단)

### Step 1: Read Requirement

`docs/CLI-FEATURE-REQUIREMENTS.md` 에서 다음 키를 추출:

```yaml
req_id: REQ-CLI-AUTH-1
command: "auth login [username]"
api_endpoint: "POST /auth/login"
session_state: ["token", "user_id"]
error_cases: ["server error", "invalid input"]
```

요구사항이 파일에 없으면 stop + `[FAIL] cli-dev — Step 1: REQ-CLI-id 미발견`.

### Step 2: Write Tests First (TDD)

Read `references/test-template.md` and create `tests/cli/test_<domain>_actions.py`.
최소 3 시나리오 (success / missing-arg / api-error).

### Step 3: Implement Action Handler

Read `references/action-template.md` and create `src/cli/actions/<domain>.py`.
`references/patterns.md` 의 5 패턴 + 출력 포맷 + 명명 규칙 일관 적용.

### Step 4: Run Tests

```bash
pytest tests/cli/test_<domain>_actions.py -v
```

실패 테스트가 있으면 stop.

### Step 5: Run Quality Checks

```bash
ruff check --fix src/cli/
ruff format src/cli/
```

`references/patterns.md` 끝의 Validation Checklist 점검 후 Output 단계로.

## Output

성공 시:

```
[OK] cli-dev — REQ-CLI-<scope>-<n> implemented
  files:
    src/cli/actions/<domain>.py
    tests/cli/test_<domain>_actions.py
  tests: <n_passed>/<n_total> passed
  lint:  clean

Next: /gh:commit
```

실패 시:

```
[FAIL] cli-dev — Step <n>: <reason>
```
