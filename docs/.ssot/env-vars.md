# Environment Variables Catalog

Cross-skill / cross-tool env vars that change runtime behaviour. New
toggles MUST land here so operators can grep one file before adopting
a new repo or workspace.

## `gh:*` skills

### `GH_DISABLE_AI_METRICS`

| Field | Value |
|---|---|
| Default | unset |
| Active when | set to `1` |
| Scope | every `gh:*` skill that writes to GitHub (issue/PR body footer, issue/PR comment) |
| Source SSOT | `claude/skills/gh-issue-create/references/metrics-helper.md` |
| Issue | [#399](https://github.com/dEitY719/dotfiles/issues/399) — design comment [#384](https://github.com/dEitY719/dotfiles/issues/384#issuecomment-4404284951) |

When the variable is `1`, the following skills skip ai-metrics
attachment and produce identical artifacts otherwise:

- `gh:issue-create` — issue body footer
- `gh:pr` — PR body footer
- `gh:commit` — linked-issue comment
- `gh:pr-reply`, `gh:pr-approve`, `gh:pr-merge`, `gh:pr-resolve-conflict` — PR comment
- `gh:pr-merge-emergency` — incident issue body footer
- `gh:issue-flow` — flow-aggregate issue comment (Step 2.6)

`gh:issue-implement` and `gh:issue-read` print metrics to stdout only,
so the env var has no effect there.

`gh:add-ai-metrics` is the **deliberate retrofit** path and **ignores**
this var — that is its entire purpose.

Use cases:

- External / company repos that disallow AI-usage markers in artifacts
- Debugging or one-off invocations where the footer would be noise
- Mirroring a teammate's preference temporarily

Per-call examples:

```bash
GH_DISABLE_AI_METRICS=1 /gh-pr 399
GH_DISABLE_AI_METRICS=1 /gh-commit
```

Persist for a session:

```bash
export GH_DISABLE_AI_METRICS=1
```

### `GH_PR_MERGE_SKIP_BOARD_CHECK`

| Field | Value |
|---|---|
| Default | unset |
| Active when | set to `1` |
| Scope | `gh:pr-merge` board approval gate (Step 4-B) |
| Source SSOT | `claude/skills/gh-pr-merge/SKILL.md` |
| Issue | [#397](https://github.com/dEitY719/dotfiles/issues/397) |

When `1`, bypasses the projectV2 board "Approved" check inside
`gh:pr-merge`. Used during board-config transitions where the
authoritative status moves between fields.

### `GH_PROJECT_STATUS_SYNC`

| Field | Value |
|---|---|
| Default | unset (treated as enabled) |
| Active when | set to `0` |
| Scope | every `gh:*` skill that calls `_gh_project_status_sync` |
| Source SSOT | `shell-common/functions/gh_project_status.sh` |

When `0`, skip pushing project-board card status updates. Repos
without a projectV2 attachment auto-skip without needing the var.

### `GH_REPO`

| Field | Value |
|---|---|
| Default | unset |
| Active when | set to `OWNER/REPO` or `HOST/OWNER/REPO` |
| Scope | `_gh_project_status_sync` / `_gh_project_status_query_current` repo resolution |
| Source SSOT | `shell-common/functions/gh_project_status.sh` |
| Issue | [#1405](https://github.com/dEitY719/dotfiles/issues/1405) |

Pins the repo whose projectV2 board is read/written, instead of
auto-detecting it. Same variable `gh` itself honors, so a value already
exported for `gh` is reused as-is (both the `OWNER/REPO` and
`HOST/OWNER/REPO` forms are accepted; the host segment is validated then
dropped — host routing stays `GH_HOST`'s job).

Precedence, first non-empty wins:

1. `--repo <owner/repo>` argument to `_gh_project_status_sync` (or the
   optional 3rd positional of `_gh_project_status_query_current`)
2. `GH_REPO`
3. `TARGET_REPO`
4. `gh repo view --json owner,name` auto-detect

A malformed value at levels 1–3 fails closed (resolution returns 1) — it
does **not** fall through to auto-detect. A bare `gh repo view` reports
what `gh repo set-default` chose, not git's origin, so silently rescuing a
typo could sync a different repo's board.

### `TARGET_REPO`

| Field | Value |
|---|---|
| Default | unset |
| Active when | set to `OWNER/REPO` or `HOST/OWNER/REPO` |
| Scope | `_gh_project_status_sync` / `_gh_project_status_query_current` repo resolution |
| Source SSOT | `shell-common/functions/gh_project_status.sh` |
| Issue | [#1405](https://github.com/dEitY719/dotfiles/issues/1405) |

Same meaning as `GH_REPO`, one step lower in the precedence chain above.
Exists because the `gh:*` skills already export `TARGET_REPO` when they
pin a remote, so the board helper picks it up without the skill having to
also set `GH_REPO`. Ignored when `GH_REPO` or an explicit `--repo`
argument is present.

## How to add a new entry

1. Document the var here first (this file is the catalog SSOT).
2. Implement the env branch in the skill / function SSOT.
3. Add a regression test in `tests/bats/` that covers the set/unset
   branches.
4. Land all three in the same PR.
