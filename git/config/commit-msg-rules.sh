#!/bin/bash
# Commit message validation rules
# Used by: git/hooks/commit-msg
# Purpose: Define Conventional Commits rules for the team

# ============================================
# ALLOWED COMMIT TYPES (8 types)
# ============================================
# Reference: https://www.conventionalcommits.org/
COMMIT_TYPES=(
    "feat"      # ✨ A new feature
    "fix"       # 🐛 A bug fix
    "docs"      # 📚 Documentation changes
    "style"     # 🎨 Code style changes (formatting, semicolons, etc.)
    "refactor"  # ♻️ Code refactoring without feature/fix
    "perf"      # ⚡ Performance improvements
    "test"      # ✅ Test-related changes
    "chore"     # 🔧 Build, CI, dependency updates
)

# ============================================
# MESSAGE LENGTH RULES
# ============================================
SUBJECT_MAX_LENGTH=72          # First line (subject) max length
BODY_MAX_LENGTH=72             # Body line max length (per Conventional Commits spec)
MIN_MESSAGE_LENGTH=10          # Minimum meaningful message length

# ============================================
# FORBIDDEN MESSAGE PATTERNS (차단할 메시지)
# ============================================
# These patterns indicate temporary/debug commits that should not be pushed
# IMPORTANT: Use exact patterns to avoid blocking valid types like "test:"
FORBIDDEN_PATTERNS=(
    "^WIP"                     # Work In Progress (any message starting with WIP)
    "^WIP:"                    # WIP: format
    "^tmp"                     # Temporary commit
    "^test$"                   # ONLY single word "test" (not "test: description")
    "^fix$"                    # ONLY single word "fix" (not "fix: description")
    "^TEMP"                    # Temporary marker
    "^DEBUG"                   # Debug marker
    "^XX[^A-Z0-9]"            # XX followed by non-alphanumeric (not release version)
    "^TODO"                    # Incomplete work
    "^FIXME"                   # Incomplete fix
    "^XXX"                     # Another placeholder
    "^!!!"                     # Urgency marker (not formal)
)

# ============================================
# JIRA KEY PATTERN (선택사항)
# ============================================
# Format: [PROJ-123] where PROJ = alphanumeric, 123 = number
# Used by post-commit hook for work log tracking
JIRA_PATTERN='\[[A-Z][A-Z0-9]*-[0-9]+\]'

# ============================================
# WARNING MESSAGE TEMPLATES
# ============================================
MSG_INVALID_TYPE="❌ Invalid commit type. Use one of: feat, fix, docs, style, refactor, perf, test, chore"
MSG_SUBJECT_TOO_LONG="❌ Subject line too long (> ${SUBJECT_MAX_LENGTH} chars). Keep it concise."
MSG_SUBJECT_TOO_SHORT="❌ Subject line too short (< ${MIN_MESSAGE_LENGTH} chars). Be more descriptive."
MSG_NO_SEPARATOR="❌ Missing empty line between subject and body."
MSG_BODY_TOO_LONG="❌ Body line exceeds ${BODY_MAX_LENGTH} characters."
MSG_FORBIDDEN="❌ This looks like a temporary/debug commit. Use proper Conventional Commits format."
MSG_EMPTY="❌ Commit message is empty."

# ============================================
# HINT: Good Commit Message Example
# ============================================
# Subject: feat(auth): add JWT token refresh mechanism
#
# Body:
# - Implement automatic token refresh on expiration
# - Add refresh token rotation logic
# - Closes #456
#
# Footer (optional):
# TimeSpent: 2.5h
# Category: feature
