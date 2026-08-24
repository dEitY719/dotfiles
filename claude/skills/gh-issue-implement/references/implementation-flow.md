# gh:issue-implement — Implementation Flow

## Preconditions

Run these in parallel at start; all must pass:

- `git rev-parse --show-toplevel` — must succeed (in a git repo).
- `git rev-parse --abbrev-ref HEAD` — must NOT equal the default branch.
  Get default via
  `GH_HOST="$TARGET_HOST" gh repo view "$TARGET_REPO" --json defaultBranchRef -q .defaultBranchRef.name`
  (pass the resolved host + repo explicitly — avoids implicit repo/host
  detection, which on a dual-host login resolves to gh CLI's own default
  repo rather than git's `origin`, #1403).
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

### Common steps (both paths)

1. Fetch issue (same `GH_HOST="$TARGET_HOST" gh issue view --repo "$TARGET_REPO"
   --json ...` as gh:issue-read).
2. Extract change intent from body + comments.
3. Scan repo structure: read AGENTS.md, CLAUDE.md, top-level README if present.
4. Detect `$TEST_CMD` (above), then capture the **baseline**: run
   `$TEST_CMD` once with no edits and record the failing set as
   `pre_existing_failures`. Any test failing in that baseline is never
   "caused" by this skill's edits.

Then branch on the Step 2 superpowers detection result **and** whether a
test runner was detected:

- **runner detected AND superpowers detected** → "TDD path" below (default).
- **no runner detected** → "Fallback path" below, regardless of superpowers
  detection. The TDD path requires running tests to verify RED and GREEN —
  without a runner there is nothing to verify, so it cannot function. Skip
  the baseline and every test step in whichever path runs; report "No test
  runner detected, skipping tests." per "Test runner detection" above.
- **runner detected, superpowers not detected** → "Fallback path" below.

### TDD path (superpowers detected)

`Skill(superpowers:test-driven-development)` drives the implementation.
Invocation detail: `references/superpowers-detection.md` → "Invocation
of superpowers skills" → "In `direct` mode".

1. Split the issue's intent into behaviors, smallest first.
2. Per behavior, run one red-green-refactor cycle: write the failing
   test, watch it fail for the right reason, write minimal code, verify
   green, refactor.
3. **Pre-existing exception** — the TDD skill's "Other tests fail? Fix
   now." applies only to failures NOT in `pre_existing_failures`.
   A test in that list stays untouched and is reported as pre-existing.
4. Repeat until the issue's intent is satisfied, then run `$TEST_CMD`
   once more for the final report numbers.
5. Report.

There is **no iteration cap** on this path — the red-green-refactor
cycle already bounds each step. Stop and hand back to the human when
you judge yourself stuck: the same test failing the same way after
repeated fixes, a fix that keeps breaking a previously-green test, or
a failure you cannot explain. Report what was tried instead of
inventing a new attempt budget.

### Fallback path (superpowers not detected)

Unchanged legacy flow — always available, never degraded.

1. Identify files to touch. For each file:
   - Use `Read` to load current content (if exists).
   - Use `Edit`/`Write` to modify/create.
2. Run `$TEST_CMD`. Capture output.
3. If fail → **Test-failure loop** (below).
4. Report.

## Test-failure loop (max 3 iterations, fallback path only)

Uses `pre_existing_failures` from common step 4 above.

Loop:

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
  pre-existing in the final output. Holds on the TDD path too.
- `attempt` counts `$TEST_CMD` runs that had at least one CAUSED
  failure. Runs with only PRE-EXISTING failures do not consume attempts.
- Baseline run happens before any edit — this is what makes the
  CAUSED vs PRE-EXISTING split well-defined, on both paths.

## Final report format

`Path:` is printed for `direct` mode only — it names which branch of
the direct-mode flow ran (`tdd` or `fallback`).

Success:
```
gh:issue-implement #<N> complete
  Mode:     <direct|plan|brainstorming>
  Path:     <tdd|fallback>
  Changes:
    <path1>  (new|modified)
    <path2>  (new|modified)
  Tests:    <n passed>, <n failed>, <n pre-existing failures>
  Next:     /gh-commit && /gh-pr   (or /gh-issue-flow to do both)
```

Failure, fallback path (test loop exhausted):
```
gh:issue-implement #<N> stopped after 3 test-fix attempts
  Mode:     <mode>
  Path:     fallback
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

Failure, TDD path (judged stuck):
```
gh:issue-implement #<N> stopped — TDD cycle stuck
  Mode:     direct
  Path:     tdd
  Changes:  <list>
  Stuck at: <behavior being implemented>
  Symptom:  <same failure repeating | fix breaks a green test | unexplained failure>
  Tried:
    <attempt1 — outcome>
    <attempt2 — outcome>
  Pre-existing failures (not touched):
    <test3>
  Resolution: review the cycle above, decide the design, re-run.
```

## ai-metrics line

After the report, append the ai-metrics line (context only — no GitHub
artifact exists yet at this stage):

```
[ai-metrics:gh-issue-implement] ~{ELAPSED} min — will be included in gh-commit metrics
```

Compute `ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))` just before printing.
