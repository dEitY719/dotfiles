# gh:issue-flow — Post-PR Quality Gate (Steps 2.3.1 / 2.3.2 / 2.3.3)

Runs after Step 2.3 (`gh:pr`) has produced `<PR_NUM>`, before the rebase
steps 2.5 / 2.5.1. The whole gate is **soft-fail**: review and simplify are
additive polish, so any failure warns and the chain continues — never block.

## F-3 — dispatch 2.3.1 ∥ 2.3.2 as two parallel Agent subagents in one turn

Steps 2.3.1 and 2.3.2 are independent (pr-review reads the remote PR diff;
simplify edits the local working tree), so dispatch **both Agent subagents
in a single turn** for parallel execution. Do not serialize them. No
conversational prose between the dispatches (see `references/critical-contract.md`);
the Agent/Bash tool calls of this gate are themselves permitted between the
Skill() calls — only prose is forbidden.

### Step 2.3.1 — codex second-opinion review

- Check availability first: `command -v codex`.
- **Present** → dispatch an Agent that runs
  `Skill(gh:pr-review, "--ai codex <PR_NUM>")`. It streams codex findings and
  posts them as a PR comment (no approve / request-changes — that is not this
  gate's job).
- **Absent** → skip. A missing `codex` CLI is a normal skip, not a failure.

### Step 2.3.2 — /simplify on the branch diff

- Dispatch an Agent that runs the built-in `/simplify`.
- `simplify` operates on the **working-tree / branch diff**, so a PR-number
  argument may be ignored — do not rely on passing `<PR_NUM>` to it. It edits
  local files to reduce duplication / complexity without changing behaviour.

## Step 2.3.3 — commit + push simplify changes (only if the tree changed)

After both subagents return:

- If `/simplify` produced working-tree changes (`git status --porcelain`
  non-empty) → commit with an explicit `-m` message in the repo's
  conventional-commit style (e.g.
  `git commit -m "refactor(<scope>): simplify per /simplify"`) and
  `git push`. Never run a bare `git commit` — in a non-interactive AI
  environment it opens an editor and hangs; always pass `-m`.
- If the tree is clean → skip (simplify found nothing to change).

**Ordering is load-bearing: 2.3.3 MUST run before the rebase steps 2.5 /
2.5.1.** A dirty working tree breaks `git rebase`, so the simplify commit has
to land (or be confirmed absent) before any rebase-sync runs.

## Soft-fail policy

- codex absent → 2.3.1 skip (not a failure).
- simplify no change → 2.3.3 skip.
- Any error in review, simplify, or the simplify commit/push → emit a
  `[WARN] …` line and continue to Step 2.4. The gate never stops the flow.
