#!/bin/bash
# Test suite for prepare-commit-msg hook
# Tests JIRA key extraction and template generation

set -o errexit
set -o pipefail

# Import rules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config/prepare-commit-msg-rules.sh"

# ============================================
# TEST CASES
# ============================================

run_test() {
    local branch="$1"
    local expected_jira="$2"

    JIRA=""
    if [[ "$branch" =~ $JIRA_PATTERN ]]; then
        JIRA="${BASH_REMATCH[0]}"
    fi

    if [ "$JIRA" = "$expected_jira" ]; then
        if [ -z "$JIRA" ]; then
            echo "✓ $branch → (no key)"
        else
            echo "✓ $branch → [$JIRA]"
        fi
        return 0
    else
        echo "✗ $branch → [$JIRA] (expected: [$expected_jira])"
        return 1
    fi
}

# ============================================
# RUN TESTS
# ============================================

echo "=== Prepare-Commit-Msg Hook Tests ==="
echo ""
echo "JIRA Pattern: $JIRA_PATTERN"
echo "Template Branches: ${TEMPLATE_BRANCHES[*]}"
echo ""

all_passed=1

echo "Testing with JIRA keys (should extract):"
run_test "feature/SWINNOTEAM-906-user-profile" "SWINNOTEAM-906" || all_passed=0
run_test "feature/SWINNOTEAM-906-add-auth" "SWINNOTEAM-906" || all_passed=0
run_test "bugfix/PROJ-245-login-bug" "PROJ-245" || all_passed=0
run_test "hotfix/JIRA-1-urgent-fix" "JIRA-1" || all_passed=0
run_test "bugfix/ABC-999-test-case" "ABC-999" || all_passed=0

echo ""
echo "Testing without JIRA keys (no extraction):"
run_test "feature/user-profile" "" || all_passed=0
run_test "bugfix/refactor-auth" "" || all_passed=0
run_test "hotfix/urgent-fix" "" || all_passed=0
run_test "feature/simple-name" "" || all_passed=0
run_test "develop" "" || all_passed=0
run_test "main" "" || all_passed=0

echo ""
echo "Testing edge cases:"
run_test "feature/PROJ-10-x" "PROJ-10" || all_passed=0
run_test "feature/VERYLONGKEY-999-test" "VERYLONGKEY-999" || all_passed=0

echo ""
if [ $all_passed -eq 1 ]; then
    echo "✅ All tests passed!"
    exit 0
else
    echo "❌ Some tests failed"
    exit 1
fi
