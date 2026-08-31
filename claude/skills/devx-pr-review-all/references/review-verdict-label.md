# devx:pr-review-all — Review verdict → merge-gate label

SSOT for how a reviewer lane's closing verdict line becomes a machine-readable
PR label. Implementation: `shell-common/functions/devx_pr_review_all.sh`;
regression suite: `tests/bats/functions/devx_pr_review_all_verdict.bats`.

Why it exists: every `gh:pr-review` preset mandates a closing verdict line, and
until #1527 nothing in the repo read it. PR #1518 collected two independent
blocking verdicts and merged 32 minutes later, because the merge train's only
real gate was CI.

**Wiring status — fully wired as of #1564.** All three sides now exist:

| side | where | since |
|---|---|---|
| marker (`<!-- ai-review:<ai>:<sha> -->`) | `_gh_pr_review_build_comment_body` in `gh_pr_review.sh` | #1564 |
| producer (parse → aggregate → label) | `devx:pr-review-all` **Step 3.5**, via `devx_pr_review_all_apply_label` | #1564 |
| invalidation (drop a stale verdict) | `_gh_pr_drop_label`, called by every head-advancing skill | #1563 |
| consumer (hard merge gate) | `gh:pr-merge-train` **Step 3.5**, `references/review-verdict-gate.md` | #1564 |
| provisioning (the labels exist in the repo) | `gh:label-bootstrap` pipeline feed | #1564 |
| freshness (sha marker for `review-passed`) | `devx_pr_review_all_apply_label`'s 4th arg; read by `_gh_pr_merge_train_review_passed_stale` | #1601 |
| second producer (one reviewer, scoped re-review) | `gh:pr-reply` Step 6's targeted lane, `claude/skills/gh-pr-reply/references/targeted-rereview.md` — same `devx_pr_review_all_apply_label` write path, gated per reviewer/severity | #1616 |

#1563's label-lifecycle invalidation rules are the piece that makes the rest
safe: every skill that advances a PR's head (`gh:pr-reply`,
`gh:pr-resolve-conflict`, `gh:pr-resolve-outdated`) drops the stale verdict
through the shared `_gh_pr_drop_label` helper, whose header comment in
`shell-common/functions/gh_pr_edit_safe.sh` is the SSOT for the asymmetry rule:
`review-passed` is dropped unconditionally by all three; `review-blocked` is
dropped unconditionally too, but by exactly one of them — `gh:pr-reply`, once
its Step 5 reply-all contract completes (#1634). The two rebase skills never
drop `review-blocked` — they hold no evidence any blocker was addressed. A
BLOCKING verdict from `gh:pr-reply`'s own targeted re-review lane can still
re-apply `review-blocked` afterward, through `devx_pr_review_all_apply_label`
on fresh evidence — not a reversal of the unconditional drop.

## The labels

| label | meaning |
|---|---|
| `review-blocked` | at least one reviewer lane returned a blocking verdict |
| `review-passed` | every lane that ran returned a non-blocking verdict, and at least one lane ran |

Neither belongs to the 10-label SSOT (`gh-label-bootstrap/references/gh-labels.md`).
Like `CI fail` and `conflict` they are **pipeline-state** labels, not
issue-classification ones, and that document explicitly scopes such labels out.
They are provisioned from that file's **separate `pipeline|` feed** instead
(#1564), which `--prune` preserves alongside the base 10.

**Absence is the third state, and it means "not verified".** A PR carrying
neither label has not been shown to pass review. That is what makes a time
backstop unnecessary here: a stuck PR is one label away from moving, and a
human can add or remove it at any time.

## The four helpers

```
devx_pr_review_all_lane_block <ai> [<head-sha>]   # comment bodies on stdin
  -> that lane's raw block, or nothing
devx_pr_review_all_verdict                        # one lane's raw text on stdin
  -> blocking | concerns | lgtm | unknown
devx_pr_review_all_aggregate                      # verdict tokens on stdin,
                                                  #   one per line, one per lane
  -> label=review-blocked | label=review-passed | label=    (+ lanes=N)
devx_pr_review_all_apply_label <pr> <repo> [host] # verdict tokens on stdin
  -> aggregates, removes the opposite label, adds the label. One report line.
```

The first three are pure: stdin in, stdout out, no network, no shell state.
`devx_pr_review_all_apply_label` is the one that touches GitHub, and it is
soft-fail by construction — see "Applying the label" below.

## Reading a lane's verdict

Each reviewer lane (`agy`, `codex`, `opencode`, `hermes`) ends its output with
a mandatory verdict line — `판정: [LGTM|우려있음|블로킹]` or
`Verdict: [LGTM|CONCERNS|BLOCKING]` (`gh-pr-review/references/review-presets.md`,
rendered at runtime by `_gh_pr_review_common_prefix` in `gh_pr_review.sh`).

**Do not try to read that line out of the lane's return value.** `gh:pr-review`
guarantees exactly one line back — `[OK] PR #<N> reviewed by <ai> … — comment:
<URL>` — and each lane runs as a subagent, which returns a *summary* of what it
did. Neither carries the verdict. A gate built on that would have every lane
parse as `unknown`, never write a label, and skip every PR forever.

Read it from the artifact the lane already wrote instead. `gh:pr-review` Step 6
posts the reviewer's raw output to the PR wrapped in
`<!-- ai-review:<ai>:<head-sha> -->` markers, synchronously, before it returns —
a durable machine-readable record rather than a summary. Fetch the comments
**once**, then per lane:

```sh
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/devx_pr_review_all.sh"

head_sha=$(GH_HOST="$TARGET_HOST" gh pr view "$pr" --repo "$TARGET_REPO" \
    --json headRefOid --jq .headRefOid)

BODIES=$(GH_HOST="$TARGET_HOST" gh api --paginate \
    "repos/$TARGET_REPO/issues/$pr/comments" --jq '.[].body')

verdict=$(printf '%s\n' "$BODIES" |
    devx_pr_review_all_lane_block "$ai" "$head_sha" |
    devx_pr_review_all_verdict)
# -> blocking | concerns | lgtm | unknown
```

`devx_pr_review_all_lane_block` takes the **last complete** block for that lane,
so a re-review supersedes an earlier verdict, and it ignores an unterminated
block — half a review is not a verdict.

### Freshness: the head-sha argument

The second argument is optional to the *function*, not to a caller that gates a
merge. Without it the helper cannot tell a block this run just posted from one
left by an earlier round. A run that posted nothing —
`GH_DISABLE_AI_METRICS=1`, `--no-post-comment`, or a post that failed — would
then silently reuse a stale verdict, and a stale verdict can authorize a merge
of code it never saw.

With a sha given, only `<!-- ai-review:<ai>:<head-sha> -->` … `<!-- /ai-review:<ai>:<head-sha> -->`
blocks match, both markers must carry the same sha, and a lane with no block for
that exact ai+sha pair yields nothing — which reads downstream as `unknown`,
so no label, so no merge. Fail-closed.

`gh:pr-review`'s marker writer (`_gh_pr_review_build_comment_body` in
`shell-common/functions/gh_pr_review.sh`) emits the sha-tagged form since
#1564; the sha comes from the `headRefOid` field of the one consolidated
`gh pr view` that function's caller already makes, so freshness costs no extra
round-trip. **Always pass the sha.** Omitting it is not a safer default — it
is the stale-verdict hole this argument exists to close.

> **Comments posted before #1564** carry the unsuffixed marker and read as
> `unknown` under the sha-aware path — no label, no merge. That is the
> documented fail-closed direction: the PR is re-reviewed, and the fresh
> comment carries the tag. Do **not** add a compatibility path that accepts an
> untagged block when a sha was requested; it would resurrect exactly the reuse
> this closes.

**Read the sha before any push of this run.** The lanes reviewed the PR's
current *remote* head. `devx:pr-review-all`'s own `/simplify` lane may have
committed locally by the time the verdicts are collected, but Step 4 has not
pushed yet — so `gh pr view --json headRefOid` still answers the sha the lanes
actually reviewed. Reading it after the push answers the *new* sha, every lane
misses, and the gate is silently dead. That is why Step 3.5 sits before Step 4.

### What the verdict parser accepts

- Case-insensitive, both `판정:` and `Verdict:`, fullwidth `：` normalized.
- Surrounding markdown emphasis and a leading list dash are stripped.
- Only lines that *start* with the verdict key count; a finding line such as
  `[BLOCKER] a.sh:1 — …` is never mistaken for the verdict.
- The last verdict line in the input wins — the presets put it last.
- The **unanswered template** is rejected: a value that opens with `[` *and*
  carries a `|` inside the brackets (`[LGTM|CONCERNS|BLOCKING]`) is a lane
  echoing its own instructions back, and yields `unknown`.
- A genuine answer that merely contains a pipe or a bracket elsewhere still
  parses: `Verdict: BLOCKING | 5 findings` → `blocking`, `Verdict: [BLOCKING]`
  → `blocking`, `판정: 블로킹 [BLOCKER 4건]` → `blocking`. Rejecting any line
  containing `|` was #1527's bug; it left real blocking verdicts unlabelled.
- Anything else — no verdict line, an unrecognized value — is `unknown`.

## Aggregating the lanes

`devx_pr_review_all_aggregate` reads **newline-delimited verdict tokens from
stdin**, one line per lane that ran. It does *not* take positional arguments,
and that is load-bearing rather than stylistic: the obvious call site
`devx_pr_review_all_aggregate $VERDICTS` depends on the shell word-splitting an
unquoted expansion, which zsh does not do without `SH_WORD_SPLIT`. In zsh the
whole string arrived as one argument, so a two-lane PR reported `lanes=1` and
dropped the blocking verdict outright — and zsh is this repo's default
interactive shell. A newline-delimited stream behaves identically in bash, zsh
and dash.

Build the stream with `printf` inside the lane loop and pipe it straight in.
Never stage the verdicts in a variable and re-expand it:

```sh
AGG=$(
    for ai in agy codex opencode hermes; do
        lane_ran "$ai" || continue          # a skipped lane contributes NOTHING
        v=$(printf '%s\n' "$BODIES" |
            devx_pr_review_all_lane_block "$ai" "$head_sha" |
            devx_pr_review_all_verdict)
        printf '%s\n' "$v"
    done | devx_pr_review_all_aggregate
)
label=$(printf '%s\n' "$AGG" | sed -n 's/^label=//p')
lanes=$(printf '%s\n' "$AGG" | sed -n 's/^lanes=//p')
```

Read the two `key=value` lines with `sed`, not `eval` — the values are
controlled, but a parser that cannot execute anything is the right default for
something that gates a merge.

In practice the call site pipes the same stream straight into
`devx_pr_review_all_apply_label` (next section), which does this aggregation
and the two `sed` reads internally. Reach for `devx_pr_review_all_aggregate`
directly only when you want the verdict *without* writing a label.

| lanes that ran | outcome | `label` |
|---|---|---|
| any lane `blocking` | blocked | `review-blocked` |
| ≥1 lane, all `lgtm`/`concerns` | passed | `review-passed` |
| ≥1 lane, any `unknown` | verdict not established | *(empty)* |
| zero | nothing was checked | *(empty)* |

`우려있음`/`CONCERNS` is a **pass** — a non-blocking opinion, which `gh:pr-reply`
still answers. `unknown` is not, because a lane whose output stopped parsing is
indistinguishable from a lane that never reached a verdict.

**A lane that did not run contributes no line at all.** `command -v` empty, a
non-internal PC, a non-zero exit — every `[SKIP]`/`[WARN]` row of the report —
is absent from the stream, not an `unknown`. "Not checked" and "checked and
passed" must never collapse into the same state. The `/simplify` lane never
contributes; it produces no verdict. Blank lines are ignored, so a stray one
cannot inflate `lanes=` into a false "verified".

## Applying the label

`devx_pr_review_all_apply_label` (`shell-common/functions/devx_pr_review_all.sh`)
owns this. Build the verdict stream and pipe it in — do **not** stage the
verdicts in a variable and re-expand it (same zsh rule as the section above):

```sh
for ai in agy codex opencode hermes; do
    lane_ran "$ai" || continue          # a skipped lane contributes NOTHING
    printf '%s\n' "$BODIES" |
        devx_pr_review_all_lane_block "$ai" "$head_sha" |
        devx_pr_review_all_verdict
done | devx_pr_review_all_apply_label "$pr" "$TARGET_REPO" "$TARGET_HOST" "$head_sha"
```

**Always pass `$head_sha` as the 4th argument** (#1601) — the same sha already
read at the top of this section, before any push. See "Freshness marker for
`review-passed`" below.

What it does, and why each part is the way it is:

- Adds through `_gh_pr_edit_safe_label` (`shell-common/functions/gh_pr_edit_safe.sh`),
  never bare `gh pr edit --add-label` — that silently exits 1 on repos with
  classic Projects attached (#326). The opposite label is removed through the
  REST endpoint, for the same reason.
- **The opposite label is removed first, and unconditionally.** A re-review
  that flips `review-blocked` to `review-passed` has to clear the old one, or a
  consumer sees both. (`gh:pr-merge-train`'s gate resolves that case
  deterministically — `review-blocked` wins — but a consumer should never have
  to.)
- `GH_HOST` is pinned per call inside a subshell, so a dual-host login cannot
  write the label to the wrong server (#1403 / #1407) and the caller's own
  `GH_HOST` survives.
- **Soft-fail throughout**: rc is 0 for every labelling outcome, because an
  unlabelled PR already reads as "not verified" downstream. Only a usage error
  (missing `<pr>`/`<repo>`) returns 2.

It prints one primary line:

| stream | line |
|---|---|
| a `blocking` lane | `[OK] PR #<n> labelled \`review-blocked\` (<k> lane(s))` |
| ≥1 lane, all non-blocking | `[OK] PR #<n> labelled \`review-passed\` (<k> lane(s))` |
| empty `label` (no lane, or an `unknown`) | `[WARN] no reviewer lane produced a verdict — PR #<n> left unlabelled` |
| `_gh_pr_edit_safe_label` rc 3 | `[WARN] label \`<l>\` missing in <repo> — provision it first (gh:label-bootstrap)` |
| any other non-zero rc | `[WARN] labelling PR #<n> failed — treat the PR as unverified` |

A second `[WARN]` line follows, but only on the one path in "Freshness marker
for `review-passed`" below (the marker POST itself failing after a
successful `review-passed` label) — every other outcome above stays exactly
one line (PR #1608 review, codex round-3 FOLLOW-UP: this table used to
promise "exactly one line" unconditionally, which stopped being true once
that second warning was added).

`_gh_pr_edit_safe_label` returns 3 when the label does not exist in the repo and
**refuses to auto-create it** (`feedback_gh_label_no_autocreate.md`, #326) —
hence the `gh:label-bootstrap` pointer in that line. Its `pipeline|` feed
(`gh-label-bootstrap/references/gh-labels.md`) is where the two labels are
provisioned, and `--prune` preserves them.

## Freshness marker for `review-passed` (#1601)

The label alone only proves "some head was reviewed" — its invalidation
depends on every skill that advances a PR's head remembering to drop it
(`gh_pr_edit_safe.sh` → "Verdict-label invalidation"). That list can never be
complete: a manual `git push --force-with-lease`, a GitHub web-UI commit, or
a future tool all advance the head with no hook this repo controls, leaving
a stale `review-passed` that `gh:pr-merge-train`'s gate would trust.

`devx_pr_review_all_apply_label`'s 4th argument closes that gap from the
*read* side instead of chasing more write-side call sites. When the resolved
verdict is `review-passed` and a head-sha is given, it posts one plain issue
comment:

```
<!-- review-verdict:review-passed:<head-sha> -->
```

`gh:pr-merge-train`'s gate (`_gh_pr_merge_train_review_passed_stale` in
`shell-common/functions/gh_pr_merge_train.sh`) reads the last such marker back
and compares its sha against the PR's *current* `headRefOid` before trusting
the label — full detail:
`gh-pr-merge-train/references/review-verdict-gate.md` → "Freshness check".

This is a different thing from the "not a comment parser" rule two sections
up: that rule forbids re-deriving a reviewer's LGTM/BLOCKING verdict from
free-form CLI output, where a reformat could silently unlock the gate. This
marker is a fixed, machine-only stamp only this function ever writes, read by
a fixed regex — no reviewer output touches it either way.

Never posted for `review-blocked`: a stale block is already the safe
direction (it over-skips, never over-merges), so it needs no freshness proof.
The post is soft-fail — it never changes the primary line's content or the
function's rc 0 — but a failed post adds a second `[WARN]` line naming the
PR (PR #1608 review, agy + codex BLOCKER: silently losing the marker meant a
"successfully labelled" PR could later read as stale on the merge train with
no trace of why).

## Why this lives in the producer

The alternative — having the merge train grep review comment bodies — couples
the merge gate to every reviewer CLI's output format. A reviewer reformatting
its verdict line would then silently *unlock* the gate. Parsing here means the
same reformat produces `unknown`, no label, and a skipped PR: the failure
direction is the safe one.

The decisive reason, though, is that **only the producer knows which lanes
ran**. A consumer reading comment bodies cannot tell "lane skipped" from "lane
ran and posted nothing" — and that distinction *is* the absence-is-not-a-pass
invariant. It is not recoverable downstream at any level of parsing care.
