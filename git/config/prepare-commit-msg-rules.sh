#!/bin/bash
# Prepare-commit-msg configuration
# Used by: git/hooks/prepare-commit-msg
# Purpose: Auto-generate commit message templates from branch names

# ============================================
# JIRA KEY PATTERN
# ============================================
# Match JIRA keys in branch names like:
# - feature/SWINNOTEAM-906-user-profile
# - bugfix/PROJ-123-fix-login
# Pattern: [A-Z]+[A-Z0-9]*-[0-9]+
JIRA_PATTERN='[A-Z][A-Z0-9]*-[0-9]+'

# ============================================
# BRANCH PATTERNS
# ============================================
# What types of branches should get templates?
TEMPLATE_BRANCHES=(
    "feature/*"
    "bugfix/*"
    "hotfix/*"
    "fix/*"
)

# ============================================
# TEMPLATE FORMAT
# ============================================
# When JIRA key is found, use this template
TEMPLATE_WITH_JIRA="[{JIRA}] {TYPE}: {DESCRIPTION}"

# When no JIRA key, use this template
TEMPLATE_WITHOUT_JIRA="{TYPE}: {DESCRIPTION}"

# ============================================
# EXAMPLE TEMPLATES
# ============================================
# With JIRA:
# [SWINNOTEAM-906] feat: add user profile page
# [SWINNOTEAM-906] fix: resolve login bug
#
# Without JIRA:
# feat: add user profile page
# fix: resolve login bug
