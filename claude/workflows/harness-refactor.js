
export const meta = {
  name: 'harness-refactor',
  description: 'Apply low-risk harness improvements: remove duplicates, clarify skill triggers, extract references',
  phases: [
    { title: 'Pre-flight', detail: 'Verify all target files exist, create archive directory' },
    { title: 'Apply Changes', detail: '10 parallel agents modify non-overlapping file groups' },
    { title: 'Verify', detail: 'Line count validation on all modified files' },
    { title: 'Final Report', detail: 'Change summary, behavior delta, smoke-test prompts, remaining high-risk items' },
  ],
}

const HOME = (typeof process !== 'undefined' && process.env?.HOME) || '/home/deity719'
const ARCHIVE = `${HOME}/dotfiles/.claude/archive/harness-refactor-2026-06-11`
const SKILLS = `${HOME}/dotfiles/claude/skills`
const ROOT = `${HOME}/dotfiles`

const CHANGE_SCHEMA = {
  type: 'object',
  properties: {
    agent: { type: 'string' },
    files_modified: { type: 'array', items: { type: 'string' } },
    files_created: { type: 'array', items: { type: 'string' } },
    changes: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          file: { type: 'string' },
          description: { type: 'string' },
          lines_before: { type: 'number' },
          lines_after: { type: 'number' },
        },
        required: ['file', 'description', 'lines_before', 'lines_after']
      }
    },
    skipped: { type: 'array', items: { type: 'string' } },
    errors: { type: 'array', items: { type: 'string' } },
  },
  required: ['agent', 'files_modified', 'files_created', 'changes', 'skipped', 'errors']
}

// ─── Phase 1: Pre-flight ───────────────────────────────────────────────────
phase('Pre-flight')

const preflight = await agent(`
Pre-flight setup for harness-refactor workflow. DO NOT MODIFY ANY FILES in this step.

STEP 1: Create archive directory
Run: mkdir -p "${ARCHIVE}"
Confirm it was created.

STEP 2: For each file below, run: wc -l <file> 2>/dev/null || echo "NOT_FOUND"
Report each as: FILE: <path> | STATUS: EXISTS/NOT_FOUND | LINES: N

Files to check:
- ${ROOT}/AGENTS.md
- ${ROOT}/claude/AGENTS.md
- ${ROOT}/aws/AGENTS.md
- ${ROOT}/docs/AGENTS.md
- ${HOME}/.claude/settings.local.json
- ${SKILLS}/devx-restart/SKILL.md
- ${SKILLS}/devx-resume-after-limit/SKILL.md
- ${SKILLS}/devx-visualize/SKILL.md
- ${SKILLS}/devx-excalidraw-diagram/SKILL.md
- ${SKILLS}/write-task-history/SKILL.md
- ${SKILLS}/write-insight/SKILL.md
- ${SKILLS}/write-rca/SKILL.md
- ${SKILLS}/devx-schedule/SKILL.md
- ${SKILLS}/claude-plugin-structure-check/SKILL.md
- ${SKILLS}/claude-plugin-structure-refactor/SKILL.md
- ${SKILLS}/devx-trd-to-issues/SKILL.md
- ${SKILLS}/devx-pr-to-ssot-issue/SKILL.md
- ${SKILLS}/gh-pr-resolve-ci-fail/SKILL.md

Also check existing references/ dirs:
- ls ${SKILLS}/devx-visualize/references/ 2>/dev/null || echo "none"
- ls ${SKILLS}/claude-plugin-structure-check/references/ 2>/dev/null || echo "none"
- ls ${SKILLS}/claude-plugin-structure-refactor/references/ 2>/dev/null || echo "none"
- ls ${SKILLS}/devx-trd-to-issues/references/ 2>/dev/null || echo "none"
- ls ${SKILLS}/devx-pr-to-ssot-issue/references/ 2>/dev/null || echo "none"
- ls ${SKILLS}/gh-pr-resolve-ci-fail/references/ 2>/dev/null || echo "none"
`, { label: 'preflight', phase: 'Pre-flight' })

log('Pre-flight done. Applying changes in 10 parallel agents...')
phase('Apply Changes')

const allResults = await parallel([

  // AGENT A: Root AGENTS.md — remove duplicate sections
  () => agent(`
You are AGENT-A. Task: Remove duplicate sections from root AGENTS.md.

TARGET FILE: ${ROOT}/AGENTS.md

CONSTRAINTS (read first):
- Do NOT modify hooks, MCP config, or application code
- Do NOT permanently delete — save removed content to archive FIRST
- Do NOT remove: architecture overview, AGENTS.md 100줄 limit rule, loading order rules, git-crypt notes
- If you cannot find a section precisely, skip it and report why

PROCEDURE:

1. Read the file: ${ROOT}/AGENTS.md
2. Run: wc -l ${ROOT}/AGENTS.md  (record lines_before)
3. Identify these sections to REMOVE (find by section heading text):
   a) "Operational Commands" section — duplicates CLAUDE.md Commands section (mise run lint/fix/test commands)
   b) "Design Principles" section — SOLID/DRY/TDD general principles, not repo-specific
   c) "Naming Rules" section — duplicated in CLAUDE.md and shell-common/AGENTS.md
   d) In "Standards & References" section: remove ONLY the lines linking to:
      - command-guidelines.md
      - github-project-board.md
      - discussions-policy.md
      (Keep git-crypt notes, semantic commits line, and any other content)

4. Write removed content to archive BEFORE editing:
   File: ${ARCHIVE}/AGENTS-root-removed-sections.md
   Include header: "# Removed from AGENTS.md (root) on 2026-06-11\\n# Reason: Duplicates CLAUDE.md\\n\\n"

5. Apply edits to ${ROOT}/AGENTS.md using Edit tool (make multiple Edit calls if needed)

6. Run: wc -l ${ROOT}/AGENTS.md  (record lines_after)

Return structured result with agent="agent-a", all modified/created files, changes with before/after line counts.
`, { label: 'agent-a-agents-root', phase: 'Apply Changes', schema: CHANGE_SCHEMA }),

  // AGENT B: claude/ + aws/ + docs/ AGENTS.md cleanup
  () => agent(`
You are AGENT-B. Task: Clean up claude/AGENTS.md, aws/AGENTS.md, and docs/AGENTS.md.

CONSTRAINTS:
- Do NOT modify hooks, MCP config, or application code
- Do NOT permanently delete — save removed content to archive FIRST
- Skip any section you cannot identify precisely and report why

PART 1 — ${ROOT}/claude/AGENTS.md:
1. Read file, record wc -l
2. Find the section explaining WHY the unified connection approach was chosen.
   It has multiple bullets. The first two bullets describe what OpenCode or Gemini USED TO DO with symlinks (historical past state). The third bullet explains Codex .system/ directory requirement (still active).
3. Remove ONLY bullets 1 and 2. Keep bullet 3.
4. Save removed content to ${ARCHIVE}/claude-AGENTS-removed-bullets.md
5. Apply Edit, record wc -l after

PART 2 — ${ROOT}/aws/AGENTS.md:
1. Read file, record wc -l
2. Find and remove the entire section titled like "왜 settings.local.json 디자인을 폐기했나" — this explains why an old design was abandoned. Remove section header + all its content.
3. In the "settings.json 머지 정책" section, find the historical justification text mentioning URL pattern matching that broke due to host rebranding (e.g., mentions a2g.samsungds.net). Remove ONLY that justification text. Keep the current rule.
4. Save removed content to ${ARCHIVE}/aws-AGENTS-removed-sections.md
5. Apply Edit(s), record wc -l after

PART 3 — ${ROOT}/docs/AGENTS.md:
1. Read file, record wc -l
2. Find the code block (triple-backtick bash block) showing archive procedure shell commands (mv, echo, date commands for archiving).
3. Remove ONLY the code block. Keep any surrounding prose about WHY documents should be archived.
4. Save removed content to ${ARCHIVE}/docs-AGENTS-removed-codeblock.md
5. Apply Edit, record wc -l after

Return structured result with agent="agent-b".
`, { label: 'agent-b-other-agents', phase: 'Apply Changes', schema: CHANGE_SCHEMA }),

  // AGENT C: settings.local.json — remove stale permissions
  () => agent(`
You are AGENT-C. Task: Remove 4 stale permissions from settings.local.json.

TARGET FILE: ${HOME}/.claude/settings.local.json

CONSTRAINTS:
- Do NOT remove any permissions other than the 4 specified below
- Do NOT modify allowedTools, env, hooks, or any other settings
- Preserve valid JSON formatting
- Save removed content to archive first

PROCEDURE:
1. Read the file
2. Record wc -l before
3. In the permissions.allow array, find and remove ONLY these exact entries (if they exist):
   - "Bash(tox:*)"
   - "Bash(fc-match:*)"
   - "Bash(fc-list:*)"
   - "Bash(markdownlint:*)"
   These are stale from old sessions — the current toolchain uses only mise/ruff/shellcheck/shfmt.
4. Save removed entries to: ${ARCHIVE}/settings-local-removed-permissions.md
   Header: "# Removed from ~/.claude/settings.local.json on 2026-06-11\\n# Reason: Stale, not in current toolchain\\n\\n"
5. Write updated settings.local.json (preserving all other content exactly, valid JSON)
6. Record wc -l after
7. If none of the 4 entries exist, add them all to skipped list — do not modify file

Return structured result with agent="agent-c".
`, { label: 'agent-c-settings', phase: 'Apply Changes', schema: CHANGE_SCHEMA }),

  // AGENT D: devx-restart + devx-resume-after-limit trigger clarification
  () => agent(`
You are AGENT-D. Task: Clarify triggers for devx-restart and devx-resume-after-limit to eliminate trigger confusion.

CONSTRAINT: Do NOT restructure files. Only modify trigger/description text. No hooks/MCP changes.

PART 1 — ${SKILLS}/devx-restart/SKILL.md:
1. Read file, record wc -l
2. Find the skill's description field (YAML frontmatter) or trigger/when-to-use section
3. Prepend to or rewrite the trigger to START WITH: "API 소켓 에러, OOM, 또는 ESC 키로 현재 세션이 중단된 후 재개할 때"
4. At the end of that trigger text, add: "(토큰 한계 리셋 후 크론 자동 재개는 devx:resume-after-limit 사용)"
5. Apply Edit, record wc -l after

PART 2 — ${SKILLS}/devx-resume-after-limit/SKILL.md:
1. Read file, record wc -l
2. Find the skill's description/trigger section
3. Prepend to or rewrite trigger to START WITH: "토큰 한계(rate limit) 리셋 후 크론 잡 자동 재개 — devx:rate-limit-guard와 쌍으로 동작"
4. At the end, add: "(API 에러/ESC 중단 후 현재 세션 재개는 devx:restart 사용)"
5. Apply Edit, record wc -l after

Return structured result with agent="agent-d".
`, { label: 'agent-d-devx-triggers', phase: 'Apply Changes', schema: CHANGE_SCHEMA }),

  // AGENT E: write-task-history, write-insight, write-rca, devx-excalidraw-diagram, devx-schedule triggers
  () => agent(`
You are AGENT-E. Task: Clarify triggers for 5 skills to reduce wrong-skill invocations.

CONSTRAINT: Do NOT restructure files. Only modify description/trigger/frontmatter text. No hooks/MCP changes.

PART 1 — ${SKILLS}/write-task-history/SKILL.md:
1. Read file, record wc -l
2. Find description/trigger. Modify to start with: "오늘 한 작업을 JIRA 티켓 + PR 설명 형식으로 daily log에 기록"
3. Add cross-ref at end: "(재사용 패턴 문서화는 write:insight, 장애 분석은 write:rca)"
4. Apply Edit, record wc -l after

PART 2 — ${SKILLS}/write-insight/SKILL.md:
1. Read file, record wc -l
2. Find description/trigger. Modify to start with: "현재 대화에서 재사용 가능한 패턴/교훈을 docs/guide/learnings/에 영구 문서화"
3. Add cross-ref: "(작업 로그는 write:task-history, 장애 분석은 write:rca)"
4. Apply Edit, record wc -l after

PART 3 — ${SKILLS}/write-rca/SKILL.md:
1. Read file, record wc -l
2. Find description/trigger. Modify to start with: "장애, 버그, 반복 실수에 대한 Root Cause Analysis 보고서 작성"
3. Add cross-ref: "(재사용 패턴 문서화는 write:insight, 작업 로그는 write:task-history)"
4. Apply Edit, record wc -l after

PART 4 — ${SKILLS}/devx-excalidraw-diagram/SKILL.md:
1. Read file, record wc -l
2. Find description/trigger. Append to it: "(인터랙티브 HTML 슬라이드/대시보드는 devx:visualize 사용)"
3. Apply Edit, record wc -l after

PART 5 — ${SKILLS}/devx-schedule/SKILL.md:
1. Read file, record wc -l
2. In YAML frontmatter: if there is no "allowed-tools" field, add: allowed-tools: [CronCreate]
3. In description/trigger: add "gh:issue-flow 내 세션 로컬 지연 단계용; 클라우드 에이전트 정기 스케줄은 내장 /schedule 스킬 사용"
4. Apply Edit(s), record wc -l after

Return structured result with agent="agent-e".
`, { label: 'agent-e-write-triggers', phase: 'Apply Changes', schema: CHANGE_SCHEMA }),

  // AGENT F: devx-visualize — trigger + Critical Requirements extraction
  () => agent(`
You are AGENT-F. Task: devx-visualize SKILL.md — two changes: trigger cross-ref AND extract Critical Requirements to references/.

TARGET: ${SKILLS}/devx-visualize/SKILL.md

CONSTRAINT: Keep the 5-step visualization procedure in SKILL.md. Only extract the "Non-negotiable requirements" list. No hooks/MCP changes.

PROCEDURE:

1. Read ${SKILLS}/devx-visualize/SKILL.md
2. Record wc -l before
3. Find description/trigger field. Append: "(Excalidraw .excalidraw 파일은 devx:excalidraw-diagram 사용)"

4. Find the "Critical Requirements" section (titled something like "Critical Requirements (NON-NEGOTIABLE)" or similar).
   This section contains ~8-12 specific requirements/rules that must always be followed.

5. Extract that ENTIRE section's content to:
   ${SKILLS}/devx-visualize/references/requirements.md
   
   Write that file with header:
   "# devx-visualize: Critical Requirements\\n\\nThese requirements must be followed for every visualization.\\n\\n"
   Then include the full requirements list.

6. In SKILL.md, replace the extracted "Critical Requirements" section body with a 2-line pointer:
   "## Critical Requirements\\nSee [references/requirements.md](references/requirements.md) for the full list."

7. Run: mkdir -p ${SKILLS}/devx-visualize/references/
8. Record wc -l after. Target: ~104 → ~88 lines.

Return structured result with agent="agent-f".
`, { label: 'agent-f-devx-visualize', phase: 'Apply Changes', schema: CHANGE_SCHEMA }),

  // AGENT G: claude-plugin-structure-check — evaluation rules extraction
  () => agent(`
You are AGENT-G. Task: claude-plugin-structure-check SKILL.md — extract detailed evaluation logic to references/evaluation-rules.md.

TARGET: ${SKILLS}/claude-plugin-structure-check/SKILL.md

CONSTRAINT: Keep the high-level audit procedure and report format in SKILL.md. Only extract the DETAILED CLASSIFICATION/SCORING LOGIC. No hooks/MCP changes.

PROCEDURE:

1. Read ${SKILLS}/claude-plugin-structure-check/SKILL.md
2. Record wc -l before
3. Find the sections containing:
   - Mode detection algorithm (logic for classifying M1-M6 and R1-R5 types, or equivalent classification logic)
   - Detailed scoring/evaluation rules for each mode

4. Extract those detailed algorithm sections to:
   ${SKILLS}/claude-plugin-structure-check/references/evaluation-rules.md
   
   Header: "# claude-plugin-structure-check: Evaluation Rules\\n\\nDetailed mode detection and scoring logic.\\n\\n"

5. In SKILL.md, replace the detailed algorithm content with:
   "For detailed evaluation rules and mode/type classification logic: see [references/evaluation-rules.md](references/evaluation-rules.md)"

6. mkdir -p ${SKILLS}/claude-plugin-structure-check/references/
7. Record wc -l after. Target: ~110 → ~85 lines.

If you cannot clearly identify the sections, extract conservatively (only what's clearly algorithm/scoring detail, not procedure steps) and report what you did.

Return structured result with agent="agent-g".
`, { label: 'agent-g-plugin-check', phase: 'Apply Changes', schema: CHANGE_SCHEMA }),

  // AGENT H: claude-plugin-structure-refactor — multiple references extractions
  () => agent(`
You are AGENT-H. Task: claude-plugin-structure-refactor SKILL.md — extract detailed rule content to references/.

TARGET: ${SKILLS}/claude-plugin-structure-refactor/SKILL.md

CONSTRAINT: Keep the 5-step execution order in SKILL.md. Only extract DETAILED RULE CONTENT (not the steps themselves). No hooks/MCP changes.

PROCEDURE:

1. Read ${SKILLS}/claude-plugin-structure-refactor/SKILL.md
2. Record wc -l before
3. mkdir -p ${SKILLS}/claude-plugin-structure-refactor/references/

4. Find and extract these sections (if they exist — skip gracefully if not found):
   a) Transformation guard logic in Step 2 (detailed conditions/rules for when to apply transforms)
      → write to references/structure-spec.md
      Header: "# Structure Refactor: Transformation Rules\\n\\n"
      
   b) --op flag rules/guide in Step 4 (R1 delegation, Pages activation, R5 backfill rules)
      → write to references/op-rules.md
      Header: "# Structure Refactor: --op Flag Rules\\n\\n"
      
   c) The "Constraints" section (Never/Always rules, ~15-20 lines)
      → write to references/constraints.md
      Header: "# Structure Refactor: Constraints\\n\\n"

5. For each extracted section, replace in SKILL.md with a 1-2 line pointer:
   "Detailed rules: see [references/structure-spec.md](references/structure-spec.md)"
   etc.

6. Record wc -l after. Target: ~139 → ~90 lines.

Return structured result with agent="agent-h".
`, { label: 'agent-h-plugin-refactor', phase: 'Apply Changes', schema: CHANGE_SCHEMA }),

  // AGENT I: devx-trd-to-issues + devx-pr-to-ssot-issue references extraction
  () => agent(`
You are AGENT-I. Task: Extract references for devx-trd-to-issues and devx-pr-to-ssot-issue.

CONSTRAINT: Keep the high-level procedure steps. Only extract substep details and classification logic. No hooks/MCP changes.

PART 1 — ${SKILLS}/devx-trd-to-issues/SKILL.md:
1. Read file, record wc -l before
2. Find "Step 4" and its detailed substeps (label validation, milestone batch creation, issue creation, citation resolution, milestone promotion — these are the DETAILED mechanics of each substep).
3. mkdir -p ${SKILLS}/devx-trd-to-issues/references/
4. Extract substep details to: ${SKILLS}/devx-trd-to-issues/references/bulk-create-procedure.md
   Header: "# TRD to Issues: Step 4 Bulk Create Procedure\\n\\nDetailed substeps for the issue creation phase.\\n\\n"
5. In SKILL.md, keep "Step 4: Create Issues" as a step heading, but replace the substep details with:
   "Detailed substep procedure: see [references/bulk-create-procedure.md](references/bulk-create-procedure.md)"
6. Record wc -l after. Target: ~106 → ~90 lines.

PART 2 — ${SKILLS}/devx-pr-to-ssot-issue/SKILL.md:
1. Read file, record wc -l before
2. Two changes:
   a) Find bucket classification logic (Step 2) and gap detection instructions (Step 3 — the detailed gap-finding logic, not the step header).
      mkdir -p ${SKILLS}/devx-pr-to-ssot-issue/references/
      Extract to: ${SKILLS}/devx-pr-to-ssot-issue/references/gap-detection.md
      Header: "# PR to SSOT Issue: Gap Detection & Classification\\n\\n"
      Replace in SKILL.md with pointer.
   b) Find any TODO annotations like "(TODO, 별도 이슈)" or similar inline TODO markers. Remove them.
3. Record wc -l after. Target: ~103 → ~90 lines.

Return structured result with agent="agent-i".
`, { label: 'agent-i-trd-pr', phase: 'Apply Changes', schema: CHANGE_SCHEMA }),

  // AGENT J: gh-pr-resolve-ci-fail — CI log analysis extraction + stale reference removal
  () => agent(`
You are AGENT-J. Task: gh-pr-resolve-ci-fail SKILL.md — extract CI analysis rules to references/ and remove stale issue references.

TARGET: ${SKILLS}/gh-pr-resolve-ci-fail/SKILL.md

CONSTRAINT: Keep the main CI fix procedure (fetch logs → find root cause → fix → commit → push). Only extract DETAILED RULE CONTENT and remove stale cross-references. No hooks/MCP changes.

PROCEDURE:

1. Read ${SKILLS}/gh-pr-resolve-ci-fail/SKILL.md
2. Record wc -l before
3. mkdir -p ${SKILLS}/gh-pr-resolve-ci-fail/references/

4. Find "inherited red" detection logic — the rules for distinguishing when a CI failure is inherited from the base branch vs. caused by this PR's changes.
   Extract to: ${SKILLS}/gh-pr-resolve-ci-fail/references/ci-log-analysis.md
   Header: "# CI Log Analysis Rules\\n\\nRules for root-cause classification of CI failures.\\n\\n"
   In SKILL.md, replace with: "For CI log analysis and inherited-red detection: see [references/ci-log-analysis.md](references/ci-log-analysis.md)"

5. If there is a "Never/Constraints" section with rules like "Never delegate to gh:commit":
   Extract to: ${SKILLS}/gh-pr-resolve-ci-fail/references/constraints.md
   Header: "# gh-pr-resolve-ci-fail: Constraints\\n\\n"
   Replace with pointer.

6. Find and REMOVE any inline reference to a specific GitHub Issue number (e.g., "Issue #755" or similar historical cross-reference to a resolved issue). These are archaeology — remove just that annotation/parenthetical.

7. Record wc -l after. Target: ~103 → ~92 lines.

Return structured result with agent="agent-j".
`, { label: 'agent-j-ci-fail', phase: 'Apply Changes', schema: CHANGE_SCHEMA }),

])

log('All parallel agents done. Running verification...')
phase('Verify')

const verification = await agent(`
Verification phase: Check all modified files have the expected changes.

Run wc -l on each target file and report:
${ROOT}/AGENTS.md
${ROOT}/claude/AGENTS.md
${ROOT}/aws/AGENTS.md
${ROOT}/docs/AGENTS.md
${HOME}/.claude/settings.local.json
${SKILLS}/devx-restart/SKILL.md
${SKILLS}/devx-resume-after-limit/SKILL.md
${SKILLS}/devx-visualize/SKILL.md
${SKILLS}/devx-excalidraw-diagram/SKILL.md
${SKILLS}/write-task-history/SKILL.md
${SKILLS}/write-insight/SKILL.md
${SKILLS}/write-rca/SKILL.md
${SKILLS}/devx-schedule/SKILL.md
${SKILLS}/claude-plugin-structure-check/SKILL.md
${SKILLS}/claude-plugin-structure-refactor/SKILL.md
${SKILLS}/devx-trd-to-issues/SKILL.md
${SKILLS}/devx-pr-to-ssot-issue/SKILL.md
${SKILLS}/gh-pr-resolve-ci-fail/SKILL.md

Also verify these reference files were created:
ls -la ${SKILLS}/devx-visualize/references/ 2>/dev/null || echo "devx-visualize/references: MISSING"
ls -la ${SKILLS}/claude-plugin-structure-check/references/ 2>/dev/null || echo "plugin-check/references: MISSING"
ls -la ${SKILLS}/claude-plugin-structure-refactor/references/ 2>/dev/null || echo "plugin-refactor/references: MISSING"
ls -la ${SKILLS}/devx-trd-to-issues/references/ 2>/dev/null || echo "trd-to-issues/references: MISSING"
ls -la ${SKILLS}/devx-pr-to-ssot-issue/references/ 2>/dev/null || echo "pr-to-ssot/references: MISSING"
ls -la ${SKILLS}/gh-pr-resolve-ci-fail/references/ 2>/dev/null || echo "ci-fail/references: MISSING"

Also check archive:
ls -la ${ARCHIVE}/ 2>/dev/null || echo "ARCHIVE EMPTY OR MISSING"

For each SKILL.md that had references extracted, check it has a pointer:
grep -l "references/" ${SKILLS}/devx-visualize/SKILL.md 2>/dev/null || echo "devx-visualize: MISSING POINTER"
grep -l "references/" ${SKILLS}/claude-plugin-structure-check/SKILL.md 2>/dev/null || echo "plugin-check: MISSING POINTER"
grep -l "references/" ${SKILLS}/claude-plugin-structure-refactor/SKILL.md 2>/dev/null || echo "plugin-refactor: MISSING POINTER"
grep -l "references/" ${SKILLS}/devx-trd-to-issues/SKILL.md 2>/dev/null || echo "trd-to-issues: MISSING POINTER"
grep -l "references/" ${SKILLS}/devx-pr-to-ssot-issue/SKILL.md 2>/dev/null || echo "pr-to-ssot: MISSING POINTER"
grep -l "references/" ${SKILLS}/gh-pr-resolve-ci-fail/SKILL.md 2>/dev/null || echo "ci-fail: MISSING POINTER"

Also spot-check devx-schedule frontmatter:
head -20 ${SKILLS}/devx-schedule/SKILL.md

Report all findings clearly.
`, { label: 'verification', phase: 'Verify' })

log('Verification done. Generating final report...')
phase('Final Report')

const finalReport = await agent(`
Generate the final harness-refactor report in Korean (technical terms in English).

You have:
=== PRE-FLIGHT ===
${preflight}

=== CHANGE RESULTS (10 agents) ===
${JSON.stringify(allResults, null, 2)}

=== VERIFICATION ===
${verification}

Write the report with EXACTLY these sections:

# harness-refactor 실행 결과 리포트

## 1. 변경한 파일 목록
| 파일 | 변경 유형 | 이전 줄 수 | 이후 줄 수 | 절감 |

## 2. 새로 생성한 파일 목록 (references/ + archive/)
| 파일 경로 | 내용 |

## 3. 파일별 변경 이유
각 파일에 대해 2-3줄: 무엇을 제거/변경했는지, 왜 안전한지

## 4. Before / After 요약
- 전역 컨텍스트 파일 총 줄 수 합계: Before → After
- Skill SKILL.md 파일 총 줄 수 합계: Before → After
- 새로 생성된 references/ 파일 수
- 아카이브된 내용 수

## 5. diff 요약
각 파일별 핵심 변경 내용 1-2줄

## 6. Claude의 행동이 어떻게 달라질 수 있는지
- 어떤 규칙이 사라지거나 이동했는지 (주의: Claude가 이제 rules를 보지 못할 수 있음)
- 어떤 Skill의 트리거가 더 좁아졌는지 (이제 더 정확하게 호출됨)
- 어떤 지식이 references/ 파일에만 있어서 Claude가 명시적으로 참조해야 하는지

## 7. 실패하거나 스킵된 변경 목록
이유와 함께 상세히

## 8. 이번에 적용하지 않은 High-Risk 항목 (Human Approval Required)
(harness-legacy-check 리포트에서 식별된 것들)

## 9. Smoke-test 프롬프트 5개
새 하네스를 검증하기 위한, 실제 복사해서 사용할 수 있는 프롬프트들.
각각 어떤 변경을 검증하는지 한 줄 설명 포함.

\`\`\`
1. [프롬프트 내용]
\`\`\`

## 10. 다음 단계 권고
`, { label: 'final-report', phase: 'Final Report' })

return { finalReport }
