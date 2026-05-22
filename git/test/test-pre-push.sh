#!/bin/bash
# Test suite for pre-push hook
#
# Covers two layers:
#   1. Protected-branch detection (pure logic — sources pre-push-rules.sh).
#   2. Upstream leak guard (T-1 .. T-7 from issue #708) — invokes the real
#      hook against a throwaway git repo with synthetic stdin / argv.
#
# Fixtures use generic placeholder strings (example.internal, /home/.*/
# private-overlay/) — no real internal identifiers ever appear in this file.

set -o errexit
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/config/pre-push-rules.sh"

HOOK="${SCRIPT_DIR}/hooks/pre-push"
ZERO_SHA="0000000000000000000000000000000000000000"

# ============================================
# LAYER 1 — PROTECTED_BRANCHES (pure logic)
# ============================================

run_test() {
    local branch="$1"
    local expected="$2"

    local is_protected=0
    for protected in "${PROTECTED_BRANCHES[@]}"; do
        if [[ "$protected" == *"*" ]]; then
            pattern="${protected//\*/.*}"
            if [[ "$branch" =~ ^${pattern}$ ]]; then
                is_protected=1
                break
            fi
        else
            if [ "$branch" = "$protected" ]; then
                is_protected=1
                break
            fi
        fi
    done

    if [ $is_protected -eq 1 ]; then
        result="BLOCKED"
    else
        result="ALLOWED"
    fi

    if [ "$result" = "$expected" ]; then
        echo "✓ $branch → $result"
        return 0
    else
        echo "✗ $branch → $result (expected: $expected)"
        return 1
    fi
}

# ============================================
# LAYER 2 — LEAK GUARD (T-1 .. T-7)
# ============================================

# Fixture: tiny git repo with one commit. Caller mutates from there.
_setup_repo() {
    local dir
    dir=$(mktemp -d -t leak-guard-test.XXXXXX)
    git -C "$dir" init -q
    git -C "$dir" config user.email "leak-test@example.com"
    git -C "$dir" config user.name "leak-test"
    git -C "$dir" config commit.gpgsign false
    echo "seed" >"$dir/seed.txt"
    git -C "$dir" add seed.txt
    git -C "$dir" -c core.hooksPath=/dev/null commit -q -m "seed"
    printf '%s' "$dir"
}

# Invoke the real hook against the given repo. Returns the hook's exit
# code and captures stdout+stderr in $LEAK_OUT.
_invoke_hook() {
    local dir="$1" remote_name="$2" remote_url="$3"
    local local_sha remote_sha rc out
    local_sha=$(git -C "$dir" rev-parse HEAD)
    remote_sha="${4:-$ZERO_SHA}"

    set +e
    out=$(cd "$dir" \
        && printf 'refs/heads/test %s refs/heads/test %s\n' "$local_sha" "$remote_sha" \
        | "$HOOK" "$remote_name" "$remote_url" 2>&1)
    rc=$?
    set -e
    LEAK_OUT="$out"
    return "$rc"
}

_assert_eq() {
    local name="$1" want="$2" got="$3"
    if [ "$want" = "$got" ]; then
        echo "✓ $name"
        return 0
    fi
    echo "✗ $name"
    echo "    want: $want"
    echo "    got:  $got"
    [ -n "${LEAK_OUT:-}" ] && echo "    out:  ${LEAK_OUT}"
    return 1
}

# Common env for leak-guard tests — generic placeholder values only.
# UPSTREAM_REMOTES_ERE picks any github.com URL; LEAK_PATTERNS_ERE picks
# two placeholder patterns that should never appear in real OSS code.
_LEAK_UPSTREAM_ERE='github\.com[:/].+/.+(\.git)?$'
_LEAK_PATTERNS_ERE='example\.internal|/private-overlay/'

_t1_origin_push_with_pattern_passes() {
    local dir
    dir=$(_setup_repo)
    echo "leak: example.internal endpoint" >>"$dir/seed.txt"
    git -C "$dir" -c core.hooksPath=/dev/null commit -aq -m "add leak content"

    set +e
    UPSTREAM_REMOTES_ERE="$_LEAK_UPSTREAM_ERE" \
        LEAK_PATTERNS_ERE="$_LEAK_PATTERNS_ERE" \
        _invoke_hook "$dir" origin "ssh://git@private-mirror.example/foo/bar.git"
    local rc=$?
    set -e
    rm -rf "$dir"
    _assert_eq "T-1 origin push with pattern -> exit 0 (guard inactive)" 0 "$rc"
}

_t2_upstream_push_no_pattern_passes() {
    local dir
    dir=$(_setup_repo)
    echo "plain content, nothing sensitive" >>"$dir/seed.txt"
    git -C "$dir" -c core.hooksPath=/dev/null commit -aq -m "clean change"

    set +e
    UPSTREAM_REMOTES_ERE="$_LEAK_UPSTREAM_ERE" \
        LEAK_PATTERNS_ERE="$_LEAK_PATTERNS_ERE" \
        _invoke_hook "$dir" upstream "https://github.com/owner/repo.git"
    local rc=$?
    set -e
    rm -rf "$dir"
    _assert_eq "T-2 upstream push no pattern -> exit 0" 0 "$rc"
}

_t3_upstream_push_pattern_in_commit_message_blocks() {
    local dir
    dir=$(_setup_repo)
    echo "harmless line" >>"$dir/seed.txt"
    git -C "$dir" -c core.hooksPath=/dev/null commit -aq \
        -m "wip: probe example.internal endpoint"

    set +e
    UPSTREAM_REMOTES_ERE="$_LEAK_UPSTREAM_ERE" \
        LEAK_PATTERNS_ERE="$_LEAK_PATTERNS_ERE" \
        _invoke_hook "$dir" upstream "https://github.com/owner/repo.git"
    local rc=$?
    set -e

    local rc_ok=0
    if [ "$rc" -eq 1 ] \
        && printf '%s' "$LEAK_OUT" | grep -q "Upstream push blocked" \
        && printf '%s' "$LEAK_OUT" | grep -q "<commit message>" \
        && printf '%s' "$LEAK_OUT" | grep -q "example.internal"; then
        rc_ok=1
    fi
    rm -rf "$dir"
    _assert_eq "T-3 pattern in commit message -> exit 1 + diagnostic" 1 "$rc_ok"
}

_t4_upstream_push_pattern_in_diff_blocks() {
    local dir
    dir=$(_setup_repo)
    echo "OVERLAY_PATH=/home/user/private-overlay/skills" >>"$dir/seed.txt"
    git -C "$dir" -c core.hooksPath=/dev/null commit -aq -m "ordinary subject"

    set +e
    UPSTREAM_REMOTES_ERE="$_LEAK_UPSTREAM_ERE" \
        LEAK_PATTERNS_ERE="$_LEAK_PATTERNS_ERE" \
        _invoke_hook "$dir" upstream "https://github.com/owner/repo.git"
    local rc=$?
    set -e

    local rc_ok=0
    if [ "$rc" -eq 1 ] \
        && printf '%s' "$LEAK_OUT" | grep -q "Upstream push blocked" \
        && printf '%s' "$LEAK_OUT" | grep -q "seed.txt" \
        && printf '%s' "$LEAK_OUT" | grep -q "/private-overlay/"; then
        rc_ok=1
    fi
    rm -rf "$dir"
    _assert_eq "T-4 pattern in file diff -> exit 1 + diagnostic" 1 "$rc_ok"
}

_t5_skip_leak_guard_escape_hatch() {
    local dir
    dir=$(_setup_repo)
    echo "leak: example.internal" >>"$dir/seed.txt"
    git -C "$dir" -c core.hooksPath=/dev/null commit -aq -m "would normally block"

    set +e
    SKIP_LEAK_GUARD=1 \
        UPSTREAM_REMOTES_ERE="$_LEAK_UPSTREAM_ERE" \
        LEAK_PATTERNS_ERE="$_LEAK_PATTERNS_ERE" \
        _invoke_hook "$dir" upstream "https://github.com/owner/repo.git"
    local rc=$?
    set -e
    rm -rf "$dir"
    _assert_eq "T-5 SKIP_LEAK_GUARD=1 -> exit 0" 0 "$rc"
}

_t6_skip_pre_push_escape_hatch() {
    local dir
    dir=$(_setup_repo)
    echo "leak: example.internal" >>"$dir/seed.txt"
    git -C "$dir" -c core.hooksPath=/dev/null commit -aq -m "would normally block"

    set +e
    SKIP_PRE_PUSH=1 \
        UPSTREAM_REMOTES_ERE="$_LEAK_UPSTREAM_ERE" \
        LEAK_PATTERNS_ERE="$_LEAK_PATTERNS_ERE" \
        _invoke_hook "$dir" upstream "https://github.com/owner/repo.git"
    local rc=$?
    set -e
    rm -rf "$dir"
    _assert_eq "T-6 SKIP_PRE_PUSH=1 -> exit 0 (whole hook skipped)" 0 "$rc"
}

_t7_protected_branch_takes_priority() {
    # Protected-branch check runs before the leak guard within the same ref
    # iteration. Pushing `main` with a leak should be blocked by layer 1
    # (exit 1) with the protected-branch message, not the leak message.
    local dir
    dir=$(_setup_repo)
    git -C "$dir" branch -m main 2>/dev/null || git -C "$dir" checkout -qb main
    echo "leak: example.internal" >>"$dir/seed.txt"
    git -C "$dir" -c core.hooksPath=/dev/null commit -aq -m "main with leak"

    local local_sha rc out
    local_sha=$(git -C "$dir" rev-parse HEAD)

    set +e
    out=$(cd "$dir" \
        && UPSTREAM_REMOTES_ERE="$_LEAK_UPSTREAM_ERE" \
        LEAK_PATTERNS_ERE="$_LEAK_PATTERNS_ERE" \
        printf 'refs/heads/main %s refs/heads/main %s\n' "$local_sha" "$ZERO_SHA" \
        | "$HOOK" upstream "https://github.com/owner/repo.git" 2>&1)
    rc=$?
    set -e

    local rc_ok=0
    if [ "$rc" -eq 1 ] \
        && printf '%s' "$out" | grep -q "protected branch"; then
        rc_ok=1
    fi
    rm -rf "$dir"
    LEAK_OUT="$out"
    _assert_eq "T-7 protected-branch wins over leak guard" 1 "$rc_ok"
}

# ============================================
# RUN TESTS
# ============================================

echo "=== Pre-push Hook Tests ==="
echo ""
echo "Protected branches: ${PROTECTED_BRANCHES[*]}"
echo ""

all_passed=1

echo "Testing protected branches (should be BLOCKED):"
run_test "main" "BLOCKED" || all_passed=0
run_test "master" "BLOCKED" || all_passed=0
run_test "release/1.0" "BLOCKED" || all_passed=0
run_test "release/2.5.3" "BLOCKED" || all_passed=0
run_test "release/v1.0.0" "BLOCKED" || all_passed=0

echo ""
echo "Testing feature branches (should be ALLOWED):"
run_test "feature/my-feature" "ALLOWED" || all_passed=0
run_test "feature/auth-token" "ALLOWED" || all_passed=0
run_test "develop" "ALLOWED" || all_passed=0
run_test "bugfix/urgent" "ALLOWED" || all_passed=0
run_test "hotfix/security" "ALLOWED" || all_passed=0
run_test "test/experiment" "ALLOWED" || all_passed=0

echo ""
echo "Testing leak guard (T-1 .. T-7):"
_t1_origin_push_with_pattern_passes || all_passed=0
_t2_upstream_push_no_pattern_passes || all_passed=0
_t3_upstream_push_pattern_in_commit_message_blocks || all_passed=0
_t4_upstream_push_pattern_in_diff_blocks || all_passed=0
_t5_skip_leak_guard_escape_hatch || all_passed=0
_t6_skip_pre_push_escape_hatch || all_passed=0
_t7_protected_branch_takes_priority || all_passed=0

echo ""
if [ $all_passed -eq 1 ]; then
    echo "✅ All tests passed!"
    exit 0
else
    echo "❌ Some tests failed"
    exit 1
fi
