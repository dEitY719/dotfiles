#!/usr/bin/env bats
# tests/bats/functions/gh_discussion.bats
# Unit tests for _gh_discussion_repo_id / _gh_discussion_category_id /
# _gh_discussion_create — the GraphQL wrappers used by the
# `gh:discussion-create` skill (issue #617).
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
    run grep -c 'repoId=R_kgDO_TEST' "$GH_LOG"
    assert_output "1"
    run grep -c 'categoryId=DIC_kTEST' "$GH_LOG"
    assert_output "1"
    run grep -c 'title=Test\\ title' "$GH_LOG"
    assert_output "1"
    run grep -c 'body=hello\\ world' "$GH_LOG"
    assert_output "1"
}
