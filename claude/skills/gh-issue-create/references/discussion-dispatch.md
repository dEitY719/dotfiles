# gh:issue-create — Create dispatch (Step 4)

Read `references/create-cmd.md` and paste the matching bash block
verbatim:

- **Issue path** (default, `DISCUSSION_MODE` unset) — `mktemp` body
  file, `GH_DISABLE_AI_METRICS=1` short-circuit (issue #399),
  ai-metrics footer printf, and `gh issue create` with `LABEL_ARGS` /
  `MILESTONE_ARGS` from Step 2.5.
- **Discussion path** (`DISCUSSION_MODE=1`) — same body file +
  ai-metrics footer, then source
  `shell-common/functions/gh_discussion.sh` and run the three lookups
  (`_gh_discussion_repo_id`, `_gh_discussion_category_id`,
  `_gh_discussion_create`). Print the Discussion URL instead of an
  issue URL. If the helper is missing, fail with
  `[FAIL] gh-discussion helper not found at $DOTFILES_ROOT/shell-common/functions/gh_discussion.sh`
  and exit 1.

확인 질문하지 말고 즉시 실행.
