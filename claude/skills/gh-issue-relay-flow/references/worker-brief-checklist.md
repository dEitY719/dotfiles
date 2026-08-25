# gh:issue-relay-flow — Worker Brief Checklist

Detailed procedure for Step 3. This file is a checklist of what the brief
must contain, not a fixed script — the executor writes the actual brief
text fresh each run, tailored to the issue at hand (per the root
`CLAUDE.md` Advisor/Worker brief principle: no hardcoded boilerplate,
enough context that the Worker never needs to re-explore).

## Fetch the issue

```bash
GH_HOST="$DEST_HOST" gh issue view <N> --repo "$DEST_REPO" --json title,body,comments
```

`$DEST_REPO` (owner/repo of the destination remote) and `$DEST_HOST` are
both resolved in Step 2's remote resolution (`gh:relay-merge`'s
`remote-resolution.md` substep 6), from one and the same remote URL. Keep
**both** halves: `--repo` names the repo but carries no host, so a bare `gh`
would follow its own `gh repo set-default` — and this flow exists precisely
because the destination is a *different* host from `origin`, so that default
is the wrong server by construction (#1403 / #1407).

This is the brief's raw material — body **and** comments, verbatim, not
summarized away (later steps, and the Worker, need the full context).

## Open Questions gate — resolve before delegating

Scan the fetched body/comments for an "Open Questions" (or equivalent)
section. If it lists **unresolved** items:

- Show the list to the user now and get answers (interactive), **or**
- If the user already answered them earlier in this conversation, do not
  re-ask — write the decision directly into the brief as a resolved
  fact so the Worker never has to guess or ask again.

**Never delegate implementation while an Open Question is still genuinely
unresolved.** This is not hypothetical — the session that authored this
skill hit exactly this gap on issue #1346 itself (its own Open Questions
section had no answer recorded yet at delegation time). See
`references/constraints.md` and the SKILL.md Error Cases for the hard rule.

## Brief checklist — what the Worker needs, every time

Assemble a self-contained prompt for the opus subagent (`Agent` tool,
`model: "opus"`) covering:

- **Absolute path** to the target repository (the worktree/checkout the
  Advisor is running in — the Worker inherits no context, so state it
  explicitly even though it seems obvious from the session).
- **The issue's full body** (verbatim, from the fetch above) plus **any
  Open Questions resolutions** decided in the previous step, written as
  settled facts, not as questions the Worker should re-litigate.
- An explicit instruction that the brief is self-contained for a full
  **TDD loop** — write failing test(s) → implement → get them passing —
  inside this one delegation; the Worker should not need a second round
  trip for straightforward failures.
- **Explicit completion criteria**, enumerated (e.g. "tests X, Y, Z pass",
  "lint command Q is clean", "file at path P now contains change R") —
  not a vague "implement the issue."
- **Commit/push policy**, decided by the executor per the situation and
  stated plainly in the brief — either "commit locally, do not push" or
  "write files only, do not commit" (Step 4's Advisor verification works
  either way via `git diff <BASE_SHA>..HEAD`, which covers committed
  changes; uncommitted changes need `git diff` without a ref, or a
  Worker-side `git add` first — pick one and say so in the brief, do not
  leave it ambiguous). Never let the Worker push.
- **Repo conventions relevant to this issue**, pre-summarized by the
  executor from what it already knows (file locations, naming rules,
  existing patterns to follow) — the same principle as the root
  `CLAUDE.md` brief-writing guidance: give the Worker what's already been
  discovered so it does not re-explore ground the Advisor already covered.

## Before delegation

Record `BASE_SHA=$(git rev-parse HEAD)` (SKILL.md Step 3) right before
invoking the `Agent` tool call, while `HEAD` still points at the branch
tip created in Step 2 — this is what Step 4's `git diff` and Step 5's relay
range both anchor on.
