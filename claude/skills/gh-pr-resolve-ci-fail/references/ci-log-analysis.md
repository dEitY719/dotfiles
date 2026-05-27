# gh:pr-resolve-ci-fail — CI Log Analysis

Detail companion for SKILL.md Steps 2, 3, and 6.

## Step 2 — Fetch failing checks

### Pre-check (is `main` red?)

PR 회귀 fix 에 들어가기 전에 main 자체가 적색인지 먼저 확인한다.
#755 의 28건 bats fail 처럼 PR 입장에선 inherited red — PR 차원의
fix 가 원천적으로 불가능한 케이스를 30분 분석 후에야 깨닫는 회귀를 막는다.

#### 1초 점검 명령

```bash
# 같은 워크플로의 main 최신 3 runs
gh run list --repo "$TARGET_REPO" \
    --branch main \
    --workflow "$WORKFLOW_NAME" \
    --limit 3 \
    --json databaseId,conclusion,headSha,updatedAt
```

#### 판정 기준 — "same step as main"

같은 step 에서 fail 했다고 보려면 두 조건을 모두 만족해야 한다:

1. main 최신 3 runs 중 **2 개 이상** `conclusion == "failure"` (또는
   `"timed_out"`).
2. main 의 실패 run 과 PR run 이 **동일 job + 동일 step name** 에서
   터진다 — `gh run view <main-run-id> --log-failed` 와
   `gh run view <pr-run-id> --log-failed` 의 첫 `##[error]` /
   `Error:` 라인 (또는 첫 non-zero exit 의 step header) 이 일치하는지
   2초 비교.

두 조건 모두 참 → inherited red. SKILL.md Step 2 의 `[STOP]` 메시지로
종료. 라벨은 떼지 않는다 (CI 가 실제로 PR 회귀 없음을 증명하지 못한 상태).

#### False-positive — main 의 transient red

다음 케이스는 inherited red 가 **아니므로** pre-check 통과로 처리하고
통상 절차 진행:

- main 최신 3 runs 가 `failure / success / success` 처럼 1회만 fail
  이고 직후 run 이 다시 green — flaky / transient. 회복됨.
- main 의 실패 run 과 PR run 의 fail step name 이 다름 — 같은 적색이
  아니라 PR 만의 새 회귀.
- main 의 fail 이 24h 이상 지난 단발 — 최신 2 run 이 green 이면 무시.

#### Skip 조건

`GH_PR_RESOLVE_CI_SKIP_MAIN_CHECK=1` 가 set 이면 pre-check 를 건너뛴다 —
사용자가 의도적으로 main red 상태에서 PR fix 를 강제 진행하려는 경우
(e.g., main 회복 PR 자체의 CI 디버깅).

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

`HEAD_REF` is already bound in SKILL.md Step 1 (from the initial
`gh pr view --json number,state,headRefName` call) — reuse it,
do not re-fetch.

Fetch the recent run list **once** for the branch, then jq-filter
per failing workflow inside the loop:

```bash
# Pre-fetch once: most recent run for each workflow on this branch.
RUNS_JSON=$(gh run list --branch "$HEAD_REF" --limit 50 \
    --json databaseId,workflowName,headSha)

# In the per-failing-workflow loop:
for WF_NAME in $FAILING_WORKFLOWS; do
    RUN_ID=$(printf '%s' "$RUNS_JSON" \
        | jq -r --arg n "$WF_NAME" \
            '[.[] | select(.workflowName==$n)] | .[0].databaseId')
    gh run view "$RUN_ID" --log-failed
done
```

One `gh run list` call instead of N. Cuts network/process overhead
when several workflows fail at once. `gh run view` does not accept
`--repo`; rely on cwd-based repo detection.

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
