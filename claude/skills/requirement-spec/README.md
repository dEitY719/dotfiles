# REQ Feature Definition Skill

Convert free-form requirements into structured REQ format.

## Usage

```
User: "고객이 사용자 접속 이력 조회 기능을 요청했어"
User: "프로필 페이지에 배지 표시 기능 추가해"
User: "CLI에 세션 저장 명령어 필요해"
```

## What It Does

1. **Parse** natural language requirement
2. **Classify** type (Frontend/Backend/CLI/Agent)
3. **Assign** priority (H/M/L)
4. **Generate** unique REQ-ID (duplicate check)
5. **Create** structured requirement document

## REQ-ID Format

```
REQ-[TYPE]-[CATEGORY]-[NUMBER]

Examples:
  REQ-F-Login-1     (Frontend)
  REQ-B-Access-1    (Backend)
  REQ-CLI-Session-1 (CLI)
  REQ-A-Scoring-1   (Agent)
```

## Output

Generates markdown ready for `docs/feature_requirement_mvp1.md`:

- REQ ID and title
- Description
- Use case examples
- Expected output
- Error cases
- Acceptance criteria
- Dependencies

## Next Steps After Definition

```
# Add to requirement file
Copy markdown to: docs/feature_requirement_mvp1.md

# Start development
> "REQ-B-Access-1 개발해"
```

## Related Skills

- `req-workflow` - Execute 4-phase development after REQ is defined
