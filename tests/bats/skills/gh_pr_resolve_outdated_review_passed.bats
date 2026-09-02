#!/usr/bin/env bats
# tests/bats/skills/gh_pr_resolve_outdated_review_passed.bats
# Issue #1698 — gh:pr-resolve-outdated Step 5's `review-passed` reconciliation:
#   claude/skills/gh-pr-resolve-outdated/references/verdict-label-removal.sh.md
#   shell-common/functions/gh_pr_resolve_outdated.sh
# Source-of-truth fixture: _fixtures/gh_pr_resolve_outdated_review_passed.sh
#
# The fixture does NOT re-implement the patch-id compare or the label
# write/drop — it sources the shipped functions, so a mirror cannot pass
# while production drifts (#1524's rule).
#
# Cases:
#   1. Clean rebase, patch-id identical, review-passed currently present AND
#      its #1601 marker is fresh for OLD_HEAD -> label kept, new marker
#      posted, no DELETE, no review-blocked touched.
#   2. Rebase whose content actually changed (different patch-id) -> label
#      dropped, exactly today's pre-#1698 behavior.
#   3. Unreadable patch-id (bogus shas) -> fail-closed, same as case 2.
#   4. Works against a `--worktree <path>`-style checkout, not just CWD.
#   5. Patch-id identical but the PR carries no marker at all -> falls to the
#      drop path, never manufactures a verdict nobody granted (PR #1699
#      review, codex BLOCKER).
#   6. Patch-id identical, label present, but its marker is for a DIFFERENT
#      sha (stale) -> falls to the drop path; a present-but-stale label must
#      never be laundered onto the new head (PR #1699 review, codex round-2
#      BLOCKER).
#   7. Same, but no marker at all (label present with no #1601 evidence) ->
#      same drop path.
#   8. Keep path whose marker repost itself fails -> reported as
#      `marker=failed`, not silently claimed as `reposted` (PR #1699 review,
#      codex round-3 BLOCKER).
#   9. Patch-id identical, marker fresh, but the label was ALREADY dropped by
#      some other path -> RE-GRANTED (issue #1700). Before #1700 the gate also
#      required the label to be attached, so the first path to strip it also
#      destroyed every other path's standing to re-confirm — see the file
#      header of `shell-common/functions/gh_pr_resolve_outdated.sh`.
#  10. Same, but with no marker either -> still drops. Removing the label from
#      the gate must not weaken PR #1699's self-certification guard.
#  11-15. F-4 report token: patch-id state and outcome are reported as two
#      independent fields, so `patch-id=identical label=dropped` is no longer
#      indistinguishable from a genuine content change.
#
# `STUB_CURRENT_LABELS` (comma-separated, default "review-passed") controls
# what `_gh_pr_resolve_outdated_has_label`'s `gh api .../labels` GET returns.
# `STUB_COMMENTS_JSON` / `STUB_ME_LOGIN` control the #1601 freshness lookup —
# `_marker_comment <login> <sha>` builds one matching comment object.
# `STUB_MARKER_POST_RC` fails the keep-path's marker repost.

load '../test_helper'

FIXTURE='tests/bats/skills/_fixtures/gh_pr_resolve_outdated_review_passed.sh'

# One PR-comment object carrying a fresh `review-verdict:review-passed`
# marker for <sha>, authored by <login> — mirrors what
# `devx_pr_review_all_write_label` actually posts.
_marker_comment() {
    jq -nc --arg login "$1" --arg sha "$2" \
        '{user: {login: $login}, body: ("<!-- review-verdict:review-passed:" + $sha + " -->")}'
}

setup() {
    setup_isolated_home
    GH_LOG="${BATS_TEST_TMPDIR}/gh.log"
    : >"$GH_LOG"
    export GH_LOG
    STUB_CURRENT_LABELS="${STUB_CURRENT_LABELS:-review-passed}"
    STUB_ME_LOGIN="${STUB_ME_LOGIN:-pipeline-bot}"
    : "${STUB_COMMENTS_JSON:=[]}"
    export STUB_CURRENT_LABELS STUB_ME_LOGIN STUB_COMMENTS_JSON
    # shellcheck disable=SC1090
    source "${_BATS_REAL_DOTFILES_ROOT}/${FIXTURE}"
    # shellcheck disable=SC2317  # called indirectly by the helpers under test
    gh() {
        printf 'gh %s [GH_HOST=%s]\n' "$*" "${GH_HOST-}" >>"$GH_LOG"
        if [ "$1" = "api" ]; then
            case "$2" in
                */labels)
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
        return 0
    }
}

teardown() {
    teardown_isolated_home
}

# Builds a repo where a clean rebase is simulated with a real `git
# cherry-pick`: OLD_HEAD's diff for x.txt onto OLD_BASE is reproduced
# byte-for-byte as NEW_HEAD_SAME's diff onto NEW_BASE (new commit, same
# content) -- the exact shape a conflict-free rebase produces. NEW_HEAD_DIFF
# instead carries genuinely different content, for the "real change" case.
_1698_make_repo() {
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
        OLD_HEAD=$(git rev-parse HEAD)

        git checkout -q "$OLD_BASE"
        printf 'a=2\n' >a.txt
        git add a.txt
        git commit -qm "base v2 (another PR merged first)"
        NEW_BASE=$(git rev-parse HEAD)

        git cherry-pick "$OLD_HEAD" >/dev/null
        NEW_HEAD_SAME=$(git rev-parse HEAD)

        git checkout -q "$NEW_BASE"
        printf 'goodbye\n' >x.txt
        git add x.txt
        git commit -qm "PR: add x.txt (different content after rebase)"
        NEW_HEAD_DIFF=$(git rev-parse HEAD)

        printf 'REPO_DIR=%s\nOLD_BASE=%s\nOLD_HEAD=%s\nNEW_BASE=%s\nNEW_HEAD_SAME=%s\nNEW_HEAD_DIFF=%s\n' \
            "$REPO_DIR" "$OLD_BASE" "$OLD_HEAD" "$NEW_BASE" "$NEW_HEAD_SAME" "$NEW_HEAD_DIFF"
    )
}

# ---------------------------------------------------------------------------
# _gh_pr_resolve_outdated_patch_id
# ---------------------------------------------------------------------------

@test "patch-id: identical content across different bases yields the same hash" {
    eval "$(_1698_make_repo)"
    cd "$REPO_DIR" || fail "cd failed"
    old_pid=$(_gh_pr_resolve_outdated_patch_id "$OLD_BASE" "$OLD_HEAD")
    new_pid=$(_gh_pr_resolve_outdated_patch_id "$NEW_BASE" "$NEW_HEAD_SAME")
    [ -n "$old_pid" ]
    [ "$old_pid" = "$new_pid" ]
}

@test "patch-id: genuinely different content yields a different hash" {
    eval "$(_1698_make_repo)"
    cd "$REPO_DIR" || fail "cd failed"
    old_pid=$(_gh_pr_resolve_outdated_patch_id "$OLD_BASE" "$OLD_HEAD")
    diff_pid=$(_gh_pr_resolve_outdated_patch_id "$NEW_BASE" "$NEW_HEAD_DIFF")
    [ -n "$diff_pid" ]
    [ "$old_pid" != "$diff_pid" ]
}

@test "patch-id: bogus shas yield an empty result, not a crash" {
    eval "$(_1698_make_repo)"
    cd "$REPO_DIR" || fail "cd failed"
    run _gh_pr_resolve_outdated_patch_id "deadbeef" "cafef00d"
    assert_success
    [ -z "$output" ]
}

@test "patch-id: --worktree-style -C path works without cd'ing into it" {
    eval "$(_1698_make_repo)"
    cd "${BATS_TEST_TMPDIR}" || fail "cd failed"
    old_pid=$(_gh_pr_resolve_outdated_patch_id "$OLD_BASE" "$OLD_HEAD" "$REPO_DIR")
    new_pid=$(_gh_pr_resolve_outdated_patch_id "$NEW_BASE" "$NEW_HEAD_SAME" "$REPO_DIR")
    [ -n "$old_pid" ]
    [ "$old_pid" = "$new_pid" ]
}

# ---------------------------------------------------------------------------
# _gh_pr_resolve_outdated_reconcile_review_passed (via the fixture wrapper)
# ---------------------------------------------------------------------------

@test "reconcile: unchanged patch-id keeps the label and reposts the freshness marker, no DELETE" {
    eval "$(_1698_make_repo)"
    cd "$REPO_DIR" || fail "cd failed"
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_marker_comment "$STUB_ME_LOGIN" "$OLD_HEAD")" '[$c]')
    resolve_outdated_step5_reconcile 1695 acme/widget ghe.example.com \
        "$OLD_BASE" "$OLD_HEAD" "$NEW_BASE" "$NEW_HEAD_SAME"
    run cat "$GH_LOG"
    refute_output --partial 'labels/review-passed'
    # BLOCKER (codex, PR #1699 review): must never touch review-blocked —
    # only the caller-owned devx:pr-review-all/gh:pr-reply may.
    refute_output --partial 'review-blocked'
    assert_output --partial "add 1695 review-passed --repo acme/widget"
    assert_output --partial "review-verdict:review-passed:${NEW_HEAD_SAME}"
}

@test "reconcile: keep path reports marker=failed when the repost itself fails (not swallowed)" {
    eval "$(_1698_make_repo)"
    cd "$REPO_DIR" || fail "cd failed"
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_marker_comment "$STUB_ME_LOGIN" "$OLD_HEAD")" '[$c]')
    STUB_MARKER_POST_RC=1
    run resolve_outdated_step5_reconcile 1695 acme/widget ghe.example.com \
        "$OLD_BASE" "$OLD_HEAD" "$NEW_BASE" "$NEW_HEAD_SAME"
    assert_success
    assert_output --partial 'patch-id=identical label=granted'
    assert_output --partial 'marker=failed'
    run cat "$GH_LOG"
    # The label add still ran (labelling is not reverted on a marker-only
    # failure) — only the report string must be honest that the marker
    # itself did not land.
    assert_output --partial "add 1695 review-passed --repo acme/widget"
}

@test "reconcile: label present but its marker is for a DIFFERENT sha (stale) -> drops" {
    eval "$(_1698_make_repo)"
    cd "$REPO_DIR" || fail "cd failed"
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_marker_comment "$STUB_ME_LOGIN" "some-earlier-sha")" '[$c]')
    resolve_outdated_step5_reconcile 1695 acme/widget ghe.example.com \
        "$OLD_BASE" "$OLD_HEAD" "$NEW_BASE" "$NEW_HEAD_SAME"
    run cat "$GH_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/1695/labels/review-passed'
    refute_output --partial 'add 1695 review-passed'
}

@test "reconcile: label present but no freshness marker at all -> drops" {
    eval "$(_1698_make_repo)"
    cd "$REPO_DIR" || fail "cd failed"
    STUB_COMMENTS_JSON='[]'
    resolve_outdated_step5_reconcile 1695 acme/widget ghe.example.com \
        "$OLD_BASE" "$OLD_HEAD" "$NEW_BASE" "$NEW_HEAD_SAME"
    run cat "$GH_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/1695/labels/review-passed'
    refute_output --partial 'add 1695 review-passed'
}

@test "reconcile: unchanged patch-id but review-passed was never granted -> drops (never self-certifies)" {
    eval "$(_1698_make_repo)"
    cd "$REPO_DIR" || fail "cd failed"
    STUB_CURRENT_LABELS="test,fix"
    resolve_outdated_step5_reconcile 1695 acme/widget ghe.example.com \
        "$OLD_BASE" "$OLD_HEAD" "$NEW_BASE" "$NEW_HEAD_SAME"
    run cat "$GH_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/1695/labels/review-passed'
    refute_output --partial 'add 1695 review-passed'
}

@test "reconcile (#1700): patch-id identical + fresh marker but the label was ALREADY dropped -> re-grants" {
    eval "$(_1698_make_repo)"
    cd "$REPO_DIR" || fail "cd failed"
    # The #1700 scenario: gh:pr-resolve-conflict (or any other drop path) got
    # there first and removed the label. The marker — the real evidence the
    # verdict was ever issued — survives, so the re-confirmation must too.
    STUB_CURRENT_LABELS="test,fix"
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_marker_comment "$STUB_ME_LOGIN" "$OLD_HEAD")" '[$c]')
    resolve_outdated_step5_reconcile 1695 acme/widget ghe.example.com \
        "$OLD_BASE" "$OLD_HEAD" "$NEW_BASE" "$NEW_HEAD_SAME"
    run cat "$GH_LOG"
    refute_output --partial 'labels/review-passed'
    refute_output --partial 'review-blocked'
    assert_output --partial "add 1695 review-passed --repo acme/widget"
    assert_output --partial "review-verdict:review-passed:${NEW_HEAD_SAME}"
}

@test "reconcile (#1700): patch-id identical, label absent AND no marker -> still drops (never self-certifies)" {
    eval "$(_1698_make_repo)"
    cd "$REPO_DIR" || fail "cd failed"
    # Dropping the has_label gate must NOT weaken PR #1699's self-certification
    # guard: a PR nobody ever reviewed has no marker, so the freshness check
    # returns rc 2 (ABSENT) and the drop path still wins.
    STUB_CURRENT_LABELS="test,fix"
    STUB_COMMENTS_JSON='[]'
    resolve_outdated_step5_reconcile 1695 acme/widget ghe.example.com \
        "$OLD_BASE" "$OLD_HEAD" "$NEW_BASE" "$NEW_HEAD_SAME"
    run cat "$GH_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/1695/labels/review-passed'
    refute_output --partial 'add 1695 review-passed'
}

@test "reconcile: changed patch-id drops the label exactly as before, no add" {
    eval "$(_1698_make_repo)"
    cd "$REPO_DIR" || fail "cd failed"
    resolve_outdated_step5_reconcile 1695 acme/widget ghe.example.com \
        "$OLD_BASE" "$OLD_HEAD" "$NEW_BASE" "$NEW_HEAD_DIFF"
    run cat "$GH_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/1695/labels/review-passed'
    refute_output --partial 'add 1695 review-passed'
}

@test "reconcile: unreadable old-side shas fail closed to the drop path" {
    eval "$(_1698_make_repo)"
    cd "$REPO_DIR" || fail "cd failed"
    resolve_outdated_step5_reconcile 1695 acme/widget ghe.example.com \
        "deadbeef" "cafef00d" "$NEW_BASE" "$NEW_HEAD_SAME"
    run cat "$GH_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/1695/labels/review-passed'
    refute_output --partial 'add 1695 review-passed'
}

# ---------------------------------------------------------------------------
# F-4 (#1700) — the report token carries patch-id state and outcome as two
# INDEPENDENT fields. The old single string folded "content actually changed"
# together with "was never certified", so an operator reading `patch-id=changed`
# on a byte-identical rebase wrongly concluded a re-review was warranted.
# ---------------------------------------------------------------------------

@test "token (#1700): a re-grant reports patch-id=identical, label=granted and prior=absent" {
    eval "$(_1698_make_repo)"
    cd "$REPO_DIR" || fail "cd failed"
    STUB_CURRENT_LABELS="test,fix"
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_marker_comment "$STUB_ME_LOGIN" "$OLD_HEAD")" '[$c]')
    run resolve_outdated_step5_reconcile 1695 acme/widget ghe.example.com \
        "$OLD_BASE" "$OLD_HEAD" "$NEW_BASE" "$NEW_HEAD_SAME"
    assert_success
    assert_output --partial 'patch-id=identical'
    assert_output --partial 'label=granted'
    assert_output --partial 'prior=absent'
    assert_output --partial 'marker=reposted'
}

@test "token (#1700): a still-attached keep reports prior=present, not a fresh grant" {
    eval "$(_1698_make_repo)"
    cd "$REPO_DIR" || fail "cd failed"
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_marker_comment "$STUB_ME_LOGIN" "$OLD_HEAD")" '[$c]')
    run resolve_outdated_step5_reconcile 1695 acme/widget ghe.example.com \
        "$OLD_BASE" "$OLD_HEAD" "$NEW_BASE" "$NEW_HEAD_SAME"
    assert_success
    assert_output --partial 'patch-id=identical'
    assert_output --partial 'label=granted'
    assert_output --partial 'prior=present'
}

@test "token (#1700): an identical patch-id that still drops never claims patch-id=changed" {
    eval "$(_1698_make_repo)"
    cd "$REPO_DIR" || fail "cd failed"
    STUB_COMMENTS_JSON='[]'
    run resolve_outdated_step5_reconcile 1695 acme/widget ghe.example.com \
        "$OLD_BASE" "$OLD_HEAD" "$NEW_BASE" "$NEW_HEAD_SAME"
    assert_success
    # The whole point of F-4: the content really was identical, so saying
    # "changed" here misdirects the operator toward a pointless re-review.
    assert_output --partial 'patch-id=identical'
    assert_output --partial 'label=dropped'
    refute_output --partial 'patch-id=changed'
}

@test "token (#1700): genuinely changed content reports patch-id=changed label=dropped" {
    eval "$(_1698_make_repo)"
    cd "$REPO_DIR" || fail "cd failed"
    run resolve_outdated_step5_reconcile 1695 acme/widget ghe.example.com \
        "$OLD_BASE" "$OLD_HEAD" "$NEW_BASE" "$NEW_HEAD_DIFF"
    assert_success
    assert_output --partial 'patch-id=changed'
    assert_output --partial 'label=dropped'
}

@test "token (#1700): unreadable shas report patch-id=unreadable, distinct from changed" {
    eval "$(_1698_make_repo)"
    cd "$REPO_DIR" || fail "cd failed"
    run resolve_outdated_step5_reconcile 1695 acme/widget ghe.example.com \
        "deadbeef" "cafef00d" "$NEW_BASE" "$NEW_HEAD_SAME"
    assert_success
    assert_output --partial 'patch-id=unreadable'
    assert_output --partial 'label=dropped'
    refute_output --partial 'patch-id=changed'
}

@test "reconcile: works from outside the repo via the worktree-path argument" {
    eval "$(_1698_make_repo)"
    cd "${BATS_TEST_TMPDIR}" || fail "cd failed"
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_marker_comment "$STUB_ME_LOGIN" "$OLD_HEAD")" '[$c]')
    resolve_outdated_step5_reconcile 1695 acme/widget ghe.example.com \
        "$OLD_BASE" "$OLD_HEAD" "$NEW_BASE" "$NEW_HEAD_SAME" "$REPO_DIR"
    run cat "$GH_LOG"
    refute_output --partial 'labels/review-passed'
    assert_output --partial "review-verdict:review-passed:${NEW_HEAD_SAME}"
}
