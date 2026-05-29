# Design: `/gh:issue-proceed` Skill

**Created**: 2026-05-30
**Status**: Design (awaiting user review → writing-plans → implementation)
**Owner**: panicdna@gmail.com
**Source**: brainstorming session in quantfolio worktree `wt/issue-47/1` (spawning context: closure of umbrella #47 series)
**Approach**: A — Slim wrapper mirroring `/gh:issue-implement` 6-step shell

---

## 1. Intent & positioning

### 1.1 Problem

GitHub issues come in two distinct shapes:

- **Code-change requests** — "implement feature X", "fix bug Y". Existing skill: `/gh:issue-implement`.
- **Work-order / directive issues** — verify/triage/analysis/audit tasks whose body contains an embedded **execution protocol** (numbered steps + decision rules + deliverables + done criteria). Examples authored in this conversation: quantfolio #78 (CLI manual end-to-end verify), #79 (docs PR ship), #80 (backlog triage), #81 (strategy inventory analysis).

`/gh:issue-implement` assumes "edit files to satisfy the issue". Directive issues need a different verb: "execute the protocol embedded in the issue body". Today there is no skill for that — the user has to drive each step manually or rely on the LLM's ad-hoc reading of the issue.

### 1.2 What `/gh:issue-proceed` does

Reads a GitHub directive issue, validates the embedded protocol against a strict 8-section schema, executes the protocol end-to-end **without human intervention**, applies write actions (commit / PR / comment / close / file follow-up issue) where the protocol authorizes them, and produces a structured audit report.

### 1.3 Explicit non-goals

- **Not a replacement** for `/gh:issue-implement`. Directive issues are a sibling class, not a superset.
- **Not a PR-merge skill** — that responsibility belongs to `/gh:pr-merge` / `/gh:pr-merge-emergency`.
- **Not a brainstorming skill** — directive issues are already designed; this skill executes them.
- **Not a code generator** for the directive itself — humans (or `/devx:trd-to-issues`-style helpers) author the directive.

---

## 2. Architectural decisions (settled in brainstorming)

| # | Decision | Value |
|---|---|---|
| D-1 | Write authority | **Full directive authority** — skill may commit, push, comment, close, file issues, open PRs when the protocol so dictates. Safety gates (§4) provide the floor. |
| D-2 | Schema strictness | **Strict** — refuse with a structured error any issue lacking the 8 required sections (§3). |
| D-3 | Worktree precondition | **Conditional** — auto-detect from issue body whether mutation is required, then enforce branch + clean tree accordingly (§5.1). |
| D-4 | Mode dispatch | **None** — always direct execution. No `plan`/`brainstorming` modes. The directive *is* the plan. |
| D-5 | Composition | **Yes, via `Skill()`** — call `/gh:commit`, `/gh:pr`, `/gh:issue-create`, `/gh:issue-read` for matching action verbs (§3.6). Inline `gh` CLI only for single-shot ops (comment / close / label). |
| D-6 | Progress tracking | **TaskCreate per parsed step** — real-time visible progress; metadata stores per-step result + classification (§3.5). |
| D-7 | Skill family | **Sibling of `/gh:issue-implement`** — same 6-step shell, but Step 2 (superpowers detection) and Step 4 (mode dispatch) are dropped; Step 5 swaps "implement+test" for "execute protocol". |

---

## 3. Protocol schema (`references/protocol-schema.md`)

Issue body must contain **8 required sections**, each identified by an H2 or H3 heading whose normalized text matches one of the listed aliases (case-insensitive substring; alias list per row is OR).

### 3.1 Required sections

**"Empty" definition** (used uniformly below): section content under 50 chars after stripping leading/trailing whitespace, markdown list markers (`-`, `*`, `1.`), and code-fence delimiters.

| # | Key | Aliases | Failure rule |
|---|---|---|---|
| 1 | `goal` | `Goal`, `목표` | fail if empty |
| 2 | `preconditions` | `Preconditions`, `사전 조건`, `Prerequisites` | fail if empty |
| 3 | `execution_protocol` | `Execution Protocol`, `Execution Matrix`, `실행 절차`, `Steps` | fail if empty **or** if no parseable steps (§3.3) |
| 4 | `decision_rules` | `Decision Rules`, `결정 규칙`, `Branching`, `Decision matrix` | fail if empty |
| 5 | `deliverables` | `Deliverables`, `산출물`, `Output`, `Outputs` | fail if empty |
| 6 | `done_criteria` | `Done Criteria`, `종료 조건`, `Acceptance`, `Acceptance Criteria` | fail if no `- [ ]` or `- [x]` checklist item found |
| 7 | `out_of_scope` | `Out of Scope`, `Out-of-scope`, `범위 밖` | fail if empty |
| 8 | `safety` | `Safety`, `Safety / Abort`, `Abort`, `안전 규칙`, `Safety Rules` | fail if empty |

### 3.2 Recommended (optional, parsed if present)

- `background` — context
- `references` — external links
- `track` — explicit `verify-only` declaration that overrides mutation auto-detection (§5.1)

### 3.3 Step parsing in `execution_protocol`

Two formats auto-detected:

| Format | Trigger | Result |
|---|---|---|
| **Matrix mode** | A markdown table with header row containing `#`, `Workflow`/`Step`, `Command`/`명령` | one parsed step per data row |
| **Numbered mode** | `^### \d+\.` or `^\d+\.` lines | one parsed step per numbered block until the next sibling heading |

Both formats normalize into the same step record: `{index, description, command_block_or_text, expected_outcome}`.

### 3.4 Validation failure output

```
gh:issue-proceed #<N> schema validation failed
  Missing required sections:
    - <key>  (aliases tried: ...)
  Empty required sections:
    - <key>  (heading present, content < 50 chars)
  Unparseable sections:
    - execution_protocol  (no matrix table and no numbered steps found)
  Fix the issue body to satisfy the directive schema, then retry.
  Reference: <repo>/docs/feature/gh-issue-proceed-skill/design.md §3
```

No comment is posted on the validated issue itself — schema failure is a caller-side problem.

---

## 4. Safety gates (`references/safety-gates.md`)

Four layers, listed from strictest to weakest. Each layer can independently trigger abort.

### 4.1 Layer 1 — Absolute prohibitions (ignored even if the issue body says so)

| Pattern | Detection | Behavior |
|---|---|---|
| `git push --force` to default branch | pre-execute pattern match | abort |
| `git push --force` (general) | pre-execute | abort — only `--force-with-lease` allowed, and only when §safety authorizes |
| `rm -rf` outside `$PWD` | pre-execute path resolution | abort |
| Destructive DB ops (`admin reset`, `DROP`, `TRUNCATE`, mass DELETE) | command keyword match | abort |
| Secret in any output (`*_KEY`, `*_TOKEN`, `*_SECRET`, `password=`, `Bearer `, JWT shape) | stdout/stderr regex stream scan | abort + output never posted to GitHub |
| Cross-worktree mutation | pre-execute path check against `git worktree list` | abort |
| `gh pr merge` | command match | abort — sibling skills handle this |
| Branch deletion (`git branch -D`, `gh api -X DELETE` against branches) | command match | abort |
| Reopen of a non-self closed issue | command match | abort |

The list lives in `references/safety-gates.md` as the SSOT `ABSOLUTE_BLOCK_PATTERNS`. Triggering it: skill aborts, comments on the proceed issue with `[blocked] absolute prohibition triggered: <pattern>`, leaves the proceed issue open for manual review.

### 4.2 Layer 2 — Conditional permissions (allowed only when §safety explicitly opts in)

| Action | Required §safety token (exact substring) |
|---|---|
| Bulk-close (≥5 issues) | `allow: bulk-close` |
| Bulk-create (≥5 new issues) | `allow: bulk-create-issue` |
| Force-with-lease push | `allow: force-with-lease` |
| Non-allowlisted outbound network | `allow: net: <host glob>` |
| Cross-repo mutation | `allow: cross-repo: <owner/repo>` |

Default-deny. Missing token → action treated as Layer-1 abort.

### 4.3 Layer 3 — Pre-flight (Step 5 entry, parallel)

All must pass or skill stops with hint:

- Current branch ≠ default (only enforced when mutation class — §5.1).
- No untracked secret-shaped files (`.env`, `*.pem`, `*.key`) in working tree.
- `gh auth status` succeeds.
- §preconditions block executes successfully (dry-run any embedded check commands).

### 4.4 Layer 4 — Runtime monitors

| Monitor | Default | Override |
|---|---|---|
| Per-step timeout | 5 min | §preconditions may state `per-step timeout: <N>m` |
| Global timeout | 60 min | §preconditions may state `global timeout: <N>m` |
| Output secret scanner | always on | none — never overrideable |
| Write-action quota | per-type ceiling 5 (close / create / commit / pr / comment counted separately, excluding self-comment / self-close) **and** total ceiling 20 across all types | §safety `allow: bulk-close`/`bulk-create-issue` raises the matching per-type ceiling to 50; total ceiling stays 20 unless §safety also declares `allow: total-quota: <N>` |
| Edit-path memory | always on | none — needed for §6 audit |

---

## 5. Execution semantics (`references/execution-flow.md`)

### 5.1 Conditional worktree precondition

Mutation-required keywords scanned in §deliverables ∪ §execution_protocol ∪ §decision_rules:

- `commit_changes`, `Skill(gh:commit)`, `git commit`
- `open_pr`, `Skill(gh:pr)`, `gh pr create`
- `queue_doc_patch`
- "신규 파일" / "new file" in deliverables

Precondition classes:

| Class | Trigger | Requirements |
|---|---|---|
| `read-only` | no mutation keyword | git repo only; any branch OK |
| `mutation-required` | ≥1 mutation keyword | worktree + non-default branch + clean tree |
| `mixed` | mutation + `allow: cross-repo` | mutation-required + cross-repo permission check |
| `verify-only` (override) | §track = `verify-only` | force read-only regardless of keywords |

Class is logged to stdout on Step 1 entry. Mismatch (e.g., `mutation-required` while on `main`) → fail with remediation hint.

### 5.2 Step loop (pseudocode)

```
parsed_steps = parse(execution_protocol)              # matrix or numbered

for step in parsed_steps:
    TaskCreate(subject="Step <n>: <description>",
               activeForm="Executing step <n>")
    start = now()

    result = LLM.execute(
        step,
        out_of_scope=section_content["out_of_scope"],
        safety_layer1=ABSOLUTE_BLOCK_PATTERNS,
    )

    classification = LLM.classify(
        result,
        allowed=decision_rules.keywords,
        fail_closed_on_unknown=True,                  # never invent a class
    )

    action_verb = decision_rules[classification]
    apply(action_verb)                                # §5.3

    TaskUpdate(taskId=step.id, status=completed,
               metadata={"result": ..., "classification": ...})

    if now() - start > per_step_timeout:
        # retroactive TIMEOUT
        apply(decision_rules["TIMEOUT"])

if all_done_criteria_met and no_abort:
    close_proceed_issue()
else:
    keep_open + final_comment

# done_criteria_met semantics:
#   - Parse all `- [ ]` and `- [x]` items from section_content["done_criteria"].
#   - Items already `- [x]` in the body are assumed pre-satisfied (authoring-time).
#   - For each `- [ ]` item, the skill matches it against executed write actions
#     and step classifications. If every `- [ ]` item has a matching audit entry,
#     done_criteria_met = True.
#   - If matching is ambiguous (item text doesn't clearly map to any verb),
#     done_criteria_met = False — skill keeps the issue open.
```

### 5.3 Action verb registry (`references/execution-flow.md`)

Fixed allowlist. Unknown verb in decision rule → fail-closed at parse time.

| Verb | Implementation |
|---|---|
| `continue` | proceed to next step |
| `file_issue: <template-key>` | `Skill(gh:issue-create, payload=...)`. **Template source**: the issue body's §decision_rules section defines named templates inline (e.g., a markdown sub-block under the rule row) — the `<template-key>` references that block by name. If no template is found, the skill substitutes a minimal default `{title: "<auto>", body: "Filed by /gh:issue-proceed from #<N> step <s>", labels: []}`. |
| `queue_doc_patch: <file>` | accumulate; flushed as single commit + PR in Step 6 |
| `comment_on_self: <body>` | `gh issue comment <PROCEED_N>` |
| `comment_on_other: <N> <body>` | `gh issue comment <N>` |
| `commit_changes` | `Skill(gh:commit)` |
| `open_pr` | `Skill(gh:pr)` |
| `close_issue: <N>` | `gh issue close <N>` |
| `abort_all` | break + final report; proceed issue stays open |
| `skip` | record result only; next step |

### 5.4 Composition payload protocol

When the skill calls another skill, payload is **always structured** (no free-form prompt):

```
Skill(gh:issue-create, prompt=<<STRUCTURED
TITLE: <...>
BODY: <markdown>
LABELS: <comma-list>
NO_INTERACTIVE: true
STRUCTURED)
```

Callees that see `NO_INTERACTIVE: true` skip confirmation prompts. This contract must be added to each composed skill in a follow-up. (Tracked as part of implementation; not blocking the proceed skill itself.)

---

## 6. Reporting (`references/report-format.md`)

### 6.1 Per-step audit (always)

| # | Step | Result | Classification | Verb applied | Duration |
|---|---|---|---|---|---|
| 1 | help | PASS | PASS | continue | 4s |
| 2 | stock list 1 10 | FAIL-CLI | FAIL-CLI | file_issue: #NN | 12s |
| ... | | | | | |

### 6.2 Write-action audit

```markdown
### Write actions executed
| # | Action | Target | Triggered by step | Triggered by rule |
|---|---|---|---|---|

### Blocked attempts
(none) | <list>

### Aborts
(none) | reason: <layer-N pattern>
```

### 6.3 Done-criteria reconciliation

Compare §done_criteria checklist to actual matrix outcomes. Any unchecked item lists the reason ("step skipped: SKIP-NET", etc.).

### 6.4 Outcome

| All done + no abort | partial | abort |
|---|---|---|
| `close_issue: <self>` + final comment | keep-open + final comment with `N/M criteria met` | keep-open + final comment with `[aborted] <layer> <pattern>` |

### 6.5 `ai-metrics`

```
[ai-metrics:gh-issue-proceed] ~{ELAPSED} min — write actions: {N}, blocked: {M}
```

---

## 7. File layout

```
~/dotfiles/claude/skills/gh-issue-proceed/
├── SKILL.md                          (~120 lines: 4-step shell + Constraints)
└── references/
    ├── help.md                       (full --help)
    ├── repo-resolution.md            (reuse strategy decided in impl)
    ├── fetch-issue.md                (reuse strategy decided in impl)
    ├── claim.md                      (reuse strategy decided in impl)
    ├── protocol-schema.md            (§3 — 8 sections, aliases, parser)
    ├── preconditions.md              (§5.1 — 4-class detection)
    ├── execution-flow.md             (§5.2-5.4 — step loop, verb registry, payload)
    ├── safety-gates.md               (§4 — 4 layers, ABSOLUTE_BLOCK_PATTERNS SSOT)
    └── report-format.md              (§6 — audit templates)
```

> The three "reuse" files (`repo-resolution`, `fetch-issue`, `claim`) currently exist in `/gh:issue-implement` and `/gh:issue-read`. Reuse strategy (symlink vs copy vs new module) is left to the implementation plan — both options are valid; preference depends on dotfiles conventions to be confirmed during writing-plans.

---

## 8. Testing

| Layer | Approach |
|---|---|
| Schema validator | unit test (bats or shell). Fixtures: all-OK, 1-missing, empty-section, H3-nested, KO-aliases |
| Step parser | unit test. Fixtures: matrix-only, numbered-only, mixed-malformed |
| Safety Layer 1 patterns | regex unit tests per pattern |
| End-to-end smoke | run the skill on its own tracking issue (the one created in step §10) in a sandboxed scratch issue context |
| Composition payload | mock Skill() calls; assert STRUCTURED payload shape |

Test home: `~/dotfiles/claude/skills/gh-issue-proceed/tests/` (introduces test-dir convention if absent; confirm during writing-plans).

---

## 9. Edge cases

| Case | Behavior |
|---|---|
| Issue closed already | Step 3 refusal (`already closed`); precedes schema check |
| Hierarchical execution_protocol (sub-protocols at H4+) | Only the canonical execution_protocol section is parsed for steps; H4 content is context only |
| Re-running a partially-done issue | TaskList consulted; resume at first non-completed step IF the issue body declares `Re-runnable: true`; else abort with `[manual-review] non-idempotent rerun` |
| Network failure mid-step | retry once; second failure → BLOCKED via decision rules |
| Directive itself is broken (references nonexistent file/command) | classify as FAIL; comment `[doc-bug] protocol references nonexistent <X>`; abort |
| Decision rules don't cover an actual result class | first unhandled → BLOCKED; counts as dynamic schema violation |

---

## 10. Acceptance criteria (for the implementation issue)

- [ ] `SKILL.md` at `~/dotfiles/claude/skills/gh-issue-proceed/` ≤ 150 lines, 4-step shell + Constraints
- [ ] All 8 `references/*.md` files present and SSOT-consistent with this design
- [ ] Schema validator passes 5 fixture variants (all-OK, missing, empty, H3, KO)
- [ ] Safety Layer 1 patterns covered by unit tests (one positive + one negative per pattern)
- [ ] End-to-end smoke test against a scratch directive issue passes
- [ ] Sibling skill descriptions (`gh-issue-implement`, `gh-issue-read`) updated to cross-link `[[gh:issue-proceed]]`
- [ ] PR opened against `~/dotfiles` `main`; CI green
- [ ] Tracking issue (filed alongside this design) closed automatically via PR's `Closes #<N>`

---

## 11. Open questions (resolved during writing-plans)

1. Reuse strategy for `repo-resolution.md` / `fetch-issue.md` / `claim.md` — symlink, copy, or extract to shared `claude/skills/_lib/`?
2. Test convention — does dotfiles already have a per-skill test pattern, or does this skill introduce one?
3. `STRUCTURED` payload contract on composed skills — needs follow-up edits to `/gh:commit`, `/gh:pr`, `/gh:issue-create`; sequence vs. parallel with this skill's PR.
4. Should the skill emit step-completion markers (`[step:gh-issue-proceed/<name>] OK`) for harness step-skip guard, mirroring `/gh:issue-implement` (issue #753 pattern in dotfiles)?
