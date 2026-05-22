#!/bin/bash
# Pre-push validation rules (SSOT)
# Used by: git/hooks/pre-push
# Purpose:
#   1. Prevent accidental pushes to protected branches.
#   2. Prevent leaks of user-supplied "internal" patterns when pushing to a
#      remote identified as upstream (e.g. a public OSS mirror).
#
# shellcheck disable=SC2034
# (Variables in this file are consumed by the pre-push hook that sources it.)

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

# ============================================
# UPSTREAM PUSH LEAK GUARD (F-1, F-2, F-4, F-7)
# ============================================
# The leak guard runs only when the push target's remote URL matches
# UPSTREAM_REMOTES_ERE. This lets the same dotfiles checkout live in
# multiple remotes — push to your private mirror flows unimpeded, push to
# the public upstream is scanned for user-supplied "internal" patterns.
#
# Both variables default to the empty string. Empty means the mechanism is
# present but inert — no upstream is identified and no pattern is enforced
# until the user opts in by exporting these. This keeps the OSS default
# value-free; the *values* live in the user's environment, not in the repo.
#
# Example (e.g. in ~/.zshrc, ~/.bashrc, or a gitignored local rc):
#
#   export UPSTREAM_REMOTES_ERE='github\.com[:/]<owner>/<repo>(\.git)?$'
#   export LEAK_PATTERNS_ERE='<your-private-host>\.example\.com|/your-private-overlay/'
#
UPSTREAM_REMOTES_ERE="${UPSTREAM_REMOTES_ERE-}"
LEAK_PATTERNS_ERE="${LEAK_PATTERNS_ERE-}"

# ============================================
# ERROR MESSAGES — leak guard layer
# ============================================
MSG_LEAK_BLOCKED="Upstream push blocked: internal-pattern match detected"
MSG_LEAK_HINT="
To fix this:
   1. Inspect: git log <range> -p | grep -nE \"\${LEAK_PATTERNS_ERE}\"
   2. Squash / amend / drop the offending commit, then re-push.
   3. (Emergency) SKIP_LEAK_GUARD=1 git push <remote> <branch>
      Use only when you have manually verified the diff is safe.
"
