# gh:issue-implement — Implementation Flow

## Preconditions

Run these in parallel at start; all must pass:

- `git rev-parse --show-toplevel` — must succeed (in a git repo).
- `git rev-parse --abbrev-ref HEAD` — must NOT equal the default branch.
  Get default via `gh repo view "$TARGET_REPO" --json defaultBranchRef -q .defaultBranchRef.name`
  (pass the resolved repo explicitly — avoids implicit repo detection
  when the cwd is under a fork or unusual remote setup).
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

Before starting edits, capture a baseline: run `$TEST_CMD` once with
no edits and record the set of failing tests as `pre_existing_failures`.
Any test failing in that baseline is never "caused" by this skill's
edits.

Then loop:

```
attempt = 0
while attempt < 3:
    result = run($TEST_CMD)
    failing = parse_failing_tests(result)
    caused = failing - pre_existing_failures

    if caused is empty:
        break   # all remaining failures are pre-existing, done

    for test in caused:
        re_read(failing_test_file, edited_source_files)
        make_targeted_fix(test)    # smallest edit
    attempt += 1

# After loop:
if caused still non-empty:
    emit "stopped after 3 test-fix attempts" report
else:
    emit "complete" report with <n pre-existing> count
```

**Invariants:**
- PRE-EXISTING failures are NEVER fixed by this skill — reported as
  pre-existing in the final output.
- `attempt` counts `$TEST_CMD` runs that had at least one CAUSED
  failure. Runs with only PRE-EXISTING failures do not consume attempts.
- Baseline run happens before any edit — this is what makes the
  CAUSED vs PRE-EXISTING split well-defined.

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
