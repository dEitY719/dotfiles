#!/usr/bin/env bash
# tests/bats/skills/_fixtures/review_passed_gh_stub.sh
# Shared bats scaffolding for the two `review-passed` reconcile suites:
#   gh_pr_resolve_outdated_review_passed.bats  (issue #1698)
#   gh_pr_resolve_conflict_review_passed.bats  (issue #1700)
#
# Both suites pin the SAME shared function
# (`_gh_pr_resolve_outdated_reconcile_review_passed`) through a skill-specific
# wrapper fixture — only the wrapper name and its argument-variable names
# differ (`OLD_HEAD` vs `BACKUP_SHA`), so the `gh`/`_gh_pr_edit_safe_label`
# stubs, the marker-comment builder, and the rebase git repo each test needs
# were identical between the two files. Kept in one place per #1524 (a test
# helper must not be free to drift from the fixture it exercises).

# One PR-comment object carrying a fresh `review-verdict:review-passed`
# marker for <sha>, authored by <login> — mirrors what
# `devx_pr_review_all_write_label` actually posts.
_marker_comment() {
    jq -nc --arg login "$1" --arg sha "$2" \
        '{user: {login: $login}, body: ("<!-- review-verdict:review-passed:" + $sha + " -->")}'
}

# Call from setup(), AFTER GH_LOG/STUB_* are exported and the skill-specific
# fixture is sourced — defines the `gh` and `_gh_pr_edit_safe_label` stubs
# both suites share verbatim.
_review_passed_gh_stub_setup() {
    # shellcheck disable=SC2317  # called indirectly by the helpers under test
    gh() {
        printf 'gh %s [GH_HOST=%s]\n' "$*" "${GH_HOST-}" >>"$GH_LOG"
        if [ "$1" = "api" ]; then
            case "$2" in
                */labels)
                    # `STUB_LABELS_RC` (default 0) lets a test reproduce a
                    # labels-API failure, which the helper must report as
                    # UNDETERMINED (rc 2) rather than "not attached" — the
                    # BLOCKER 1 the PR #1703 self-record review found.
                    if [ "${STUB_LABELS_RC:-0}" -ne 0 ]; then
                        return "$STUB_LABELS_RC"
                    fi
                    printf '%s\n' "$STUB_CURRENT_LABELS" | tr ',' '\n'
                    return 0
                    ;;
                user)
                    printf '%s\n' "$STUB_ME_LOGIN"
                    return 0
                    ;;
            esac
            case "$*" in
                *"/comments"*"--jq"*)
                    # Single-page only (no Link header) — enough to exercise
                    # the freshness check without re-deriving pagination,
                    # already pinned elsewhere (gh_pr_merge_train_review_verdict_gate.bats).
                    _fs_jq_expr=""
                    _fs_want_next=0
                    for _fs_arg in "$@"; do
                        if [ "$_fs_want_next" -eq 1 ]; then
                            _fs_jq_expr="$_fs_arg"
                            _fs_want_next=0
                            continue
                        fi
                        case "$_fs_arg" in
                            --jq) _fs_want_next=1 ;;
                            -i)
                                printf 'HTTP/1.1 200 OK\n'
                                printf 'Content-Type: application/json; charset=utf-8\r\n'
                                printf '\r\n'
                                ;;
                        esac
                    done
                    printf '%s' "$STUB_COMMENTS_JSON" | jq -r "$_fs_jq_expr"
                    return 0
                    ;;
                *"-X POST"*"/comments"*)
                    # The keep-path marker repost — distinct from the
                    # freshness GET above (no `--jq`). STUB_MARKER_POST_RC
                    # simulates the POST itself failing (PR #1699 review,
                    # codex round-3 BLOCKER: this path was untested).
                    return "${STUB_MARKER_POST_RC:-0}"
                    ;;
            esac
        fi
        return 0
    }
    # shellcheck disable=SC2317  # called indirectly by the helpers under test
    _gh_pr_edit_safe_label() {
        printf 'add %s [GH_HOST=%s]\n' "$*" "${GH_HOST-}" >>"$GH_LOG"
        # STUB_LABEL_ADD_RC simulates the label ADD itself failing — distinct
        # from STUB_MARKER_POST_RC (the marker POST that follows it). Before
        # PR #1703's agy FOLLOW-UP the two were indistinguishable in the
        # report token, which claimed `label=granted` even here.
        return "${STUB_LABEL_ADD_RC:-0}"
    }
}

# Builds a repo where a clean rebase is simulated with a real `git
# cherry-pick`: the old head's diff for x.txt onto OLD_BASE is reproduced
# byte-for-byte as NEW_HEAD_SAME's diff onto NEW_BASE (new commit, same
# content) -- the exact shape a conflict-free rebase produces, including one
# a Step 3 that hit zero conflicts leaves behind (#1700). NEW_HEAD_DIFF
# instead carries genuinely different content, for the "real change" case.
#
# Prints REPO_DIR / OLD_BASE / <old-head-var> / NEW_BASE / NEW_HEAD_SAME /
# NEW_HEAD_DIFF as `eval`-able assignments. $1 names the old-head variable
# (`OLD_HEAD` for gh:pr-resolve-outdated, `BACKUP` for gh:pr-resolve-conflict)
# so each suite's `eval "$(...)"` call site reads with that skill's own
# vocabulary — the two skills differ only in what they call this value.
_review_passed_make_rebase_repo() {
    local _old_head_var="${1:-OLD_HEAD}"
    REPO_DIR="$(mktemp -d "${BATS_TEST_TMPDIR}/repo.XXXXXX")"
    (
        cd "$REPO_DIR" || exit 1
        git init -q -b main
        git config user.email t@t
        git config user.name Test

        printf 'a=1\n' >a.txt
        git add a.txt
        git commit -qm "base v1"
        OLD_BASE=$(git rev-parse HEAD)

        printf 'hello\n' >x.txt
        git add x.txt
        git commit -qm "PR: add x.txt"
        _rpr_old_head=$(git rev-parse HEAD)

        git checkout -q "$OLD_BASE"
        printf 'a=2\n' >a.txt
        git add a.txt
        git commit -qm "base v2 (another PR merged first)"
        NEW_BASE=$(git rev-parse HEAD)

        git cherry-pick "$_rpr_old_head" >/dev/null
        NEW_HEAD_SAME=$(git rev-parse HEAD)

        git checkout -q "$NEW_BASE"
        printf 'goodbye\n' >x.txt
        git add x.txt
        git commit -qm "PR: add x.txt (content changed after rebase)"
        NEW_HEAD_DIFF=$(git rev-parse HEAD)

        printf 'REPO_DIR=%s\nOLD_BASE=%s\n%s=%s\nNEW_BASE=%s\nNEW_HEAD_SAME=%s\nNEW_HEAD_DIFF=%s\n' \
            "$REPO_DIR" "$OLD_BASE" "$_old_head_var" "$_rpr_old_head" "$NEW_BASE" "$NEW_HEAD_SAME" "$NEW_HEAD_DIFF"
    )
}

# The #1704 shape, which `_review_passed_make_rebase_repo` above structurally
# CANNOT produce: its PR commit only ADDS a new file, and a new file's diff has
# no context lines to shift, so `git patch-id --stable` matches there whether or
# not the base moved. Here the PR edits a line inside an existing file and the
# new base inserts an unrelated block directly above it — the PR's own +/- lines
# stay byte-identical while the hunk's context window changes, which is exactly
# the false `changed` verdict #1704 fixes. Default (-U3) patch-ids differ across
# the two ranges; `-U0` patch-ids match.
#
# Prints REPO_DIR / OLD_BASE / <old-head-var> / NEW_BASE /
# NEW_HEAD_CONTEXT_SHIFT as `eval`-able assignments, same convention as its
# sibling ($1 names the old-head variable).
_review_passed_make_context_drift_repo() {
    local _old_head_var="${1:-OLD_HEAD}"
    REPO_DIR="$(mktemp -d "${BATS_TEST_TMPDIR}/repo.XXXXXX")"
    (
        cd "$REPO_DIR" || exit 1
        git init -q -b main
        git config user.email t@t
        git config user.name Test

        printf 'line1\nline2\nline3\nline4\nline5\n' >f.txt
        git add f.txt
        git commit -qm "base v1"
        OLD_BASE=$(git rev-parse HEAD)

        printf 'line1\nline2\nline3-changed\nline4\nline5\n' >f.txt
        git add f.txt
        git commit -qm "PR: change line3"
        _rpr_old_head=$(git rev-parse HEAD)

        git checkout -q "$OLD_BASE"
        printf 'line1\nline2\nextra-block\nline3\nline4\nline5\n' >f.txt
        git add f.txt
        git commit -qm "base v2 (unrelated block inserted just above line3)"
        NEW_BASE=$(git rev-parse HEAD)

        # Reapply the PR's own change (line3 -> line3-changed) onto the new
        # base. The +/- lines are byte-identical to the old head's diff, but
        # the hunk's context window now includes "extra-block" -- default
        # (-U3) patch-id differs, -U0 does not.
        printf 'line1\nline2\nextra-block\nline3-changed\nline4\nline5\n' >f.txt
        git add f.txt
        git commit -qm "PR: change line3 (rebased)"
        NEW_HEAD_CONTEXT_SHIFT=$(git rev-parse HEAD)

        printf 'REPO_DIR=%s\nOLD_BASE=%s\n%s=%s\nNEW_BASE=%s\nNEW_HEAD_CONTEXT_SHIFT=%s\n' \
            "$REPO_DIR" "$OLD_BASE" "$_old_head_var" "$_rpr_old_head" "$NEW_BASE" "$NEW_HEAD_CONTEXT_SHIFT"
    )
}

# The negative twin of `_review_passed_make_context_drift_repo` (PR #1712
# review, codex BLOCKER). Identical in every respect the `-U0` comparison can
# see — same PR change (line3 -> line3-changed), so the `-U0` patch-ids still
# match across the two ranges — except that the base's own advance also MODIFIES
# an existing line (line1) instead of only inserting. That is the shape a
# context-free patch-id cannot distinguish from harmless drift but which could
# have rewritten something the PR's surviving lines depend on, so the
# pure-insertion guard must refuse to rescue it: `patch-id=changed`, label
# dropped, even under `lenient`.
#
# Prints REPO_DIR / OLD_BASE / <old-head-var> / NEW_BASE /
# NEW_HEAD_BASE_MODIFIED as `eval`-able assignments ($1 names the old-head
# variable, same convention as its siblings).
_review_passed_make_base_modify_repo() {
    local _old_head_var="${1:-OLD_HEAD}"
    REPO_DIR="$(mktemp -d "${BATS_TEST_TMPDIR}/repo.XXXXXX")"
    (
        cd "$REPO_DIR" || exit 1
        git init -q -b main
        git config user.email t@t
        git config user.name Test

        printf 'line1\nline2\nline3\nline4\nline5\n' >f.txt
        git add f.txt
        git commit -qm "base v1"
        OLD_BASE=$(git rev-parse HEAD)

        printf 'line1\nline2\nline3-changed\nline4\nline5\n' >f.txt
        git add f.txt
        git commit -qm "PR: change line3"
        _rpr_old_head=$(git rev-parse HEAD)

        git checkout -q "$OLD_BASE"
        # Inserts extra-block AND rewrites line1 -- the deletion that
        # disqualifies the rescue.
        printf 'line1-changed-by-main\nline2\nextra-block\nline3\nline4\nline5\n' >f.txt
        git add f.txt
        git commit -qm "base v2 (inserts a block AND rewrites line1)"
        NEW_BASE=$(git rev-parse HEAD)

        printf 'line1-changed-by-main\nline2\nextra-block\nline3-changed\nline4\nline5\n' >f.txt
        git add f.txt
        git commit -qm "PR: change line3 (rebased)"
        NEW_HEAD_BASE_MODIFIED=$(git rev-parse HEAD)

        printf 'REPO_DIR=%s\nOLD_BASE=%s\n%s=%s\nNEW_BASE=%s\nNEW_HEAD_BASE_MODIFIED=%s\n' \
            "$REPO_DIR" "$OLD_BASE" "$_old_head_var" "$_rpr_old_head" "$NEW_BASE" "$NEW_HEAD_BASE_MODIFIED"
    )
}
