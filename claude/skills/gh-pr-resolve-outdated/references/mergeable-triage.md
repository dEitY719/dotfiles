# Mergeable triage matrix

Step 2 maps `gh pr view --json mergeable,mergeStateStatus` to an action:

| `mergeable` | `mergeStateStatus` | Action |
|---|---|---|
| `MERGEABLE` | `CLEAN`/`UNSTABLE` | `[OK] PR은 이미 up-to-date — nothing to do.` exit 0 (NF-1) |
| `MERGEABLE` | `BEHIND` | proceed to Step 3 (the case this skill handles) |
| `CONFLICTING` | — | `[FAIL] PR has merge conflicts — use /gh:pr-resolve-conflict` + exit 3 |
| `UNKNOWN` | — | GitHub still computing; print hint + exit 0 (retry later) |

`BLOCKED` alone (CI/approval pending) is not an out-of-date case — not handled here.

## Step 5 verification

After the push, re-read `--json mergeable,mergeStateStatus,url`:

- `mergeStateStatus ∈ {CLEAN, UNSTABLE, BLOCKED}` → banner cleared
  (`BLOCKED` here = CI/approval pending, normal).
- Still `BEHIND` → push didn't land; print PR URL, do not loop.
