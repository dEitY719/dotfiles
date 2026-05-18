# gh:pr-resolve-ci-fail — Safety Nets

Detail companion for SKILL.md Steps 1, 4, 5, and 7.

## Preconditions (Step 1)

Run as a parallel batch. Any failure → stop with the matching message.

| Check | How | Fail message |
|---|---|---|
| Inside a git repo | `git rev-parse --show-toplevel` | `[FAIL] not inside a git repo` |
| Not on default branch | Compare `git rev-parse --abbrev-ref HEAD` against `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` | `[FAIL] refuses on default branch (<DEFAULT>) — check out the PR's head branch first` |
| Working tree clean | `git status --porcelain` empty | `[FAIL] working tree dirty — commit/stash your edits first; this skill never auto-stashes` |
| No in-progress rebase / merge / cherry-pick | `git rev-parse --git-path rebase-merge` / `rebase-apply` / `MERGE_HEAD` / `CHERRY_PICK_HEAD` / `REVERT_HEAD` all absent | `[FAIL] in-progress <name> at <marker> — finish or abort first` |

### Why no auto-stash

Sister skill `gh-pr-resolve-conflict` does auto-stash because rebase
controls the entire working tree. This skill **edits the working tree
itself** in Step 4, so an auto-stash would silently drop the user's
unrelated edits onto the stash list and then pop them onto our CI fix
commit. The safer default is to demand a clean tree.

## Local validation gate (Step 4)

The "infinite loop" risk: push fix → CI still red → fix → push → CI
still red → … The mitigation is to run the same command CI ran
locally, before pushing, and stop on red.

### Detection heuristic for "what CI ran"

Read the failing workflow's YAML (`gh api repos/.../contents/.github/workflows/<file>`)
and extract the `run:` line from the step that failed. If parsing the
YAML is too fragile, fall back to the project's conventional commands
in order:

1. `tox` (if `tox.ini` exists at repo root) — dotfiles convention.
2. `./tests/test` (if exists) — dotfiles convention.
3. `pytest` (if `pyproject.toml` has `[tool.pytest]`).
4. `npm test` / `pnpm test` / `yarn test` (if `package.json` exists).
5. `ruff check && ruff format --check` (if Python project).
6. `shellcheck` + `shfmt -d` (if shell-heavy project).

If none match, print:

```
[WARN] cannot infer local lint/test command — run CI's command manually and re-invoke.
```

and stop. Better to ask the user than to push blind.

### Stop message on red

```
[FAIL] local checks failed — fix before push.

<command output>

Re-run this skill once local checks pass.
```

Do not push. Do not remove the label. Step 5 must be reached with
green local checks.

## Step 5 push

```bash
git add -A
git commit -m "fix(ci): <one-line summary> (#$PR_NUMBER)"
git push "$REMOTE" HEAD
```

### Why no `--force-with-lease`

This skill only fast-forwards. If the upstream has new commits
(someone pushed to the same branch while we worked), we want the push
to be **rejected**, not silently overwrite the colleague's work.

### Push-rejected message

```
[FAIL] push rejected by upstream — someone pushed to this branch while you worked.

Recovery:
  git fetch <REMOTE>
  git log --oneline HEAD..<REMOTE>/<HEAD_REF>
  # decide whether to merge those in or rebase onto them, then re-run

Backup of pre-Step-4 HEAD: $BACKUP_SHA
  git reset --hard $BACKUP_SHA     # discard the local CI fix entirely
```

The label is NOT removed. Reviewers should still see CI red until the
push lands.

## Step 7 label removal + ai-metrics

The label-removal block uses REST DELETE (not `gh pr edit
--remove-label`) for the same classic-Projects silent-fail issue
documented in `gh-pr-resolve-conflict` (#326 Bug B).

```bash
gh api -X DELETE "repos/{owner}/{repo}/issues/$PR_NUMBER/labels/CI%20fail" \
    --repo "$TARGET_REPO" \
    >/dev/null 2>&1 \
  && echo "[OK] \`CI fail\` 라벨 제거됨 — 동료 재-Approve 흐름 해제" \
  || echo "[WARN] \`CI fail\` 라벨 제거 실패 (이미 없거나 권한 없음 — 수동 제거 필요할 수 있음)"
```

`{owner}/{repo}` literal with `--repo "$TARGET_REPO"` lets `gh api`
handle both URL and `owner/repo` forms safely. URL-encode any space
or special char in the label name (e.g. `CI%20fail`).

### ai-metrics PR comment (soft-fail)

```bash
ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))
if [ "${GH_DISABLE_AI_METRICS:-0}" = "1" ]; then
    : # ai-metrics comment skipped via GH_DISABLE_AI_METRICS
else
    gh api "repos/$TARGET_REPO/issues/$PR_NUMBER/comments" -X POST \
      -f body="---
<details>
<summary>🤖 AI Metrics · 📊 ~${TOKENS:-3000} tokens · 👤 ~2 h · 🤖 ~$ELAPSED min</summary>

<!-- ai-metrics:gh-pr-resolve-ci-fail -->
📊 ~${TOKENS:-3000} tokens · 👤 ~2 h · 🤖 ~$ELAPSED min
<!-- /ai-metrics:gh-pr-resolve-ci-fail -->

</details>
CI fail 해결: ~$ELAPSED min · 사람: ~2 h" \
      >/dev/null 2>&1 \
      || echo "[WARN] ai-metrics comment failed — continuing."
fi
```

- `${TOKENS:-3000}` — caller may pre-export an estimate; default 3000.
- `~2 h` — `fix` lookup from `gh-issue-create/references/metrics-baseline.md`.
- soft-fail: comment failure does NOT block the success report.

## Recovery cheat-sheet (final report appendix)

```
If something went wrong:
  git reset --hard $BACKUP_SHA     # discard local CI fix entirely
  git reflog                        # find any lost ref
  gh pr view <N> --json labels     # confirm label state
  gh pr edit <N> --add-label "CI fail"  # manually re-add if needed
```
