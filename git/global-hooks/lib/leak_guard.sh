#!/usr/bin/env bash
# git/global-hooks/lib/leak_guard.sh
#
# Leak guard activation + output redaction, shared by the global pre-commit
# hook (Layer 1, #2008) and the project hook's
# git/hooks/checks/leak_pattern_check.sh (#1970, #2002) — one implementation.
# Lives under global-hooks/ because the global hook runs in every repository
# on the machine and must not depend on files a repo may not ship; the
# project hook reaches it inside this same dotfiles checkout.
#
# Library only: defines functions, runs nothing. Variables (user-exported,
# SSOT: git/config/pre-push-rules.sh): UPSTREAM_REMOTES_ERE, LEAK_PATTERNS_ERE,
# SKIP_LEAK_GUARD.

# leak_guard_active — true only when ALL hold:
#   - SKIP_LEAK_GUARD is not 1
#   - LEAK_PATTERNS_ERE and UPSTREAM_REMOTES_ERE are non-empty
#   - some remote URL of this repo matches UPSTREAM_REMOTES_ERE
# The env checks come first, so an inactive PC never even runs `git config`.
leak_guard_active() {
    [ "${SKIP_LEAK_GUARD:-0}" = "1" ] && return 1
    [ -n "${LEAK_PATTERNS_ERE:-}" ] || return 1
    [ -n "${UPSTREAM_REMOTES_ERE:-}" ] || return 1
    git config --get-regexp '^remote\..*\.url$' 2>/dev/null \
        | cut -d' ' -f2- | grep -qE -- "${UPSTREAM_REMOTES_ERE}"
}

# leak_redact — stdin to stdout, every LEAK_PATTERNS_ERE match replaced by
# `<redacted>` (#2002). Bash's own ERE engine, so the pattern is never
# interpolated into a sed/awk program and needs no escaping; a match that
# is empty ends the loop instead of spinning.
leak_redact() {
    local line out m
    while IFS= read -r line || [ -n "$line" ]; do
        out=""
        while [[ $line =~ $LEAK_PATTERNS_ERE ]] && [ -n "${BASH_REMATCH[0]}" ]; do
            m=${BASH_REMATCH[0]}
            out+="${line%%"$m"*}<redacted>"
            line=${line#*"$m"}
        done
        printf '%s\n' "$out$line"
    done
}
