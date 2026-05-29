---
name: devx:dissect-builtin
description: >-
  Analyze and document Claude Code built-in skills. Load a built-in skill's
  prompt via the Skill tool, explain its behavior in Korean, and save structured
  documentation (README.md + PROMPT.md) to the dotfiles repository. Use when the
  user wants to study, dissect, or document a built-in skill (e.g.,
  "/devx:dissect-builtin simplify", "/devx:dissect-builtin loop"). Trigger on requests
  like "내장 스킬 분석", "built-in skill 공부", or "스킬 해부".
metadata:
  model_recommendation:
    tier: sonnet
    reason: "structure analysis + Korean documentation generation; moderate reasoning"
    claude: prefer
    non_claude: advisory-only
---

# Dissect Built-in Skill

## Help

If args is `-h`/`--help`/`help`, read `references/help.md` verbatim and stop.

Analyze a Claude Code built-in skill and produce structured documentation in Korean.

## Usage

```
/devx:dissect-builtin <skill-name>
```

## Workflow

Run these steps in order. Stop immediately on any error (skill load failure, agent failure, write error) and emit a `[FAIL]` verdict.

### Step 1: Load the skill prompt

Use the Skill tool to load the target built-in skill:

```
Skill(skill: "<skill-name>")
```

The raw prompt will be injected into context. Capture and preserve the full original text.

### Step 2: Launch two agents in parallel

Use the Agent tool to launch both agents concurrently in a single message.
Output directory: `claude/built-in-skills/<skill-name>/` (relative to dotfiles repo root).

| Output    | Path                                          | Format    |
|-----------|-----------------------------------------------|-----------|
| README.md | claude/built-in-skills/<skill-name>/README.md | Korean MD |
| PROMPT.md | claude/built-in-skills/<skill-name>/PROMPT.md | Verbatim  |

#### Agent 1: Analyze and write README.md

Analyze the loaded prompt and write `README.md` in Korean with:

1. **한줄 요약**: 스킬이 하는 일을 한 문장으로
2. **동작 단계(Phase)**: 스킬이 수행하는 단계별 흐름
3. **상세 체크 항목**: 각 단계에서 확인하는 구체적 항목 (있는 경우)
4. **특징**: 주목할 만한 설계 특성 (병렬 실행, 쓰기 권한, 특정 도메인 특화 등)

Use summary tables where appropriate. Suggested headings: `# /<skill-name> -
<Title>` → 한줄 설명(내장 스킬임을 명시) → `## 동작 요약` → `## Phase N: ...` →
`## 특징`. Adapt headings to the skill's actual phases — do not force a fixed template.

#### Agent 2: Write PROMPT.md

Write the original prompt verbatim to `PROMPT.md`. No wrapper headings, no code fences — just the raw prompt content as-is.

### Step 3: Confirm with user

Wait for both agents to complete, then emit a deterministic verdict:

```
[OK] devx:dissect-builtin
  Skill:    <skill-name>
  Outputs:  claude/built-in-skills/<skill-name>/README.md
            claude/built-in-skills/<skill-name>/PROMPT.md
  Next:     /gh:commit
```

실패 시:

```
[FAIL] devx:dissect-builtin
  Step:    <Step 1 load | Step 2 agent | Step 2 write>
  Detail:  <error or skill not built-in>
```

## Constraints

- PROMPT.md must be an exact copy of the original prompt. Do not summarize, translate, or reformat.
- README.md is written in Korean. Use English only for technical terms.
- Do not use the filename `SKILL.md` for output — it conflicts with Claude Code's skill loading mechanism.
- If the target skill cannot be loaded (not a built-in skill), inform the user and suggest alternatives.
