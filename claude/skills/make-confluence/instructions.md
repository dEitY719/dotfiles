# make-confluence: Detailed Implementation Instructions

## Overview

Transform markdown technical documentation into Confluence-formatted guides with structured Problem-Solution-Results sections, TL;DR summaries, and difficulty ratings.

## Input Data Sources

### Primary: Markdown Files

**Location**: `docs/technic/` or `rca-knowledge/docs/analysis/{category}/`

**Format**: Standard markdown with headings, code blocks, lists

Example:
```markdown
# Parallel Testing with pytest-xdist

## Problem
275 test cases take 250 seconds to run, slowing down developer feedback loop.

## Root Cause
Tests run sequentially without parallelization, one test at a time.

## Solution
Use pytest-xdist plugin to parallelize test execution across multiple workers.

### Installation
\`\`\`bash
pip install pytest-xdist
\`\`\`

### Configuration
Add to pytest.ini:
\`\`\`ini
[pytest]
addopts = -n auto
\`\`\`

## Results
- Test execution time: 250s → 8s (31x improvement)
- Eliminated flaky test failures from test isolation
- All developers get faster feedback
```

### Secondary: Git Metadata

For each file:
```bash
git log -1 --format="%an|%ai|%H" <file>
```

Extract:
- Author name
- Commit date (YYYY-MM-DD)
- Commit hash

### Optional: File Metadata

Comments in file:
```markdown
---
category: testing
difficulty: 3
tags: pytest, testing, performance
---
```

## Processing Steps

### Step 1: Read and Parse Markdown

1. Load file content
2. Extract frontmatter (if exists) for metadata
3. Parse heading hierarchy (H1, H2, H3, etc.)
4. Identify code blocks with ` ```language `
5. Extract paragraphs and lists

### Step 2: Analyze Content Structure

Detect sections by heading names (case-insensitive):
- **Problem**: "Problem", "Issue", "Symptom", "What's the problem"
- **Root Cause**: "Root Cause", "Cause", "Why", "Analysis"
- **Solution**: "Solution", "How to fix", "Implementation", "Approach"
- **Results**: "Results", "Outcome", "Impact", "Benefits"

Extract content between matching headers:
```bash
# If file has "## Problem" and "## Solution"
# Extract text between them as problem content
```

### Step 3: Generate TL;DR (3-Line Summary)

Rules for TL;DR generation:
1. **Line 1** (Issue/Impact): What's the problem? (max 15 words)
   - Example: "pytest-xdist로 테스트 3-4배 속도 향상 (250s → 8s)"
2. **Line 2** (Root Cause or Key Approach): Why or how? (max 15 words)
   - Example: "Worker별 격리 환경으로 간헐적 실패 제거"
3. **Line 3** (Applicability): Who benefits? (max 15 words)
   - Example: "모든 pytest 프로젝트에 적용 가능"

Algorithm:
```bash
# Extract key metrics from Results section
# Extract main problem from Problem section
# Extract approach from Solution section
# Combine into 3 bullets, each ≤15 words
```

### Step 4: Extract and Clean Content

For each detected section:
1. Remove intermediate headings
2. Preserve code blocks exactly
3. Convert lists to markdown bullets
4. Remove redundant text
5. Keep relevant examples

### Step 5: Estimate Difficulty Rating

Heuristic based on:
- Number of code blocks: More code = higher difficulty
- Number of prerequisites: Longer setup = higher
- Language complexity: Complex concepts = higher
- Conceptual depth: How abstract/advanced

Scoring:
```
⭐         = Simple configuration, no coding
⭐⭐       = Single config change + restart
⭐⭐⭐     = Multi-step setup, basic coding
⭐⭐⭐⭐   = Complex setup, advanced concepts
⭐⭐⭐⭐⭐ = Deep expertise required, many steps
```

### Step 6: Build Output Structure

Template:
```markdown
# {Title}

**작성자**: {Author} | **일정**: {Date}
**카테고리**: {Category} | **난이도**: {Rating}

## TL;DR (1분 요약)
- {Summary Line 1}
- {Summary Line 2}
- {Summary Line 3}

## 문제 (Problem)
{Problem content - 1-3 paragraphs}

## 원인 (Root Cause)
{Root cause analysis - short explanation}

## 해결 (Solution)
{Solution content with numbered steps/subsections}

## 성과 (Results)
{Results with metrics and impact}

## 적용 범위 (Applicability)
- ✓ Requirements/prerequisites
- ✓ Who should use this

## 추가 자료 (Additional Resources)
- Link 1
- Link 2
```

### Step 7: Determine Output Location

1. **Extract category** from:
   - Frontmatter `category:` field, OR
   - First parent directory name (`docs/technic/testing/` → "testing"), OR
   - User --category flag, OR
   - Default to "other"

2. **Valid categories**: testing, infrastructure, documentation, performance, security, communication, training, other

3. **Output path**:
   ```
   rca-knowledge/docs/confluence-guides/{category}/YYYY-MM-DD-{slug}.md

   Where {slug} = lowercase title with dashes
   Example: "Parallel Testing with pytest-xdist" → "parallel-testing-with-pytest-xdist"
   ```

### Step 8: Save Output

1. Create directory: `rca-knowledge/docs/confluence-guides/{category}/`
2. Filename: `YYYY-MM-DD-{slug}.md`
3. Content: Full formatted markdown
4. Encoding: UTF-8

If file exists:
```bash
backup_path="${output_path}.backup.${timestamp}"
mv "$output_path" "$backup_path"
# Create new file
```

## Implementation Checklist

- [ ] Read markdown file
- [ ] Extract git metadata (author, date)
- [ ] Parse markdown structure (headings, code blocks)
- [ ] Detect Problem/Cause/Solution/Results sections
- [ ] Generate TL;DR (3 lines, each ≤15 words)
- [ ] Estimate difficulty rating (⭐ 1-5)
- [ ] Extract and clean section content
- [ ] Determine category (frontmatter → directory → flag → default)
- [ ] Create output directory if needed
- [ ] Generate output filename (YYYY-MM-DD-slug)
- [ ] Write formatted markdown
- [ ] Verify structure validity
- [ ] Test with sample files

## Error Handling

### Missing Problem Section
```
Warning: Could not detect Problem section
Action: Use first non-heading paragraph as problem
```

### No Results Found
```
Warning: Could not detect Results section
Action: Skip Results section in output
```

### Invalid Category
```
Error: Unknown category '{category}'
Valid: testing, infrastructure, documentation, performance, security, communication, training, other
Solution: Use --category flag or add to frontmatter
```

### File Not Found
```
Error: Input file not found: {path}
Solution: Check path exists and is readable
```

### Git Metadata Missing
```
Warning: Git author/date could not be extracted
Action: Use file modification time and system user
```

## Success Criteria

- ✓ Reads markdown file successfully
- ✓ Detects all major sections
- ✓ TL;DR: exactly 3 lines, each ≤15 words
- ✓ Difficulty: single digit (1-5)
- ✓ Category: valid and consistent
- ✓ Filename: YYYY-MM-DD-{slug}.md format
- ✓ Output: valid markdown structure
- ✓ Code blocks: preserved exactly
- ✓ Directory: auto-created if missing
- ✓ Handles missing metadata gracefully

## Testing Strategy

### Test 1: Parse Sample Markdown
```bash
# Input: docs/technic/parallel-testing-with-xdist.md
# Verify sections extracted correctly
# Check TL;DR word counts
```

### Test 2: Git Metadata
```bash
# Verify author and date extracted from git
# Handle files not in git gracefully
```

### Test 3: Category Detection
```bash
# Test: docs/technic/testing/file.md → category: testing
# Test: --category flag override
# Test: frontmatter parsing
```

### Test 4: Output Format
```bash
# Verify markdown structure
# Check code blocks preserved
# Validate difficulty rating
```

### Test 5: Filename Generation
```bash
# "Parallel Testing..." → "parallel-testing-with-xdist"
# Check timestamp (YYYY-MM-DD) format
# Test special characters in title
```
