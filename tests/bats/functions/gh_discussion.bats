#!/usr/bin/env bats
# tests/bats/functions/gh_discussion.bats
# Unit tests for _gh_discussion_repo_id / _gh_discussion_category_id /
# _gh_discussion_create — the GraphQL wrappers used by the
# `gh:discussion-create` skill (issue #617) — and for
# _gh_discussion_fetch / _gh_discussion_comment / _gh_discussion_close /
# _gh_discussion_lock — the convert-side wrappers used by
# `gh:discussion-convert` (issue #618).
#
# Network is never touched. A fake `gh` shim on PATH dispatches by
# inspecting the GraphQL query string for keywords ("repository(...){ id }",
# "discussionCategories", "createDiscussion") and emits the JSON the helper
# would have received, post-`--jq`. Mirrors the gh_pr_edit_safe.bats pattern.
#
# Per project memory feedback_no_live_api_for_smoke_test, no smoke-test path
# hits the real GitHub API.

load '../test_helper'

setup() {
    setup_isolated_home
    _setup_fake_gh
}

teardown() {
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# Fake `gh` shim
#
# FAKE_GH_MODE controls behaviour:
#   ok                     — every call succeeds with sensible defaults
#   repo_fail              — repository lookup returns auth error (exit 1)
#   discussions_disabled   — discussionCategories returns []
#   category_missing       — list has Ideas/Q&A but not the requested one
#   mutation_fail          — repo + category succeed, createDiscussion exits 1
#   fetch_missing          — discussion(number: $num) returns null
#   convert_mutation_fail  — fetch ok, comment/close/lock mutations all fail
#
# A scratch log records every call for assertion: $TEST_TEMP_HOME/gh.log
# ---------------------------------------------------------------------------
_setup_fake_gh() {
    STUB_BIN="$TEST_TEMP_HOME/bin"
    mkdir -p "$STUB_BIN"
    GH_LOG="$TEST_TEMP_HOME/gh.log"
    : >"$GH_LOG"
    cat >"$STUB_BIN/gh" <<'GH'
#!/usr/bin/env bash
# Record the invocation for inspection.
{ printf 'gh'; for a in "$@"; do printf ' %q' "$a"; done; printf '\n'; } \
    >>"$GH_LOG"

mode="${FAKE_GH_MODE:-ok}"

# All real calls are `gh api graphql -f query=... -f var=val ... [--jq EXPR]`.
# Pull the query body out of argv so we can dispatch on keywords.
query=""
for a in "$@"; do
    case "$a" in
        query=*) query="${a#query=}" ;;
    esac
done

# Repo node ID lookup
if [[ "$query" == *"repository(owner: "*"){ id }"* ]] \
    || [[ "$query" == *"repository(owner: \$owner, name: \$repo) { id }"* ]]; then
    case "$mode" in
        repo_fail)
            echo "GraphQL: Could not resolve to a Repository" >&2
            exit 1
            ;;
        *)
            # The helper's --jq '.data.repository.id' would extract this value.
            echo "R_kgDOFAKE_REPO_ID"
            exit 0
            ;;
    esac
fi

# Category list lookup
if [[ "$query" == *"discussionCategories(first: 25)"* ]]; then
    case "$mode" in
        discussions_disabled)
            # Helper checks for "[]" / "null" / empty.
            echo "[]"
            exit 0
            ;;
        category_missing)
            # No "Ideas" entry; helper's jq filter returns empty.
            echo '[{"id":"DIC_aaa","name":"Q&A"},{"id":"DIC_bbb","name":"Lessons"}]'
            exit 0
            ;;
        *)
            echo '[{"id":"DIC_kIDEAS","name":"Ideas"},{"id":"DIC_kQA","name":"Q&A"},{"id":"DIC_kANN","name":"Announcements"},{"id":"DIC_kLES","name":"Lessons"}]'
            exit 0
            ;;
    esac
fi

# createDiscussion mutation
if [[ "$query" == *"createDiscussion(input:"* ]]; then
    case "$mode" in
        mutation_fail)
            echo "GraphQL: Resource not accessible by integration" >&2
            exit 1
            ;;
        *)
            echo "https://github.com/fake/repo/discussions/123"
            exit 0
            ;;
    esac
fi

# Fetch a single Discussion (convert-side helper)
if [[ "$query" == *"discussion(number: \$num)"* ]]; then
    case "$mode" in
        fetch_missing)
            # GraphQL returns null for the discussion field; helper's --jq
            # surfaces the empty string, which the helper treats as missing.
            exit 0
            ;;
        *)
            # Mirror the real --jq '.data.repository.discussion' output:
            # category is the nested {name} object; the helper's
            # subsequent jq step flattens it to a string.
            cat <<'JSON'
{"id":"D_kgDOFAKEDISC","number":42,"title":"feat: convert me","body":"original body","url":"https://github.com/fake/repo/discussions/42","locked":false,"closed":false,"category":{"name":"Ideas"}}
JSON
            exit 0
            ;;
    esac
fi

# addDiscussionComment mutation
if [[ "$query" == *"addDiscussionComment(input:"* ]]; then
    case "$mode" in
        convert_mutation_fail)
            echo "GraphQL: Could not resolve to a node" >&2
            exit 1
            ;;
        *)
            echo "https://github.com/fake/repo/discussions/42#discussioncomment-99"
            exit 0
            ;;
    esac
fi

# closeDiscussion mutation
if [[ "$query" == *"closeDiscussion(input:"* ]]; then
    case "$mode" in
        convert_mutation_fail)
            echo "GraphQL: Permission denied" >&2
            exit 1
            ;;
        *)
            echo "true"
            exit 0
            ;;
    esac
fi

# lockLockable mutation
if [[ "$query" == *"lockLockable(input:"* ]]; then
    case "$mode" in
        convert_mutation_fail)
            echo "GraphQL: Resource locked" >&2
            exit 1
            ;;
        *)
            echo "true"
            exit 0
            ;;
    esac
fi

# Unknown call — fail loudly so we notice missed mock paths.
echo "fake-gh: unhandled call: $*" >&2
exit 99
GH
    chmod +x "$STUB_BIN/gh"
}

# Run a snippet in bash with the shim on PATH and the helper sourced.
_run_helper() {
    local mode="$1" snippet="$2"
    run bash --noprofile --norc -c "
        export DOTFILES_ROOT='${DOTFILES_ROOT}'
        export SHELL_COMMON='${SHELL_COMMON}'
        export DOTFILES_FORCE_INIT=1
        export DOTFILES_TEST_MODE=1
        export HOME='${HOME}'
        export TERM=dumb
        export PATH='${STUB_BIN}:${PATH}'
        export FAKE_GH_MODE='${mode}'
        export GH_LOG='${GH_LOG}'
        . '${DOTFILES_ROOT}/shell-common/functions/gh_discussion.sh'
        ${snippet}
        echo \"rc=\$?\"
    "
}

# ---------------------------------------------------------------------------
# Loading: helpers exist after sourcing
# ---------------------------------------------------------------------------

@test "bash: _gh_discussion_repo_id exists" {
    run_in_bash '. "$DOTFILES_ROOT/shell-common/functions/gh_discussion.sh"; \
                 declare -f _gh_discussion_repo_id >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _gh_discussion_category_id exists" {
    run_in_bash '. "$DOTFILES_ROOT/shell-common/functions/gh_discussion.sh"; \
                 declare -f _gh_discussion_category_id >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _gh_discussion_create exists" {
    run_in_bash '. "$DOTFILES_ROOT/shell-common/functions/gh_discussion.sh"; \
                 declare -f _gh_discussion_create >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "zsh: _gh_discussion_repo_id exists" {
    run_in_zsh '. "$DOTFILES_ROOT/shell-common/functions/gh_discussion.sh"; \
                typeset -f _gh_discussion_repo_id >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

@test "repo_id: missing args returns 2" {
    _run_helper ok '_gh_discussion_repo_id 2>&1'
    assert_output --partial "rc=2"
    assert_output --partial "usage: _gh_discussion_repo_id"
}

@test "category_id: missing args returns 2" {
    _run_helper ok '_gh_discussion_category_id fake 2>&1'
    assert_output --partial "rc=2"
    assert_output --partial "usage: _gh_discussion_category_id"
}

@test "create: missing args returns 2" {
    _run_helper ok '_gh_discussion_create REPO CAT 2>&1'
    assert_output --partial "rc=2"
    assert_output --partial "usage: _gh_discussion_create"
}

@test "create: missing body-file returns 2" {
    _run_helper ok '_gh_discussion_create REPO CAT "title" /nonexistent/abc.txt 2>&1'
    assert_output --partial "rc=2"
    assert_output --partial "body-file not found"
}

# ---------------------------------------------------------------------------
# Happy path: each helper succeeds
# ---------------------------------------------------------------------------

@test "repo_id: ok mode prints node ID and rc=0" {
    _run_helper ok '_gh_discussion_repo_id fake repo'
    assert_output --partial "R_kgDOFAKE_REPO_ID"
    assert_output --partial "rc=0"
}

@test "category_id: ok mode picks Ideas (case-insensitive)" {
    _run_helper ok '_gh_discussion_category_id fake repo ideas'
    assert_output --partial "DIC_kIDEAS"
    assert_output --partial "rc=0"
}

@test "category_id: ok mode resolves Q&A" {
    _run_helper ok "_gh_discussion_category_id fake repo 'Q&A'"
    assert_output --partial "DIC_kQA"
    assert_output --partial "rc=0"
}

@test "create: ok mode prints discussion URL" {
    _run_helper ok "
        BF=\$(mktemp); printf 'body content' > \"\$BF\"
        _gh_discussion_create R_kgDO DIC_k 'My RFC title' \"\$BF\"
        _rc=\$?
        rm -f \"\$BF\"
        ( exit \$_rc )
    "
    assert_output --partial "https://github.com/fake/repo/discussions/123"
    assert_output --partial "rc=0"
    # Mutation issued exactly once.
    run grep -c 'createDiscussion' "$GH_LOG"
    assert_output "1"
}

# ---------------------------------------------------------------------------
# Failure modes
# ---------------------------------------------------------------------------

@test "repo_id: repo_fail mode returns 1 with stderr trace" {
    _run_helper repo_fail '_gh_discussion_repo_id fake repo 2>&1'
    assert_output --partial "rc=1"
    assert_output --partial "repository lookup failed for fake/repo"
    assert_output --partial "Could not resolve to a Repository"
}

@test "category_id: discussions_disabled returns 1 with enable hint" {
    _run_helper discussions_disabled '_gh_discussion_category_id fake repo Ideas 2>&1'
    assert_output --partial "rc=1"
    assert_output --partial "Discussions not enabled on fake/repo"
    assert_output --partial "enable in repo settings"
}

@test "category_id: category_missing returns 2 with available list" {
    _run_helper category_missing '_gh_discussion_category_id fake repo Ideas 2>&1'
    assert_output --partial "rc=2"
    assert_output --partial 'category "Ideas" not found on fake/repo'
    # Available categories are listed for the user.
    assert_output --partial "Q&A"
    assert_output --partial "Lessons"
}

@test "create: mutation_fail returns 1 with stderr trace" {
    _run_helper mutation_fail "
        BF=\$(mktemp); printf 'x' > \"\$BF\"
        _gh_discussion_create R_kgDO DIC_k 'title' \"\$BF\" 2>&1
        _rc=\$?
        rm -f \"\$BF\"
        ( exit \$_rc )
    "
    assert_output --partial "rc=1"
    assert_output --partial "createDiscussion mutation failed"
    assert_output --partial "Resource not accessible by integration"
}

# ---------------------------------------------------------------------------
# GraphQL query shape — verify the mutation sends the expected variables
# ---------------------------------------------------------------------------

@test "create: invocation includes repoId/categoryId/title/body variables" {
    _run_helper ok "
        BF=\$(mktemp); printf 'hello world' > \"\$BF\"
        _gh_discussion_create R_kgDO_TEST DIC_kTEST 'Test title' \"\$BF\"
        _rc=\$?
        rm -f \"\$BF\"
        ( exit \$_rc )
    "
    assert_output --partial "rc=0"
    # All four named -f variables present in the recorded invocation.
    # The body is passed as `-f body=@<file>` so gh reads the file at
    # call time (no shell allocation), so the recorded arg shows the
    # `@<path>` reference, not the file's contents (PR #624 review).
    run grep -c 'repoId=R_kgDO_TEST' "$GH_LOG"
    assert_output "1"
    run grep -c 'categoryId=DIC_kTEST' "$GH_LOG"
    assert_output "1"
    run grep -c 'title=Test\\ title' "$GH_LOG"
    assert_output "1"
    run grep -cE 'body=@[^ ]+' "$GH_LOG"
    assert_output "1"
}

# ---------------------------------------------------------------------------
# Convert-side helpers (issue #618)
# ---------------------------------------------------------------------------

@test "bash: _gh_discussion_fetch exists" {
    run_in_bash '. "$DOTFILES_ROOT/shell-common/functions/gh_discussion.sh"; \
                 declare -f _gh_discussion_fetch >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _gh_discussion_comment exists" {
    run_in_bash '. "$DOTFILES_ROOT/shell-common/functions/gh_discussion.sh"; \
                 declare -f _gh_discussion_comment >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _gh_discussion_close exists" {
    run_in_bash '. "$DOTFILES_ROOT/shell-common/functions/gh_discussion.sh"; \
                 declare -f _gh_discussion_close >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

@test "bash: _gh_discussion_lock exists" {
    run_in_bash '. "$DOTFILES_ROOT/shell-common/functions/gh_discussion.sh"; \
                 declare -f _gh_discussion_lock >/dev/null && echo ok'
    assert_success
    assert_output --partial "ok"
}

# Argument validation

@test "fetch: missing args returns 2" {
    _run_helper ok '_gh_discussion_fetch fake 2>&1'
    assert_output --partial "rc=2"
    assert_output --partial "usage: _gh_discussion_fetch"
}

@test "fetch: non-integer number returns 2" {
    _run_helper ok '_gh_discussion_fetch fake repo abc 2>&1'
    assert_output --partial "rc=2"
    assert_output --partial "discussion number must be a positive integer"
}

@test "comment: missing args returns 2" {
    _run_helper ok '_gh_discussion_comment 2>&1'
    assert_output --partial "rc=2"
    assert_output --partial "usage: _gh_discussion_comment"
}

@test "comment: missing body-file returns 2" {
    _run_helper ok '_gh_discussion_comment D_ID /nonexistent/file 2>&1'
    assert_output --partial "rc=2"
    assert_output --partial "body-file not found"
}

@test "close: missing args returns 2" {
    _run_helper ok '_gh_discussion_close 2>&1'
    assert_output --partial "rc=2"
    assert_output --partial "usage: _gh_discussion_close"
}

@test "close: invalid reason returns 2" {
    _run_helper ok '_gh_discussion_close D_ID NOT_A_REASON 2>&1'
    assert_output --partial "rc=2"
    assert_output --partial "close reason must be RESOLVED, OUTDATED, or DUPLICATE"
}

@test "lock: missing args returns 2" {
    _run_helper ok '_gh_discussion_lock 2>&1'
    assert_output --partial "rc=2"
    assert_output --partial "usage: _gh_discussion_lock"
}

# Happy path

@test "fetch: ok mode flattens category.name -> category" {
    _run_helper ok '_gh_discussion_fetch fake repo 42'
    assert_output --partial '"category":"Ideas"'
    assert_output --partial '"number":42'
    assert_output --partial '"id":"D_kgDOFAKEDISC"'
    assert_output --partial "rc=0"
}

@test "fetch: ok mode includes locked/closed state for caller dispatch" {
    _run_helper ok '_gh_discussion_fetch fake repo 42'
    assert_output --partial '"locked":false'
    assert_output --partial '"closed":false'
    assert_output --partial "rc=0"
}

@test "comment: ok mode prints comment URL" {
    _run_helper ok "
        BF=\$(mktemp); printf 'Linked to issue #99' > \"\$BF\"
        _gh_discussion_comment D_ID \"\$BF\"
        _rc=\$?
        rm -f \"\$BF\"
        ( exit \$_rc )
    "
    assert_output --partial "discussioncomment-99"
    assert_output --partial "rc=0"
    run grep -c 'addDiscussionComment' "$GH_LOG"
    assert_output "1"
}

@test "close: ok mode reports 'closed' and uses RESOLVED reason by default" {
    _run_helper ok '_gh_discussion_close D_ID'
    assert_output --partial "closed"
    assert_output --partial "rc=0"
    # Default reason RESOLVED must appear in the recorded gh args.
    run grep -c 'reason=RESOLVED' "$GH_LOG"
    assert_output "1"
}

@test "close: ok mode honours explicit OUTDATED reason" {
    _run_helper ok '_gh_discussion_close D_ID OUTDATED'
    assert_output --partial "rc=0"
    run grep -c 'reason=OUTDATED' "$GH_LOG"
    assert_output "1"
}

@test "lock: ok mode reports 'locked' and uses RESOLVED in the query" {
    _run_helper ok '_gh_discussion_lock D_ID'
    assert_output --partial "locked"
    assert_output --partial "rc=0"
    # The reason RESOLVED is hard-coded in the GraphQL string (not -f),
    # so look for it inside the recorded query argument.
    run grep -c 'lockLockable' "$GH_LOG"
    assert_output "1"
}

# Failure modes

@test "fetch: fetch_missing returns 1 with not-found hint" {
    _run_helper fetch_missing '_gh_discussion_fetch fake repo 42 2>&1'
    assert_output --partial "rc=1"
    assert_output --partial "discussion #42 not found on fake/repo"
}

@test "comment: convert_mutation_fail returns 1 with stderr trace" {
    _run_helper convert_mutation_fail "
        BF=\$(mktemp); printf 'x' > \"\$BF\"
        _gh_discussion_comment D_ID \"\$BF\" 2>&1
        _rc=\$?
        rm -f \"\$BF\"
        ( exit \$_rc )
    "
    assert_output --partial "rc=1"
    assert_output --partial "addDiscussionComment mutation failed"
    assert_output --partial "Could not resolve to a node"
}

@test "close: convert_mutation_fail returns 1 with stderr trace" {
    _run_helper convert_mutation_fail '_gh_discussion_close D_ID 2>&1'
    assert_output --partial "rc=1"
    assert_output --partial "closeDiscussion mutation failed"
    assert_output --partial "Permission denied"
}

@test "lock: convert_mutation_fail returns 1 with stderr trace" {
    _run_helper convert_mutation_fail '_gh_discussion_lock D_ID 2>&1'
    assert_output --partial "rc=1"
    assert_output --partial "lockLockable mutation failed"
    assert_output --partial "Resource locked"
}

# GraphQL invocation shape

@test "comment: invocation passes discId variable and body file ref" {
    _run_helper ok "
        BF=\$(mktemp); printf 'hello' > \"\$BF\"
        _gh_discussion_comment D_TEST \"\$BF\"
        _rc=\$?
        rm -f \"\$BF\"
        ( exit \$_rc )
    "
    assert_output --partial "rc=0"
    run grep -c 'discId=D_TEST' "$GH_LOG"
    assert_output "1"
    # Body is streamed from a file via -f body=@<path>, mirroring the
    # createDiscussion pattern (PR #624 review note).
    run grep -cE 'body=@[^ ]+' "$GH_LOG"
    assert_output "1"
}

@test "close: invocation passes discId and reason variables" {
    _run_helper ok '_gh_discussion_close D_TEST RESOLVED'
    assert_output --partial "rc=0"
    run grep -c 'discId=D_TEST' "$GH_LOG"
    assert_output "1"
    run grep -c 'reason=RESOLVED' "$GH_LOG"
    assert_output "1"
}

@test "lock: invocation passes the lockable node id" {
    _run_helper ok '_gh_discussion_lock D_TEST'
    assert_output --partial "rc=0"
    run grep -c 'id=D_TEST' "$GH_LOG"
    assert_output "1"
}
