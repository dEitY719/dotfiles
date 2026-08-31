#!/usr/bin/env bats
# tests/bats/functions/gh_pr_review_paths_scope.bats
# Issue #1616 F-3 — `gh:pr-review --paths`, the file-scoped review the
# targeted re-review lane needs.
#
# gh:pr-reply's lane re-verifies ONE reviewer against ONLY the files its fix
# commits touched. Without a scope flag the only way to shrink the material
# is the ≥800-line large-diff delegation branch, which has a separate known
# defect (it never stamps `<!-- ai-review:<ai>:<head-sha> -->`) — so the lane
# must stay on the small-diff inline path regardless of the full PR's size.
# `--paths` is that switch: it filters the unified diff by file, so a
# 3000-line PR still reviews inline when the scope is two files.

load '../test_helper'

setup() {
    setup_isolated_home
    # shellcheck disable=SC1090
    source "${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_review.sh"
}

teardown() {
    teardown_isolated_home
}

# One small two-file unified diff, the shape `gh pr diff` emits.
_two_file_diff() {
    cat <<'EOF'
diff --git a/kept.sh b/kept.sh
index 1111111..2222222 100644
--- a/kept.sh
+++ b/kept.sh
@@ -1,2 +1,2 @@
-old kept line
+new kept line
diff --git a/dropped.sh b/dropped.sh
index 3333333..4444444 100644
--- a/dropped.sh
+++ b/dropped.sh
@@ -1,2 +1,2 @@
-old dropped line
+new dropped line
EOF
}

_stub_gh_diff() {
    local stub_dir="$TEST_TEMP_HOME/bin"
    mkdir -p "$stub_dir"
    cat >"$stub_dir/gh" <<'EOF'
#!/bin/sh
cat "$GH_STUB_DIFF_FILE"
EOF
    chmod +x "$stub_dir/gh"
    export PATH="$stub_dir:$PATH"
    GH_STUB_DIFF_FILE="$TEST_TEMP_HOME/diff.txt"
    export GH_STUB_DIFF_FILE
    _two_file_diff >"$GH_STUB_DIFF_FILE"
}

# ---------------------------------------------------------------------
# Parser — the flag is additive and the default is unchanged
# ---------------------------------------------------------------------

@test "parse: no --paths -> paths= is empty (unchanged default for every existing caller)" {
    run gh_pr_review_parse --ai codex 99
    assert_success
    assert_line 'paths='
}

@test "parse: --paths <p> resolves" {
    run gh_pr_review_parse --ai codex --paths shell-common/functions/a.sh 99
    assert_success
    assert_line 'paths=shell-common/functions/a.sh'
}

@test "parse: --paths=<p> resolves" {
    run gh_pr_review_parse --ai codex --paths=a.sh 99
    assert_success
    assert_line 'paths=a.sh'
}

@test "parse: --paths repeats and accumulates in order" {
    run gh_pr_review_parse --ai codex --paths a.sh --paths=b.sh 99
    assert_success
    assert_line 'paths=a.sh b.sh'
}

@test "parse: --paths with no value -> exit 2" {
    run gh_pr_review_parse --ai codex --paths
    assert_failure 2
}

@test "parse: --paths with an empty value -> exit 2" {
    run gh_pr_review_parse --ai codex --paths= 99
    assert_failure 2
}

@test "parse: --paths does not consume the positional PR number" {
    run gh_pr_review_parse --ai codex --paths a.sh 99 upstream
    assert_success
    assert_line 'pr=99'
    assert_line 'remote=upstream'
}

# ---------------------------------------------------------------------
# The diff filter
# ---------------------------------------------------------------------

@test "filter: a matching path keeps its whole section and drops the rest" {
    _two_file_diff >"${BATS_TEST_TMPDIR}/d.txt"
    run bash -c ". '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_review.sh'
        _gh_pr_review_filter_diff_paths kept.sh <'${BATS_TEST_TMPDIR}/d.txt'"
    assert_success
    assert_output --partial 'diff --git a/kept.sh b/kept.sh'
    assert_output --partial '+new kept line'
    refute_output --partial 'dropped.sh'
    refute_output --partial 'new dropped line'
}

@test "filter: several paths keep several sections" {
    _two_file_diff >"${BATS_TEST_TMPDIR}/d.txt"
    run bash -c ". '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_review.sh'
        _gh_pr_review_filter_diff_paths kept.sh dropped.sh <'${BATS_TEST_TMPDIR}/d.txt'"
    assert_success
    assert_output --partial 'a/kept.sh'
    assert_output --partial 'a/dropped.sh'
}

@test "filter: a rename is matched on its old path too" {
    cat >"${BATS_TEST_TMPDIR}/d.txt" <<'EOF'
diff --git a/old/name.sh b/new/name.sh
similarity index 90%
rename from old/name.sh
rename to new/name.sh
--- a/old/name.sh
+++ b/new/name.sh
@@ -1 +1 @@
-a
+b
EOF
    run bash -c ". '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_review.sh'
        _gh_pr_review_filter_diff_paths old/name.sh <'${BATS_TEST_TMPDIR}/d.txt'"
    assert_success
    assert_output --partial 'rename to new/name.sh'
}

@test "filter: a path that matches nothing yields nothing" {
    _two_file_diff >"${BATS_TEST_TMPDIR}/d.txt"
    run bash -c ". '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_review.sh'
        _gh_pr_review_filter_diff_paths absent.sh <'${BATS_TEST_TMPDIR}/d.txt'"
    assert_success
    assert_output ''
}

@test "filter: no paths at all is a usage error, never a silent pass-through" {
    _two_file_diff >"${BATS_TEST_TMPDIR}/d.txt"
    run bash -c ". '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_pr_review.sh'
        _gh_pr_review_filter_diff_paths <'${BATS_TEST_TMPDIR}/d.txt' 2>/dev/null"
    assert_failure 2
    assert_output ''
}

# ---------------------------------------------------------------------
# Prompt builder integration
# ---------------------------------------------------------------------

@test "build_prompt: no paths arg keeps the full diff and the unscoped header" {
    _stub_gh_diff
    local out="$TEST_TEMP_HOME/p.txt"
    run _gh_pr_review_build_prompt default "$out" 99 owner/repo main feature
    assert_success
    run grep -q 'PR DIFF (PR #99, repo owner/repo, base main → head feature)' "$out"
    assert_success
    run grep -q 'new dropped line' "$out"
    assert_success
}

@test "build_prompt: a paths arg scopes the diff and says so in the header" {
    _stub_gh_diff
    local out="$TEST_TEMP_HOME/p.txt"
    run _gh_pr_review_build_prompt default "$out" 99 owner/repo main feature kept.sh
    assert_success
    run grep -q 'scoped to: kept.sh' "$out"
    assert_success
    run grep -q 'new kept line' "$out"
    assert_success
    run grep -q 'new dropped line' "$out"
    assert_failure
}

@test "build_prompt: a scope that matches no file fails closed (exit 3), never an empty review" {
    # An empty diff would make the reviewer opine on nothing and answer LGTM.
    # For the #1616 lane that answer would clear `review-blocked` on no
    # evidence at all, so this must abort before the CLI ever runs.
    _stub_gh_diff
    local out="$TEST_TEMP_HOME/p.txt"
    run _gh_pr_review_build_prompt default "$out" 99 owner/repo main feature absent.sh
    assert_failure 3
}

@test "build_prompt: an empty UNSCOPED diff is still tolerated (unchanged behavior)" {
    _stub_gh_diff
    : >"$GH_STUB_DIFF_FILE"
    local out="$TEST_TEMP_HOME/p.txt"
    run _gh_pr_review_build_prompt default "$out" 99 owner/repo main feature
    assert_success
}
