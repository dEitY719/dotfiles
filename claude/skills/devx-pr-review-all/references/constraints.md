# Constraints (rationale) — for devx:pr-review-all

The SKILL.md body lists these as terse rules; the full rationale lives here.

- **Every reviewer lane is soft-fail — never hard-fail.** A missing `agy`
  or `codex` CLI (`command -v` empty), a rate-limit, or any non-zero exit from
  `gh:pr-review` marks only that lane `[SKIP]`/`[WARN]`; the other lanes and
  the rest of the flow continue. If both agy and codex are unavailable,
  `/simplify` still runs. `gh:pr-review` already does its own
  `command -v`/OPEN/draft pre-flight, so do **not** duplicate those as
  hard-fails here — always wrap the lane softly.

- **Never run a bare `git commit`.** In a non-interactive AI shell a bare
  commit opens an editor for the message and hangs. Always pass `-m` with a
  conventional-commit message. The auto-fix agents (`/code-review --fix`,
  `/simplify`) edit files without staging them, so a plain `-m` finds nothing
  staged and fails with `no changes added to commit` — use `-am` so the
  commit picks up the unstaged edits too, e.g.
  `git commit -am "refactor(<scope>): simplify per /simplify"`.

- **`/code-review --fix` and `/simplify` both mutate the working tree — never
  run them concurrently with each other.** agy/codex only post PR
  comments, so they're safe to fan out fully in parallel. But two agents
  editing the same files at the same time is a real correctness risk (lost
  edits, interleaved partial writes, a resulting diff that matches neither
  agent's intent). Step 3's third lane is therefore internally sequential —
  `/code-review --fix` runs to completion and commits before `/simplify`
  starts — even though the lane as a whole still dispatches in the same turn
  as agy/codex.

- **Each auto-fix sub-step gets its own commit, not one combined commit.**
  `fix(<scope>): code-review --fix` and `refactor(<scope>): simplify per
  /simplify` land as two separate commits when both mutate the tree. This
  keeps `git blame`/revert granular — a bad `/simplify` cleanup can be
  reverted without touching a `/code-review --fix` correctness fix, and vice
  versa. A single `git push` at Step 4 sends up whichever commits exist.

- **Delay is not a guarantee — inline reply is the deterministic path.**
  agy/codex reviews are synchronous `gh:pr-review` CLI calls: they post the
  PR comment before returning. Because Step 3 awaits all three Agents, the
  comments exist by the time Step 5 runs, so an **inline** `gh:pr-reply` sees
  them with deterministic ordering — no fixed delay needed. `--defer-reply` is
  a convenience for the issue-flow path (short turns), not a correctness
  requirement; the read-after-write is same-auth and effectively immediate.

- **`devx:schedule` is minutes-only.** It has no sub-minute resolution, so a
  "500 seconds" intent maps to `--defer-reply 8` (≈480 s). When precise
  ordering matters, prefer the inline reply — it is exact, not approximate.

- **approve / request-changes is out of scope.** This skill collects reviews
  and replies to comments; it never submits a `gh pr review` decision. That is
  `gh:pr-approve`'s job.

- **Built-in `/simplify` and `/code-review --fix` both ignore the PR# argument**
  and operate on the current working tree / branch diff. This is why Step 2
  checks out the PR head branch first when running standalone — without it,
  either command would edit whatever tree happens to be checked out. On the
  issue-flow delegation path the branch is already correct, so the checkout
  is a no-op skip.

- **The auto-fix commits + push (Step 4) run synchronously before return.**
  On the issue-flow delegation path this guarantees no dirty tree is left for
  the later rebase steps — a dirty working tree breaks `git rebase`.

- No emojis anywhere. POSIX-compatible shell snippets (`[ ]`, `>/dev/null 2>&1`).

- **`gh:pr-reply` now takes a `[remote]` positional** (issue #1165) — Step 5
  threads the same `<remote>` this skill parsed as `gh:pr-reply`'s second
  positional arg (`Skill(gh:pr-reply, "<pr> <remote>")`). `gh:pr-reply` then
  resolves `TARGET_REPO` by parsing that remote's URL (SSOT helper
  `_gh_pr_review_resolve_target_repo`), not from `gh`'s default-repo
  heuristic. This closes the former local multi-remote ambiguity (e.g. both
  `origin` and `upstream` on GitHub): the reply now lands on the intended
  repo regardless of which remote gh would have guessed. The Step 2
  `gh pr checkout <pr> -R <TARGET_REPO>` is still load-bearing for
  `/simplify` (working-tree diff), but no longer the only thing keeping the
  reply pass on the right repo.
