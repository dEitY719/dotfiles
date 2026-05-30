---
name: gh:discussion-convert
description: >-
  Promote a decided `Ideas` Discussion into a tracked Issue by emulating
  GitHub's UI `Convert to issue` flow — creates the Issue with an
  `Originated from discussion #<N>` backlink, posts a `Linked to issue #<M>`
  comment back on the Discussion, locks + closes it (reason Resolved), and
  moves the new Issue card to `In progress`. Use when the user runs
  /gh:discussion-convert, /gh-discussion-convert, asks "Discussion #N
  결정났으니 issue 로 승격", "RFC 결정 — convert 해줘", or wants the 4-step
  variant from `discussions-policy.md` (#612) automated end-to-end. Sister
  skill of [[gh-discussion-create]]; reuses the same `gh_discussion.sh`
  helpers. Idempotent — a re-run prints the existing issue URL and exits 0.
  Refuses non-`Ideas` categories unless `--force-category` is set. Accepts
  `<N>` plus optional `[remote]` and `--no-comment`/`--no-lock`/
  `--no-board-sync`/`--no-close`; `-h`/`--help`/`help` prints usage.
allowed-tools: Bash, Read, Grep
metadata:
  model_recommendation:
    tier: haiku
    reason: "type conversion CLI wrap; 4-step UI emulation, bounded mutations"
    claude: prefer
    non_claude: advisory-only
---

# gh:discussion-convert — Decided Ideas Discussion -> Issue

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Role

Automate the 4-step `Discussion -> Issue` 변환 규약 from
`docs/.ssot/discussions-policy.md` (#612). GitHub exposes no public
`convertDiscussion` mutation, so this skill emulates the UI path via four
primitive mutations (createIssue + comment + close + lock) plus a board
sync, keeping the bidirectional-backlink invariant (principle #4). Print
the new Issue URL; idempotent (Step 4).

## Options

Arguments (`<discussion-number>`, `[remote]`, the four `--no-*` skip flags,
`--force-category`, `-h`/`--help`/`help`) →
[`references/options.md`](references/options.md).

## Step 1: Detect Repo Context

Record `START_TS=$(date +%s)` for elapsed-time reporting. Parse args, confirm
a git repo, and resolve `TARGET_REPO` via the chosen remote — substeps in
[`references/repo-resolution.md`](references/repo-resolution.md). No silent
`origin` fallback on a missing remote.

## Step 2: Fetch the Discussion

Source `shell-common/functions/gh_discussion.sh` and call
`_gh_discussion_fetch "$_owner" "$_repo" "$N"`. Read with `jq`: `.id` (node
ID for comment/close/lock), `.number`, `.title`, `.body`, `.url`,
`.category`, `.closed`, `.locked`. Fetch failure -> abort with stderr.

## Step 3: Category Guard

If `.category != "Ideas"` and `--force-category` is not set, refuse with
the message in [`references/error-cases.md`](references/error-cases.md),
exit 1, and skip Steps 4-9. Principle #2 ("결정되면 즉시 convert") targets
only the Ideas bucket; other categories have different lifecycles and must
not be silently coerced into the tracker.

## Step 4: Idempotency Check (BEFORE any mutation)

Search for an Issue whose body already contains the backlink marker
`Originated from discussion #${N}`. The full `gh issue list` command and the
load-bearing `// empty` rationale live in
[`references/convert-cmd.md`](references/convert-cmd.md) Step 4. On a match,
print `[OK] Discussion #<N> already converted to <url>`, exit 0 (NF-1).

## Step 5: Create the Issue

Build the backlink + verbatim Discussion body and `gh issue create`,
capturing `<M>` — detail in
[`references/create-issue.md`](references/create-issue.md).

## Steps 6-8: Post-Create Mutations

Board sync (Step 6), backlink comment (Step 7), close + lock (Step 8) —
all best-effort, all after the Issue exists. Detail and skip-flag logic in
[`references/post-create-mutations.md`](references/post-create-mutations.md).

## Step 9: Report

Print the `[OK]` line + `steps:` summary + `Next:` hint per
[`references/report-template.md`](references/report-template.md). On failure,
name the failing step and quote the first helper stderr line.

## Constraints

Operating invariants (always `--repo`, fail on missing remote, Ideas-only
guard, best-effort post-create mutations, idempotency) →
[`references/constraints.md`](references/constraints.md).
