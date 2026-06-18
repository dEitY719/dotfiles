# Step 3 execution sequence — the four stages of protocol execution

Companion to `execution-flow.md` (verb registry, §5.3 verb→action map) and
`safety-gates.md` (the four layers). This file is the expanded form of the
Step 3 stage list summarized in `SKILL.md`. All STOP / fail-closed /
default-deny triggers below are decision logic — never relax them without
re-reading `safety-gates.md`.

## 1. Pre-flight (safety Layer 3)

Run these checks in parallel; **any** failure → STOP before the loop:

- Current branch ≠ default branch (enforced only for the `mutation`
  precondition class — see `preconditions.md`).
- No untracked secret-shaped files (`.env`, `*.pem`, `*.key`) in the tree.
- `gh auth status` succeeds.
- §preconditions block dry-runs successfully (any embedded check commands).

## 2. Parse steps

Parse the `execution_protocol` section into ordered steps — **matrix** or
**numbered** mode per `protocol-schema.md` §3.3. An unknown action verb
referenced in `decision_rules` → **fail-closed at parse time** (do not
enter the loop).

## 3. Step loop

For each parsed step, in order:

1. `TaskCreate` for the step.
2. Execute under Layer-1 absolute prohibitions + Layer-4 runtime monitors
   (per-step timeout, global timeout, output secret scanner, write-action
   quota). A monitor trip aborts the loop.
3. Classify the result against the body's `decision_rules`. An unknown
   result class → **fail-closed** (abort; never invent a class).
4. Apply the mapped action verb per `execution-flow.md` §5.3. The verb must
   exist in the fixed verb registry — never invent one.
5. `TaskUpdate` with the result + classification.

**Conditional permissions** (bulk ops, force-with-lease, cross-repo,
outbound net) are **default-deny**: allowed only when the body's §safety
carries the matching `allow:` token (`safety-gates.md` §4.2). A missing
token promotes the action to a Layer-1 abort.

## 4. Done-criteria reconciliation

Match every `- [ ]` item in `done_criteria` to an executed write action /
classification.

- All matched and no abort occurred → `close_issue: <self>` + final
  summary comment.
- Otherwise → keep the issue open with an `N/M criteria met` comment.

After the loop completes (or aborts) emit
`printf '[step:gh-issue-proceed/execute] OK\n'`.
