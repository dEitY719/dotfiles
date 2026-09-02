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
# Shared builder behind the two thin wrappers below (simplify pass, PR #1720
# review — the two were a ~35-line copy differing only in base v2's content
# and the result variable name). Same PR change in both (line3 -> line3-
# changed) so the `-U0` patch-ids always match across the two ranges; what
# differs is whether base v2's own commit ($2) also modifies an existing line
# (disqualifying the pure-insertion rescue) or only inserts (qualifying it).
#
# $1 old-head-var name ($1 of the public wrappers, same convention as
#    `_review_passed_make_rebase_repo`)
# $2 base v2's file content (the "unrelated main change" commit)
# $3 result-var name for the rebased head sha
#
# Prints REPO_DIR / OLD_BASE / <old-head-var> / NEW_BASE / <result-var> as
# `eval`-able assignments.
_review_passed_make_context_or_base_modify_repo() {
    local _old_head_var="${1:-OLD_HEAD}" _base_v2_content="$2" _result_var="$3"
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
        printf '%s' "$_base_v2_content" >f.txt
        git add f.txt
        git commit -qm "base v2 (unrelated main change)"
        NEW_BASE=$(git rev-parse HEAD)

        # Reapply the PR's own change (line3 -> line3-changed) onto the new
        # base. The +/- lines stay byte-identical to the old head's diff
        # regardless of what base v2 did elsewhere in the file.
        printf '%s' "$_base_v2_content" | sed 's/^line3$/line3-changed/' >f.txt
        git add f.txt
        git commit -qm "PR: change line3 (rebased)"
        _rpr_new_head=$(git rev-parse HEAD)

        printf 'REPO_DIR=%s\nOLD_BASE=%s\n%s=%s\nNEW_BASE=%s\n%s=%s\n' \
            "$REPO_DIR" "$OLD_BASE" "$_old_head_var" "$_rpr_old_head" "$NEW_BASE" "$_result_var" "$_rpr_new_head"
    )
}

# The #1704 shape, which `_review_passed_make_rebase_repo` above structurally
# CANNOT produce: its PR commit only ADDS a new file, and a new file's diff has
# no context lines to shift, so `git patch-id --stable` matches there whether or
# not the base moved. Here the PR edits a line inside an existing file and the
# new base inserts an unrelated block directly above it — the PR's own +/- lines
# stay byte-identical while the hunk's context window changes, which is exactly
# the false `changed` verdict #1704 fixes. Default (-U3) patch-ids differ across
# the two ranges; `-U0` patch-ids match. Base v2 is a PURE INSERTION (no line
# removed), so the #1712 pure-insertion guard also allows the rescue.
_review_passed_make_context_drift_repo() {
    _review_passed_make_context_or_base_modify_repo "${1:-OLD_HEAD}" \
        'line1
line2
extra-block
line3
line4
line5
' NEW_HEAD_CONTEXT_SHIFT
}

# The negative twin (PR #1712 review, codex BLOCKER). Identical in every
# respect the `-U0` comparison can see — the `-U0` patch-ids still match across
# the two ranges — except that base v2 also MODIFIES an existing line (line1)
# instead of only inserting. That is the shape a context-free patch-id cannot
# distinguish from harmless drift but which could have rewritten something the
# PR's surviving lines depend on, so the pure-insertion guard must refuse to
# rescue it: `patch-id=changed`, label dropped, even under `lenient`.
_review_passed_make_base_modify_repo() {
    _review_passed_make_context_or_base_modify_repo "${1:-OLD_HEAD}" \
        'line1-changed-by-main
line2
extra-block
line3
line4
line5
' NEW_HEAD_BASE_MODIFIED
}
