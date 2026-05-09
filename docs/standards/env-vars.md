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

## How to add a new entry

1. Document the var here first (this file is the catalog SSOT).
2. Implement the env branch in the skill / function SSOT.
3. Add a regression test in `tests/bats/` that covers the set/unset
   branches.
4. Land all three in the same PR.
