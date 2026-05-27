---
name: gh:pr
description: >-
  Create a GitHub pull request from the current branch, bundling all commits
  since it diverged from the base branch. Use when the user runs /gh:pr,
  /gh-pr, or asks "PR 생성", "풀리퀘 만들어", "지금까지 커밋들로 PR 올려". Pushes
  the branch if needed, drafts a structured PR body covering every commit in
  the range (not just HEAD), auto-links a related issue when known, and
  returns only the PR URL. Accepts `-h`/`--help`/`help` to print usage.
allowed-tools: Bash, Read, Grep
---

# gh:pr — Create Pull Request

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
its content verbatim, then stop. No API calls.

## Role

Bundle the current branch's commits into a GitHub PR with a well-structured
body. Push the branch if needed. Return the PR URL.

## Options

| Argument | Description | Default |
|----------|-------------|---------|
| `[N]` (positional) | Legacy `/gh:pr 123` form — overrides issue auto-detection. | — |
| `--no-stack` | Force a non-stacked PR even when stacked-PR signals fire. | off |
| `--base <branch>` | Explicit base branch; bypasses stacked-PR detection. | repo default |
| `GH_DISABLE_AI_METRICS=1` (env) | Skip ai-metrics footer append in Step 4. | off |
| `GH_PR_LINT_BYPASS=1` (env) | Skip Step 4.5 lint guard. | off |
| `DOTFILES_ROOT` (env) | Root used to source `gh_pr_lint.sh`. | `$HOME/dotfiles` |
| `-h`/`--help`/`help` | Print `references/help.md` verbatim and stop. | — |

`--no-stack` and `--base` are mutually exclusive — see Step 1a exit codes.
Auto-detected parent PR must be `OPEN` — refuses (rc=5) otherwise.

## Step 1: Parse Args, Resolve Base Branch, Gather State

Record `START_TS=$(date +%s)` immediately for elapsed-time tracking in Step 4.

### Step 1a: Parse args + resolve base via stacked-PR detection

Read `references/stacked-pr.md` and paste the SSOT functions
(`parse_stacked_args`, `is_stacked_pr_repo`, `find_parent_pr_candidates`,
`assert_parent_pr_open`) and the dispatch block ("How Step 1 of
SKILL.md ties it together") verbatim. They bind `BASE_BRANCH`,
`PARENT_PR`, and `ISSUE_NUMBER`, and they exit on bad input — `rc=2`
for mutually-exclusive flags, `rc=3` for a bad `--base` value, `rc=5`
when the auto-detected parent PR is no longer `OPEN` (stacking refuses
on closed/merged parents — recovery hint: reopen the parent or rerun
with `--no-stack`). Abort without pushing on any of them.

### Step 1b: Gather range + push state (parallel)

Run in a single message, using `$BASE_BRANCH` from Step 1a:
`git rev-parse --abbrev-ref HEAD`, `git status`, `git fetch origin`,
`git log --oneline "$BASE_BRANCH"..HEAD`, `git diff "$BASE_BRANCH"...HEAD`,
and `git rev-parse --symbolic-full-name @{u} 2>/dev/null`.

Stop conditions: current branch equals `BASE_BRANCH` → ask for a
feature branch; `git log "$BASE_BRANCH"..HEAD` empty → nothing to PR.

## Step 2: Analyze ALL Commits in the Range

The PR body must reflect **every commit** in the range, not just the latest.
Read `git log <base>..HEAD` output and group changes by theme. A 5-commit PR
mentions all 5 concerns.

## Step 3: Resolve the Issue Number

Same precedence as `gh:commit`: (1) explicit `/gh:pr <N>` arg, (2)
recent conversation `#N` / `Issue #N created`, (3) commit messages in
the range (`Refs/Closes/Fixes #N`), (4) none → omit the link.

## Step 4: Draft Title and Body

Read `references/pr-body-template.md` for title rules, body structure,
and the body markdown. Match the language of existing commits (Korean
if commits are Korean).

Then read `references/ai-metrics-footer.md` and follow it verbatim to
compute `TOKENS`, `HUMAN_H`, `ELAPSED` and append the footer to `$BODY`
(soft-fail — warn on error, never block). Honours
`GH_DISABLE_AI_METRICS=1` (issue #399).

## Step 4.5: Lint Guard (pre-push)

Read `references/lint-guard.md` and paste its "Helper" source-and-run
snippet verbatim. Runs against `$BASE_BRANCH` **before** the push in
Step 5. Hard-fails on lint errors; auto-skips when no tools are
detected, when the change set is empty, or when `GH_PR_LINT_BYPASS=1`.

## Step 5: Push and Create

Read `references/push-and-create.md` for the upstream-state push policy and
the `gh pr create` command (uses `mktemp` body file, `--assignee @me`,
`--base "$BASE_BRANCH"` from Step 1a).

## Step 6: Apply Labels

Derive labels from conventional-commit types in `git log <base>..HEAD` and
PR scope (e.g. `skill` for `claude/skills/` changes). Apply only labels that
exist in the repo (`gh label list`) — never create new ones. See
`references/pr-body-template.md` for the full mapping and safe-apply loop.

## Step 7: Sync Project Board Status

Push the new PR card to `In review` and correct any linked Issue cards
the GitHub builtin mis-moved to `In review` (Issues belong in
`In progress` — see `references/project-board-sync.md` for the
rationale, hook auto-skip narrative, and `GH_REPO` requirement).

First, detect a PostToolUse hook that already handles this sync — when
present, skip the inline call to avoid triple-syncing (issue #390):

```bash
hook_skip=0
for hook_path in \
    "${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}/.claude/hooks/post-pr-create-status.sh" \
    "$HOME/.claude/hooks/post-gh-pr-create.sh" \
    "$HOME/dotfiles/claude/hooks/post-gh-pr-create.sh"
do
    if [ -x "$hook_path" ]; then
        hook_skip=1
        printf '[gh-pr] board sync delegated to PostToolUse hook (%s) — skipping inline.\n' "$hook_path" >&2
        break
    fi
done

if [ "$hook_skip" -eq 0 ]; then
    # helper-fallback NF-1 (#644): silent-skip when helper missing.
    # Defense-in-depth (#724): also detect "[ -r ] passes but function never
    # defined" (interactive-guard regression, partial sourcing, future rename).
    # `|| true` would otherwise absorb `command not found` (rc 127) and the
    # entire reconciliation would silently no-op — the failure mode from #724.
    _HELPER="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_project_status.sh"
    if [ -r "$_HELPER" ]; then
        . "$_HELPER"
        if ! command -v _gh_project_status_sync >/dev/null 2>&1; then
            printf '[gh-pr] %s sourced but _gh_project_status_sync undefined — board sync skipped (#724).\n' \
                "$_HELPER" >&2
        else
            _gh_project_status_sync pr "$PR_NUMBER" "In review" || true
            # Auto-resolve GH_REPO when unset/empty so the linked-issues
            # sync isn't silently no-op'd by an empty repo arg (PR #780
            # review). Matches the existing convention in
            # shell-common/functions/gh_pr_edit_safe.sh and
            # gh_audit_builtin_workflows.sh.
            if [ -z "${GH_REPO:-}" ]; then
                GH_REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
            fi
            for _issue in $(_gh_pr_closing_issue_numbers "$PR_NUMBER" "$GH_REPO" 2>/dev/null || true); do
                _gh_project_status_sync issue "$_issue" "In progress" \
                    --only-from "Backlog,Ready,In review" || true
            done
        fi
    fi
fi
```

`GH_REPO` should be `owner/repo` (e.g. `dEitY719/dotfiles`). The block
auto-resolves it via `gh repo view --json nameWithOwner --jq
.nameWithOwner` when unset/empty so the linked-issues loop never
silently no-ops on a missing env var. Opt-out per invocation:
`GH_PROJECT_STATUS_SYNC=0`. Repos without a projectV2 board auto-skip
silently (helper returns 0).

Track the outcome for Step 8's report row:
- `hook_skip=1` → `[SKIP]: hook auto-skip`
- helper missing or function undefined → `[SKIP]: helper unavailable`
- helper ran, no projectV2 board → `[SKIP]: no projectV2`
- helper ran with at least one card moved → `[OK]: PR card -> "In review"`

## Step 8: Report

성공 시:

```
[OK] PR: https://github.com/owner/repo/pull/<N>
[OK] Board sync: PR card -> "In review" (or [SKIP]: hook auto-skip / no projectV2 / helper unavailable)
Next: /gh:pr-reply (after CI green) — replies to review comments
```

The `Board sync:` row is a defense-in-depth visual checklist (issue
#747) — its absence in conversation transcripts is a regression signal
that Step 7 was silently skipped.

Step 1b empty-range / on-base-branch stops, Step 1a `rc=2`/`rc=3`, or
Step 4.5 lint failure:

```
[FAIL] <one-line reason>
Next: <recovery — e.g. switch branch, fix lint, drop conflicting flag>
```

No additional summary — the user opens GitHub directly from the URL.

## Constraints

Read `references/constraints.md` for hard rules: no force-push without
approval, default base only, no AI footer unless the repo already uses one,
never skip commits in the Summary.
