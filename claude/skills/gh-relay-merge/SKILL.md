---
name: gh:relay-merge
description: >-
  Relay a PR's commits from an isolated `origin` to `upstream` when a proxy
  blocks `git push` — probe first, then patch+gist with a `git am` apply-guide.
  Use for /gh:relay-merge, /gh-relay-merge, "origin PR를 upstream 으로 릴레이",
  "push 막혀서 gist 로 넘겨줘".
allowed-tools: Bash, Read, Write, Grep, Glob
metadata:
  model_recommendation:
    tier: opus
    reason: "asymmetric-network branch logic + per-patch size/artifact reasoning + no-silent-truncation judgement; multi-step relay with irreversible gist/comment side effects"
    claude: prefer
    non_claude: advisory-only
---

# gh:relay-merge — Patch+Gist Relay for Push-Blocked Upstream

## Role

머지된(또는 열린) PR 의 커밋을 **격리된 `origin`(사내 GHE) 에서 별개의 `upstream`(github.com) 으로** 넘긴다.
전제는 비대칭 네트워크 — 사내 프록시가 `git push upstream` 을 막지만 `gh api` 와 단일 파일 `gh gist create` 는 통한다.
먼저 push 가능 여부를 **실제로 프로브**해서, 정상 push 가 되면 [[gh-pr]] 에 위임하고 멈춘다(릴레이는 폴백이지 기본이
아니다). HTTP 403 / block-page 로 차단이 확인될 때만 릴레이 모드로 간다: 커밋당 `git format-patch` → 호출당 파일
1개 gist 업로드 → 목적지 이슈에 `git am` apply-guide 코멘트.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Step 1: Preconditions — two mutually-exclusive input modes

Input is EITHER positional `<origin-PR#>` OR `--commits <base>..<head>` (both supplied → hard error, stop).
Shared flags: `--remote`, `--target-issue`, `--known-failures`, `--generated-patterns` (table: `references/help.md`).
- **PR mode**: `GH_HOST="$SOURCE_HOST" gh pr view <N> --repo "$SOURCE_REPO" --json number,state,url,headRefOid,baseRefName,mergeCommit,statusCheckRollup,reviewDecision`.
  Do **not** require `merged` — use the PR's current head/base commits.
- **`--commits` mode**: skip `gh pr view`; use the range directly. Git semantics — `base` EXCLUDED, `head`
  INCLUDED. No PR object exists, so Step 3's pre-flight uses the head SHA parsed from the arg.

Resolve `--remote` per `references/remote-resolution.md`; missing `upstream` with no explicit `--remote` → hard
error, never fall back to `origin`. Confirm the destination is reachable (`git fetch` / `git ls-remote`) first.
It also binds `SOURCE_REPO`/`SOURCE_HOST` + `DEST_REPO`/`DEST_HOST`, each pair from **one** remote URL. Two hosts
in one run → no global `GH_HOST`: every `gh` call carries its own side's host inline (#1403 / #1407).

## Step 2: Push-Capability Probe (branch point)

Run the throwaway-ref real push probe in `references/push-probe.md`.
- Probe says push works → **SIMPLE PATH**: delegate to [[gh-pr]] (or an equivalent normal branch push + PR) and
  stop. Relay mode is a fallback, not the default.
- Confirmed blocked (HTTP 403 / block-page marker) → continue to Step 3.
- Transient/inconclusive → retry once with short backoff; still inconclusive → not-blocked, take SIMPLE PATH.

## Step 3: Determine Commit Range + Pre-flight

Resolve the range's base/head SHAs (from the PR, or parsed from `--commits`)
and run the destination-divergence sanity check in
`references/patch-generation.md` → "Pre-flight" — it runs in **both** input
modes. Warn up front about structurally-known conflict categories instead of
shipping patches that will fail `git am` on the far side.

## Step 4: Generate Patches

Run `git format-patch` over the commit range (one `git am`-able file per commit) and enforce the
`RELAY_PATCH_MAX_BYTES` size cutoff, generated-artifact exclusion, and no-silent-truncation rule per
`references/patch-generation.md`.

## Step 5: Upload Gists (one file per call)

Upload each patch via single-file `gh gist create`, sequentially — never
multi-file/parallel — per `references/gist-relay.md`. Stop on any failure.

## Step 6: Post the Apply-Guide Comment

Build the comment from `references/apply-guide-template.md`, which owns its
wording and section order. Post to a NEW destination issue (default) or
`--target-issue <N>`; render `--known-failures` into its known-failures section.

## Step 7: Origin-side Cleanup (optional)

Only with explicit user confirmation, close a duplicate origin-side tracking
issue with a cross-reference comment. Never auto-close.

## Step 8: Report

Summarize the destination issue/comment URL, gist count, whether any patches were split (artifact exclusion or
file-group pre-split), and — if Step 2's probe passed — that the simple push+PR path was used instead of relay.

## Constraints

See `references/constraints.md` for the full list. Hard rules: never fall
back to `origin` silently · never plain-`push`-then-relay (probe first) ·
never multi-file/parallel `gh gist create` · never silently truncate (only
generated artifacts stripped; oversized commits get file-group pre-split) ·
never auto-close an origin issue.

## Related Skills

`gh:pr` (SIMPLE PATH delegate when push works) · `gh:issue-relay-flow` (issue → branch → implement → this skill). Full argument/flag table: `references/help.md`.
