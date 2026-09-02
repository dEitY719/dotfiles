#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/gh_pr_resolve_outdated.sh
# Step 5 `review-passed` reconciliation for BOTH rebase+force-push skills —
# gh:pr-resolve-outdated and gh:pr-resolve-conflict (issues #1698, #1700).
#
# Before this file existed, Step 5 unconditionally dropped `review-passed`
# after every successful `git push --force-with-lease` — the rebase changed
# `head_sha`, and the label is a claim about one specific `head_sha` (SSOT
# #1563). That is correct when the rebase actually changed reviewed content,
# but a clean, conflict-free rebase onto a moved base often reproduces the
# EXACT SAME diff under a new commit SHA. Dropping the label there forces a
# full `devx:pr-review-all` re-run (4 external CLIs) for zero new content —
# observed 2026-09-01: 4 PRs stuck on this after a `gh:pr-merge-train` run.
#
# Fix: compare `git patch-id --stable` of the PR's diff before vs. after the
# rebase. Identical, AND the PR still carries a FRESH `review-verdict`
# marker for the old head -> the verdict is still true for the new head, so
# instead of dropping the label, re-post the SAME freshness marker format
# (#1601) for the new SHA — the existing
# `_gh_pr_merge_train_review_passed_stale()` reader then sees it as fresh on
# the very next tick, with no changes to that reader or to the marker format.
# Anything else (patch-id differs, unreadable, or no fresh marker) -> drop as
# before (a no-op when absent).
#
# BOTH rebase skills call this (#1700). #1698 shipped it to
# `gh:pr-resolve-outdated` alone, on the claim that "resolving a conflict by
# definition changes content" — which is FALSE, and was this issue's root
# cause. `gh:pr-resolve-conflict`'s own Step 3 routinely completes with ZERO
# conflicts: `git rebase` exits 0 even when GitHub had marked the PR
# `CONFLICTING` (the base moved again, or the verdict was simply stale), and
# what it leaves behind is the identical content-identical-rebase shape this
# file already handles. So whichever skill happened to pick a PR up decided
# whether its label survived. Duplicating the logic instead of sharing it
# would just re-open that gap, so the conflict skill sources this file
# directly (the same cross-file sourcing convention this file itself uses for
# `gh_pr_merge_train.sh` / `gh_pr_edit_safe.sh`). The function keeps its
# original name and home: it is reached by an explicit `.` + call from one
# extra doc, and renaming it would churn every existing call site and test
# for cosmetic reasons alone (issue #1700 marks the rename optional).
#
# Residual, deliberately accepted (PR #1699 review, codex round-4): identical
# patch-id proves the PR's OWN diff is byte-for-byte unchanged, not that the
# new base's unrelated changes cannot alter runtime behavior when combined
# with it (e.g. a helper the PR calls was renamed on main in a way that
# doesn't collide textually with the PR's own hunks, so the rebase stays
# conflict-free). This mirrors the accepted risk in
# `shell-common/functions/gcp_scan.sh`'s own patch-id-based drift discriminator
# (issue #1136/#1688) — a textual-identity check is not a semantic-identity
# proof, in either use. Two things bound it here: (1) a genuine base/PR
# interaction is exactly the shape `git rebase` is most likely to surface as a
# real conflict, which routes to `gh:pr-resolve-conflict` and a fresh review
# instead of this file entirely; (2) CI still runs against the new head after
# push and gates `gh:pr-merge`/`gh:pr-merge-train` regardless of this label, so
# a base-interaction bug that breaks the build or a test is still caught
# before merge — only a bug that passes CI yet is behaviorally wrong slips
# through, which is a residual risk of any code-review process, not one this
# file introduces. The alternative (unconditional drop, this file's pre-#1698
# behavior) trades that narrow, CI-backstopped residual for a 100%-of-the-time
# cost this issue exists to remove — an explicit, user-approved trade-off
# (issue #1698 "확정 사항"), not an oversight.
#
# The label add + marker post below are done directly (`_gh_pr_edit_safe_label`
# + one `gh api` POST in the exact format `devx_pr_review_all_write_label`
# already uses), NOT by calling `devx_pr_review_all_write_label` itself — that
# helper's first action is deleting the OPPOSITE label (`review-blocked`,
# because it services both directions), which would violate this skill's
# absolute "never touch review-blocked" constraint (PR #1699 review, codex
# BLOCKER). A PR that was NEVER reviewed must also never earn `review-passed`
# from a coincidentally-matching patch-id — a self-certifying grant this file
# must never manufacture (same review).
#
# What proves "was certified" is the MARKER, not the label (#1700). Until then
# the guard above was `_gh_pr_resolve_outdated_has_label` — "is the label
# attached right now" — and that was the wrong question. A label is
# destructible state that any of five drop paths can strip, so whichever path
# reached a PR first also destroyed every other path's standing to ever
# re-confirm the verdict: content byte-for-byte unchanged, yet the only way
# back was a full 4-CLI re-review (PR #1687, issue #1700). The
# `<!-- review-verdict:review-passed:<sha> -->` marker is never deleted by any
# path, so gating on it removes that race entirely. It is also the STRONGER
# guard, not a weaker one: the marker is direct evidence a verdict was
# actually issued for that exact head, where a bare label only shows one is
# attached now. A never-reviewed PR has no marker at all, so the freshness
# check below returns rc 2 (ABSENT) and the drop path still wins.
# `_gh_pr_resolve_outdated_has_label` survives as a function, but its call
# site is now purely DIAGNOSTIC — it fills the report's `prior=` field.
#
# Label presence alone was never enough either (PR #1699 review, codex round-2
# BLOCKER): a label can outlive its own freshness marker (e.g. some other bug
# already left the PR in a stale-but-labelled state before this skill ever
# ran) — reusing it would launder that staleness onto the new head. That
# review is what put the #1601 freshness check on the "keep" path in the first
# place; #1700 merely promoted it from second condition to only condition. So
# the "keep" path calls the existing #1601 freshness check,
# `_gh_pr_merge_train_review_passed_stale <pr> <repo> <host> <old-head-sha>
# <trusted-login>` (`shell-common/functions/gh_pr_merge_train.sh`) — only its
# rc 0 (FRESH: last marker from the trusted login equals `OLD_HEAD_SHA`
# exactly) proceeds; any other rc (stale, absent, undetermined) falls through
# to the ordinary drop. Reused as-is, not reimplemented — the marker format,
# pagination and bot-login handling stay defined in exactly one place.
#
# Unlike `gh:pr-merge-train`'s own routing table — which leaves a label
# UNTOUCHED on rc 2 (absent marker) / rc 3 (lookup undetermined), because
# there the label is already sitting on the PR regardless of what this file
# does — every non-zero rc here (1, 2, AND 3 alike) falls through to the
# SAME drop this file has always performed on every rebase before #1698 ever
# existed (PR #1699 review, codex round-4: flagged rc 2/3 folding into the
# drop path as destroying a "valid" label on a transient API failure). It
# is not a regression: this function only ever runs after a successful
# rebase, whose pre-#1698 baseline was drop unconditionally, always,
# glitch or not. A rc-2/3 API hiccup here returns to that exact baseline
# rather than reaching the newly-added keep path — never worse than before
# this file existed, only sometimes better (on the rc 0 path).
# `GH_PR_RESOLVE_OUTDATED_TRUSTED_LOGIN` overrides the auto-resolved identity
# (same override shape as `GH_PR_MERGE_TRAIN_TRUSTED_LOGIN` /
# `DEVX_PR_REVIEW_ALL_TRUSTED_LOGIN`) for a pipeline that authenticates the
# reviewer and this skill as different accounts. Deliberately its OWN
# variable, not a fallback chain through the other two (PR #1699 review,
# codex round-3 FOLLOW-UP raised chaining them; skipped — the SSOT already
# states the opposite intentionally: "deliberately separate... a deployment
# that splits the review, reply, and merge roles across accounts must be
# able to set each independently", `devx-pr-review-all/references/
# review-verdict-label.md` → "Marker authorship"). In the common single-
# account case all three auto-resolve to the same login anyway.
#
# That override is READ-side only, and must stay that way (PR #1699 review,
# codex round-5 BLOCKER): the repost below always lands under whatever
# account `gh` is actually authenticated as — there is no way to author a
# GitHub comment as a different login than the live token, override or not.
# So if `GH_PR_RESOLVE_OUTDATED_TRUSTED_LOGIN` is ever pointed at an account
# OTHER than the authenticated one (validating an old marker against a login
# this run cannot write as), the freshly reposted marker is authored by the
# WRONG identity for that override to trust on its next read — self-
# defeating in exactly that split-write configuration. This is not unique to
# this file: every marker writer in the codebase
# (`devx_pr_review_all_write_label`'s own repost included) shares the same
# "the authenticated account IS the trusted login" assumption; the override
# exists for a reader validating history from an account that used to run
# this pipeline, not for an ongoing split between who is trusted and who is
# currently authenticated. Setting the override to anything but the live
# `gh` identity is a misconfiguration, not a case this file can compensate
# for.
#
# Usage:
#   _gh_pr_resolve_outdated_patch_id <base-sha> <head-sha> [worktree-path]
#   _gh_pr_resolve_outdated_has_label <pr> <repo> <host> <label>
#   _gh_pr_resolve_outdated_reconcile_review_passed \
#       <pr> <repo> <host> <old-base-sha> <old-head-sha> \
#       <new-base-sha> <new-head-sha> [worktree-path]
#   (`gh:pr-resolve-conflict` passes its own `BACKUP_SHA` as <old-head-sha>;
#    the two skills differ only in what they name that argument)
#   (the freshness marker, when reposted, is stamped with <new-head-sha>)
#
# Report token — two INDEPENDENT dimensions on every path (#1700 F-4):
#   patch-id=<identical|changed|unreadable>  what the content comparison said
#   label=<granted|dropped>                  what this run actually did
#   prior=<present|absent>                   (granted only) was the label still
#       attached — `absent` marks a #1700 re-grant after another path already
#       stripped it, `present` an ordinary #1698 keep
#   marker=<reposted|failed>                 (granted only) did the repost land
# Before the split, the drop path printed a fixed `patch-id=changed` whatever
# its reason, so `patch-id=identical label=dropped` ("content was the same,
# but nothing proved it was ever certified") was reported as if the content
# had changed — reading as "re-review warranted" when it was not.

# Advisory only (issue #1454, propagated by #1505; PR #1699 review, codex
# round-4 FOLLOW-UP): warn once on stderr when this file was sourced from a
# checkout that is a different git repo than $HOME/dotfiles — a wrong-checkout
# `SHELL_COMMON` would otherwise silently run stale logic with no diagnostic.
# Never blocks; the guard function itself is a silent no-op outside the
# genuine foreign-checkout case. Mirrors the identical block in
# `gh_pr_edit_safe.sh` / `devx_pr_review_all.sh` verbatim — see that file for
# the $0-vs-$BASH_SOURCE rationale.
if [ -n "${ZSH_VERSION-}" ]; then
    _drg_self="$0"
elif [ -n "${BASH_VERSION-}" ]; then
    _drg_self="${BASH_SOURCE[0]-}"
else
    _drg_self=""
fi
_drg_helper="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/dotfiles_root.sh"
if [ -r "$_drg_helper" ]; then
    . "$_drg_helper" || true
fi
if command -v _dotfiles_root_guard_self >/dev/null 2>&1; then
    _dotfiles_root_guard_self "$_drg_self" "gh_pr_resolve_outdated"
else
    printf '[gh_pr_resolve_outdated] %s missing or did not define _dotfiles_root_guard_self — #1454 guard skipped (#724).\n' \
        "$_drg_helper" >&2
fi
unset _drg_self _drg_helper

# One patch-id hash for a whole diff range (not per-commit): `git patch-id
# --stable` accepts a multi-commit diff on stdin and folds it into one hash,
# which is exactly the whole-PR-range comparison this needs. Empty output
# (no line at all — an empty diff, or `git diff`/`git patch-id` itself
# failing) is reported as an empty string, never guessed at: the caller
# treats "unreadable" the same as "different" (fail closed, same rule this
# repo already uses for the approval gate and the #1601 freshness check).
_gh_pr_resolve_outdated_patch_id() {
    local _base="$1" _head="$2" _worktree="${3-}"
    if [ -z "$_base" ] || [ -z "$_head" ]; then
        printf '[gh-pr-resolve-outdated] usage: _gh_pr_resolve_outdated_patch_id <base-sha> <head-sha> [worktree-path]\n' >&2
        return 2
    fi
    local _out
    if [ -n "$_worktree" ]; then
        _out=$(git -C "$_worktree" diff "$_base".."$_head" 2>/dev/null | git -C "$_worktree" patch-id --stable 2>/dev/null)
    else
        _out=$(git diff "$_base".."$_head" 2>/dev/null | git patch-id --stable 2>/dev/null)
    fi
    # patch-id output is "<hash> <commit>"; only the hash is comparable across
    # the two sides (the trailing commit field differs by construction).
    printf '%s\n' "$_out" | awk '{print $1; exit}'
}

# Returns 0 when <label> is currently on the PR, 1 when it is not (including
# every lookup failure — fail closed, same as the freshness check this file
# feeds: an unreadable label list must never be read as "present").
_gh_pr_resolve_outdated_has_label() {
    local _pr="$1" _repo="$2" _host="${3-}" _label="$4"
    if [ -z "$_pr" ] || [ -z "$_repo" ] || [ -z "$_label" ]; then
        printf '[gh-pr-resolve-outdated] usage: _gh_pr_resolve_outdated_has_label <pr> <repo> <host> <label>\n' >&2
        return 1
    fi
    local _labels
    _labels=$(
        if [ -n "$_host" ]; then
            # shellcheck disable=SC2030,SC2031  # deliberately subshell-scoped
            export GH_HOST="$_host"
        fi
        gh api "repos/$_repo/issues/$_pr/labels" --jq '.[].name' 2>/dev/null
    ) || return 1
    printf '%s\n' "$_labels" | grep -Fxq -- "$_label"
}

# Soft-fail throughout (same contract as the unconditional drop it replaces):
# a failed reconciliation costs one stderr line, never the caller's exit
# status — Step 4's push already succeeded, so this step must never turn that
# into a failure.
_gh_pr_resolve_outdated_reconcile_review_passed() {
    local _pr="$1" _repo="$2" _host="$3"
    local _old_base="$4" _old_head="$5" _new_base="$6" _new_head="$7"
    local _worktree="${8-}"

    if [ -z "$_pr" ] || [ -z "$_repo" ]; then
        printf '[gh-pr-resolve-outdated] usage: _gh_pr_resolve_outdated_reconcile_review_passed <pr> <repo> <host> <old-base> <old-head> <new-base> <new-head> [worktree-path]\n' >&2
        return 2
    fi

    if ! command -v _gh_pr_drop_label >/dev/null 2>&1; then
        # shellcheck source=/dev/null
        . "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_pr_edit_safe.sh" 2>/dev/null || :
    fi
    if ! command -v _gh_pr_merge_train_review_passed_stale >/dev/null 2>&1; then
        # shellcheck source=/dev/null
        . "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_pr_merge_train.sh" 2>/dev/null || :
    fi

    local _old_pid _new_pid _me _fresh_rc _pid_state
    _old_pid=$(_gh_pr_resolve_outdated_patch_id "$_old_base" "$_old_head" "$_worktree")
    _new_pid=$(_gh_pr_resolve_outdated_patch_id "$_new_base" "$_new_head" "$_worktree")

    # The patch-id dimension is resolved ONCE, up front, and reported on
    # every path — see the file header's "Report token" section for why
    # (#1700 F-4). `unreadable` stays distinct from `changed`: both fail
    # closed to the drop, but only one is evidence about the content.
    if [ -z "$_old_pid" ] || [ -z "$_new_pid" ]; then
        _pid_state=unreadable
    elif [ "$_old_pid" = "$_new_pid" ]; then
        _pid_state=identical
    else
        _pid_state=changed
    fi

    _fresh_rc=1
    if [ "$_pid_state" = identical ] &&
        command -v _gh_pr_merge_train_review_passed_stale >/dev/null 2>&1; then
        _me="${GH_PR_RESOLVE_OUTDATED_TRUSTED_LOGIN:-$(
            if [ -n "$_host" ]; then
                # shellcheck disable=SC2030,SC2031  # deliberately subshell-scoped
                export GH_HOST="$_host"
            fi
            gh api user -q .login 2>/dev/null
        )}"
        # `|| _fresh_rc=$?`, not a bare call: this file is sourced into
        # callers that may have `set -e` armed (bats test bodies do), and
        # errexit fires on the non-zero rc BEFORE a trailing `_fresh_rc=$?`
        # would ever run (same caveat `devx_pr_review_all.sh` documents).
        # Pre-set to 0 (fresh) so a genuine rc-0 success needs no assignment
        # of its own — only the `||` branch overwrites it, on failure.
        _fresh_rc=0
        _gh_pr_merge_train_review_passed_stale "$_pr" "$_repo" "$_host" "$_old_head" "$_me" ||
            _fresh_rc=$?
    fi

    if [ "$_fresh_rc" -eq 0 ]; then
        # Direct add + marker post — NOT `devx_pr_review_all_write_label`,
        # which also deletes the opposite `review-blocked` label as its first
        # action. This file must never touch that label (see the header note).
        #
        # A failed marker POST is reported, not swallowed (PR #1699 review,
        # codex round-3 BLOCKER): silently claiming `marker=reposted` while
        # the repost actually failed would leave `review-passed` labelled
        # with no marker proving it for `NEW_HEAD_SHA` — the exact
        # `marker=failed` distinction `devx_pr_review_all_write_label`
        # already makes (`review-verdict-label.md` → "Freshness marker").
        # Soft-fail is unchanged: this is a report string, never a non-zero
        # return — the next tick's #1601 check self-heals either way.
        # DIAGNOSTIC ONLY (#1700 F-2, full rationale in the file header's
        # "What proves..." section): `_prior` is a report field, not a gate.
        # Read BEFORE the add below, or it would always report `present`. An
        # `if` (not `&&`) so a rc-1 lookup cannot trip a caller's errexit.
        local _marker=reposted _prior=absent
        if _gh_pr_resolve_outdated_has_label "$_pr" "$_repo" "$_host" review-passed; then
            _prior=present
        fi
        (
            if [ -n "$_host" ]; then
                # shellcheck disable=SC2030,SC2031  # deliberately subshell-scoped
                export GH_HOST="$_host"
            fi
            _gh_pr_edit_safe_label "$_pr" review-passed --repo "$_repo" >/dev/null 2>&1 &&
                gh api -X POST "repos/$_repo/issues/$_pr/comments" \
                    -f "body=<!-- review-verdict:review-passed:$_new_head -->" >/dev/null 2>&1
        ) || _marker=failed
        printf 'patch-id=%s label=granted prior=%s marker=%s\n' \
            "$_pid_state" "$_prior" "$_marker"
        return 0
    fi

    _gh_pr_drop_label "$_pr" review-passed "$_repo" "$_host" >/dev/null 2>&1 || :
    printf 'patch-id=%s label=dropped\n' "$_pid_state"
    return 0
}
