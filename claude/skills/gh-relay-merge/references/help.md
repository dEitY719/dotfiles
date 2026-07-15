# gh:relay-merge — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | `<origin-PR#>` or `-h`/`--help`/`help` | — | PR on `origin` whose commit range is the relay payload (merged or open) |
| flag | `--remote <name-or-URL>` | `upstream` | Destination remote. Name (resolved via `git remote get-url`) or raw URL |
| flag | `--target-issue <N>` | new issue | Post the apply-guide to this existing destination issue/PR instead of creating a new one |
| flag | `--generated-patterns <globs>` | built-in list | Comma-separated globs marking generated artifacts to strip from oversized patches |

## Usage

```
/gh-relay-merge 168                              # relay origin PR #168 to upstream
/gh-relay-merge 168 --remote fork                # relay to remote named 'fork'
/gh-relay-merge 168 --remote https://github.com/org/repo.git
/gh-relay-merge 168 --target-issue 42            # post guide to existing issue #42
/gh-relay-merge 168 --generated-patterns '**/gen/**,*.lock'
/gh-relay-merge -h                               # this help
```

## When to use this skill

- You work in `origin` (an isolated internal network, e.g. corporate GHE)
  and need a merged/open PR's commits to reach a separate `upstream`
  (e.g. github.com).
- The network path is **asymmetric**: `git fetch upstream` works, but
  `git push upstream <branch>` is blocked by a corporate proxy (HTTP 403
  block page). `gh api` single REST calls work; single-file
  `gh gist create` works.

## When NOT to use

- `git push upstream` actually works. Use `/gh-pr` directly — this skill's
  Step 2 probe will detect that and delegate to it anyway.
- Both remotes are the same host / no asymmetric block exists.

## What the skill does

1. Resolves the origin PR and the `--remote` destination (hard error on a
   missing remote — never silent fallback to `origin`), and confirms the
   destination is reachable.
2. **Probes push capability** with a throwaway-ref `--dry-run` push. If
   push works, delegates to `gh:pr` and stops (relay is a fallback only).
3. On confirmed block (HTTP 403 / block-page), resolves the PR's
   base/head commit range and runs a destination-divergence pre-flight.
4. `git format-patch` per commit; oversized patches whose bulk is a
   recognized generated artifact are regenerated without that diff (with a
   recorded regeneration command); anything else oversized stops the skill.
5. Uploads each patch via single-file `gh gist create`, one call at a time.
6. Posts an apply-guide comment (gist table + `git am` steps + regeneration
   commands + verification basis) to a new or `--target-issue` destination.
7. Optionally (with explicit confirmation) closes a duplicate origin issue.
8. Reports the destination URL, gist count, and any split-patch decisions.

## Constants (tunable)

- `RELAY_PATCH_MAX_BYTES` = **40960** (40KB) — fixed safe per-file gist
  size cutoff. Empirically ~35KB is known-good and ~62KB known-bad; there
  is no confirmed safe threshold between them, so 40KB is the conservative
  named constant. Not auto-detected — tune here if real limits change.
- Default `--generated-patterns`: `**/generated/**`, `**/*.generated.*`,
  `openapi.json`, `package-lock.json`, `*.lock`, `**/dist/**`, `**/build/**`.

## What this skill will NOT do

- Fall back to `origin` when the requested remote is missing.
- Push normally and *then* relay — it always probes first.
- Create a multi-file gist or run gist uploads in parallel.
- Silently truncate a patch. Only recognized generated-artifact diffs are
  stripped; any other oversized patch stops the skill with a report.
- Auto-close an origin-side issue without explicit confirmation.

## Related skills

- `gh:pr` — the SIMPLE PATH delegate when push actually works.
- `gh:issue-flow` — conventions for posting issue comments / metrics.
- `gh:issue-implement` — source of the "resolve remote, never silent
  fallback" pattern reused in `references/remote-resolution.md`.
