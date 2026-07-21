# gh:relay-merge — Hard Constraints

Deliberate boundaries. Do not violate them even when the user asks "just
this once" — the safer alternative is usually `gh:pr` (normal push) once
the network allows it.

## Never fall back to `origin` silently

If the requested `--remote` (or the default `upstream`) does not exist,
hard-error with the list of available remotes and stop. `origin` is the
*source* of the relay payload, never a destination. Silent fallback masks
typos and would relay commits into the wrong (internal) repo. Same rule as
`gh:issue-implement`'s repo resolution.

## Never push-then-relay — probe first

Relay mode (public gists + a destination issue comment) has irreversible
side effects. Always run the Step 2 push-capability probe first. If push
works, take the SIMPLE PATH (`gh:pr`) and stop. Only a *confirmed* block
(HTTP 403 / block-page marker) triggers relay. Transient/inconclusive
errors get one backoff retry, then default to not-blocked — never treat a
flaky network as a confirmed block.

## Never multi-file or parallel `gh gist create`

Upload exactly one patch file per `gh gist create` invocation, sequentially.
Multi-file gist creation always fails under this network policy regardless
of file count, and parallel uploads risk rate-limit / abuse triggers.

## Never silently truncate a patch

A patch over `RELAY_PATCH_MAX_BYTES` (40KB) is only ever shrunk by excluding
**recognized generated-artifact** paths (with a recorded regeneration
command), or — for an oversized non-artifact commit — pre-split by file
group into independently `git am`-able sub-patches (see
`references/patch-generation.md` → "File-group pre-split"). Only when a
single **file's** own diff alone still exceeds the limit does the skill
stop and report — do not truncate or split arbitrary code diffs at that
point. Truncation corrupts the commit `git am` reconstructs. This is the
repo's "no silent caps" norm.

## Never auto-close an origin-side issue

Step 7 cleanup (closing a duplicate origin tracking issue with a
cross-reference) runs **only** with the user's explicit confirmation. No
auto-close, ever.

## Never post a partial apply-guide

If gist upload stops midway, list the gists already created and stop before
Step 6. A partial apply-guide (missing patches, wrong order) is worse than
none — the destination reader would build a broken commit series.

## Size cutoff is a fixed named constant

`RELAY_PATCH_MAX_BYTES = 40960`. Do not implement binary-search
auto-detection of the real gist limit. The value is named and greppable so
it can be tuned from future empirical evidence in one place.
