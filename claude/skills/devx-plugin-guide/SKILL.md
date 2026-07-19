---
name: devx:plugin-guide
description: >-
  Generate a Korean, human-facing guide doc for an already-installed Claude
  Code plugin by reading its cached SKILL.md files, then update the plugins
  index. Use when the user runs /devx:plugin-guide <plugin-name>, or asks
  "이 플러그인 가이드 만들어줘", "플러그인 문서화해줘", "새 플러그인 스킬
  정리해줘". Produces docs/guide/plugins/<plugin>.md with 3 fixed sections
  (설치 방법 / 스킬 설명 / 사용법). Does NOT install plugins and does NOT
  commit. Accepts `<plugin-name> [--force]` and `-h`/`--help`/`help`.
allowed-tools: Bash, Read, Grep, Write, Edit
metadata:
  model_recommendation:
    tier: sonnet
    reason: "parses N SKILL.md frontmatters + builds a structured Korean doc; low-risk doc writes, no code changes"
    claude: prefer
    non_claude: advisory-only
---

# devx:plugin-guide — Plugin Guide Generator

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
its content verbatim, then stop. No file reads/writes.

## Step 1: Parse Args

Positional: `<plugin-name> [--force]`.

| Arg | Description | Default | Required |
|-----|-------------|---------|----------|
| `<plugin-name>` | `<plugin>@<marketplace>` or `<plugin>` alone | — | Yes |
| `--force` | Regenerate even if the target doc already exists | off | No |

Split `<plugin-name>` on `@` into `PLUGIN` and (optional) `MARKETPLACE`.
The output filename is always `PLUGIN.md`. Missing arg → print
`Run /devx-plugin-guide -h for usage.` and stop.

Set repo root `ROOT` = this dotfiles repo, `CFG=${CLAUDE_CONFIG_DIR:-$HOME/.claude}`.

## Step 2: Verify Installed (F-2)

Grep `claude/plugin/plugins.json` for an entry matching `PLUGIN@`. If found and
`MARKETPLACE` was omitted, take `MARKETPLACE` from the matched entry.

Not found → this is the **not-installed error case**. Print the install
instructions block from `references/help.md` ("설치 안내") filled in with this
plugin + its `marketplaces.json` `owner/repo`, then **stop** — never run
`/plugin install` yourself. The user installs, then re-runs the skill.

## Step 3: Locate Cache + Enumerate Skills (F-3)

```bash
find "$CFG/plugins/cache/<MARKETPLACE>/<PLUGIN>" -maxdepth 4 -iname SKILL.md
```

If multiple version dirs exist, keep only the highest (`sort -V` on the
version path component). Zero `SKILL.md` found → this is the **no-skills error
case**: report `스킬 없음, 문서화 대상 아님` and stop.

If skill count > 10, print ONE warning line
(`스킬 N개 (>10) — YAGNI: 단일 파일로 생성`) and continue with a single file.
Do NOT build subdirectory-splitting logic.

For each `SKILL.md`, read frontmatter `name`/`description` and skim the body for
its one core rule → a 1-2 line "하는 일" summary (see `references/doc-template.md`).

## Step 4: Idempotent Skip (Acceptance: safe re-run)

If `docs/guide/plugins/<PLUGIN>.md` already exists and `--force` was NOT passed:
print `이미 문서화됨 — 재생성하려면 --force` and stop. Do NOT diff or merge
sections. `--force` overwrites the file wholesale.

## Step 5: Write the Doc (F-4, F-6)

Write `docs/guide/plugins/<PLUGIN>.md` in **Korean**, following the exact
3-section skeleton in `references/doc-template.md`
(설치 방법 → 스킬 설명 → 사용법 예제). SKILL.md sources are English; summarize
them in Korean — do not copy English prose.

## Step 6: Update Index (F-5)

Append one line under `## Index` in `docs/guide/plugins/README.md`:
`- [<PLUGIN>](./<PLUGIN>.md) — <one-line Korean summary>`. **Idempotent**: if a
line already links `./<PLUGIN>.md`, skip. `docs/guide/README.md` already has a
`plugins/` link — leave it untouched (add only if genuinely absent).

## Step 7: Report

Print the report per `references/help.md` "출력 형식": `[OK]` verdict, files
written/skipped, skill count, and the next step (review the doc, then commit
manually — this skill never commits).

## Constraints

- Never install plugins / run `/plugin install` (F-2 stops for the user), never
  commit or open a PR (Non-Goal), never smoke-test skills (out of scope).
- Generated docs are Korean (docs/AGENTS.md Language Policy); the SKILL.md
  sources stay English — do not confuse the two. No emojis anywhere.
