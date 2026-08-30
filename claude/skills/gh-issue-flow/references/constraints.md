# gh:issue-flow — Constraints

- Never invoke implementation modes other than `direct`.
- Never retry a failed step. Human decides retry or fix.
- Never skip a step. All 6 or stop.
- **Quality-gate soft-fail exception.** Step 2.4 (`devx:pr-review-all`)
  is additive polish, not gating: agy/codex absent → that lane skips
  (not a failure); `/simplify` produced no change → no commit; any error
  in review/simplify/commit → `[WARN]` and continue. The gate never stops
  the flow.
- **Simplify commit before rebase.** Step 2.4 commits + pushes any
  simplify changes **synchronously inside `devx:pr-review-all`** before it
  returns, so the tree is clean before the rebase steps 2.5 / 2.5.1 — a
  dirty working tree breaks `git rebase`.
- **Merge-train wake soft-fail exception (#1482).** Step 2.4.1
  (`aicron run merge-train`) fires right after Step 2.4, whether or not 2.4
  succeeded — it is not a `Skill()` call and never stops the flow. It only
  fires when the literal `<remote>` resolves to the same repo URL as
  `$HOME/dotfiles`'s own `origin`; any other remote is a silent skip, not a
  failure (#1498 — see "Guarded to `$HOME/dotfiles`'s own `origin` only" in
  `references/merge-train-wake.md`). This guard is never a live `$REMOTE`
  env-var read — PR #1539 review found that fragile (a Bash tool call is
  not guaranteed to inherit an earlier call's exports). When it does fire,
  it is launched **backgrounded** (harness `run_in_background`, not awaited) so
  the dispatcher's own up-to-~4-min `herdr agent prompt --wait` never
  delays Step 2.5/2.5.1, which don't depend on its outcome. Only a missing
  `aicron.sh` (checked synchronously, before launch) is a single `[WARN]`;
  the dispatcher's own exit code is never observed by this step. Detail:
  `references/merge-train-wake.md`.
- Step 2.5.1 (gh:pr-resolve-outdated) does a clean rebase-sync when the
  base moved forward with no conflicts; it is a no-op when the PR is
  already up to date.
- **CI-fail resolution is out of scope for this chain.** Step 2.5 and
  2.5.1 call only `gh:pr-resolve-conflict` / `gh:pr-resolve-outdated` —
  never `gh:pr-resolve-ci-fail`. CI checks haven't finished by the time
  this flow reaches those steps, so a synchronous call would be
  meaningless; Step 2.4.1's merge-train wake hands that off to
  `gh:pr-merge-train`'s routing table once checks report. Detail:
  `gh-pr-merge-train/references/routing-table.md`.
- **Never fall back to `_dotfiles_setup_mode` alone for the host (#1403).**
  Step 1 exports `GH_HOST`/`TARGET_REPO`/`TARGET_HOST` from the `[remote]`'s
  URL, and every GitHub-touching sub-skill receives `[remote]` as an explicit
  positional (#1405): 2.1 `gh:issue-implement`, 2.2 `gh:commit`, 2.3 `gh:pr`,
  2.4 `devx:pr-review-all`. Each re-derives its own target with
  `_gh_host_from_url`/`_gh_parse_owner_repo_url` over **that** remote's URL, so
  the whole chain lands on the same repo and host. A sub-skill falling back
  further, to `_dotfiles_setup_mode` (`_gh_resolve_host` with no URL) instead
  of a URL-derived host, is the regression this line guards against — that
  path can disagree with `$TARGET_REPO` whenever the PC's setup-mode default
  isn't the remote in play (internal PC: `origin`=GHES,
  `upstream`=github.com). `gh` reports no error when it lands on the wrong
  host, so the divergence surfaces as a "missing" issue or PR.
- Never mutate state between steps beyond what the sub-skills do.
  Exception: Step 2.6 may post a comment after Step 2.5.1 — this is
  intentional and must soft-fail (never block the flow). If a future
  variant of Step 2.6 needs to mutate PR labels or body, route through
  `_gh_pr_edit_safe_label` / `_gh_pr_edit_safe_body`
  (`shell-common/functions/gh_pr_edit_safe.sh`); plain `gh pr edit
  --add-label` / `--body-file` silently exits 1 on repos with classic
  Projects attached (issue #326 Bug B).
- Do NOT preface or summarize beyond the compact report.
- Do NOT end the turn until the Step 3 report is issued (success or
  failure template). A `Next:` / resume-hint from a sub-skill
  (notably gh:issue-implement's `Next: /gh-commit && /gh-pr <N>`) is
  a waypoint during this composition, not a final answer — keep
  going. Don't let a success hint from 2.1 or 2.2 end the flow
  before Step 3.
- **Never drop `--no-next-hint` from the Step 2.1 invocation.** It is
  the mechanical guard against the early-stop failure mode documented
  in `references/critical-contract.md`. If a refactor of Step 2 looks
  cleaner without it, the refactor is wrong.
- **Zero conversational text between Skill() calls in Step 2.** No
  recap ("Step 2.1 complete, now committing..."), no progress
  markdown headers, no per-step bullet summaries. Such text reads as
  a turn-ending answer and re-introduces the early-stop. The only
  prose allowed inside Step 2 is the final Step 3 report. The quality
  gate runs inside the delegated Step 2.4 (`devx:pr-review-all`), so
  Step 2 is a six-`Skill()` sequence with no inline gate dispatch or
  Bash commit+push between calls — **except** the one documented,
  backgrounded, non-fatal Step 2.4.1 dispatcher wake (#1482), which is
  not a `Skill()` call and adds no prose. It is the sole intentional
  exception; do not add a second one without updating this line.
- **Do NOT stop after any sub-skill completes.** Each step (2.1 through
  2.5.1, including the Step 2.4 quality gate and the Step 2.4.1 merge-train
  wake) is a waypoint, not a final answer. Continue to the next step
  immediately. The only valid stopping points are: a step failure (output
  the failure report), or the Step 3 success report after all 6 skills
  complete.
