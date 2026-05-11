---
name: confluence:page
description: >-
  Transform markdown technical documentation into Confluence-formatted guides
  with structured problem-solution-results format.
---

# confluence:page

## Invocation

```bash
# Generate Confluence page from markdown file
/confluence:page docs/technic/parallel-testing-with-xdist.md

# Specify category
/confluence:page docs/analysis/docker-optimization.md --category infrastructure

# Generate for all docs in directory
/confluence:page docs/technic/
```

## What It Does

1. **Reads markdown file** or directory of files
2. **Extracts metadata** (title, author, date, git info)
3. **Analyzes content** (problem, cause, solution, results)
4. **Generates TL;DR** (3-line executive summary)
5. **Estimates difficulty** (1 to 5)
6. **Formats output** in Confluence markdown
7. **Saves to** `rca-knowledge/docs/confluence-guides/{category}/YYYY-MM-DD-{title}.md`

## Output Format

```markdown
# Parallel Testing with pytest-xdist

**작성자**: Your Name | **일정**: 2026-01-27
**카테고리**: testing | **난이도**: 3

## TL;DR (1분 요약)
- pytest-xdist로 테스트 3-4배 속도 향상 (250s → 8s)
- Worker별 격리 환경으로 간헐적 실패 제거
- 모든 pytest 프로젝트에 적용 가능

## 문제 (Problem)
- **현상**: 275개 테스트가 250초 소요
- **영향**: 개발자 피드백 지연

## 원인 (Root Cause)
Sequential test execution bottleneck

## 해결 (Solution)
### 1단계: pytest-xdist 설치
\`\`\`bash
pip install pytest-xdist
\`\`\`

## 성과 (Results)
- [OK] 테스트 시간: 250s → 8s (31배 향상)
- [OK] 안정성: 간헐적 실패 100% 제거
- [OK] 영향: 모든 개발자의 피드백 시간 단축

## 적용 범위
- [OK] Python 3.7+
- [OK] pytest 5.0+
- [OK] All test frameworks

## 참고 링크
- [pytest-xdist 문서](https://pytest-xdist.readthedocs.io)
- Git: abc1234
```

## Input Data

- **Primary**: Markdown files from `docs/technic/` or `rca-knowledge/docs/analysis/`
- **Secondary**: Git metadata (author, date, commit)
- **Optional**: Content structure (Heading hierarchy, code blocks)

## Success Criteria

[OK] Extracts problem statement accurately
[OK] Identifies root cause from context
[OK] Generates 3-line TL;DR (each ≤15 words)
[OK] Estimates difficulty (1-5)
[OK] Produces valid Confluence markdown
[OK] Saves with proper filename (YYYY-MM-DD-title.md)
[OK] Organizes by category
[OK] Preserves code blocks and formatting
