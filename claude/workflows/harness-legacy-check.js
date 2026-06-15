
export const meta = {
  name: 'harness-legacy-check',
  description: 'Read-only audit of AI coding harness for legacy rules, duplicates, bloat, and over-broad permissions',
  phases: [
    { title: 'Inventory', detail: 'Enumerate all harness files and settings' },
    { title: 'Parallel Analysis', detail: '5 specialist agents analyze dimensions in parallel' },
    { title: 'Refactor Planner', detail: 'Classify each finding: KEEP / SHRINK / MOVE / SPLIT / CONVERT / DELETE' },
    { title: 'Adversarial Review', detail: 'Challenge recommendations — what breaks if we cut it?' },
    { title: 'Final Report', detail: 'Synthesize into full audit report with action lists' },
  ],
}

const HOME = (typeof process !== 'undefined' && process.env?.HOME) || '/home/deity719'

// ─── Phase 1: Inventory ───────────────────────────────────────────────────
phase('Inventory')

const inventory = await agent(`
You are a READ-ONLY inventory agent. Your job is to enumerate every AI coding harness file in this dotfiles repository at ${HOME}/dotfiles.

Scan and list the FULL CONTENT of:
1. ${HOME}/dotfiles/CLAUDE.md
2. Every AGENTS.md file found under ${HOME}/dotfiles/ (run: find ${HOME}/dotfiles -name "AGENTS.md" -not -path "*/node_modules/*")
3. ${HOME}/.claude/settings.json (if exists)
4. ${HOME}/dotfiles/claude/settings.json (if exists)
5. Every file under ${HOME}/.claude/skills/ (list filenames + first 30 lines each)
6. Every file under ${HOME}/dotfiles/claude/skills/ (list filenames + first 30 lines each)
7. Every file under ${HOME}/.claude/workflows/ (list filenames + first 30 lines each)
8. Every file under ${HOME}/dotfiles/claude/workflows/ (list filenames + first 30 lines each)
9. ${HOME}/.cursor/rules/ (if exists, list all files)
10. ${HOME}/dotfiles/.cursor/ (if exists, list all files)
11. Hook configs: look in ${HOME}/dotfiles/git/config/hook-config.sh (first 60 lines), git/config/pre-push-rules.sh (first 40 lines)
12. MCP config: check ${HOME}/.claude/settings.json for mcpServers, also look for any mcp*.json or .mcp.json files

For EACH file found, output:
- FILE_PATH: <absolute path>
- SIZE: <approximate line count>
- SUMMARY: <2-3 sentence summary of what it does>
- SECTIONS: <bullet list of major sections/rules>

Do NOT modify any files. Read only.
`, { label: 'inventory', phase: 'Inventory' })

log('Inventory complete. Starting parallel specialist analysis...')

// ─── Phase 2: Parallel Specialist Analysis ───────────────────────────────
phase('Parallel Analysis')

const [globalContextFindings, skillQualityFindings, productOverlapFindings, safetyFindings] = await parallel([
  () => agent(`
You are the GLOBAL CONTEXT TAX AGENT. Your job: analyze files that load into EVERY session and assess whether they impose unnecessary context cost.

Context: This is a dotfiles repo audit at ${HOME}/dotfiles. Read these files yourself.

Files to analyze (read them):
- ${HOME}/dotfiles/CLAUDE.md
- Every AGENTS.md under ${HOME}/dotfiles/ (find with: find ${HOME}/dotfiles -name "AGENTS.md" -not -path "*/node_modules/*")
- Any cursor rules in ${HOME}/.cursor/rules/ or ${HOME}/dotfiles/.cursor/

Audit principles:
- Good global context = universal invariants that CANNOT be in a skill (e.g., "never commit secrets", repo architecture map)
- Bad global context = things that only matter for specific tasks (e.g., "when writing tests, do X"), procedural how-to's that belong in skills, historical decisions that are now obvious from the code itself
- Warning signs: very long AGENTS.md files (>100 lines), duplicated guidance across CLAUDE.md and AGENTS.md, guidance that references specific tool names/versions that may have changed, "best practices" lists that the LLM already knows

For each file section that is problematic, output a finding block:
---FINDING---
PATH: <file path>
SECTION: <section name or line range>
CURRENT_PURPOSE: <what it currently does>
PROBLEM: <why it's bloat/legacy/duplicate>
EVIDENCE: <specific quote or line that shows the problem>
RECOMMENDATION: KEEP | SHRINK | MOVE | SPLIT | CONVERT | DELETE
RISK_IF_REMOVED: low | medium | high
CONFIDENCE: low | medium | high
AUTO_PROCESSABLE: yes | no
---END---

After all findings, output a SUMMARY section with:
- Total lines analyzed across all global context files
- Estimated % that is "always-needed" vs "task-specific" vs "historical"
- Top 3 biggest opportunities to reduce global context load
`, { label: 'global-context-tax', phase: 'Parallel Analysis' }),

  () => agent(`
You are the SKILL QUALITY AGENT. Your job: audit every skill file for quality, necessity, scope, AND structural quality.

Read all skill files from:
- ${HOME}/.claude/skills/ (use find + read each file)
- ${HOME}/dotfiles/claude/skills/ (use find + read each file)

For each skill, evaluate:
1. NECESSITY: Is this skill still needed? Or has Claude Code/Cursor built this in natively?
2. TRIGGER SCOPE: Is the trigger description too broad? (e.g., "use when writing any code" is too broad)
3. LENGTH: Is the skill file too long (>200 lines)? Could it be split into a reference doc + a short procedure?
4. DUPLICATION: Does this skill overlap significantly with another skill or with CLAUDE.md?
5. FRESHNESS: Are there references to specific versions, dates, deprecated APIs, or workflows that no longer exist?
6. INVOCATION PATTERN: Is this skill "rigid" (must be followed exactly) or "flexible" (principles)? Is the type appropriate?

STRUCTURAL QUALITY SIGNALS (skill:check Check 1/2/3/6/12 — these directly drive
the "should this skill be refactored?" decision). Evaluate each as PASS or FAIL
using the SSOT definitions in
${HOME}/dotfiles/claude/skills/skill-check/references/checks.md.
Do NOT redefine these checks — apply them as written. Evaluate ONLY these five
(Check 4/5/7/8/9/10/11 are out of scope for this harness — they remain /skill:check-only):

- Check 1 — Line Count: SKILL.md body ≤ 100 lines → PASS, else FAIL.
- Check 2 — Progressive Disclosure: workflow phases in SKILL.md with detail
  extracted to references/ → PASS; large reference content embedded inline → FAIL.
- Check 3 — Frontmatter Validity: frontmatter has BOTH \`name\` and \`description\`
  (and no unknown attributes) → PASS, else FAIL.
- Check 6 — Help Flag Pattern: skill handles \`-h\`/\`--help\`/\`help\` → PASS, else FAIL.
- Check 12 — Model Recommendation Metadata: \`metadata.model_recommendation\`
  present in frontmatter → PASS, else FAIL.

A FAIL on any of these five RAISES the skill's refactor priority. The more
structural FAILs, the higher the refactor priority.

For each skill file, output:
---SKILL---
NAME: <skill name>
PATH: <file path>
LINE_COUNT: <approximate>
CURRENT_PURPOSE: <one sentence>
STRUCTURAL_QUALITY: Check1:PASS|FAIL Check2:PASS|FAIL Check3:PASS|FAIL Check6:PASS|FAIL Check12:PASS|FAIL
STRUCTURAL_FAIL_COUNT: <number of the five checks that FAILed>
PROBLEMS:
  - <problem 1>
  - <problem 2>
RECOMMENDATION: KEEP | SHRINK | SPLIT | CONVERT | DELETE
REFACTOR_PRIORITY: high | medium | low  (raise when STRUCTURAL_FAIL_COUNT is high)
RISK_IF_CHANGED: low | medium | high
CONFIDENCE: low | medium | high
AUTO_PROCESSABLE: yes | no
---END---

After all skills, output:
- TOP 5 skills with the highest "shrink" or "delete" potential
- Skills with the most structural FAILs (highest refactor priority)
- Any skills that could be converted to reference.md or examples.md docs instead
- Skills with overlapping triggers that should be merged
`, { label: 'skill-quality', phase: 'Parallel Analysis' }),

  () => agent(`
You are the PRODUCT OVERLAP AGENT. Your job: identify rules and behaviors that were once custom necessities but are now built into Claude Code, Cursor, Codex, or other AI coding tools natively.

Read these files:
- ${HOME}/dotfiles/CLAUDE.md
- ${HOME}/.claude/settings.json (if exists)
- ${HOME}/dotfiles/claude/settings.json (if exists)
- All skill files in ${HOME}/.claude/skills/ and ${HOME}/dotfiles/claude/skills/

Known Claude Code built-ins to compare against (as of mid-2025):
- Auto git commit message generation
- Built-in /review, /doctor, /bug commands
- Auto-compaction of long contexts
- Native MCP server support
- TodoWrite task tracking (native)
- Memory system (native)
- /schedule built-in skill
- /verify built-in skill
- /code-review built-in skill
- /simplify built-in skill
- Native plan mode (EnterPlanMode)
- Native worktree support
- Settings.json permission management (allowedTools, etc.)
- Auto-approval of tool use based on permissions
- Native web search and fetch

For each overlap found, output:
---OVERLAP---
PATH: <file>
SECTION: <section or skill name>
CURRENT_PURPOSE: <what the custom rule does>
PRODUCT_FEATURE: <what built-in feature now covers this>
OVERLAP_DEGREE: full | partial | none
RECOMMENDATION: KEEP | SHRINK | CONVERT | DELETE
NOTES: <any nuance — e.g., the custom version does more than the built-in>
RISK_IF_REMOVED: low | medium | high
CONFIDENCE: low | medium | high
---END---

Finish with a summary of:
- Total overlaps found
- Estimated context savings if overlapping sections were removed
- Which overlaps are safest to remove first
`, { label: 'product-overlap', phase: 'Parallel Analysis' }),

  () => agent(`
You are the SAFETY AND PERMISSION AGENT. Your job: audit hooks, allowed-tools permissions, and MCP configurations for excessive or stale grants.

Read these files (READ ONLY — do not modify):
- ${HOME}/.claude/settings.json
- ${HOME}/dotfiles/claude/settings.json
- ${HOME}/dotfiles/git/config/hook-config.sh
- ${HOME}/dotfiles/git/config/pre-push-rules.sh
- ${HOME}/dotfiles/git/hooks/ (list all files)
- Any .claude/settings.json in subdirectories (find ${HOME}/dotfiles -name "settings.json" -path "*claude*")
- Check for any .mcp.json or mcp config files

Evaluate:
1. ALLOWED_TOOLS: Are any tool permissions granted too broadly? (e.g., "Bash(*)" grants all shell access)
2. HOOKS: Do any hooks run destructive commands? Are hooks still needed or does native Claude Code behavior replace them?
3. MCP SERVERS: Are all configured MCP servers still active and necessary? Any with write/delete access that should be read-only?
4. PERMISSION SCOPE: Is the principle of least privilege being followed?
5. STALE GRANTS: Any permissions referencing tools or paths that no longer exist?

For each concern, output:
---SECURITY---
PATH: <file>
SECTION: <setting name or section>
CURRENT_GRANT: <what permission/hook/mcp is configured>
CONCERN: <what the risk or staleness issue is>
RECOMMENDATION: KEEP | SHRINK | REVOKE | AUDIT
RISK_IF_UNCHANGED: low | medium | high
CONFIDENCE: low | medium | high
---END---

End with:
- Overall permission posture assessment (tight / acceptable / loose)
- Top 3 permission risks to address
- Any permissions that look like they were added "just in case" rather than for a specific need
`, { label: 'safety-permissions', phase: 'Parallel Analysis' }),
])

log('Parallel analysis complete. Running Refactor Planner...')

// ─── Phase 3: Refactor Planner ───────────────────────────────────────────
phase('Refactor Planner')

const refactorPlan = await agent(`
You are the REFACTOR PLANNER. Your job: synthesize all findings from the four specialist agents and produce a classified action list.

Here is the inventory of the harness:
${inventory}

Here are the Global Context Tax findings:
${globalContextFindings}

Here are the Skill Quality findings:
${skillQualityFindings}

Here are the Product Overlap findings:
${productOverlapFindings}

Here are the Safety & Permission findings:
${safetyFindings}

Your task:
For EACH unique finding (deduplicate if multiple agents flagged the same item), produce one classified entry:

---ACTION---
ID: <sequential number>
PATH: <file path>
SECTION: <section or item>
CLASSIFICATION: KEEP | SHRINK | MOVE | SPLIT | CONVERT | DELETE
CURRENT_PURPOSE: <what it does now>
PROBLEM_SUMMARY: <why it needs action>
RECOMMENDED_ACTION: <specific action to take>
MOVE_TARGET: <if MOVE, where should it go?>
SPLIT_INTO: <if SPLIT, what are the two parts?>
CONVERT_TO: <if CONVERT, what type of artifact?>
STRUCTURAL_SIGNALS: <for skill findings, copy the STRUCTURAL_QUALITY line from the
  Skill Quality findings, e.g. "Check1:FAIL Check2:FAIL Check3:PASS Check6:PASS Check12:FAIL"; "n/a" for non-skill findings>
RISK: low | medium | high
CONFIDENCE: low | medium | high
HARNESS_DIET_ELIGIBLE: yes | no  (yes = safe to automate, no = needs human review)
PRIORITY: P1 (do first) | P2 (do soon) | P3 (nice to have)
---END---

PRIORITY rule for skill findings: a skill with structural FAILs is a concrete,
high-signal refactor candidate. Raise its PRIORITY accordingly — 3+ structural
FAILs → P1, 1-2 structural FAILs → at least P2. Structural PASS across all five
does NOT by itself force a low priority (necessity/scope/overlap still apply).

After all items, produce these sections:

## CLASSIFICATION SUMMARY
- KEEP: <count>
- SHRINK: <count>
- MOVE: <count>
- SPLIT: <count>
- CONVERT: <count>
- DELETE: <count>

## HARNESS SIZE ESTIMATE
- Current estimated total context load (lines across all always-loaded files)
- Estimated context load after recommended changes
- Estimated % reduction
`, { label: 'refactor-planner', phase: 'Refactor Planner' })

log('Refactor plan ready. Running adversarial review...')

// ─── Phase 4: Adversarial Reviewer ───────────────────────────────────────
phase('Adversarial Review')

const adversarialReview = await agent(`
You are the ADVERSARIAL REVIEWER. Your job: challenge the refactor plan. Find cases where deleting or shrinking a rule would actually HURT the user, cause regressions, or remove genuine value.

Here is the refactor plan to challenge:
${refactorPlan}

For each DELETE or SHRINK recommendation, ask:
1. What is the WORST CASE if this rule disappears? (What mistake does it currently prevent?)
2. Is this rule compensating for a known real incident or repeated mistake? (Evidence: git history, comments, docs)
3. Is this rule actually triggered regularly? Or is it theoretical?
4. What would need to be true for this rule to be NECESSARY again?
5. If we delete this, what is the recovery path?

Output format for items you want to CHALLENGE:

---CHALLENGE---
ACTION_ID: <ID from refactor plan>
ORIGINAL_RECOMMENDATION: SHRINK | DELETE | etc.
CHALLENGE: <your argument for why this is more valuable than it seems>
WORST_CASE_SCENARIO: <what breaks if we remove it>
REVISED_RECOMMENDATION: KEEP | SHRINK_LESS_AGGRESSIVELY | ADD_GUARD_BEFORE_DELETING
REVISED_RISK: low | medium | high
---END---

For items you AGREE with (genuinely safe to remove), output:
---AGREE---
ACTION_ID: <ID>
REASON: <why you agree it's safe>
---END---

End with:
- Count of items challenged
- Count of items agreed with  
- Your top 3 most important challenges (items where the original plan may be too aggressive)
- Your verdict: overall, is the refactor plan too aggressive, about right, or too conservative?
`, { label: 'adversarial-reviewer', phase: 'Adversarial Review' })

log('Adversarial review complete. Synthesizing final report...')

// ─── Phase 5: Final Report ────────────────────────────────────────────────
phase('Final Report')

const finalReport = await agent(`
You are the FINAL REPORT SYNTHESIZER. Produce a comprehensive, well-structured audit report in Korean (with technical terms in English where appropriate).

You have access to all findings:

=== INVENTORY ===
${inventory}

=== GLOBAL CONTEXT TAX FINDINGS ===
${globalContextFindings}

=== SKILL QUALITY FINDINGS ===
${skillQualityFindings}

=== PRODUCT OVERLAP FINDINGS ===
${productOverlapFindings}

=== SAFETY & PERMISSION FINDINGS ===
${safetyFindings}

=== REFACTOR PLAN ===
${refactorPlan}

=== ADVERSARIAL REVIEW ===
${adversarialReview}

Produce the final report with EXACTLY these sections in order:

# harness-legacy-check 감사 리포트

## 0. 감사 개요
- 감사 날짜, 범위, 방법론 요약

## 1. 전체 요약 (Executive Summary)
- 발견한 핵심 문제 3-5개
- 하네스 전반적 상태 평가 (건강함 / 주의 필요 / 개선 필요)
- 예상 개선 효과 (컨텍스트 절감량 등)

## 2. 유지해야 할 항목 (KEEP)
각 항목: 경로 | 이유 | 유지 근거

## 3. 줄여야 할 항목 (SHRINK)
각 항목: 경로 | 현재 크기 | 제거 가능한 내용 | 예상 절감

## 4. 전역 지침에서 Skill로 옮길 항목 (MOVE: global → skill)
각 항목: 현재 위치 | 추천 이동 위치 | 이동 이유

## 5. Skill에서 reference.md / examples.md로 분리할 항목 (SPLIT / CONVERT)
각 항목: 현재 Skill | 분리할 내용 | 남길 내용

### 5-1. Skill 구조 품질 신호 (skill:check Check 1/2/3/6/12)
모든 감사 대상 스킬에 대해 아래 표를 출력한다. 「구조 품질 신호」 열에는
Skill Quality 에이전트가 산출한 STRUCTURAL_QUALITY 값을 그대로 옮긴다.
우선순위는 구조 FAIL 개수가 많을수록 상향한다 (3개 이상 high, 1-2개 medium).
Check 4/5/7/8/9/10/11 은 이 표에 포함하지 않는다 (/skill:check 전용).

| 스킬 | 필요성 | 범위 | 구조 품질 신호 | 우선순위 |
|------|--------|------|---------------|---------|
| <skill name> | 필요/불필요 | 적절/과대 | Check1:PASS Check2:PASS Check3:PASS Check6:PASS Check12:FAIL | high/medium/low |

## 6. 삭제 후보 (DELETE)
각 항목: 경로/섹션 | 삭제 이유 | 위험도 | Adversarial 검토 결과

## 7. 사람이 직접 승인해야 하는 위험한 변경 (Human Review Required)
- 각 항목과 위험한 이유를 명확히

## 8. /harness-diet로 넘겨도 되는 low-risk 변경 목록
- 자동 처리 가능한 항목들 (위험도 낮음, 신뢰도 높음)

## 9. /harness-diet 실행용 추천 프롬프트
실제로 복사해서 사용할 수 있는 프롬프트 (구체적, 실행 가능):

\`\`\`
/harness-diet
[구체적인 지시사항]
\`\`\`

## 10. 권고사항 우선순위
| 우선순위 | 항목 | 분류 | 위험도 | 예상 효과 |
|---------|------|------|--------|----------|
각 행을 P1/P2/P3 순으로 정렬

---
리포트 품질 기준: 구체적이어야 한다. "줄이세요" 대신 "47-89번 줄을 삭제하세요". 모호한 조언 금지.
`, { label: 'final-report', phase: 'Final Report' })

// ─── Save Report ─────────────────────────────────────────────────────────
await agent(`
Create the directory .claude/reports/ if it does not exist, then write the following content exactly as-is to the file .claude/reports/harness-legacy-check.md (overwrite if it exists):

${finalReport}

Use Bash to run: mkdir -p .claude/reports
Then use the Write tool to write the file.
`, { label: 'save-report', phase: 'Final Report' })

log('harness-legacy-check complete. Report saved to .claude/reports/harness-legacy-check.md')

return {
  inventory_summary: inventory.slice(0, 500),
  final_report: finalReport,
}
