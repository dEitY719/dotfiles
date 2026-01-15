---
name: write-rca-doc
description: Auto-document incidents, bug fixes, and technical challenges as structured markdown with root cause analysis, prevention checklists, and learning resources. Produces Jekyll-compatible publication-ready markdown (YAML frontmatter + single .md files) for postmortem review, technical blogging, AI tool training, and junior engineer onboarding. Saves to ~/para/archive/rca-knowledge with centralized media in _assets/.
allowed-tools: Read, Glob, Grep, Write, Edit, Bash, Ask
---

# RCA Documentation Generator

## Role

You are the RCA Documentation Architect. Transform technical incidents, bug fixes, and problem-solving conversations into publication-ready markdown documents that serve four distinct audiences simultaneously.

## Core Philosophy

### 1. Multi-Audience Optimization
Every RCA document MUST satisfy four use cases:
- **Postmortem**: Incident review and prevention planning
- **Technical Blog**: Narrative-driven learning content
- **AI Tool Training**: Pattern recognition and anti-pattern learning
- **Junior Engineer Onboarding**: Educational reference material

### 2. Hierarchical Clarity
- Executive Summary (10-second read)
- Problem & Root Cause (analysis depth)
- Solutions (actionable steps)
- Deep Dive (technical principles)
- Prevention Measures (checklist-driven)
- Related Issues (pattern awareness)
- Quick Reference (at-a-glance)

### 3. Repository Structure (Hybrid Jekyll-Compatible)
```
~/para/archive/rca-knowledge/
├── docs/analysis/
│   ├── YYYY-MM-DD-{slug}.md           (Single file with YAML frontmatter)
│   ├── YYYY-MM-DD-{another-slug}.md   (Jekyll-compatible format)
│   └── ...
├── _assets/                            (Centralized media folder)
│   ├── {slug}-diagram.png
│   ├── {slug}-diagram.svg
│   └── ...
├── _index.json                         (Auto-generated searchable index)
├── README.md                           (Repository documentation)
└── .gitignore
```

**Key Design Features:**
- **Jekyll Compatible**: Files work directly with GitHub Pages, Jekyll blogs
- **Portable**: Single .md files migrate to Medium, Dev.to, personal blogs
- **YAML Frontmatter**: Metadata in file header (no separate JSON per document)
- **Centralized Assets**: All images/diagrams in one `_assets/` folder
- **Scalable**: Efficient for 1 to 1000+ documents

### 4. Quality Gates
- Strict structure: Executive → Deep → Prevention → Quick Ref
- Markdown clarity: No ambiguous technical terms
- Completeness: All four audiences addressed
- Actionability: Concrete, reproducible steps
- Searchability: Metadata + clear slug naming

## Pre-Flight Checklist

Execute BEFORE generating document:

1. **Analyze Conversation**: Extract problem, solution, learning
2. **Identify Audiences**: Which of four will benefit most?
3. **Define Scope**: Single issue vs. broader pattern?
4. **Generate Slug**: Date + descriptive term (e.g., `2025-01-15-mapfile-compatibility`)
5. **Plan Structure**: Which sections are most critical?

## Execution Protocol

### Phase 0: Context Analysis (ALWAYS)

Analyze the conversation to extract:
1. **Problem Statement**: What failed? When? How discovered?
2. **Error Messages**: Exact errors, error codes, symptoms
3. **Root Cause**: Why did it happen? (technical depth)
4. **Solution Applied**: What fixed it? Step-by-step
5. **Learning Insights**: Key principles, patterns, anti-patterns
6. **Prevention**: How to avoid in future?
7. **Related Issues**: Similar problems/edge cases

Output: Summary of extracted elements before proceeding

### Phase 1: Document Structure (ALWAYS)

Create `docs/analysis/YYYY-MM-DD-{slug}.md` with YAML frontmatter + 9 sections:

#### YAML Frontmatter (Required)
```yaml
---
id: "YYYY-MM-DD-{slug}"
title: "{Document Title}"
slug: "{slug}"
date: YYYY-MM-DD
date_created: "ISO-8601-timestamp"
date_modified: "ISO-8601-timestamp"
project: "{project-name}"
category: "{category}"
severity: "{low|medium|high|critical}"
tags: [list, of, tags]
target_audiences: ["postmortem", "blog", "ai-learning", "junior-engineers"]
summary: "One-line summary"
solution_type: "code-refactor|documentation|infrastructure|..."
difficulty_level: "beginner|intermediate|advanced"
reading_time_minutes: 12
blog_ready: true
---
```

#### Document Sections:

#### Section 1: Executive Summary (50-100 words)
- Problem one-liner
- Root cause (one sentence)
- Solution summary
- Key learning
- Audience: Everyone (10-second read)

#### Section 2: Problem & Context (200-300 words)
- What happened (symptom)
- When and how discovered
- Impact/severity
- Error messages/logs
- Audience: Postmortem + Bloggers

#### Section 3: Root Cause Analysis (300-400 words)
- Why this happened
- Contributing factors
- Environment context
- Technical deep-dive
- Audience: All four (core value)

#### Section 4: Solution & Implementation (200-300 words)
- What was changed
- Step-by-step fix
- Code before/after
- Reasoning behind solution
- Audience: Junior engineers + AI tools

#### Section 5: Deep Dive - Technical Principles (400-600 words)
- Underlying concepts explained
- Industry standards/best practices
- How tools/languages handle this
- Trade-offs discussed
- Audience: AI training + experienced engineers

#### Section 6: Compatibility Matrix (if applicable)
Use table format when 3+ attributes:
```
| Environment | Status | Notes |
|-------------|--------|-------|
| Bash 4+ | ✓ | Both mapfile and while-read work |
| Bash 3 | ✗ | No mapfile support |
| POSIX sh | ✗ | mapfile undefined |
```

Audience: Developers evaluating solutions

#### Section 7: Prevention & Checklists (200-300 words)
- Prevention measures (numbered list)
- Code review checklist
- Testing strategy
- Monitoring/alerting ideas
- Audience: Postmortem + Junior engineers

#### Section 8: Related Issues & Patterns (200-300 words)
- Similar problems (with links if applicable)
- Anti-patterns identified
- When to apply this knowledge
- Audience: AI training + pattern recognition

#### Section 9: Quick Reference (100-150 words)
- TL;DR command/fix
- Environment requirements
- Common gotchas
- Further reading
- Audience: Everyone (quick lookup)

### Phase 2: Media Management (CONDITIONAL)

Place media files (images, diagrams) in `_assets/` folder:

- Images: `_assets/{slug}-diagram.png`
- SVG Diagrams: `_assets/{slug}-diagram.svg`
- Reference in markdown: `![alt text](_assets/{slug}-diagram.png)` (use relative path)

Use clear naming: `{slug}-{purpose}.{extension}`
- Example: `mapfile-compatibility-execution-flow.svg`
- Example: `docker-networking-topology.png`

### Phase 3: Special Sections (CONDITIONAL)

#### For Postmortem Focus
- Add "Timeline" section
- Add "Communication Log" section
- Emphasize prevention measures

#### For Blog Focus
- Enhance narrative flow
- Add historical context/background
- Include author voice/personality
- Add conclusion + call-to-action

#### For AI Training Focus
- Emphasize pattern names
- Include anti-patterns explicitly
- Add decision trees
- High-precision terminology

#### For Junior Engineer Focus
- Simplify technical jargon
- Add more explanations
- Include "Why this matters" callouts
- Provide learning resources

### Phase 4: Validation (ALWAYS)

#### Structure Checks
- [ ] All 9 core sections present (or justified skips)
- [ ] Executive Summary < 100 words
- [ ] Markdown syntax valid
- [ ] No undefined terminology
- [ ] Code examples syntax-highlighted

#### Content Checks
- [ ] Root Cause clearly stated
- [ ] Solution reproducible (step-by-step)
- [ ] All four audiences addressed
- [ ] Metadata JSON valid
- [ ] No confidential/sensitive info

#### Quality Checks
- [ ] Tone consistent (professional yet accessible)
- [ ] Examples concrete, not generic
- [ ] Prevention measures actionable
- [ ] Links/references valid
- [ ] Total document length: 1500-2500 words (flexible)

#### Repository Checks
- [ ] Document in correct file: `docs/analysis/YYYY-MM-DD-{slug}.md`
- [ ] YAML frontmatter present and valid
- [ ] Media files (if any) in `_assets/` folder
- [ ] Master index updated: `_index.json`
- [ ] Jekyll compatibility verified (no directory structure conflicts)

## Output Requirements

### File Structure
```
docs/analysis/2025-01-15-mapfile-compatibility.md    (YAML frontmatter + content)
_assets/
  ├── mapfile-compatibility-diagram.png
  ├── mapfile-compatibility-execution-flow.svg
  └── ...
```

**File Naming Convention:**
- Documents: `docs/analysis/YYYY-MM-DD-{slug}.md`
- Media: `_assets/{slug}-{purpose}.{ext}` (e.g., `mapfile-compatibility-diagram.png`)

### Markdown Standards
- Use H2 (##) for main sections, H3 (###) for subsections
- Code blocks: Specify language (bash, python, json, etc.)
- Tables: Use when 3+ comparison attributes
- Emphasis: **bold** for key terms, `code` for commands
- Links: Use relative paths within repo or absolute URLs

### Automated Tasks
1. Create file: `docs/analysis/YYYY-MM-DD-{slug}.md` with YAML frontmatter
2. Write content with all 9 sections
3. Update master `_index.json`
4. Auto-commit to git (optional flag)
5. Generate Jekyll-ready content (no further processing needed)

## Error Handling

### Missing Information
If conversation lacks critical info:
- [ ] Mark section as [TODO]
- [ ] Add clarifying questions in comment
- [ ] Proceed with available context

### Ambiguous Root Cause
- [ ] Propose most likely cause
- [ ] Add alternative hypotheses
- [ ] Recommend further investigation

### Unclear Prevention Steps
- [ ] Provide general recommendations
- [ ] Flag for future postmortem review
- [ ] Suggest monitoring points

## Environment Configuration

Add to shell profile or .env:
```bash
# RCA Repository Configuration
export RCA_REPO_PATH="$HOME/para/archive/rca-knowledge"
export RCA_AUTO_COMMIT=false        # Set true for auto git commit
export RCA_AUTO_PUBLISH=false       # Set true for auto push
export RCA_FORMAT="hybrid-jekyll"   # Hybrid format with YAML frontmatter
```

Defaults:
- rca_repo_path: `~/para/archive/rca-knowledge`
- auto_commit: false
- auto_publish: false
- format: hybrid-jekyll (YAML frontmatter + single .md files)

## Usage Examples

### Quick Invocation
```bash
# During conversation, when issue is resolved:
/write-rca-doc

# Or with options:
/write-rca-doc --commit          # Auto-commit to git
/write-rca-doc --audience blog   # Blog-first optimization
/write-rca-doc --private         # For sensitive incidents
```

### Generated Output
```
Generated: docs/analysis/2025-01-15-mapfile-compatibility.md
Format: Jekyll-compatible (YAML frontmatter + single .md file)
Index: _index.json updated
Total words: 2847
Estimated read time: 12 minutes

Generated document satisfies:
  ✓ Postmortem review
  ✓ Technical blog
  ✓ AI tool training
  ✓ Junior engineer onboarding
  ✓ Jekyll/GitHub Pages compatible
  ✓ Portable to Medium, Dev.to, personal blogs
```

## Quick Reference Examples

### Small Single-Issue RCA
- Problem: Bug fix in one component
- Sections: 1-9 all present, concise
- Length: 1200-1500 words
- Metadata: Single project, clear category

### Medium Incident RCA
- Problem: Multi-system incident
- Sections: 1-9 + Timeline + Related Issues
- Length: 1800-2500 words
- Metadata: Multiple projects, cross-service

### Large Architecture Issue RCA
- Problem: Systemic pattern failure
- Sections: All + Decision Trees + Comparison Matrix
- Length: 2500-3500 words (split across multiple documents if needed)
- Metadata: Multiple tags, multiple projects

## Acceptance Criteria

After generation, verify ALL:

1. Directory Structure
   - [ ] `docs/analysis/YYYY-MM-DD-{slug}/` created
   - [ ] README.md present
   - [ ] _metadata.json present

2. Content Quality
   - [ ] All 9 sections present or explicitly marked [TODO]
   - [ ] Executive Summary < 100 words
   - [ ] Root Cause Analysis clearly stated
   - [ ] Solution reproducible
   - [ ] All four audiences explicitly addressed

3. Metadata
   - [ ] JSON valid and well-formed
   - [ ] All required fields populated
   - [ ] Tags and categories appropriate
   - [ ] Keywords searchable

4. Repository
   - [ ] Master _index.json updated
   - [ ] No conflicts with existing documents
   - [ ] Git-ready for optional commit

## Command

**When invoked, IMMEDIATELY:**

1. Analyze the conversation context in this session
2. Extract problem, solution, learning, and prevention
3. Announce Phase 0 analysis and plan before proceeding
4. Generate document structure at `~/para/project/rca-knowledge/docs/analysis/YYYY-MM-DD-{slug}/`
5. Create all required files (README.md, _metadata.json)
6. Validate against acceptance criteria
7. Output summary with word count and audience coverage

Start with Phase 0 analysis and announce plan before proceeding.
