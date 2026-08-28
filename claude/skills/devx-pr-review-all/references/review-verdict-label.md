# devx:pr-review-all — Review verdict → merge-gate label

SSOT for how a reviewer lane's closing verdict line becomes a machine-readable
PR label. Implementation: `shell-common/functions/devx_pr_review_all.sh`;
regression suite: `tests/bats/functions/devx_pr_review_all_verdict.bats`.

Why it exists: every `gh:pr-review` preset mandates a closing verdict line, and
until #1527 nothing in the repo read it. PR #1518 collected two independent
blocking verdicts and merged 32 minutes later, because the merge train's only
real gate was CI.

**Wiring status.** This document specifies the parser and the call convention
only. #1563's label-lifecycle invalidation rules **are** implemented: every
skill that advances a PR's head (`gh:pr-reply`, `gh:pr-resolve-conflict`,
`gh:pr-resolve-outdated`) now drops the stale verdict through the shared
`_gh_pr_drop_label` helper, whose header comment in
`shell-common/functions/gh_pr_edit_safe.sh` is the SSOT for the asymmetry rule
(`review-passed` always, `review-blocked` only on evidence). The train-side
hard gate is still tracked in #1564 and is **not** implemented, so no merge
decision consumes these labels yet — treat the gate call sites below as the
contract that issue must build against, not as code already running.

## The labels

| label | meaning |
|---|---|
| `review-blocked` | at least one reviewer lane returned a blocking verdict |
| `review-passed` | every lane that ran returned a non-blocking verdict, and at least one lane ran |

Neither belongs to the 10-label SSOT (`gh-label-bootstrap/references/gh-labels.md`).
Like `CI fail` and `conflict` they are **pipeline-state** labels, not
issue-classification ones, and that document explicitly scopes such labels out.
Provisioning them is part of #1564.

**Absence is the third state, and it means "not verified".** A PR carrying
neither label has not been shown to pass review. That is what makes a time
backstop unnecessary here: a stuck PR is one label away from moving, and a
human can add or remove it at any time.

## The three helpers

```
devx_pr_review_all_lane_block <ai> [<head-sha>]   # comment bodies on stdin
  -> that lane's raw block, or nothing
devx_pr_review_all_verdict                        # one lane's raw text on stdin
  -> blocking | concerns | lgtm | unknown
devx_pr_review_all_aggregate                      # verdict tokens on stdin,
                                                  #   one per line, one per lane
  -> label=review-blocked | label=review-passed | label=    (+ lanes=N)
```

All three are pure: stdin in, stdout out, no network, no shell state.

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
posts the reviewer's raw output to the PR wrapped in `<!-- ai-review:<ai> -->`
markers, synchronously, before it returns — a durable machine-readable record
rather than a summary. Fetch the comments **once**, then per lane:

```sh
. "${SHELL_COMMON}/functions/devx_pr_review_all.sh"

BODIES=$(GH_HOST="$TARGET_HOST" gh api --paginate \
    "repos/$TARGET_REPO/issues/$pr/comments" --jq '.[].body')

verdict=$(printf '%s\n' "$BODIES" |
    devx_pr_review_all_lane_block "$ai" |
    devx_pr_review_all_verdict)
# -> blocking | concerns | lgtm | unknown
```

`devx_pr_review_all_lane_block` takes the **last complete** block for that lane,
so a re-review supersedes an earlier verdict, and it ignores an unterminated
block — half a review is not a verdict.

### Freshness: the optional head-sha

Without a second argument the helper cannot tell a block this run just posted
from one left by an earlier round. A run that posted nothing —
`GH_DISABLE_AI_METRICS=1`, `--no-post-comment`, or a post that failed — would
then silently reuse a stale verdict, and a stale verdict can authorize a merge
of code it never saw.

Pass the PR's head sha to close that hole:

```sh
head_sha=$(GH_HOST="$TARGET_HOST" gh pr view "$pr" --repo "$TARGET_REPO" \
    --json headRefOid --jq .headRefOid)

verdict=$(printf '%s\n' "$BODIES" |
    devx_pr_review_all_lane_block "$ai" "$head_sha" |
    devx_pr_review_all_verdict)
```

With a sha given, only `<!-- ai-review:<ai>:<head-sha> -->` … `<!-- /ai-review:<ai>:<head-sha> -->`
blocks match, both markers must carry the same sha, and a lane with no block for
that exact ai+sha pair yields nothing — which reads downstream as `unknown`,
so no label, so no merge. Fail-closed.

> **Producer caveat.** `gh:pr-review`'s marker writer
> (`shell-common/functions/gh_pr_review.sh`) currently emits the plain
> `<!-- ai-review:<ai> -->` form with no sha suffix. Passing a head sha against
> today's comments therefore yields `unknown` for every lane. Emitting the
> sha-tagged marker is part of the merge-gate wiring (#1564); until it lands,
> callers should omit the second argument, which is exactly the behavior above
> without the freshness check. The sha-aware path is fully specified and
> tested here so the producer change is a one-sided edit when it happens.

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
            devx_pr_review_all_lane_block "$ai" |
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

Add through `_gh_pr_edit_safe_label` (`shell-common/functions/gh_pr_edit_safe.sh`),
never bare `gh pr edit --add-label` — that silently exits 1 on repos with
classic Projects attached (#326). Remove the opposite label through the REST
endpoint, for the same reason. The whole block is **soft-fail**: a labelling
failure leaves the PR unlabelled, which reads as "not verified".

```sh
. "${SHELL_COMMON}/functions/gh_pr_edit_safe.sh"

if [ -z "$label" ]; then
    echo "[WARN] no reviewer lane produced a verdict — PR #$pr left unlabelled"
else
    case "$label" in
    review-blocked) opposite=review-passed ;;
    *) opposite=review-blocked ;;
    esac

    GH_HOST="$TARGET_HOST" gh api -X DELETE \
        "repos/$TARGET_REPO/issues/$pr/labels/$opposite" >/dev/null 2>&1 || :

    _gh_pr_edit_safe_label "$pr" "$label" --repo "$TARGET_REPO"
    case "$?" in
    0) echo "[OK] PR #$pr labelled \`$label\` (${lanes} lane(s))" ;;
    3) echo "[WARN] label \`$label\` missing in $TARGET_REPO — provision it first" ;;
    *) echo "[WARN] labelling PR #$pr failed — treat the PR as unverified" ;;
    esac
fi
```

**The opposite label is removed first, and unconditionally.** A re-review that
flips `review-blocked` to `review-passed` has to clear the old one, or a
consumer sees both.

`_gh_pr_edit_safe_label` returns 3 when the label does not exist in the repo and
**refuses to auto-create it** (`feedback_gh_label_no_autocreate.md`, #326).
Provisioning the two pipeline labels is therefore an explicit, human-invoked
step, tracked with the rest of the wiring in #1564.

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
