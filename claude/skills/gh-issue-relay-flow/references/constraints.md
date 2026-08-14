# gh:issue-relay-flow — Hard Constraints

Deliberate boundaries. Do not violate them even when the user asks "just
this once."

## Never fall back to `origin` silently

If the requested `--remote` (or the default `upstream`) does not exist,
hard-error with the list of available remotes and stop — identical rule to
`gh:relay-merge`'s `remote-resolution.md`. `origin` is never a relay
destination; a silent fallback masks a typo and would base the branch off
the wrong repo entirely.

## Never delegate implementation with unresolved Open Questions

If the issue's body/comments contain an Open Questions section with items
that have no recorded answer (from this conversation or a prior one),
**stop before Step 3's delegation** and get the answers from the user
first. A Worker that receives an ambiguous brief will guess, and a wrong
guess on a design question is far more expensive to unwind after
implementation than before it. This is not a hypothetical: this exact skill
was authored on an issue (#1346) whose own Open Questions section had no
answer recorded at delegation time.

## Never auto-reset a reused branch that has unique commits

Per `branch-setup.md`'s reuse decision: if a same-named local branch has
commits not present on the destination's default branch, always ask before
resetting or continuing on top of them. Only a branch with zero unique
commits is eligible for a reset, and even then, ask first — never assume.

## Never duplicate `gh:relay-merge`'s responsibilities

Patch generation, the `RELAY_PATCH_MAX_BYTES` cutoff, generated-artifact
exclusion, file-group pre-split, sequential single-file gist upload, and
apply-guide posting all live in `gh:relay-merge`. Step 5 calls it verbatim
with `--commits`; this skill must never reimplement any piece of that
logic inline, even partially.

## Verification failure re-delegates, never skips ahead

If Step 4's lint/test run fails, Step 5 (relay) does not run. Re-delegate
per `verification.md`'s guidance — with a sharper brief, not a bare retry
— and re-verify before relaying. Never relay unverified changes just
because the Worker reported success.

## A `gh:relay-merge` failure is reported unmodified

If Step 5's `Skill(gh:relay-merge, ...)` call fails, surface its error
message as-is in the Step 6 report — do not paraphrase, soften, or retry
it silently. The user needs `gh:relay-merge`'s own diagnostic (which push
probe result triggered which path, which gist upload failed, etc.) to act
on it; this skill has no better information than what it passed through.
