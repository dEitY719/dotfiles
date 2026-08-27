# gh:pr-reply — Constraints

- **Never skip a reply** — every comment from Step 2 gets one, bot comments
  (gemini-code-assist, sourcery-ai, copilot) included. Even
  "Declined: out of scope" counts; this is the core contract of the skill.
  Never dismiss a bot comment as "just a bot", and never fix silently.
- Never move the PR card to `Approved` — that column is owned by
  `gh:pr-approve` (#1350). Replies and bot reviews are `COMMENTED` and never
  change `reviewDecision`, so promoting on them lands unreviewed PRs in
  `Approved` (#1349 regression). The Step 6 `In review` recovery is the only
  board write this skill performs.
- **Never add `review-passed`, and only clear `review-blocked` after actually
  pushing an accepted fix** (#1527). `devx:pr-review-all` owns both labels;
  this skill's single write is releasing the block once `PUSHED_FIXES > 0` and
  at least one comment was `ACCEPT`/`ACCEPT-PARTIAL`
  (`references/review-blocked-clear.sh.md`). Clearing it on an all-`DECLINE`
  run would let a skill overrule a blocking verdict on its own reasoning; adding
  `review-passed` would let the act of fixing certify the fix. A human removing
  the label by hand is the intended override.
- Never close or resolve threads programmatically — leave that to the user.
- Never fix files outside the PR's diff without flagging scope creep first.
- Never `--amend`, `--no-verify`, or `--force-push`. If a history rewrite is
  needed, stop and ask.
- To mutate PR labels or body, route through `_gh_pr_edit_safe_label` /
  `_gh_pr_edit_safe_body` (`shell-common/functions/gh_pr_edit_safe.sh`) — bare
  `gh pr edit --add-label` / `--body-file` silently exits 1 on classic-Projects
  repos (issue #326 Bug B).
