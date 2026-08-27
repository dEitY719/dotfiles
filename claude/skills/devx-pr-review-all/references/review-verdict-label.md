# devx:pr-review-all — Review verdict label (issue #1527)

SSOT for the two PR labels this skill emits and the merge train consumes.
`gh:pr-merge-train` reads them (`gh-pr-merge-train/references/review-verdict-gate.md`);
`gh:pr-reply` clears `review-blocked` once it has actually pushed fixes.

## The labels

| label | color | meaning |
|---|---|---|
| `review-blocked` | `b60205` | at least one reviewer lane returned a blocking verdict |
| `review-passed` | `0e8a16` | every lane that ran returned a non-blocking verdict, and at least one lane ran |

Neither is part of the 10-label SSOT (`gh-label-bootstrap/references/gh-labels.md`)
— like `CI fail` and `conflict` they are a **pipeline-state** label system, not an
issue-classification one. Unlike those two they *are* provisioned by
`gh:label-bootstrap`, from that file's separate `pipeline|` feed, and `--prune`
keeps them. **That is the rollout path** (#1527, PR #1529 codex review): without
it a repo that lacks the labels can never get them, since the add path refuses to
auto-create — so the gate would deadlock with every PR unlabelled and skipped.

**Absence is the third state, and it means "not verified".** A PR with neither
label has not been shown to pass review — the train skips it. That is what makes
a time backstop unnecessary here (contrast #1524): a stuck PR is one label away
from moving, and a human can add or remove it at any time.

## Deriving the verdicts (Step 3 → Step 5)

Each of the four reviewer lanes (`agy`, `codex`, `opencode`, `hermes`) ends its
output with a mandatory verdict line — `판정: [LGTM|우려있음|블로킹]` or
`Verdict: [LGTM|CONCERNS|BLOCKING]` (`gh-pr-review/references/review-presets.md`).
Capture each lane's raw output in Step 3, then per lane:

```sh
. "${SHELL_COMMON}/functions/devx_pr_review_all.sh"
VERDICT=$(printf '%s\n' "$LANE_OUTPUT" | devx_pr_review_all_verdict)
# -> blocking | concerns | lgtm | unknown
```

A lane that **did not run** (`command -v` empty, non-internal PC, non-zero exit —
every `[SKIP]`/`[WARN]` row of the Step 7 report) contributes **no verdict at
all**. It is not an `unknown`; it is simply absent from the aggregation. The
`/simplify` lane never contributes — it produces no verdict.

Run all three shell blocks of Step 5 — per-lane verdict, aggregate, label — in
**one** Bash tool call. The tool keeps no shell state between calls, so a split
loses the sourced functions and `$VERDICTS`/`$label`, and an empty `$label`
silently reads as "no verdict".

Then aggregate over the lanes that did run. Read the two `key=value` lines with
`sed`, not `eval` — the values are controlled, but a parser that cannot execute
anything is the right default for something that gates a merge:

```sh
AGG=$(devx_pr_review_all_aggregate $VERDICTS)      # $VERDICTS unquoted: one word per lane
label=$(printf '%s\n' "$AGG" | sed -n 's/^label=//p')
lanes=$(printf '%s\n' "$AGG" | sed -n 's/^lanes=//p')
```

| lanes that ran | outcome | `label` |
|---|---|---|
| any lane `blocking` | blocked | `review-blocked` |
| ≥1 lane, all `lgtm`/`concerns` | passed | `review-passed` |
| ≥1 lane, any `unknown` | verdict not established | *(empty)* |
| zero | nothing was checked | *(empty)* |

`우려있음`/`CONCERNS` is a **pass** — it is a non-blocking opinion, and
`gh:pr-reply` still answers it. `unknown` is not, because a lane whose output
stopped parsing is indistinguishable from a lane that never reached a verdict.

## Applying the label (Step 5)

Add through `_gh_pr_edit_safe_label`, never bare `gh pr edit --add-label` —
that silently exits 1 on repos with classic Projects attached (#326).
Remove the opposite label through the REST endpoint, for the same reason.
The whole block is **soft-fail**: a labelling failure leaves the PR unlabelled,
which the train reads as "not verified" and skips. Fail-closed by construction.

```sh
. "${SHELL_COMMON}/functions/gh_pr_edit_safe.sh"

if [ -z "$label" ]; then
    echo "[WARN] no reviewer lane produced a verdict — PR #$pr left unlabelled (train will skip it)"
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
    3) echo "[WARN] label \`$label\` missing in $TARGET_REPO — bootstrap once: /gh-label-bootstrap $TARGET_REPO" ;;
    *) echo "[WARN] labelling PR #$pr failed — train will treat it as unverified" ;;
    esac
fi
```

**The opposite label is removed first, and unconditionally.** A re-review that
flips `review-blocked` to `review-passed` has to clear the old one or the train
sees both and — per its own precedence rule — keeps skipping.

`_gh_pr_edit_safe_label` returns 3 when the label does not exist in the repo and
**refuses to auto-create it** (`feedback_gh_label_no_autocreate.md`, #326). That
is deliberate: silently creating labels from a code path is how typo'd labels
enter a repo. The bootstrap is therefore explicit and human-invoked — once per
repo, before the gate is expected to pass anything:

```sh
/gh-label-bootstrap <owner>/<repo>
```

It reads the `pipeline|` feed in `gh-label-bootstrap/references/gh-labels.md`,
POSTs whatever is missing, PATCHes drift back to the SSOT color, and never
prunes them. Re-running it is idempotent, so it is safe to fold into ordinary
repo setup alongside the 10-label sync.

## Why this lives in the producer

The alternative — having `gh:pr-merge-train` grep the review comment bodies —
couples the merge gate to every reviewer CLI's output format. A reviewer
reformatting its verdict line would then silently *unlock* the gate. Parsing
here means the same reformat produces `unknown`, no label, and a skipped PR:
the failure direction is the safe one.

The decisive reason, though, is that **only the producer knows which lanes
ran**. A consumer reading comment bodies cannot tell "lane skipped" from
"lane ran and posted nothing" — and that distinction *is* the absence-is-not-a-pass
invariant. It is not recoverable downstream at any level of parsing care.
