#!/bin/bash
# Pre-push validation rules
# Used by: git/hooks/pre-push
# Purpose: Prevent accidental pushes to protected branches

# ============================================
# PROTECTED BRANCHES (cannot push directly)
# ============================================
PROTECTED_BRANCHES=(
    "main"
    "master"
    "release/*"
)

# ============================================
# ERROR MESSAGES
# ============================================
MSG_PROTECTED_BRANCH="❌ Cannot push directly to protected branch"
MSG_USE_PR="   → Create a pull request instead"
MSG_MERGE_VIA_PR="   → Merge will be done via GitHub/GitLab PR"

# ============================================
# HINT: How to fix
# ============================================
MSG_HINT_FIX="
💡 To fix this:
   1. Create a feature branch: git checkout -b feature/your-feature
   2. Make your changes and commit
   3. Push to feature branch: git push origin feature/your-feature
   4. Create a pull request on GitHub/GitLab
   5. Merge via pull request (not direct push)
"
