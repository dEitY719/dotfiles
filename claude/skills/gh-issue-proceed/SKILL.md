---
name: gh:issue-proceed
description: >-
  Read a GitHub directive issue (a work-order issue whose body embeds an
  executable 8-section protocol) and proceed end-to-end WITHOUT human
  intervention — strictly validating the schema, executing each step per
  the body's decision rules, and applying authorized write actions
  (commit / PR / comment / close / file follow-up). Use when the user runs
  /gh:issue-proceed, /gh-issue-proceed, or asks "이 지시 이슈 끝까지 수행해",
  "directive 이슈 실행해", "proceed #81". Sibling of [[gh:issue-implement]]
  (which edits files to satisfy a code-change issue) — this skill instead
  EXECUTES the protocol the issue carries. Strict schema: refuses any issue
  missing one of the 8 required sections. Always direct mode — the directive
  is the plan; no plan/brainstorming dispatch. Safety gates (absolute
  prohibitions + token-gated conditional permissions + pre-flight + runtime
  monitors) bound every write. Accepts `<issue-number> [remote]` and
  `-h`/`--help`/`help`.
allowed-tools: Bash, Read, Grep, Glob, Edit, Write, Skill, TaskCreate, TaskUpdate, TaskList
metadata:
  model_recommendation:
    tier: opus
    reason: "full write authority + per-step safety classification + protocol reasoning; high blast radius"
    claude: prefer
    non_claude: advisory-only
---

# gh:issue-proceed — Directive Issue → Execution

Sibling of `/gh:issue-implement`: same shell, minus superpowers detection
and mode dispatch — directive issues are pre-designed, so execution is always
direct. SSOT: `docs/feature/gh-issue-proceed-skill/design.md`. On each step's
success emit its marker `printf '[step:gh-issue-proceed/<id>] OK\n'` (`<id>`
= `fetch-issue`, `schema-valid`, `execute`, `report`).

## Help

If arg #1 is `-h`, `--help`, or `help`, output `references/help.md`
verbatim, then stop. No API calls.

## Step 1: Parse Args + Resolve Repo

Record `START_TS=$(date +%s)` immediately (elapsed-time for Step 4).
Positional args: `<issue-number> [remote]` — no `mode` arg; always `direct`.

- `issue-number` — required, positive integer.
- `remote` — default `origin`. Resolve `TARGET_REPO=<owner>/<repo>` per
  `references/repo-resolution.md`. Missing remote → `git remote -v` + stop
  (no silent fallback).

## Step 2: Fetch + Claim + Schema Validation

2.1 **Fetch + Claim** (`fetch-issue` marker) — run the five claim substeps
in `references/claim.md` (fetch → block-label guard → self-assign → board
transition → depends-on). CLOSED-issue refusal precedes schema
(`references/fetch-issue.md`).

2.2 **Schema validation** (`schema-valid` marker) — validate the body
against the strict 8-section schema in `references/protocol-schema.md`. Any
missing / empty / unparseable required section → print the §3.4 failure
block and STOP — **no comment on the issue** (schema failure is caller-side).

2.3 **Precondition class** — classify per `references/preconditions.md`
(read-only / mutation-required / mixed / verify-only); log it.
`mutation-required` on the default branch or a dirty tree → STOP (hint there).

## Step 3: Execute Protocol

Full sequence in `references/step3-sequence.md` (with
`references/execution-flow.md` + `references/safety-gates.md`). Four stages;
every STOP / fail-closed / default-deny trigger below is binding:

1. **Pre-flight** (Layer 3): branch / secret-shaped files / `gh auth status`
   / dry-run §preconditions. Any failure → STOP.
2. **Parse** `execution_protocol`. Unknown verb in `decision_rules` →
   fail-closed at parse time.
3. **Step loop** — `TaskCreate` → execute under Layer-1 prohibitions +
   Layer-4 monitors → classify vs `decision_rules` (fail-closed on unknown
   class) → apply mapped verb → `TaskUpdate`. Conditional permissions (bulk
   / force-with-lease / cross-repo / net) **default-deny** — only with the
   matching §safety `allow:` token.
4. **Reconcile** `done_criteria`: all matched + no abort → `close_issue:
   <self>` + comment; else keep open `N/M criteria met`. Then emit `execute`.

## Step 4: Report

Print the audit report per `references/report-format.md` (per-step table,
write-action audit, done-criteria reconciliation, outcome), then append the
ai-metrics line defined there. Compute `ELAPSED=$(( ($(date +%s) - START_TS)
/ 60 ))` before printing; honor `GH_DISABLE_AI_METRICS=1`. Then emit `report`.

## Constraints

Gate rules are absolute; see `references/safety-gates.md` for full layers:

- **Never** force-push the default branch, leak a secret to GitHub output, mutate another worktree, or `gh pr merge` — Layer-1, body cannot override.
- **Never** invent a result class or action verb — fail-closed vs `decision_rules` and the fixed verb registry.
- **Never** apply a conditional permission (bulk / force-with-lease / cross-repo / net) without its §safety `allow:` token.
- **Never** run `mutation-required` on the default branch or a dirty tree.
- **Never** comment on schema-validation failure (caller-side).
- Mode is always `direct`; no plan / brainstorming dispatch.
