---
name: gh:pr-resolve-conflict
description: >-
  Resolve a GitHub PR's "This branch has conflicts that must be resolved"
  warning using rebase (never a merge commit), then push with
  `--force-with-lease`. Use when the user runs /gh:pr-resolve-conflict,
  /gh-pr-resolve-conflict, or asks "PR conflict 해결", "base 변경됐는데 rebase
  해줘", "리베이스로 컨플릭트 풀어". Refuses to run on the default branch,
  refuses plain `--force`, and never auto-guesses conflict content — the
  user drives each resolution. Accepts `[pr-number] [remote]`; defaults to
  the PR attached to the current branch. Accepts `-h`/`--help`/`help`.
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

# gh:pr-resolve-conflict — Rebase-based PR Conflict Resolution

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Step 1: Parse Args + Preflight

Record `START_TS=$(date +%s)` immediately for elapsed-time tracking in Step 5.

Positional args: `[pr-number] [remote]`. Both optional.

- `pr-number` — if omitted, auto-detect via
  `gh pr view --json number,headRefName,baseRefName,url,mergeable`
  on the current branch. No PR for the branch → stop.
- `remote` — default `origin`. Resolve `TARGET_REPO` via
  `git remote get-url <remote>`; missing → `git remote -v` and stop.

**Mergeable preflight** — immediately after resolving `PR_NUMBER`:

```bash
MERGEABLE=$(gh pr view "$PR_NUMBER" --repo "$TARGET_REPO" \
  --json mergeable --jq '.mergeable')
```

- `MERGEABLE == MERGEABLE` → print `[OK] PR은 이미 충돌 없음 — skip.` and stop (success).
- `MERGEABLE == UNKNOWN` → GitHub is still computing; continue the flow normally (do not skip).
- Any other value (`CONFLICTING` etc.) → continue.

**Hard preconditions** (parallel batch; any fail → stop):
- inside a git repo
- current branch ≠ repo default (refuse to rebase `main`)
- working tree clean, OR auto-stash per `references/safety.md`
  (announce the stash before running it)
- no in-progress rebase/merge/cherry-pick

Capture `BACKUP_SHA=$(git rev-parse HEAD)` and print it so the user can
`git reset --hard <sha>` if anything goes wrong.

## Step 2: Fetch + Rebase

```bash
git fetch "$REMOTE" "$BASE"
git rebase "$REMOTE/$BASE"
```

Full rebase mechanics, stash handling, and abort instructions live in
`references/rebase-flow.md`.

## Step 3: Conflict Resolution Loop

If `git rebase` exits non-zero with conflicts:

1. `git status --short` to list `UU` / `AA` / `DU` paths.
2. Print the rebase context — `git log --oneline "$REMOTE/$BASE"..HEAD`
   plus the applying commit (`git log -1 --format='%h %s' REBASE_HEAD`).
3. Open each file, resolve with the user's intent. **Never auto-guess**
   when the commit message doesn't make the choice obvious — ask.
4. `git add <file>` once the user confirms each resolution.
5. `git rebase --continue`. If more commits conflict, loop to step 1.

Full rubric (abort guidance, squash suggestions for repeated conflicts)
in `references/conflict-handling.md`.

## Step 4: Push with `--force-with-lease`

Only after `git rebase` exits 0 and the working tree is clean:

```bash
git push --force-with-lease "$REMOTE" HEAD
```

Never plain `--force`. If `--force-with-lease` is rejected (someone
pushed while you rebased), stop and surface the upstream per
`references/rebase-flow.md` — do NOT silently re-pull-and-rebase.

## Step 5: Verify Mergeable + Report

```bash
gh pr view <N> --repo "$TARGET_REPO" --json mergeable,mergeStateStatus,url,labels
```

If `mergeable == MERGEABLE` and `mergeStateStatus ∈ {CLEAN, UNSTABLE}`,
the warning is cleared. Print the final report from
`references/rebase-flow.md` → "Final report format". Still `CONFLICTING`
/ `BEHIND` → print the PR URL, name which side diverged, do not loop.

**conflict 라벨 제거** (soft-fail — `mergeable == MERGEABLE` 인 경우에만):

Check if `labels[].name` contains `"conflict"`. If so, remove via REST DELETE
(not `gh pr edit --remove-label`) — the latter can silent-fail on repos with
classic Projects attached due to GraphQL deprecation (#326 Bug B, same pattern
as `_gh_pr_edit_safe_label` fallback). 404 = label already absent → the
`||` branch surfaces a soft-fail warning, idempotent for the caller.

```bash
gh api -X DELETE "repos/{owner}/{repo}/issues/$PR_NUMBER/labels/conflict" \
    --repo "$TARGET_REPO" \
    >/dev/null 2>&1 \
  && echo "[OK] \`conflict\` 라벨 제거됨" \
  || echo "[WARN] \`conflict\` 라벨 제거 실패 — GitHub Actions 가 cover."
```

`{owner}/{repo}` placeholder + `--repo "$TARGET_REPO"` 조합을 쓰는 이유:
Step 1 의 `TARGET_REPO` 는 `git remote get-url` 결과(URL 형태)일 수
있어 `repos/$TARGET_REPO/...` 직접 보간 시 경로가 깨질 수 있다. `gh api`
의 `--repo` 플래그는 URL 과 `owner/repo` 양쪽 입력을 모두 안전하게
파싱한다.

If the label is absent, the `||` branch absorbs the 404 as a soft-fail
warning (idempotent).

After the report, post a PR comment with ai-metrics (soft-fail — warn on
error, never block). `CONFLICT_FILES` is the count of files that had
`UU`/`AA`/`DU` conflicts in Step 3. When `GH_DISABLE_AI_METRICS=1`,
skip the comment entirely (issue #399):

```bash
ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))
HUMAN_H=$(echo "scale=2; $CONFLICT_FILES * 0.5" | bc)
if [ "${GH_DISABLE_AI_METRICS:-0}" = "1" ]; then
    : # ai-metrics comment skipped via GH_DISABLE_AI_METRICS
else
    gh api "repos/$TARGET_REPO/issues/$PR_NUMBER/comments" \
      -X POST \
      -f body="<!-- ai-metrics:gh-pr-resolve-conflict tokens=${TOKENS:-3000} human_h=$HUMAN_H ai_min=$ELAPSED -->
🤖 컨플릭트 해결: ~$ELAPSED min · 👤 ~$HUMAN_H h ($CONFLICT_FILES files × 0.5 h)"
fi
```

On failure: `[WARN] ai-metrics comment failed — continuing.`

## Constraints

- Never introduce a merge commit. Rebase-only.
- Never use plain `git push --force`. `--force-with-lease` or stop.
- Never rebase onto the default branch from the default branch.
- Never auto-resolve ambiguous conflicts. Ask the user.
- Never retry a rejected `--force-with-lease` by fetching and
  re-rebasing on the user's behalf. Surface divergence and stop.
- Never skip Step 5. The whole point is clearing the PR warning.
