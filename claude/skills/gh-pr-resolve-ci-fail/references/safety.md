# gh:pr-resolve-ci-fail — Safety Nets

Detail companion for SKILL.md Steps 1, 4, 5, and 7.

Every `gh` call below assumes `TARGET_HOST` / `TARGET_REPO` are already bound
and exported by Step 1 per `references/github-target.md` (#1403, #1407).

## Preconditions (Step 1)

Run as a parallel batch. Any failure → stop with the matching message.

| Check | How | Fail message |
|---|---|---|
| Inside a git repo | `git rev-parse --show-toplevel` | `[FAIL] not inside a git repo` |
| Not on default branch | Compare `git rev-parse --abbrev-ref HEAD` against `GH_HOST="$TARGET_HOST" gh repo view --repo "$TARGET_REPO" --json defaultBranchRef -q .defaultBranchRef.name` | `[FAIL] refuses on default branch (<DEFAULT>) — check out the PR's head branch first` |
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

Read the failing workflow's YAML (`GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/contents/.github/workflows/<file>"`)
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
GH_HOST="$TARGET_HOST" gh api -X DELETE \
    "repos/$TARGET_REPO/issues/$PR_NUMBER/labels/CI%20fail" \
    >/dev/null 2>&1 \
  && echo "[OK] \`CI fail\` 라벨 제거됨 — 동료 재-Approve 흐름 해제" \
  || echo "[WARN] \`CI fail\` 라벨 제거 실패 (이미 없거나 권한 없음 — 수동 제거 필요할 수 있음)"
```

`gh api` accepts no `--repo` flag (#658), so the repo slug goes into the path
as `$TARGET_REPO` — bound in Step 1 from the remote URL. Never leave a literal
`{owner}/{repo}` here: that makes `gh` fall back to its own `gh repo set-default`
instead of git's remote, which on a dual-host login silently DELETEs a label on
the wrong server (#1403 / #1407). `GH_HOST="$TARGET_HOST"` pins that server.
URL-encode any space or special char in the label name (e.g. `CI%20fail`).

### `review-passed` drop (soft-fail, #1705)

`review-passed` is a claim about **one head commit**, and Step 5 just pushed a
new one — so the verdict is now false. Drop it right after the `CI fail`
removal, through the shared `_gh_pr_drop_label` helper (the single REST-DELETE
implementation every head-advancing skill routes through, never a hand-inlined
REST DELETE; #1563, and #326 Bug B for the add side). The helper
percent-encodes the label, pins `GH_HOST`, and absorbs "label was never there"
as success after verifying the PR's real label list (#1583) — no pre-check
needed.

```bash
. "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_pr_edit_safe.sh"

_gh_pr_drop_label "$PR_NUMBER" review-passed "$TARGET_REPO" "$TARGET_HOST" \
    >/dev/null 2>&1 \
  && echo "[OK] \`review-passed\` 라벨 제거됨 — CI 수정 커밋으로 head 가 바뀌어 이전 판정 무효화" \
  || echo "[WARN] \`review-passed\` 라벨 제거 실패 (권한/네트워크 — 수동 확인 필요할 수 있음)"
```

**Unconditional** — no patch-id comparison, unlike `gh:pr-resolve-outdated` /
`gh:pr-resolve-conflict`. Those two can produce a byte-identical diff under a
new SHA (a clean rebase), which is why they reconcile instead of dropping
(#1698 / #1700). A CI fix changes file content by definition, so no keep /
re-stamp path can ever apply here — there is nothing to reconcile.

**`review-blocked` is never touched** (#1563). This skill holds no evidence
that a reviewer's blocker was addressed — fixing red CI and answering review
comments are unrelated — so leaving that label on is the safe direction, not a
bug. Issuing either verdict label is likewise not this skill's job:
`devx:pr-review-all` (and `gh:pr-reply` under its delegation, #1636) is the
only writer.

Soft-fail: a failed drop costs one `[WARN]` line and nothing else — it never
changes the CI-fix success/failure or the Step 7 report. Both mutations sit
behind the same gate as the `CI fail` removal above: Step 5's push failed →
Step 7 does not run at all, and the label stays valid because head never moved.

### ai-metrics PR comment (soft-fail)

```bash
ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))
if [ "${GH_DISABLE_AI_METRICS:-0}" = "1" ]; then
    : # ai-metrics comment skipped via GH_DISABLE_AI_METRICS
else
    GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/issues/$PR_NUMBER/comments" -X POST \
      -f body="---
<details>
<summary>AI Metrics · tokens=~${TOKENS:-3000} · human_h=~2 · ai_min=~$ELAPSED</summary>

<!-- ai-metrics:gh-pr-resolve-ci-fail -->
AI Metrics tokens=~${TOKENS:-3000} human_h=~2 ai_min=~$ELAPSED
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
- Glyph note: the rendered footer on GitHub uses the standard ai-metrics
  glyphs (the #317 F-2 exception — see `gh-add-ai-metrics`, the footer SSOT).
  They are omitted here to keep references/ emoji-free; substitute them at
  render time to match the standard card.

## Recovery cheat-sheet (final report appendix)

```
If something went wrong:
  git reset --hard $BACKUP_SHA     # discard local CI fix entirely
  git reflog                        # find any lost ref
  GH_HOST="$TARGET_HOST" gh pr view <N> --repo "$TARGET_REPO" --json labels
  GH_HOST="$TARGET_HOST" gh pr edit <N> --repo "$TARGET_REPO" --add-label "CI fail"
```

Render `$TARGET_HOST` / `$TARGET_REPO` as their resolved values in the printed
report — the user's shell will not have them exported after the skill exits.
