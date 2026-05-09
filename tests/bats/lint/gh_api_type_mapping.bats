#!/usr/bin/env bats
# tests/bats/lint/gh_api_type_mapping.bats
# Issue #395 — heuristic regression guard for `gh api graphql` -f/-F mapping.
#
# Static-grep tests only — never invokes a live gh API call. Verifies the
# heuristic in git/hooks/checks/gh_api_type_check.sh fires on bad fixtures
# and stays silent on the real repo (which is expected to follow the
# convention after the issue #395 sweep).

load '../test_helper'

CHECK_PATH="${_BATS_REAL_DOTFILES_ROOT}/git/hooks/checks/gh_api_type_check.sh"

setup() {
    setup_isolated_home
    # shellcheck disable=SC1090
    . "$CHECK_PATH"
    WARN_FILE="$(mktemp "$BATS_TEST_TMPDIR/warn.XXXXXX")"
}

teardown() {
    [ -n "$WARN_FILE" ] && rm -f "$WARN_FILE"
    teardown_isolated_home
}

# ─────────────────────────────────────────────────────────────────────────
# Fixture-based tests: bad samples must fire, good samples must stay quiet
# ─────────────────────────────────────────────────────────────────────────

@test "signal 1: -F with literal non-numeric ID is flagged" {
    local f="$BATS_TEST_TMPDIR/bad_F_id.sh"
    cat >"$f" <<'EOF'
#!/bin/sh
# Variables: $id ID!
gh api graphql \
    -f query='mutation($id: ID!) { ... }' \
    -F id="PVTI_lADO123abc"
EOF
    run check_gh_api_type_mapping "$f" "$WARN_FILE"
    [ "$status" -eq 1 ]
    grep -q 'literal non-numeric value' "$WARN_FILE"
}

@test "signal 2: -f with literal all-digit value is flagged" {
    local f="$BATS_TEST_TMPDIR/bad_f_int.sh"
    cat >"$f" <<'EOF'
#!/bin/sh
# Variables: $num Int!
gh api graphql \
    -f query='query($num: Int!) { ... }' \
    -f num="42"
EOF
    run check_gh_api_type_mapping "$f" "$WARN_FILE"
    [ "$status" -eq 1 ]
    grep -q 'literal numeric value' "$WARN_FILE"
}

@test "signal 3: missing Variables: annotation is flagged" {
    local f="$BATS_TEST_TMPDIR/bad_no_variables.sh"
    cat >"$f" <<'EOF'
#!/bin/sh
# A query helper that forgot the type annotation.
gh api graphql \
    -f query='query($owner: String!) { repository(owner: $owner) { name } }' \
    -f owner="$_owner"
EOF
    run check_gh_api_type_mapping "$f" "$WARN_FILE"
    [ "$status" -eq 1 ]
    grep -q 'missing.*Variables' "$WARN_FILE"
}

@test "good: -f \$VAR for String! variable is silent" {
    local f="$BATS_TEST_TMPDIR/good_f_var.sh"
    cat >"$f" <<'EOF'
#!/bin/sh
# Variables: $owner String!, $repo String!
gh api graphql \
    -f query='query($owner: String!, $repo: String!) { repository(owner: $owner, name: $repo) { id } }' \
    -f owner="$_owner" \
    -f repo="$_repo"
EOF
    run check_gh_api_type_mapping "$f" "$WARN_FILE"
    [ "$status" -eq 0 ]
    [ ! -s "$WARN_FILE" ]
}

@test "good: -F \$VAR for Int! variable is silent" {
    local f="$BATS_TEST_TMPDIR/good_F_var.sh"
    cat >"$f" <<'EOF'
#!/bin/sh
# Variables: $num Int!
gh api graphql \
    -f query='query($num: Int!) { ... }' \
    -F num="$_num"
EOF
    run check_gh_api_type_mapping "$f" "$WARN_FILE"
    [ "$status" -eq 0 ]
    [ ! -s "$WARN_FILE" ]
}

@test "scope: file without 'gh api graphql' is silent" {
    local f="$BATS_TEST_TMPDIR/unrelated.sh"
    cat >"$f" <<'EOF'
#!/bin/sh
echo "no graphql here"
gh api repos/foo/bar/issues
EOF
    run check_gh_api_type_mapping "$f" "$WARN_FILE"
    [ "$status" -eq 0 ]
    [ ! -s "$WARN_FILE" ]
}

@test "scope: docs files are skipped (prose mentions, not callers)" {
    # Docs that describe the convention will mention `gh api graphql`
    # in prose. The heuristic skips them so the docs file documenting
    # the convention does not trigger itself.
    local d="$BATS_TEST_TMPDIR/docs/learnings"
    mkdir -p "$d"
    local f="$d/gh-api-type-casting.md"
    cat >"$f" <<'EOF'
# Doc — `gh api graphql`의 `-f` vs `-F`
gh api graphql -f query='...' -F id="PVTI_xxx"
EOF
    run check_gh_api_type_mapping "$f" "$WARN_FILE"
    [ "$status" -eq 0 ]
    [ ! -s "$WARN_FILE" ]
}

@test "scope: explicit 'gh-api-type-check: skip-file' marker opts out" {
    local f="$BATS_TEST_TMPDIR/exempt_via_marker.sh"
    cat >"$f" <<'EOF'
#!/bin/sh
# gh-api-type-check: skip-file
# This file documents bad patterns intentionally.
gh api graphql -f query='...' -F id="PVTI_xxx"
EOF
    run check_gh_api_type_mapping "$f" "$WARN_FILE"
    [ "$status" -eq 0 ]
    [ ! -s "$WARN_FILE" ]
}

# ─────────────────────────────────────────────────────────────────────────
# Real-repo regression: every checked-in GraphQL caller is convention-clean
# ─────────────────────────────────────────────────────────────────────────

@test "real repo: shell-common/functions/gh_project_status.sh is clean" {
    local f="${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_project_status.sh"
    run check_gh_api_type_mapping "$f" "$WARN_FILE"
    if [ "$status" -ne 0 ]; then
        echo "Findings:"
        cat "$WARN_FILE"
    fi
    [ "$status" -eq 0 ]
}

@test "real repo: shell-common/functions/gh_audit_builtin_workflows.sh is clean" {
    local f="${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/gh_audit_builtin_workflows.sh"
    run check_gh_api_type_mapping "$f" "$WARN_FILE"
    if [ "$status" -ne 0 ]; then
        echo "Findings:"
        cat "$WARN_FILE"
    fi
    [ "$status" -eq 0 ]
}
