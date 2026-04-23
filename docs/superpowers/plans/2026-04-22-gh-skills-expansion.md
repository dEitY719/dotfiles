# gh Skills Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `gh:` 스킬군에 4개 신규 스킬 + 1개 rename 추가. 이슈 기반 구현 워크플로와 3전략 PR 머지를 지원.

**Architecture:** 기존 `gh:commit` / `gh:pr` 패턴을 따르는 5개 원자 스킬 + 1개 얇은 합성 스킬. 각 스킬은 SKILL.md (≤100 줄) + `references/*.md` (상세). 합성 스킬은 Skill tool 로 다른 스킬을 연쇄 호출.

**Tech Stack:** Bash + `gh` CLI + Claude Code Skill tool. 추가 의존성 없음.

**Spec reference:** `docs/superpowers/specs/2026-04-22-gh-skills-expansion-design.md`

---

## File Structure

```
claude/skills/
├── gh-issue/                       [RENAME] → gh-issue-create/
│   └── SKILL.md                    [MODIFY] name: gh:issue → gh:issue-create
├── gh-issue-read/                  [NEW]
│   ├── SKILL.md
│   └── references/
│       ├── help.md
│       ├── output-format.md
│       └── repo-resolution.md      # shared pattern from gh-issue-create
├── gh-issue-implement/             [NEW]
│   ├── SKILL.md
│   └── references/
│       ├── help.md
│       ├── implementation-flow.md
│       └── superpowers-detection.md
├── gh-pr-merge/                    [NEW]
│   ├── SKILL.md
│   └── references/
│       ├── help.md
│       └── strategy-selection.md
└── gh-issue-flow/                  [NEW]
    ├── SKILL.md
    └── references/
        └── help.md
```

**파일 설계 원칙**:
- 각 SKILL.md 는 workflow (steps) 만 담고, 상세 로직은 `references/` 로 분리.
- `references/help.md` 는 항상 존재 (`-h` 출력용, verbatim 복사).
- `references/repo-resolution.md` 는 `gh-issue-create` 것을 참조 복사해서 `gh-issue-read` 에 둠 (나중에 링크로 변경 가능).

---

## Task 1: Rename `gh:issue` → `gh:issue-create`

**Files:**
- Modify: `claude/skills/gh-issue/SKILL.md:2` — `name: gh:issue` → `name: gh:issue-create`
- Modify: `claude/skills/gh-issue/references/help.md:1-14` — 제목·usage 라인 업데이트
- Rename directory: `claude/skills/gh-issue/` → `claude/skills/gh-issue-create/`

- [ ] **Step 1.1: Rename the skill directory**

```bash
git mv claude/skills/gh-issue claude/skills/gh-issue-create
```

- [ ] **Step 1.2: Update SKILL.md frontmatter name**

Edit `claude/skills/gh-issue-create/SKILL.md`:
- Find: `name: gh:issue`
- Replace: `name: gh:issue-create`

Also find/replace any self-reference `gh:issue` → `gh:issue-create` in the SKILL.md body (specifically heading `# gh:issue — Conversation → GitHub Issue` → `# gh:issue-create — Conversation → GitHub Issue`).

- [ ] **Step 1.3: Update help.md usage examples**

Edit `claude/skills/gh-issue-create/references/help.md`:
- Line 1 `# gh:issue — Help` → `# gh:issue-create — Help`
- Usage block: `/gh-issue` → `/gh:issue-create` (2 occurrences), keep `-h`/`--help`/`help` line.

- [ ] **Step 1.4: Update repo-resolution.md title**

Edit `claude/skills/gh-issue-create/references/repo-resolution.md:1`:
- `# gh:issue — Repo resolution` → `# gh:issue-create — Repo resolution`

- [ ] **Step 1.5: Grep for any lingering `gh:issue` bare references**

```bash
grep -rn "gh:issue\b" claude/skills/gh-issue-create/ || echo "clean"
```

Expected: `clean` (no matches, or only matches inside `gh:issue-create`).

If any match is standalone `gh:issue`, edit it.

- [ ] **Step 1.6: Verify directory structure**

```bash
ls claude/skills/gh-issue-create/
ls claude/skills/gh-issue-create/references/
```

Expected:
```
SKILL.md  references
help.md  issue-body-templates.md  repo-resolution.md
```

- [ ] **Step 1.7: Commit**

```bash
git add claude/skills/gh-issue-create claude/skills/gh-issue
git commit -m "refactor(skill): rename gh:issue to gh:issue-create

Adds symmetry with new gh:issue-read and gh:issue-implement skills
(create/read/implement verb naming)."
```

---

## Task 2: Add `gh:issue-read`

**Files:**
- Create: `claude/skills/gh-issue-read/SKILL.md`
- Create: `claude/skills/gh-issue-read/references/help.md`
- Create: `claude/skills/gh-issue-read/references/output-format.md`
- Create: `claude/skills/gh-issue-read/references/repo-resolution.md` (copy from gh-issue-create)

- [ ] **Step 2.1: Create directory tree**

```bash
mkdir -p claude/skills/gh-issue-read/references
```

- [ ] **Step 2.2: Create help.md**

Write to `claude/skills/gh-issue-read/references/help.md`:

````markdown
# gh:issue-read — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | `<issue-number>` or `-h`/`--help`/`help` | — | GitHub issue number (required unless help) |
| 2 | remote-name | `origin` | Git remote whose repo owns the issue |

## Usage

- `/gh:issue-read 42` — fetch issue #42 from `origin`'s repo, print structured summary
- `/gh:issue-read 42 upstream` — fetch from `upstream` remote's repo
- `/gh:issue-read -h` / `--help` / `help` — print this help

## What the skill does

1. Resolves the target repo from the given remote (default `origin`). Missing remote → lists `git remote -v` and stops, no silent fallback.
2. Fetches the issue via `gh issue view <N> --repo $TARGET_REPO --json ...` including body, author, labels, state, comments, assignees, timestamps.
3. Prints a structured summary:
   - Header: `#N <title> by @author (state, labels)`
   - Summary: 2-4 line extraction of what the issue asks for
   - Body: original markdown, preserved verbatim
   - Discussion: comments in chronological order with author + timestamp
   - Meta: created/updated timestamps, assignees, linked PRs
   - Checklist (if the issue contains explicit acceptance criteria)
4. Output is in the user's conversation language (Korean chat → Korean summary section headings, but body/comments stay in their original language).

## What the skill will NOT do

- Modify the issue (no close/label/assign).
- Follow through to linked PRs or other issues (only the one at hand).
- Silently fall back to `origin` when a non-existent remote is given.
- Truncate body or comments — the skill's whole point is preserving detail for humans.
````

- [ ] **Step 2.3: Copy repo-resolution.md from gh-issue-create**

```bash
cp claude/skills/gh-issue-create/references/repo-resolution.md \
   claude/skills/gh-issue-read/references/repo-resolution.md
```

Then edit line 1 of the copy:
- `# gh:issue-create — Repo resolution` → `# gh:issue-read — Repo resolution`

- [ ] **Step 2.4: Create output-format.md**

Write to `claude/skills/gh-issue-read/references/output-format.md`:

````markdown
# gh:issue-read — Output Format

## Structure

The skill prints sections in this exact order. Empty sections are omitted except Header and Body.

### 1. Header

```
#<N> <title> by @<author> (<state>, labels: <csv> | none)
```

`state` is one of `OPEN`, `CLOSED`. If the issue is closed as `not_planned` or `completed`, include that in parens:
`(CLOSED — completed)`.

### 2. Summary (2-4 lines)

Extract what the issue asks for. Start with a verb when possible.
Example:
```
Summary:
- 기존 gh:issue 스킬을 gh:issue-create 로 rename.
- 추가로 gh:issue-read, gh:issue-implement, gh:pr-merge, gh:issue-flow 스킬 신설.
- 얇은 합성 스킬 패턴 도입.
```

### 3. Body (verbatim)

Reproduce the issue body **as written**. Preserve:
- Markdown formatting (headings, code blocks, lists)
- File paths and line references
- Command outputs
- Discussion links

Do NOT summarize or compress.

### 4. Discussion (if comments > 0)

Chronological, one comment per block:
```
--- Comment by @<author> at <ISO-8601 timestamp> ---

<comment body, verbatim>
```

### 5. Meta

```
Created:  <ISO-8601>
Updated:  <ISO-8601>
Assignees: @<user1>, @<user2>  (or "none")
Linked PRs: #<pr1>, #<pr2>      (only if GitHub auto-detected; skip otherwise)
```

### 6. Checklist (if issue contains `- [ ]` items)

Extract all `- [ ]` and `- [x]` items from body and comments, keeping their original text:
```
Checklist:
- [x] Decide skill names
- [ ] Implement gh:issue-read
- [ ] Implement gh:issue-implement
```

## JSON fields to fetch

```bash
gh issue view <N> --repo "$TARGET_REPO" --json \
  number,title,body,author,labels,state,stateReason,\
  comments,assignees,createdAt,updatedAt,url
```

`comments` items: `{author, body, createdAt}`.
`labels` items: `{name}`.
`author`, `assignees` items: `{login}`.
````

- [ ] **Step 2.5: Create SKILL.md**

Write to `claude/skills/gh-issue-read/SKILL.md`:

````markdown
---
name: gh:issue-read
description: >-
  Fetch a GitHub issue by number and print a structured, human-readable
  summary without modifying it. Use when the user runs /gh:issue-read,
  /gh-issue-read, or asks "이슈 #N 읽고 정리해줘", "issue 42 뭐하는 거야",
  "#16 요약", "이 이슈 내용 파악". Preserves body and comments verbatim
  so the output can be reused as context for implementation work. Accepts
  `<issue-number> [remote]`; defaults remote to `origin`. Accepts
  `-h`/`--help`/`help` to print usage.
allowed-tools: Bash, Read, Grep
---

# gh:issue-read — Issue Summary

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Role

Fetch a single GitHub issue and print a structured summary. Read-only —
never mutate the issue. Preserve body + comments verbatim so the output
feeds downstream skills (like `gh:issue-implement`).

## Step 1: Parse Args + Resolve Repo

Positional args: `<issue-number> [remote]`.

- `issue-number` — required, positive integer. Missing/invalid → print
  usage pointer (`Run /gh:issue-read -h for usage.`) and stop.
- `remote` — default `origin`. Resolve `TARGET_REPO=<owner>/<repo>` via
  `git remote get-url <remote>`. Missing remote → list `git remote -v`
  and stop.

Substeps and error templates in `references/repo-resolution.md`.

## Step 2: Fetch Issue

```bash
gh issue view <N> --repo "$TARGET_REPO" --json \
  number,title,body,author,labels,state,stateReason,\
  comments,assignees,createdAt,updatedAt,url
```

On error (issue not found, auth failure), print `gh` stderr verbatim
and stop — do not attempt fallback.

## Step 3: Format Output

Assemble the output per `references/output-format.md`. Sections:
Header → Summary → Body → Discussion → Meta → Checklist.

- **Body** and **Discussion** are verbatim. Do NOT compress, do NOT
  rewrap, do NOT translate.
- **Summary** is your 2-4 line extraction of the ask.
- **Checklist** pulls every `- [ ]` / `- [x]` line from body + comments.
- Match the user's conversation language for section headers
  (`Summary` vs `요약` etc.) but keep content verbatim.

## Step 4: Report

Print the formatted output directly. No preamble ("Here's the issue..."),
no trailing summary ("Let me know if you want..."). The output IS the
deliverable.

## Constraints

- Read-only — never call `gh issue edit`, `close`, or `comment`.
- Never fall back to `origin` when a non-existent remote is passed.
- Never truncate or paraphrase body/comments — the point is preservation.
- Never assume English; match the issue's language in body/comments and
  the user's conversation language for section headers.
````

- [ ] **Step 2.6: Smoke test the skill structure**

```bash
# Verify frontmatter parses (name field exists)
grep -E "^name: gh:issue-read$" claude/skills/gh-issue-read/SKILL.md

# Verify all references are referenced from SKILL.md
for f in help.md output-format.md repo-resolution.md; do
  grep -q "references/$f" claude/skills/gh-issue-read/SKILL.md || echo "MISSING: $f"
done
```

Expected: grep succeeds on name, no "MISSING" output.

- [ ] **Step 2.7: Commit**

```bash
git add claude/skills/gh-issue-read
git commit -m "feat(skill): add gh:issue-read

Fetch a GitHub issue and print a structured, verbatim summary. Read-only
companion to gh:issue-create and precursor to gh:issue-implement."
```

---

## Task 3: Add `gh:pr-merge`

**Files:**
- Create: `claude/skills/gh-pr-merge/SKILL.md`
- Create: `claude/skills/gh-pr-merge/references/help.md`
- Create: `claude/skills/gh-pr-merge/references/strategy-selection.md`

- [ ] **Step 3.1: Create directory tree**

```bash
mkdir -p claude/skills/gh-pr-merge/references
```

- [ ] **Step 3.2: Create help.md**

Write to `claude/skills/gh-pr-merge/references/help.md`:

````markdown
# gh:pr-merge — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | `<pr-number>` or `-h`/`--help`/`help` | — | GitHub PR number (required unless help) |
| 2 | strategy | `rebase` | One of `rebase`, `squash`, `merge` |
| 3 | remote-name | `origin` | Git remote whose repo owns the PR |

## Usage

- `/gh:pr-merge 51` — rebase-merge PR #51 on `origin`'s repo (immediate, no confirmation)
- `/gh:pr-merge 51 squash` — squash-merge
- `/gh:pr-merge 51 merge` — create a merge commit (preserve history)
- `/gh:pr-merge 51 rebase upstream` — rebase-merge against `upstream` remote
- `/gh:pr-merge -h` / `--help` / `help` — print this help

## Strategy guide

- **`rebase`** (default) — linear history. GitHub web "Rebase and merge" button. Best for feature branches with clean commits.
- **`squash`** — collapse all PR commits into one. GitHub web "Squash and merge" button. Best for PRs with noisy WIP commits.
- **`merge`** — preserve all commits + add a merge commit. GitHub web "Create a merge commit" button. Best when commit history carries meaning (releases, multi-author collaboration).

## What the skill does

1. Parses args. Validates strategy ∈ {rebase, squash, merge}.
2. Resolves target repo from remote.
3. Pre-flight (in parallel):
   - PR state, draft status, mergeable, mergeStateStatus, reviewDecision
   - `gh pr checks` — required checks must pass
4. Hard-stops on any of:
   - PR not OPEN / is draft / has merge conflicts
   - Review decision ≠ APPROVED → suggests `gh:pr-merge-emergency` instead
   - Required check failing or pending
5. Runs `gh pr merge <N> --repo $TARGET_REPO --<strategy> --delete-branch` **without confirmation**.
6. Fetches the merge SHA and prints a compact report.

## What the skill will NOT do

- Ask "proceed?" — running the skill IS the confirmation.
- Fall back to another strategy on failure.
- Merge an un-approved PR — use `gh:pr-merge-emergency` for admin bypass with audit trail.
- Keep the head branch — always `--delete-branch`.
````

- [ ] **Step 3.3: Create strategy-selection.md**

Write to `claude/skills/gh-pr-merge/references/strategy-selection.md`:

````markdown
# gh:pr-merge — Strategy Selection

## Default: `rebase`

Matches the "Rebase and merge" button the user clicks on GitHub web.
Produces linear history, no merge commits, preserves individual commit
messages.

## When the repo disables a strategy

GitHub repo settings can disable strategies. If `gh pr merge` fails with
`Pull request merge method is not allowed`, stop and report:

```
PR #<N> merge failed: <strategy> is disabled on this repo.
Allowed strategies (check repo settings > General > Pull Requests):
  - Allow merge commits
  - Allow squash merging
  - Allow rebase merging
```

Do NOT silently switch strategies.

## Strategy → flag mapping

| Strategy | gh flag |
|---|---|
| rebase | `--rebase` |
| squash | `--squash` |
| merge | `--merge` |

## Pre-flight JSON fields

```bash
gh pr view <N> --repo "$TARGET_REPO" --json \
  number,state,isDraft,mergeable,mergeStateStatus,reviewDecision,\
  baseRefName,headRefName,author
```

## Hard-stop decisions

| Field | Value → Stop reason |
|---|---|
| `state` | `!= OPEN` → "PR already <closed\|merged>" |
| `isDraft` | `true` → "draft PR — mark ready first" |
| `mergeable` | `CONFLICTING` → "resolve conflicts first" |
| `reviewDecision` | `!= APPROVED` → "not approved — use /gh-pr-merge-emergency for admin bypass" |

## Required checks

```bash
gh pr checks <N> --repo "$TARGET_REPO" --required
```

Any row with conclusion `FAILURE` or status `IN_PROGRESS`/`QUEUED` → stop.
Only proceed when all required checks are `SUCCESS`.

## Post-merge SHA fetch

```bash
gh pr view <N> --repo "$TARGET_REPO" --json mergeCommit -q .mergeCommit.oid
```

## Final report format

```
PR #<N> merged (<strategy>)
  Merge SHA:  <sha>
  Branch:     <headRefName> → <baseRefName> (deleted)
  URL:        <pr-url>
```
````

- [ ] **Step 3.4: Create SKILL.md**

Write to `claude/skills/gh-pr-merge/SKILL.md`:

````markdown
---
name: gh:pr-merge
description: >-
  Merge an approved GitHub PR using one of three strategies — rebase
  (default), squash, or merge commit — without asking for confirmation.
  Use when the user runs /gh:pr-merge, /gh-pr-merge, or asks "PR 51
  머지해", "rebase merge", "squash merge", "#99 머지". Refuses to merge
  un-approved PRs (suggests gh:pr-merge-emergency instead), failing CI,
  draft PRs, or PRs with conflicts. Accepts
  `<pr-number> [rebase|squash|merge] [remote]`. Accepts `-h`/`--help`/`help`.
allowed-tools: Bash, Read, Grep
---

# gh:pr-merge — Merge Approved PR (3 strategies)

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Step 1: Parse Args + Resolve Repo

Positional args: `<pr-number> [strategy] [remote]`.

- `pr-number` — required, positive integer. Missing/invalid → print
  usage pointer and stop.
- `strategy` — default `rebase`. Must be `rebase`, `squash`, or `merge`.
  Any other value → print allowed values and stop.
- `remote` — default `origin`. Missing remote → `git remote -v` + stop.

## Step 2: Pre-flight (parallel)

Run in one message:
- `gh pr view <N> --repo $TARGET_REPO --json number,state,isDraft,mergeable,mergeStateStatus,reviewDecision,baseRefName,headRefName,author`
- `gh pr checks <N> --repo $TARGET_REPO --required`

**Hard stops** (see `references/strategy-selection.md` for exact table):
- `state != OPEN`
- `isDraft == true`
- `mergeable == CONFLICTING`
- `reviewDecision != APPROVED` → suggest `/gh-pr-merge-emergency` for admin bypass
- Any required check FAILURE or pending

## Step 3: Merge (no confirmation)

```bash
gh pr merge <N> --repo "$TARGET_REPO" --<strategy> --delete-branch
```

Flag mapping in `references/strategy-selection.md`.

If `gh` returns "merge method is not allowed", print the repo-settings
guidance from `references/strategy-selection.md` and stop. **Never**
silently switch strategies.

## Step 4: Fetch Merge SHA + Report

```bash
gh pr view <N> --repo "$TARGET_REPO" --json mergeCommit -q .mergeCommit.oid
```

Print **only** the compact report (format in
`references/strategy-selection.md` → "Final report format").

## Constraints

- Never ask for confirmation — running the skill is the confirmation.
- Never merge an un-approved PR. Redirect to `gh:pr-merge-emergency`.
- Never swap to a different strategy if the chosen one fails.
- Always `--delete-branch` — head branches accumulate fast.
- Never bypass CI. Required checks must pass.
````

- [ ] **Step 3.5: Smoke test**

```bash
grep -E "^name: gh:pr-merge$" claude/skills/gh-pr-merge/SKILL.md
for f in help.md strategy-selection.md; do
  grep -q "references/$f" claude/skills/gh-pr-merge/SKILL.md || echo "MISSING: $f"
done
```

Expected: grep succeeds, no MISSING.

- [ ] **Step 3.6: Commit**

```bash
git add claude/skills/gh-pr-merge
git commit -m "feat(skill): add gh:pr-merge

Merge approved PRs with rebase (default), squash, or merge commit
strategy. Refuses un-approved PRs — directs to gh:pr-merge-emergency
for admin bypass. Complements gh:pr-approve in the review workflow."
```

---

## Task 4: Add `gh:issue-implement`

**Files:**
- Create: `claude/skills/gh-issue-implement/SKILL.md`
- Create: `claude/skills/gh-issue-implement/references/help.md`
- Create: `claude/skills/gh-issue-implement/references/implementation-flow.md`
- Create: `claude/skills/gh-issue-implement/references/superpowers-detection.md`

- [ ] **Step 4.1: Create directory tree**

```bash
mkdir -p claude/skills/gh-issue-implement/references
```

- [ ] **Step 4.2: Create help.md**

Write to `claude/skills/gh-issue-implement/references/help.md`:

````markdown
# gh:issue-implement — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | `<issue-number>` or `-h`/`--help`/`help` | — | GitHub issue number |
| 2 | mode | `direct` | One of `direct`, `plan`, `brainstorming` |
| 3 | remote-name | `origin` | Git remote whose repo owns the issue |

## Usage

- `/gh:issue-implement 16` — direct mode: read issue, implement, run tests. No human intervention.
- `/gh:issue-implement 16 plan` — invoke superpowers:writing-plans first, implement per plan.
- `/gh:issue-implement 16 brainstorming` — invoke superpowers:brainstorming for design, then plan, then implement.
- `/gh:issue-implement 16 direct upstream` — direct mode on `upstream` remote's repo.
- `/gh:issue-implement -h` / `--help` / `help` — print this help.

## Precondition (by convention)

The user runs this skill **after** creating a dedicated git worktree
(e.g., via `gwt`) and `cd`-ing into it. The skill does NOT create
worktrees.

## What the skill does

1. Fetches the issue (same JSON fields as gh:issue-read).
2. Verifies precondition: inside a git repo, on a non-base branch, working tree clean.
3. Depending on mode:
   - **direct** — explores the codebase, edits/creates files, runs tests.
   - **plan** — invokes superpowers:writing-plans with the issue body as context. If issue is ambiguous (see `references/implementation-flow.md` → "Ambiguity signals"), auto-promotes to brainstorming.
   - **brainstorming** — invokes superpowers:brainstorming, then writing-plans, then implements.
4. Auto-detects the test runner (tox / pytest / bats / npm test / ...) from AGENTS.md, `pyproject.toml`, `package.json`, or `tox.ini`.
5. Test-failure loop: up to 3 attempts to fix failures caused by its own edits; pre-existing failures are reported separately, not fixed.
6. Prints a compact report: changed files, test result, next-step hint.

## superpowers plugin not installed → fallback

If `~/.claude/plugins/cache/superpowers-dev/` does not exist, any
`plan`/`brainstorming` mode falls back to `direct` with one warning line:

```
⚠️  superpowers plugin not installed — falling back to direct mode.
```

## What the skill will NOT do

- Create commits or PRs. Stops at "tests pass". Use `/gh:commit` and `/gh:pr` (or `/gh:issue-flow` for the chain).
- Create a git worktree. Use `gwt` first.
- Run on the base branch (main/master). Stops with a feature-branch reminder.
- Run with a dirty working tree (stops and asks).
````

- [ ] **Step 4.3: Create superpowers-detection.md**

Write to `claude/skills/gh-issue-implement/references/superpowers-detection.md`:

````markdown
# gh:issue-implement — superpowers Plugin Detection

## Detection rule

```bash
test -d "$HOME/.claude/plugins/cache/superpowers-dev"
```

- Exit 0 → plugin installed → honor requested mode.
- Exit non-zero → plugin missing → force `direct` mode.

## Fallback behavior

When falling back:

1. Print exactly one warning line (no stack of warnings):
   ```
   ⚠️  superpowers plugin not installed — falling back to direct mode.
   ```
2. Proceed to direct-mode implementation flow.
3. Do NOT error out. The skill should still deliver value when the
   plugin is absent — that's the whole point of the fallback.

## Why this rule

`gh:issue-implement` is shared across teammates with different plugin
setups. Hard-requiring superpowers would make the skill fail entirely
on some machines. Graceful degradation (direct mode is always
available) keeps the skill useful everywhere.

## Invocation of superpowers skills

When in `plan` mode (plugin present):

1. Invoke `Skill(superpowers:writing-plans)` after issuing a 1-line
   context block to the main model:
   ```
   Context for writing-plans: implementing issue #<N> of <TARGET_REPO>.
   Issue body follows below. Save plan to docs/superpowers/plans/.
   ```
2. Wait for the plan document to be committed.
3. Then invoke `Skill(superpowers:executing-plans)` or proceed to
   execute inline — both are valid; execute inline for the single-skill
   happy path.

In `brainstorming` mode:

1. Invoke `Skill(superpowers:brainstorming)` with the issue as the
   input idea.
2. brainstorming → writing-plans → execute, per its own terminal state.

## Ambiguity → auto-promote from plan to brainstorming

When mode is `plan`, check these signals on the fetched issue BEFORE
invoking writing-plans. If any is true, invoke brainstorming instead:

- Issue body is empty or `< 200` characters.
- No action verb in title or body (추가/수정/삭제/구현/변경/fix/add/
  update/remove/refactor).
- Body contains "어떻게 할지 상의", "논의 필요", "아이디어", "TBD",
  "to discuss".
- Comments contain contradictory requirements (e.g., one comment
  says "use X", another says "don't use X").

Print one line before promoting:

```
Issue #<N> looks ambiguous — upgrading 'plan' to 'brainstorming' for design alignment.
```
````

- [ ] **Step 4.4: Create implementation-flow.md**

Write to `claude/skills/gh-issue-implement/references/implementation-flow.md`:

````markdown
# gh:issue-implement — Implementation Flow

## Preconditions

Run these in parallel at start; all must pass:

- `git rev-parse --show-toplevel` — must succeed (in a git repo).
- `git rev-parse --abbrev-ref HEAD` — must NOT equal the default branch.
  Get default via `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`.
- `git status --porcelain` — must be empty (clean working tree).

**Failure responses:**
- Not in a repo → "Not in a git repo. cd into one first." + stop.
- On base branch → "Current branch is the base. Create a feature branch (e.g., `gwt <name>`) first." + stop.
- Dirty tree → print `git status` + "Clean or stash first." + stop.

## Test runner detection

Check in this order and use the first match:

1. `AGENTS.md` — grep for `tox`, `pytest`, `bats`, `npm test`; if a code block starts with one, use it.
2. `tox.ini` exists → `tox`.
3. `pyproject.toml` contains `[tool.pytest.ini_options]` → `pytest`.
4. `package.json` contains `"test"` script → `npm test`.
5. `tests/*.bats` exists → `bats tests/`.
6. Fallback → report "No test runner detected, skipping tests." (not an error).

Store the chosen command as `$TEST_CMD`.

## Direct-mode flow

1. Fetch issue (same `gh issue view --json ...` as gh:issue-read).
2. Extract change intent from body + comments.
3. Scan repo structure: read AGENTS.md, CLAUDE.md, top-level README if present.
4. Identify files to touch. For each file:
   - Use `Read` to load current content (if exists).
   - Use `Edit`/`Write` to modify/create.
5. Run `$TEST_CMD`. Capture output.
6. If fail → **Test-failure loop** (below).
7. Report.

## Test-failure loop (max 3 iterations)

```
attempt = 1
while attempt <= 3 and tests fail:
    a. Parse failure output. Identify failing test(s) + error message.
    b. Determine if failure is caused by the skill's edits:
       - Git diff since skill start shows touched files overlapping the
         failing test's module → CAUSED by skill edits.
       - Otherwise → PRE-EXISTING.
    c. If CAUSED:
       - Re-read the failing test and the edited file.
       - Make a targeted fix (smallest possible edit).
       - Re-run $TEST_CMD.
       - attempt += 1
    d. If PRE-EXISTING:
       - Move it to the pre-existing bucket, not the fix loop.
       - Stop looping on this test.

If attempt > 3 and tests still fail:
    Stop. Report with:
    - Files changed so far (diff summary)
    - Failing tests + their last error output
    - Whether each is skill-caused or pre-existing
    - "Manual intervention needed."
```

## Final report format

Success:
```
gh:issue-implement #<N> complete
  Mode:     <direct|plan|brainstorming>
  Changes:
    <path1>  (new|modified)
    <path2>  (new|modified)
  Tests:    <n passed>, <n failed>, <n pre-existing failures>
  Next:     /gh:commit && /gh:pr   (or /gh:issue-flow to do both)
```

Failure (test loop exhausted):
```
gh:issue-implement #<N> stopped after 3 test-fix attempts
  Mode:     <mode>
  Changes:  <list>
  Failing (caused by edits):
    <test1> — <error summary>
    <test2> — <error summary>
  Pre-existing failures (not touched):
    <test3>
  Last diff snippet:
    <file:line>
  Resolution: review the edits above, fix manually, re-run tests.
```
````

- [ ] **Step 4.5: Create SKILL.md**

Write to `claude/skills/gh-issue-implement/SKILL.md`:

````markdown
---
name: gh:issue-implement
description: >-
  Read a GitHub issue by number and implement it — editing files and
  running tests, but NOT committing or opening a PR. Use when the user
  runs /gh:issue-implement, /gh-issue-implement, or asks "issue #16
  구현해", "PR 없이 이 이슈 코드만 짜줘", "implement #42". Default mode
  is direct (no human intervention); optional `plan` or `brainstorming`
  modes invoke the matching superpowers skills when the plugin is
  installed (falls back to direct with a warning if not). Precondition:
  user is already inside a dedicated git worktree on a feature branch.
  Accepts `<issue-number> [direct|plan|brainstorming] [remote]` and
  `-h`/`--help`/`help`.
allowed-tools: Bash, Read, Grep, Glob, Edit, Write
---

# gh:issue-implement — Issue → Code

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Step 1: Parse Args + Preconditions

Positional args: `<issue-number> [mode] [remote]`.

- `issue-number` — required, positive integer.
- `mode` — default `direct`. Must be `direct`, `plan`, or `brainstorming`.
- `remote` — default `origin`.

Check preconditions in parallel (exact rules in
`references/implementation-flow.md` → "Preconditions"):
- in a git repo
- current branch ≠ default branch
- working tree clean

Fail-fast on any precondition with the reasons from that file.

## Step 2: superpowers Plugin Detection

Per `references/superpowers-detection.md`:
- If plugin missing → force mode = `direct` + print one warning line.
- Else → honor the requested mode.

## Step 3: Fetch Issue

```bash
gh issue view <N> --repo "$TARGET_REPO" --json \
  number,title,body,author,labels,state,comments,url
```

On error (not found, auth) → print stderr + stop.

## Step 4: Mode Dispatch

- **`direct`** → go to Step 5.
- **`plan`** → check ambiguity signals (list in
  `references/superpowers-detection.md`). If any → switch to
  `brainstorming`. Else invoke `Skill(superpowers:writing-plans)`.
  After plan is approved, proceed to Step 5 guided by the plan.
- **`brainstorming`** → invoke `Skill(superpowers:brainstorming)`.
  That skill's terminal state invokes writing-plans. After plan is
  approved, proceed to Step 5 guided by the plan.

## Step 5: Implement + Test

Use the direct-mode flow in `references/implementation-flow.md`:

1. Detect test runner → `$TEST_CMD`.
2. Scan repo context (AGENTS.md, CLAUDE.md, README).
3. Identify files to touch; use Edit/Write.
4. Run `$TEST_CMD`.
5. On failure → test-failure loop (max 3 iterations).

## Step 6: Report

Print the success or failure report per
`references/implementation-flow.md` → "Final report format". Always
include the `Next:` hint pointing to `gh:commit` / `gh:pr` /
`gh:issue-flow`.

## Constraints

- Never create commits or PRs. That's a deliberate boundary.
- Never create a git worktree. User runs `gwt` first by convention.
- Never run on the default branch. Always require a feature branch.
- Never dismiss pre-existing test failures by fixing them — report
  them as pre-existing.
- Never retry the test-failure loop more than 3 times. Human handoff
  is safer than infinite loops.
- Never require superpowers to work. Direct mode is always available.
````

- [ ] **Step 4.6: Smoke test**

```bash
grep -E "^name: gh:issue-implement$" claude/skills/gh-issue-implement/SKILL.md
for f in help.md implementation-flow.md superpowers-detection.md; do
  grep -q "references/$f" claude/skills/gh-issue-implement/SKILL.md || echo "MISSING: $f"
done
```

Expected: grep succeeds, no MISSING.

- [ ] **Step 4.7: Commit**

```bash
git add claude/skills/gh-issue-implement
git commit -m "feat(skill): add gh:issue-implement

Read an issue and implement it (edit + test), stopping before commit.
Default direct mode runs without human intervention (enables
gh:issue-flow). Optional plan/brainstorming modes invoke superpowers
skills when installed, falling back to direct otherwise."
```

---

## Task 5: Add `gh:issue-flow` (composition)

**Files:**
- Create: `claude/skills/gh-issue-flow/SKILL.md`
- Create: `claude/skills/gh-issue-flow/references/help.md`

- [ ] **Step 5.1: Create directory tree**

```bash
mkdir -p claude/skills/gh-issue-flow/references
```

- [ ] **Step 5.2: Create help.md**

Write to `claude/skills/gh-issue-flow/references/help.md`:

````markdown
# gh:issue-flow — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | `<issue-number>` or `-h`/`--help`/`help` | — | GitHub issue number |
| 2 | remote-name | `origin` | Git remote whose repo owns the issue |

## Usage

- `/gh:issue-flow 16` — chain: implement → commit → PR for issue #16 on `origin`.
- `/gh:issue-flow 16 upstream` — same chain on `upstream` remote.
- `/gh:issue-flow -h` / `--help` / `help` — print this help.

## What this skill chains

This skill invokes **3 skills in sequence** (each step runs only if the previous succeeded):

1. **`gh:issue-implement <N> direct`** — reads the issue, edits files, runs tests. No human intervention.
2. **`gh:commit`** — creates a commit for the changes with a message derived from the conversation (follows the repo's commit style).
3. **`gh:pr`** — pushes the branch and opens a PR, auto-linking `Closes #<N>`.

If any step fails, the chain stops immediately. No automatic retry.
The final report shows which steps ran, which failed, and how to
resume manually.

## When to use this vs the atomic skills

Use `/gh:issue-flow` when:
- The issue is straightforward and you trust direct-mode to get it right.
- You want one command → PR URL output.

Use the atomic skills (`/gh:issue-implement` + `/gh:commit` + `/gh:pr`)
separately when:
- You want to review changes before committing.
- You need plan or brainstorming mode (gh:issue-flow uses direct only).
- The issue is complex and may need several commits before PR.

## Precondition

Same as `gh:issue-implement`: already inside a dedicated git worktree
on a feature branch with a clean working tree.

## What this skill will NOT do

- Run `gh:issue-implement` in `plan` or `brainstorming` mode — only
  direct. Use atomic skills manually for those modes.
- Retry failed steps.
- Roll back partial progress — if step 2 (commit) succeeded but step
  3 (PR) failed, the commit stays.
- Create a worktree or branch — user must be on a feature branch already.
````

- [ ] **Step 5.3: Create SKILL.md**

Write to `claude/skills/gh-issue-flow/SKILL.md`:

````markdown
---
name: gh:issue-flow
description: >-
  Composition skill that chains gh:issue-implement → gh:commit → gh:pr
  for a single issue number. Use when the user runs /gh:issue-flow,
  /gh-issue-flow, or asks "issue #16 처음부터 PR까지 자동으로",
  "이슈 구현하고 커밋하고 PR까지 한방에", "full flow on #42". Uses
  direct implementation mode only — for plan/brainstorming modes, use
  the atomic gh:issue-implement skill manually. Stops on first step
  failure with a resume-instructions report. Precondition: already on
  a feature branch in a dedicated worktree. Accepts
  `<issue-number> [remote]` and `-h`/`--help`/`help`.
allowed-tools: Bash, Read, Grep
---

# gh:issue-flow — Issue → PR composition

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

The help output explicitly names the 3 chained skills:
gh:issue-implement, gh:commit, gh:pr.

## Step 1: Parse Args

- `issue-number` — required, positive integer.
- `remote` — default `origin`.

This skill takes no `mode` arg; implementation is always `direct`.

## Step 2: Chain the 3 Skills

Invoke in order. Each uses Claude Code's Skill tool. Each runs only
if the previous completed successfully.

1. **Step 2.1 — gh:issue-implement**
   ```
   Skill(gh:issue-implement, "<N> direct <remote>")
   ```
   Track success = skill returned its success report (not failure).

2. **Step 2.2 — gh:commit** (only if 2.1 succeeded)
   ```
   Skill(gh:commit)
   ```
   gh:commit auto-detects the issue number from the conversation
   (the `#<N>` was just mentioned by Step 2.1's report), so no
   explicit args needed.

3. **Step 2.3 — gh:pr** (only if 2.2 succeeded)
   ```
   Skill(gh:pr, "<N>")
   ```
   Passing the issue number ensures `Closes #<N>` ends up in the PR
   body via gh:pr's Step 3 (issue resolution).

## Step 3: Report

If all 3 succeeded:
```
gh:issue-flow complete (#<N>)
  ✓ Step 1: gh:issue-implement  (<n files changed>, <n tests passed>)
  ✓ Step 2: gh:commit            (<sha> "<subject>")
  ✓ Step 3: gh:pr                (PR #<M>)
  PR URL: <pr-url>
```

If a step failed:
```
gh:issue-flow stopped at step <i>/3 (<skill-name>)
  ✓ Step 1: gh:issue-implement  (<summary>)
  ✗ Step <i>: <skill-name>       (<failure reason>)
  ⊘ Steps <i+1>..3               (not reached)

Resume after fix:
  /<commands to finish>
```

Resume hint logic:
- Failed at step 1 → `/gh:issue-implement <N>` (user decides retry).
- Failed at step 2 → `/gh:commit && /gh:pr <N>`.
- Failed at step 3 → `/gh:pr <N>`.

## Constraints

- Never invoke implementation modes other than `direct`.
- Never retry a failed step. Human decides retry or fix.
- Never skip a step. All 3 or stop.
- Never mutate state between steps beyond what the sub-skills do.
- Do NOT preface or summarize beyond the compact report.
````

- [ ] **Step 5.4: Smoke test**

```bash
grep -E "^name: gh:issue-flow$" claude/skills/gh-issue-flow/SKILL.md
grep -q "references/help.md" claude/skills/gh-issue-flow/SKILL.md || echo "MISSING: help.md"

# Verify help explicitly names all 3 chained skills
for s in gh:issue-implement gh:commit gh:pr; do
  grep -q "$s" claude/skills/gh-issue-flow/references/help.md || echo "MISSING chain reference: $s"
done
```

Expected: grep succeeds, no MISSING.

- [ ] **Step 5.5: Commit**

```bash
git add claude/skills/gh-issue-flow
git commit -m "feat(skill): add gh:issue-flow composition skill

Chains gh:issue-implement -> gh:commit -> gh:pr in one command. Uses
direct implementation mode only. Introduces the thin-composition-skill
pattern for orchestrating multiple atomic gh: skills without resorting
to subagents."
```

---

## Task 6: Push + PR

- [ ] **Step 6.1: Push branch**

```bash
git push -u origin HEAD
```

If upstream exists already, plain `git push`.

- [ ] **Step 6.2: Open PR via gh:pr skill**

Invoke `Skill(gh:pr)` in the conversation. The skill will:
- Bundle all 5 commits into the PR body.
- Auto-link this work (no associated issue, so just descriptive body).
- Return PR URL.

Expected output: `PR created: https://github.com/dEitY719/dotfiles/pull/<N>`

---

## Final Checklist

After Task 6:

- [ ] All 5 commits landed on `wt/feat/1`.
- [ ] PR open with all 5 commits visible.
- [ ] `ls claude/skills/` shows: gh-commit, gh-issue-create, gh-issue-flow, gh-issue-implement, gh-issue-read, gh-pr, gh-pr-approve, gh-pr-merge, gh-pr-merge-emergency, gh-pr-reply (10 gh:* skills total).
- [ ] No references to bare `gh:issue` remain (grep confirms).
- [ ] Spec referenced in commit bodies where relevant.

## Post-merge smoke tests (manual, out of scope for this plan)

After the PR merges to main, run these manually (documented in spec §테스트 전략):

1. `/gh:issue-create -h` — expects help output with new `create` suffix.
2. `/gh:issue-read <some-real-issue>` — expects verbatim structured summary.
3. `/gh:issue-implement <trivial-docs-issue>` — expects file edit + tests pass + next-step hint.
4. `/gh:issue-implement <trivial-issue> plan` — expects writing-plans invocation.
5. Rename `~/.claude/plugins/cache/superpowers-dev/` temporarily, run `/gh:issue-implement <N> plan` — expects warning + direct-mode fallback.
6. Create a test PR, run `/gh:pr-merge <N>` (rebase default), `/gh:pr-merge <M> squash`, `/gh:pr-merge <K> merge`.
7. Make an un-approved PR, run `/gh:pr-merge <N>` — expects refusal + emergency-merge suggestion.
8. Run `/gh:issue-flow <N>` on a simple issue — expects happy-path all-3-steps output.
