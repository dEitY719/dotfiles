# Decision — No Disk Cache for Repo / Category IDs

Issue #617 Open Question:
> 카테고리 ID 캐시 위치 — `.cache/gh-discussions-categories.json` vs
> 매 호출 fetch (refresh 비용 vs staleness).

**Decision (2026-05-14): no cache. Look up both IDs every invocation.**

## Reasons

1. **The lookup is one cheap GraphQL call.** `discussionCategories(first: 25)`
   returns < 1 KB and is well under the GitHub API rate-limit budget the
   rest of the gh-* skill family already consumes. A single skill
   invocation that posts a Discussion makes ~3 API calls today (repo ID,
   category list, mutation). Caching saves at most one of those — the
   marginal latency saving is below the cache-coherence overhead.

2. **Staleness is a silent footgun.** If the user renames or deletes a
   category in repo settings, a stale cache would either post into the
   wrong category (rename) or fail with a confusing "category ID not
   found" error (delete). Both are worse than the no-cache baseline of
   one extra round-trip.

3. **No multi-second startup cost.** The skill is invoked from an
   interactive Claude Code session — wall-clock budget is minutes, not
   milliseconds. A 200ms saving per call is invisible in that context.

4. **YAGNI for solo-dev workflow.** This repo (`dEitY719/dotfiles`) is
   a single-developer environment. Multi-user concurrency does not
   justify the extra complexity.

## Reverse criteria

Reopen this decision when **any one** of the following becomes true:

- Skill invocation rate climbs above ~10/day (e.g. CI agent posting
  routine Lessons), making the cumulative API spend non-trivial.
- GitHub introduces a per-repo cap on Discussions metadata reads that
  the helper starts hitting.
- The category list grows past 25 (the GraphQL `first: 25` would need
  pagination), at which point caching the resolved ID becomes
  meaningfully cheaper than re-paginating.

Until then, the helper does the obvious thing: fetch on every call.

## Why this lives here

The Open Question was raised in issue #617's body. Capturing the
decision next to the code that implements it (the `_gh_discussion_*`
helpers and `Step 4` create command) keeps the rationale discoverable
when a future maintainer asks "why is there no cache?" — instead of
relying on the closed issue thread alone.
