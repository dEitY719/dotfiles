# Decomposition Rules + Labeling Heuristics

Generalized from the manual decomposition done on
[dev-team-404/AgentToolbox#433](https://github.com/dev-team-404/AgentToolbox/issues/433)
(8 Milestones × 40 Issues). The rules below are the criteria the skill
applies to every Task; the labeling heuristic decides which audience
the Task is sized for.

## Task-sizing criteria — must satisfy ALL three

A Task is considered well-sized iff:

1. **AC count: 1–3** — Acceptance Criteria are 1, 2, or 3 checkboxes.
   4+ ACs means the task is doing too much; split it.
2. **Unit-testable** — there is a clear way to verify the AC with a
   unit test, integration test, or repeatable manual check. "Make X
   look better" is not unit-testable; "X renders within 100ms on a
   1000-row table" is.
3. **Independently committable** — the Task can be committed without
   waiting on a sibling Task in the same milestone. Tasks that share
   uncommitted state with a sibling must be merged or re-split.

If a Task fails any of the three, the skill attempts one
auto-decomposition pass (split by AC, by file, or by stage). If still
failing, the Task lands in the plan's **"Decomposition failures"**
section with the failing criterion named — never silently dropped.

## Labeling heuristic

Exactly one of the size labels per Task:

| Label | Heuristic |
|-------|-----------|
| `pro-friendly` | Estimated changed files ≤ 5 **and** estimated new lines of code ≤ 300. Single-session completability is clear. |
| `max-only`     | Either heuristic exceeded, **or** the task carries non-trivial design judgment / external dependency complexity / cross-component contracts. |

When the metrics are borderline but the context (TRD section, single
file family, well-defined contract) makes single-session completion
clear, prefer `pro-friendly` — see issue #433 for the original
guidance.

Priority labels (`⚡ High`, `🔥 Urgent`, etc.) are **lifted from the
TRD** when the TRD names a priority for that section/task. They are
additive — they do not replace the size label.

## Hard rules

- **Never auto-create labels.** If a label referenced by the plan is
  missing on the target repo at `--apply` time, stop with the missing
  list. Reason: `feedback_gh_label_no_autocreate.md` — POST `/labels`
  silently creates the label, polluting the repo's label namespace.
- **Never collapse "Decomposition failures" into the main task list.**
  A failure is a signal that the user must split or rewrite the TRD
  section; hiding it defeats the purpose of dry-run review.
- **Never invent acceptance criteria.** If the TRD does not specify
  ACs for a section, the Task lands in "Decomposition failures" with
  reason "no AC found" — the user re-authors the TRD.

## Pairs with

- `references/plan-format.md` — where the labels and decomposition
  failures appear in the rendered plan.
- `references/samples/` — fixture verifying the rules apply
  consistently to a small TRD.
