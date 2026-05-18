# gh:pr-resolve-ci-fail — CI Log Analysis

Detail companion for SKILL.md Steps 2, 3, and 6.

## Step 2 — Fetch failing checks

```bash
gh pr checks "$PR_NUMBER" --repo "$TARGET_REPO" --required \
    --json name,state,workflow,link \
    --jq '[.[] | select(.state=="FAILURE")]'
```

### Filter rules

- `--required` — only required checks count. Non-required can stay red
  without blocking re-Approve, so this skill ignores them by default.
- `state == FAILURE` — explicit. `CANCELLED` and `TIMED_OUT` are
  treated separately (see in-progress carveout).
- Empty result → `[OK] no failing checks — nothing to resolve.` Exit
  success.

### In-progress carveout

If any check is `IN_PROGRESS` or `PENDING` when this skill runs, the
"all green" signal is unreliable. Print a 1-line warning and continue:

```
[WARN] <N> required checks still in progress — treating as green for now.
       If they go red after push, re-run /gh-pr-resolve-ci-fail.
```

This is intentional — we'd rather get a fix queued than block on
flaky CI scheduling.

### Non-required policy

If the user truly wants non-required checks treated as failures, they
pass them explicitly. v1 of this skill does not expose that switch —
keep YAGNI until a real ask appears.

## Step 3 — Log triage

For each failing workflow from Step 2:

```bash
HEAD_REF=$(gh pr view "$PR_NUMBER" --repo "$TARGET_REPO" --json headRefName --jq '.headRefName')
RUN_ID=$(gh run list --repo "$TARGET_REPO" --branch "$HEAD_REF" \
    --workflow "<workflow-name>" --limit 1 \
    --json databaseId --jq '.[0].databaseId')
gh run view "$RUN_ID" --repo "$TARGET_REPO" --log-failed
```

### Common failure patterns

Walk the log tail (last ~80 lines is usually enough; full log only if
the failure is upstream of a cascade):

| Pattern | Signal in log | Fix scope |
|---|---|---|
| Lint failure | `error  ...  prefer-const`, `Use \`...\``, ESLint/Ruff/shellcheck output | Edit reported files at reported lines |
| Type check | `error TS2345`, `mypy: error:`, `Argument of type ...` | Edit reported files, possibly add type annotations |
| Test failure | `FAIL `, `Test failed:`, `AssertionError`, `expect(...).toBe(...)` | Edit either the test or the implementation — read the assertion first |
| Build failure | `Cannot find module`, `Module not found`, `npm ERR!`, `bash: ...: command not found` | Often `package.json` / lockfile / env. Investigate before assuming code |
| Format check | `Code would be reformatted`, `prettier --check failed`, `shfmt -d` | Run formatter locally and re-commit |

### Heuristic for "no identifiable fix"

If the log shows:

- a Docker pull failure (`unauthorized: authentication required`),
- a network timeout (`dial tcp ... i/o timeout`),
- an OOM kill (`exit code 137`),
- a flaky test that passes locally,

→ surface the log to the user and **stop**. These are not code defects;
re-running the workflow is the right move, and this skill refuses to
push an unrelated commit just to trigger a re-run.

## Step 6 — `--wait` polling loop

```bash
WAIT_SECONDS="$1"   # from --wait flag
ELAPSED=0
INTERVAL=30
while [ "$ELAPSED" -lt "$WAIT_SECONDS" ]; do
    PENDING=$(gh pr checks "$PR_NUMBER" --repo "$TARGET_REPO" --required \
        --json state --jq '[.[] | select(.state=="IN_PROGRESS" or .state=="PENDING" or .state=="FAILURE")] | length')
    [ "$PENDING" -eq 0 ] && break
    sleep "$INTERVAL"
    ELAPSED=$(( ELAPSED + INTERVAL ))
done

if [ "$PENDING" -gt 0 ]; then
    echo "[WARN] CI still pending after ${WAIT_SECONDS}s — proceeding to label removal."
fi
```

### Why the warn-and-proceed default

The user opted in to `--wait`, so they accept the race condition that
the label might come off while CI is still going. The alternative
(refusing to remove the label on timeout) would defeat the purpose of
the skill, which is to unblock reviewer re-approval.

If they want strict "only on green", they can omit `--wait` and run
the skill twice: once to push, once after CI is confirmed green to
remove the label (Step 5 push will no-op the second time since the
fix is already pushed).
