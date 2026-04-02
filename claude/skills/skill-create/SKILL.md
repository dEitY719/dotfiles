---
name: skill:creator
description: Create new skills, modify and improve existing skills, and measure skill performance. Use when users want to create a skill from scratch, edit, or optimize an existing skill, run evals to test a skill, benchmark skill performance with variance analysis, or optimize a skill's description for better triggering accuracy.
---

# Skill Creator

A skill for creating new skills and iteratively improving them. Figure out where
the user is in the process and help them progress. Be flexible — if the user says
"just vibe with me", skip the formal eval loop.

## Core Loop

1. Decide what the skill should do
2. Write a draft
3. Run claude-with-access-to-the-skill on test prompts
4. Evaluate results (qualitative + quantitative) with the user
5. Improve the skill based on feedback
6. Repeat until satisfied
7. Optimize description for triggering accuracy
8. Package the final skill
9. Run `/skill-check` → if FAIL/WARN, run `/skill-refactor` (quality gate)

## Phase 1: Capture Intent

Extract answers from conversation history first if the user says "turn this into a skill".

1. What should this skill enable Claude to do?
2. When should this skill trigger? (what user phrases/contexts)
3. What's the expected output format?
4. Should we set up test cases? (suggest based on skill type — objective outputs benefit, subjective ones often don't)

## Phase 2: Interview and Research

Proactively ask about edge cases, input/output formats, example files, success criteria,
and dependencies. Check available MCPs for research. Wait to write test prompts until
this is ironed out.

## Phase 3: Write the SKILL.md

Read `references/skill-writing-guide.md` for anatomy, progressive disclosure, writing
patterns, frontmatter fields, communication style, and test case format.

## Phase 4: Run and Evaluate Test Cases

Read `references/eval-pipeline.md` for the full pipeline: spawning runs, drafting
assertions, capturing timing, grading, aggregating benchmarks, and launching the viewer.

IMPORTANT: Always generate the eval viewer using `eval-viewer/generate_review.py`
BEFORE evaluating outputs yourself — get results in front of the human ASAP.

## Phase 5: Improve the Skill

Read `references/improvement-philosophy.md` for guidance on generalizing from feedback,
keeping prompts lean, explaining the why, and detecting repeated work across test cases.

## Phase 6: Description Optimization

Read `references/description-optimization.md` for the trigger eval query generation,
HTML review flow, optimization loop script, and triggering mechanics.

## Phase 7: Package and Present

If `present_files` tool is available:

```bash
python -m scripts.package_skill <path/to/skill-folder>
```

Direct the user to the resulting `.skill` file path so they can install it.

## Phase 8: Post-Creation Quality Gate

Run `/skill-check` on the new SKILL.md. If any check returns FAIL or WARN,
immediately run `/skill-refactor` to bring it under 100 lines with proper
Progressive Disclosure structure. Report before/after line counts to the user.

## Platform-Specific Instructions

Read `references/platform-instructions.md` when running in Claude.ai or Cowork.

## Reference Files

- `agents/grader.md` — How to evaluate assertions against outputs
- `agents/comparator.md` — How to do blind A/B comparison between two outputs
- `agents/analyzer.md` — How to analyze why one version beat another
- `references/schemas.md` — JSON structures for evals.json, grading.json, etc.
- `references/skill-writing-guide.md` — Anatomy, patterns, style, test case format
- `references/eval-pipeline.md` — Running, grading, and reviewing test cases
- `references/improvement-philosophy.md` — How to iterate on a skill
- `references/description-optimization.md` — Trigger eval and optimization loop
- `references/platform-instructions.md` — Claude.ai and Cowork adaptations
