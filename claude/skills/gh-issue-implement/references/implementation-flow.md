# gh:issue-implement — Implementation Flow

## Preconditions

Run these in parallel at start; all must pass:

- `git rev-parse --show-toplevel` — must succeed (in a git repo).
- `git rev-parse --abbrev-ref HEAD` — must NOT equal the default branch.
  Get default via `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`.
- `git status --porcelain` — must be empty (clean working tree).

**Failure responses:**
- Not in a repo → "Not in a git repo. cd into one first." + stop.
- On base branch → "Current branch is the base. Create a feature branch (e.g., `gwt <name>`) first." + stop.
- Dirty tree → print `git status` + "Clean or stash first." + stop.

## Test runner detection

Check in this order and use the first match:

1. `AGENTS.md` — grep for `tox`, `pytest`, `bats`, `npm test`; if a code block starts with one, use it.
2. `tox.ini` exists → `tox`.
3. `pyproject.toml` contains `[tool.pytest.ini_options]` → `pytest`.
4. `package.json` contains `"test"` script → `npm test`.
5. `tests/*.bats` exists → `bats tests/`.
6. Fallback → report "No test runner detected, skipping tests." (not an error).

Store the chosen command as `$TEST_CMD`.

## Direct-mode flow

1. Fetch issue (same `gh issue view --json ...` as gh:issue-read).
2. Extract change intent from body + comments.
3. Scan repo structure: read AGENTS.md, CLAUDE.md, top-level README if present.
4. Identify files to touch. For each file:
   - Use `Read` to load current content (if exists).
   - Use `Edit`/`Write` to modify/create.
5. Run `$TEST_CMD`. Capture output.
6. If fail → **Test-failure loop** (below).
7. Report.

## Test-failure loop (max 3 iterations)

```
attempt = 1
while attempt <= 3 and tests fail:
    a. Parse failure output. Identify failing test(s) + error message.
    b. Determine if failure is caused by the skill's edits:
       - Git diff since skill start shows touched files overlapping the
         failing test's module → CAUSED by skill edits.
       - Otherwise → PRE-EXISTING.
    c. If CAUSED:
       - Re-read the failing test and the edited file.
       - Make a targeted fix (smallest possible edit).
       - Re-run $TEST_CMD.
       - attempt += 1
    d. If PRE-EXISTING:
       - Move it to the pre-existing bucket, not the fix loop.
       - Stop looping on this test.

If attempt > 3 and tests still fail:
    Stop. Report with:
    - Files changed so far (diff summary)
    - Failing tests + their last error output
    - Whether each is skill-caused or pre-existing
    - "Manual intervention needed."
```

## Final report format

Success:
```
gh:issue-implement #<N> complete
  Mode:     <direct|plan|brainstorming>
  Changes:
    <path1>  (new|modified)
    <path2>  (new|modified)
  Tests:    <n passed>, <n failed>, <n pre-existing failures>
  Next:     /gh-commit && /gh-pr   (or /gh-issue-flow to do both)
```

Failure (test loop exhausted):
```
gh:issue-implement #<N> stopped after 3 test-fix attempts
  Mode:     <mode>
  Changes:  <list>
  Failing (caused by edits):
    <test1> — <error summary>
    <test2> — <error summary>
  Pre-existing failures (not touched):
    <test3>
  Last diff snippet:
    <file:line>
  Resolution: review the edits above, fix manually, re-run tests.
```
