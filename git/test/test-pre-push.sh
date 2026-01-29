#!/bin/bash
# Test suite for pre-push hook
# Tests protected branch detection logic

set -o errexit
set -o pipefail

# Import rules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config/pre-push-rules.sh"

# ============================================
# TEST CASES
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
# RUN TESTS
# ============================================

echo "=== Pre-push Hook Tests ==="
echo ""
echo "Protected branches: ${PROTECTED_BRANCHES[*]}"
echo ""

all_passed=1

# Test protected branches
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
if [ $all_passed -eq 1 ]; then
    echo "✅ All tests passed!"
    exit 0
else
    echo "❌ Some tests failed"
    exit 1
fi
