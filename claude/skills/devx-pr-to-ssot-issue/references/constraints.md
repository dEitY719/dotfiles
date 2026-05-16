# Operational Constraints — devx:pr-to-ssot-issue

Mandatory rules. They protect the source PR (read-only) and keep the
new SSOT issue's audit trail meaningful.

## Audit trail integrity

- **`--reason` is mandatory.** ≥ 10 chars after trim. Empty / short →
  exit 2. The exception workflow is auditable specifically because
  every recovery issue carries a verbatim reason — silently allowing
  empty reasons defeats the purpose.
- **Never modify `--reason` text.** Quote-escape only when required by
  the `> [!IMPORTANT]` callout (leading `>` becomes `\>`). Do not
  shorten, normalize whitespace, or strip newlines.

## PR is read-only

- Never `gh pr edit <PR#>` — no label / body / milestone / assignee /
  reviewer change.
- Never `gh pr comment <PR#>` — the new SSOT issue is the canonical
  pointer back to the PR. The PR thread stays clean.
- Never `gh pr review <PR#>` — reviewing the PR is out of scope.
- If a future variant needs PR mutation, route through a sister
  skill (`/devx:exception-merge-checklist`) rather than relaxing this
  rule.

## Label / milestone safety

- **Never auto-create labels.** Pre-validate via `gh label list` (Step
  5.3). Missing → stop with the missing list. Memory:
  `feedback_gh_label_no_autocreate.md`.
- **Never auto-create milestones.** Pre-validate via `gh api
  /milestones` when `--milestone` is set. Missing → stop.

## Fail-closed guards

- **Overlap detected.** PR already linked to a PRD/TRD-bearing issue →
  exit 3 unless `--force-overlap` is set. Default refuse keeps the
  user from creating duplicate SSOT trackers without an explicit
  override.
- **Empty gap.** Every subagent SSOT section returns `(none)` → exit
  4. Stub issues are worse than no issue — they pollute the backlog.
- **Unknown remote.** `--remote <name>` that does not resolve →
  exit 1 with the `git remote -v` listing. Never fall back to
  `origin` silently — that would land the SSOT issue on the wrong
  repo where it can't even be cross-referenced from the source PR.
- **PR state.** `CLOSED (unmerged)` → exit 1 with "nothing to
  reverse-engineer". `OPEN` and `MERGED` are both valid entry states.

## Scope boundary

- **No auto-implementation.** This skill stops at SSOT scope
  registration. The natural follow-up is `/gh-issue-flow <new>`. Do
  not chain it from inside this skill — `gh-issue-flow` is a
  user-initiated decision, not an automatic consequence.
- **No silent secondary mutations.** The only mutations are: (a) the
  new issue, (b) the optional parent backlink comment. Anything else
  (label changes on the parent, project-board placement, assignee
  setup) is out of scope. If it needs to happen, route through a
  sister skill.

## Environment respect

- **`GH_DISABLE_AI_METRICS=1`** — skips the ai-metrics footer in the
  new issue body **and** the parent backlink comment. Parity with the
  five `gh-issue-flow` sub-skills (issue #399).
- **`GH_ISSUE_BLOCK_LABELS`** — not applicable. This skill creates
  the new issue from scratch; it does not implement an existing one.
  The block-label guard in `gh-issue-implement` Step 3.2 is the
  right place for that check.

## Mid-flow failure

- **No automatic rollback.** If Step 5.5 (`gh issue create`) succeeds
  but Step 5.6 (parent backlink) fails, the new issue stays put. The
  report warns the user and prints a manual recovery command. Same
  rule as `devx:trd-to-issues` `--apply`.
- **No retries.** Every error path is fail-fast. The human user
  decides whether to fix and re-run.

## Pairs with

- `SKILL.md` Constraints section — abbreviated mirror of this file.
- `references/create-cmd.md` — where the read-only and label rules
  are enforced.
- `feedback_gh_label_no_autocreate.md` (memory) — the underlying
  reason for the label rule.
