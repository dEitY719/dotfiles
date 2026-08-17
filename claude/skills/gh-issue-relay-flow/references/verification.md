# gh:issue-relay-flow — Advisor Verification

Detailed procedure for Step 4. The Worker's completion report is a claim,
not proof (root `CLAUDE.md`: "Worker의 완료 보고를 그대로 믿지 않는다").
Verify directly before Step 5 relays anything.

## Read the actual diff

```bash
git diff <BASE_SHA>..HEAD
```

If the Worker only wrote files without committing (per the brief's
commit/push policy from `worker-brief-checklist.md`), use `git diff` /
`git status` against the working tree instead — the point is to read the
real change, not to trust a summary of it.

Read the diff yourself; do not just check that it's non-empty. Confirm it
actually matches the issue's requirements and the completion criteria
stated in the brief.

## Discover the target repo's lint/test commands

Do not hardcode a lint/test command — every target repo is different.
Look for, in order:

1. The target repo's root `CLAUDE.md` (and `AGENTS.md` if present) — most
   repos state their standard commands explicitly (e.g. "run `bun run
   lint`", "`cd apps/server && uv run pytest`").
2. Any subdirectory `CLAUDE.md`/`AGENTS.md` relevant to the files the diff
   touched (some repos scope commands per-package — check the directories
   the diff actually changed).
3. If neither states a command, ask the user rather than guessing at one.

**Concrete example — this dotfiles repo itself**: if `gh:issue-relay-flow`
is ever run with this repo as the target, the standard commands are
`mise run lint && mise run test` (see the repo's own `mise.toml`).

## Run them and gate on the result

- **Pass** — proceed to Step 5. If any failures here were confirmed
  pre-existing and unrelated, record each one as a `<path>::<test-or-check>`
  entry and pass the comma-separated list to Step 5's `gh:relay-merge` call
  via `--known-failures`, so the apply-guide names concrete failures rather
  than a vague summary sentence. Use the bare `<path>` form only when every
  current failure in that file is pre-existing — one file can hold both a
  pre-existing failure and a new regression, and the unqualified form would
  tell the destination-side reader to skip both.
- **Fail** — do not proceed. Re-delegate to a fresh Worker call with a
  sharper brief: include the specific failing test output / lint errors,
  the file(s) involved, and anything the first brief's completion criteria
  under-specified that let the failure slip through. This is the same
  "재위임 시 다음 브리프에 무엇을 추가해야 하는지" gap the root `CLAUDE.md`
  calls out — name the concrete gap, don't just retry the same brief
  verbatim.
- **Ambiguous** (e.g. no test runner exists for this change, or the repo
  has no CI-equivalent command) — say so explicitly in the eventual Step 6
  report rather than silently treating it as a pass.

## What this step does not do

- It does not fix the Worker's mistakes itself by editing code inline —
  that reintroduces the "Advisor does the Worker's job" anti-pattern. Fix
  is always via re-delegation (a new Worker call), with narrow exceptions
  for genuinely trivial cleanup (root `CLAUDE.md`: "직접 수정은 사소한
  마무리만").
- It does not commit on the Worker's behalf beyond what the brief already
  specified — commit policy was fixed in Step 3's brief.
