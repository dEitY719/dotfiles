#!/bin/sh
# shellcheck shell=bash
# claude/skills/gh-pr/references/token-compute.sh
#
# compute_pr_tokens — derive the ai-metrics token estimate for `gh:pr`.
#
# Why this lives in code, not prose
# ---------------------------------
# SKILL.md Step 4 used to describe the input contract in natural
# language ("character count of (issue body + commit log) ÷ 4, rounded
# to nearest 500, minimum 1 000"). At execution time the agent inferred
# the inputs from the variables in scope and reached for `$BODY` (the
# PR body draft) — the closest match — instead of `$ISSUE_BODY +
# $COMMIT_LOG`. The result on PR #325 was a footer of `~1000 tokens`
# (raw 500 → floored to 1000) when the spec-compliant value was 7000.
# Pinning the contract in a callable function removes the ambiguity:
# the function name forces the caller to supply both inputs and
# documents which transform is applied.
#
# Usage (from Step 4):
#   . ~/.claude/skills/gh-pr/references/token-compute.sh
#   TOKENS=$(compute_pr_tokens "$ISSUE_BODY" "$COMMIT_LOG")
#
# Inputs:
#   $1 — linked-issue body (full markdown). Empty when no issue is linked.
#   $2 — `git log <base>..HEAD --format=%B` output (commit messages),
#        optionally concatenated with `git diff <base>..HEAD` if that is
#        what the caller wants to count. The function does not care which
#        of the two it receives — the contract is "the second input is
#        the commit-side context." Pass whichever one matches the
#        spec the caller is implementing.
#
# Both args may be empty; the floor still produces 1 000.
#
# Regression case (issue #326): PR #325 — issue body 26 045 chars + commit
# log 1 032 chars = 27 077 → /4 = 6 769 → round to 7 000.
compute_pr_tokens() {
    _gh_pr_issue_body="${1:-}"
    _gh_pr_commit_log="${2:-}"
    _gh_pr_issue_chars=$(printf '%s' "$_gh_pr_issue_body" | wc -m | tr -d ' ')
    _gh_pr_log_chars=$(printf '%s' "$_gh_pr_commit_log" | wc -m | tr -d ' ')
    _gh_pr_total=$((_gh_pr_issue_chars + _gh_pr_log_chars))
    _gh_pr_t=$(((_gh_pr_total / 4 + 250) / 500 * 500))
    [ "$_gh_pr_t" -lt 1000 ] && _gh_pr_t=1000
    printf '%s\n' "$_gh_pr_t"
    unset _gh_pr_issue_body _gh_pr_commit_log _gh_pr_issue_chars \
        _gh_pr_log_chars _gh_pr_total _gh_pr_t
}
