---
name: gh:relay-merge
description: >-
  Relay a merged (or open) PR's commits from an isolated `origin` (internal
  GHE) to a separate `upstream` (github.com) when `git push upstream` is
  blocked by a corporate proxy but `gh api` / single-file `gh gist create`
  still work. Probes push capability first — if a normal push succeeds it
  delegates to [[gh-pr]] and stops; only when push is confirmed blocked
  (HTTP 403 / block-page) does it fall back to relay mode: `git format-patch`
  per commit, one-file-per-call gist upload, then a `git am` apply-guide
  comment on the destination issue. Use when the user runs /gh:relay-merge,
  /gh-relay-merge, or asks "origin PR를 upstream 으로 릴레이", "push 막혀서
  patch+gist 로 넘겨줘", "relay merged PR to upstream via gist". Accepts
  `<origin-PR#> [--remote <name-or-URL>] [--target-issue <N>]
  [--generated-patterns <globs>]` and `-h`/`--help`/`help`.
allowed-tools: Bash, Read, Write, Grep, Glob
metadata:
  model_recommendation:
    tier: opus
    reason: "asymmetric-network branch logic + per-patch size/artifact reasoning + no-silent-truncation judgement; multi-step relay with irreversible gist/comment side effects"
    claude: prefer
    non_claude: advisory-only
---

# gh:relay-merge — Patch+Gist Relay for Push-Blocked Upstream

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Step 1: Preconditions

Positional `<origin-PR#>` (required); flags `--remote`, `--target-issue`,
`--generated-patterns`. Resolve the origin PR with
`gh pr view <N> --repo <origin-repo> --json number,state,url,headRefOid,baseRefName,mergeCommit,statusCheckRollup,reviewDecision`.
Do **not** require `merged` — use the PR's current head/base commits.
Resolve `--remote` (name or raw URL) per `references/remote-resolution.md`;
missing `upstream` with no explicit `--remote` → hard error, never fall
back to `origin`. Confirm the destination is reachable (`git fetch` /
`git ls-remote`) before anything else.

## Step 2: Push-Capability Probe (branch point)

Run the throwaway-ref dry-run push probe in `references/push-probe.md`.
- Probe says push works → **SIMPLE PATH**: delegate to [[gh-pr]] (or an
  equivalent normal branch push + PR) and stop. Relay mode is a fallback,
  not the default.
- Confirmed blocked (HTTP 403 / block-page marker) → continue to Step 3.
- Transient/inconclusive → retry once with short backoff; still
  inconclusive → treat as not-blocked and take the SIMPLE PATH.

## Step 3: Determine Commit Range + Pre-flight

Resolve the PR's base/head SHAs and run the destination-divergence
sanity check in `references/patch-generation.md` → "Pre-flight". Warn the
user up front about structurally-known conflict categories (env-specific
config blocks, internal/external variants) instead of shipping patches
that will fail `git am` on the far side.

## Step 4: Generate Patches

Run `git format-patch` over the commit range (one `git am`-able file per
commit) and enforce the `RELAY_PATCH_MAX_BYTES` size cutoff, generated-artifact
exclusion, and no-silent-truncation rule per `references/patch-generation.md`.

## Step 5: Upload Gists (one file per call)

Upload each patch with a single-file `gh gist create <one-file>`,
sequentially — never multi-file, never parallel — per
`references/gist-relay.md`. Report and stop on any non-transient failure.

## Step 6: Post the Apply-Guide Comment

Build the comment from `references/apply-guide-template.md` and post it to
a NEW destination issue (default) or `--target-issue <N>` if supplied:
ordered gist table + `git am` instructions + excluded-artifact regeneration
commands + a "verification basis" section from Step 1's PR data.

## Step 7: Origin-side Cleanup (optional)

Only with explicit user confirmation, close a duplicate origin-side
tracking issue with a cross-reference comment. Never auto-close.

## Step 8: Report

Summarize the destination issue/comment URL, gist count, whether any
patches were split for generated-artifact exclusion, and — if Step 2's
probe passed — that the simple push+PR path was used instead of relay.

## Constraints

See `references/constraints.md` for the full list. Hard rules: never fall
back to `origin` silently · never plain-`push`-then-relay (probe first) ·
never multi-file/parallel `gh gist create` · never silently truncate a
patch (only recognized generated artifacts get split) · never auto-close
an origin issue.
