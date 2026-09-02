#!/usr/bin/env bats
# tests/bats/skills/gh_pr_resolve_conflict_review_passed.bats
# Issue #1700 — gh:pr-resolve-conflict Step 5's `review-passed` reconciliation:
#   claude/skills/gh-pr-resolve-conflict/references/verdict-label-removal.sh.md
#   shell-common/functions/gh_pr_resolve_outdated.sh
# Source-of-truth fixture: _fixtures/gh_pr_resolve_conflict_review_passed.sh
#
# Why this file exists next to the near-identical
# `gh_pr_resolve_outdated_review_passed.bats`: #1698 gave the patch-id
# reconciliation to exactly ONE of the two rebase+force-push skills. This one
# kept dropping `review-passed` unconditionally even though its own Step 3 can
# complete with ZERO conflicts — `git rebase` exits 0 on a PR GitHub merely
# MARKED `CONFLICTING`, producing the same content-identical rebase its sister
# skill already handles. Whichever skill happened to pick the PR up first
# decided the outcome (issue #1700, PR #1687). The helper is shared, so this
# file only pins that THIS skill's wrapper reaches it with its own variable
# names and the right argument order — the helper's own semantics stay pinned
# next door.
#
# Cases:
#   1. Zero-conflict rebase, patch-id identical, marker fresh for BACKUP_SHA ->
#      label preserved and re-stamped for the new head, no DELETE, and
#      `review-blocked` never touched (the #1700 scenario).
#   2. A rebase that genuinely changed content -> dropped, exactly as before.
#   3. A PR that was never reviewed (no marker) -> dropped; sharing the helper
#      must not let this skill manufacture a verdict either (#1699 guard).
#   4. `--worktree <path>` mode, which `gh:pr-merge-train` always uses.

load '../test_helper'

FIXTURE='tests/bats/skills/_fixtures/gh_pr_resolve_conflict_review_passed.sh'

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

# Same shape as the sister file's helper: a real `git cherry-pick` reproduces
# OLD_HEAD's diff byte-for-byte on a moved base, which is exactly what a
# conflict-free rebase leaves behind — including one this skill was invoked for
# because GitHub reported `CONFLICTING`.
_1700_make_repo() {
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
        BACKUP=$(git rev-parse HEAD)

        git checkout -q "$OLD_BASE"
        printf 'a=2\n' >a.txt
        git add a.txt
        git commit -qm "base v2 (another PR merged first)"
        NEW_BASE=$(git rev-parse HEAD)

        git cherry-pick "$BACKUP" >/dev/null
        NEW_HEAD_SAME=$(git rev-parse HEAD)

        git checkout -q "$NEW_BASE"
        printf 'goodbye\n' >x.txt
        git add x.txt
        git commit -qm "PR: add x.txt (conflict resolved by changing content)"
        NEW_HEAD_DIFF=$(git rev-parse HEAD)

        printf 'REPO_DIR=%s\nOLD_BASE=%s\nBACKUP=%s\nNEW_BASE=%s\nNEW_HEAD_SAME=%s\nNEW_HEAD_DIFF=%s\n' \
            "$REPO_DIR" "$OLD_BASE" "$BACKUP" "$NEW_BASE" "$NEW_HEAD_SAME" "$NEW_HEAD_DIFF"
    )
}

@test "conflict Step 5 (#1700): a zero-conflict rebase with identical content keeps review-passed" {
    eval "$(_1700_make_repo)"
    cd "$REPO_DIR" || fail "cd failed"
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_marker_comment "$STUB_ME_LOGIN" "$BACKUP")" '[$c]')
    resolve_conflict_step5_reconcile 1687 acme/widget ghe.example.com \
        "$OLD_BASE" "$BACKUP" "$NEW_BASE" "$NEW_HEAD_SAME"
    run cat "$GH_LOG"
    refute_output --partial 'labels/review-passed'
    # #1563 / #1699: only devx:pr-review-all and gh:pr-reply may write this one.
    refute_output --partial 'review-blocked'
    assert_output --partial "add 1687 review-passed --repo acme/widget"
    assert_output --partial "review-verdict:review-passed:${NEW_HEAD_SAME}"
}

@test "conflict Step 5 (#1700): a rebase that really changed content still drops" {
    eval "$(_1700_make_repo)"
    cd "$REPO_DIR" || fail "cd failed"
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_marker_comment "$STUB_ME_LOGIN" "$BACKUP")" '[$c]')
    resolve_conflict_step5_reconcile 1687 acme/widget ghe.example.com \
        "$OLD_BASE" "$BACKUP" "$NEW_BASE" "$NEW_HEAD_DIFF"
    run cat "$GH_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/1687/labels/review-passed'
    refute_output --partial 'add 1687 review-passed'
}

@test "conflict Step 5 (#1700): a PR with no marker never earns the label from this skill" {
    eval "$(_1700_make_repo)"
    cd "$REPO_DIR" || fail "cd failed"
    STUB_CURRENT_LABELS="test,fix"
    STUB_COMMENTS_JSON='[]'
    resolve_conflict_step5_reconcile 1687 acme/widget ghe.example.com \
        "$OLD_BASE" "$BACKUP" "$NEW_BASE" "$NEW_HEAD_SAME"
    run cat "$GH_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/1687/labels/review-passed'
    refute_output --partial 'add 1687 review-passed'
}

@test "conflict Step 5 (#1700): works in --worktree mode, which gh:pr-merge-train always uses" {
    eval "$(_1700_make_repo)"
    cd "${BATS_TEST_TMPDIR}" || fail "cd failed"
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_marker_comment "$STUB_ME_LOGIN" "$BACKUP")" '[$c]')
    resolve_conflict_step5_reconcile 1687 acme/widget ghe.example.com \
        "$OLD_BASE" "$BACKUP" "$NEW_BASE" "$NEW_HEAD_SAME" "$REPO_DIR"
    run cat "$GH_LOG"
    refute_output --partial 'labels/review-passed'
    assert_output --partial "review-verdict:review-passed:${NEW_HEAD_SAME}"
}
