# gh:issue-proceed — Precondition classes (Step 2.3)

The skill auto-detects whether the directive requires mutation, then
enforces branch + clean-tree accordingly. The class is logged to stdout on
Step 2.3 entry.

## Mutation-required keyword scan

Scan `§deliverables ∪ §execution_protocol ∪ §decision_rules` for any of:

- `commit_changes`, `Skill(gh:commit)`, `git commit`
- `open_pr`, `Skill(gh:pr)`, `gh pr create`
- `queue_doc_patch`
- `신규 파일` / `new file` (in deliverables)

## Classes

| Class | Trigger | Requirements |
|---|---|---|
| `read-only` | no mutation keyword | git repo only; any branch OK |
| `mutation-required` | ≥1 mutation keyword | worktree + non-default branch + clean tree |
| `mixed` | mutation + `allow: cross-repo` token in §safety | mutation-required + cross-repo permission check |
| `verify-only` (override) | §track = `verify-only` | force read-only regardless of keywords |

## Enforcement

- `read-only` / `verify-only` → confirm we are inside a git repo; proceed.
- `mutation-required` / `mixed`:
  - current branch ≠ default (`main`/`master`) — else STOP.
  - working tree clean (`git status --porcelain` empty) — else STOP.
  - inside a dedicated worktree by convention (the skill does **not**
    create one).

Mismatch → STOP with a remediation hint, e.g.:

```
gh:issue-proceed #<N> precondition mismatch
  Class: mutation-required (keyword '<kw>' found in <section>)
  But: currently on default branch 'main'.
  Create a feature branch in a worktree (e.g. `gwt`) and re-run, or
  add `Track: verify-only` to the issue body if no mutation is intended.
```

## Why classify before executing

A directive that only verifies (runs a CLI, reads output, files a report)
must not be blocked by a clean-tree requirement; one that commits must
never run on `main`. Auto-detection keeps read-only directives friction-
free while fencing mutating ones — the `verify-only` override exists for
the ambiguous case where keywords appear only in quoted/example context.
