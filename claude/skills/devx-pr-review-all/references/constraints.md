# Constraints (rationale) — for devx:pr-review-all

The SKILL.md body lists these as terse rules; the full rationale lives here.

- **Every reviewer lane is soft-fail — never hard-fail.** A missing `gemini`
  or `codex` CLI (`command -v` empty), a rate-limit, or any non-zero exit from
  `gh:pr-review` marks only that lane `[SKIP]`/`[WARN]`; the other lanes and
  the rest of the flow continue. If both gemini and codex are unavailable,
  `/simplify` still runs. `gh:pr-review` already does its own
  `command -v`/OPEN/draft pre-flight, so do **not** duplicate those as
  hard-fails here — always wrap the lane softly.

- **Never run a bare `git commit`.** In a non-interactive AI shell a bare
  commit opens an editor for the message and hangs. Always pass `-m` with a
  conventional-commit message, e.g.
  `git commit -m "refactor(<scope>): simplify per /simplify"`.

- **Delay is not a guarantee — inline reply is the deterministic path.**
  gemini/codex reviews are synchronous `gh:pr-review` CLI calls: they post the
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

- **Built-in `/simplify` ignores the PR# argument** and operates on the
  current working tree / branch diff. This is why Step 2 checks out the PR
  head branch first when running standalone — without it, `/simplify` would
  edit whatever tree happens to be checked out. On the issue-flow delegation
  path the branch is already correct, so the checkout is a no-op skip.

- **The simplify commit + push (Step 4) runs synchronously before return.**
  On the issue-flow delegation path this guarantees no dirty tree is left for
  the later rebase steps — a dirty working tree breaks `git rebase`.

- No emojis anywhere. POSIX-compatible shell snippets (`[ ]`, `>/dev/null 2>&1`).
