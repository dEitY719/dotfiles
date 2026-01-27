# make-confluence Skill

Transform markdown technical documentation into Confluence-formatted guides.

## Quick Start

```bash
# Convert markdown file to Confluence guide
/make-confluence docs/technic/parallel-testing-with-xdist.md

# Specify category explicitly
/make-confluence docs/analysis/docker-optimization.md --category infrastructure

# Batch process directory
/make-confluence docs/technic/ --category testing
```

## How It Works

1. **Reads markdown** from input file
2. **Extracts structure**: Problem, Root Cause, Solution, Results
3. **Generates TL;DR**: 3-line executive summary (each ≤15 words)
4. **Estimates difficulty**: ⭐ to ⭐⭐⭐⭐⭐ rating
5. **Formats output**: Confluence-ready markdown
6. **Saves guide**: `rca-knowledge/docs/confluence-guides/{category}/YYYY-MM-DD-{title}.md`

## Output Example

```markdown
# Parallel Testing with pytest-xdist

**작성자**: Your Name | **일정**: 2026-01-27
**카테고리**: testing | **난이도**: ⭐⭐⭐

## TL;DR (1분 요약)
- pytest-xdist로 테스트 3-4배 속도 향상 (250s → 8s)
- Worker별 격리 환경으로 간헐적 실패 제거
- 모든 pytest 프로젝트에 적용 가능

## 문제 (Problem)
275 test cases taking 250 seconds...

## 해결 (Solution)
Use pytest-xdist plugin...

## 성과 (Results)
- ✅ 31x test performance improvement
- ✅ Eliminated flaky failures
```

## Features

**Content Detection**:
- Automatically identifies Problem, Solution, Results sections
- Preserves code blocks exactly as written
- Extracts git metadata (author, date)

**Metadata**:
- Category: testing, infrastructure, documentation, performance, security, communication, training, other
- Difficulty: ⭐ (1) to ⭐⭐⭐⭐⭐ (5) automatic estimation
- Git author and date: automatic from git history

**Output**:
- Valid Confluence markdown
- Structured sections with Korean headers
- Ready for copy-paste into Confluence
- Organized by category

## Implementation

**Tool**: `/home/bwyoon/dotfiles/shell-common/tools/custom/make_confluence.sh`

**Usage**:
```bash
make_confluence.sh <input_file> [--category {category}]
```

**Options**:
- `--category {category}`: Override detected category
- Input can be file or directory
- Auto-creates output directories

## Integration

Works with:
- `docs/technic/` markdown files
- `rca-knowledge/docs/analysis/` markdown files
- Any markdown with Problem/Solution structure

Output location:
- `rca-knowledge/docs/confluence-guides/{category}/YYYY-MM-DD-{title}.md`

## Next Steps

- Integration with `/make-jira` for weekly reports
- Automation of technical documentation pipeline
- Confluence API publishing (Phase P3)
- Metadata registry in `rca-knowledge/_index.json`
