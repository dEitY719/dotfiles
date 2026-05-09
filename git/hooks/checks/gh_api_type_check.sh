#!/usr/bin/env bash
# git/hooks/checks/gh_api_type_check.sh
#
# Heuristic regression guard for `gh api graphql` -f/-F flag mapping.
# Issue #395 / design #384.
#
# `gh api graphql` accepts two flag flavors for binding GraphQL variables:
#   -f name=value  → raw String (use for String!, ID!)
#   -F name=value  → type inference; pure numeric → Int (use for Int!)
#
# Mismatch is silent: GraphQL returns 422, jq prints empty, the caller's
# best-effort path eats the failure. Recurring incidents (#384) motivated
# a static guard. Heuristic — false positives are tolerated; this check
# only WARNS, never blocks.
#
# Three signals:
#   1. -F with literal non-numeric value (e.g. -F id="PVTI_xxx").
#      $VAR references are not flagged (cannot tell at lint time whether
#      the var holds a number).
#   2. -f with literal all-digit value (likely Int! that should use -F).
#      $VAR references are not flagged (same reason).
#   3. `gh api graphql` block lacking a `# Variables: ...` annotation
#      within the preceding 5 lines. The convention establishes a single
#      place a reviewer can verify type contracts at a glance.
#
# Usage:
#   . git/hooks/checks/gh_api_type_check.sh
#   check_gh_api_type_mapping <abs_path> <warnings_file>
#
# Returns 0 on no findings, 1 on at least one finding (caller decides
# whether to surface as warning or hard fail). Pre-commit currently
# treats it as a warning per the design.

check_gh_api_type_mapping() {
    local abs_path="$1"
    local warnings_file="$2"
    local found=0

    [ -f "$abs_path" ] || return 0

    # Skip docs and meta-files (this check itself, the bats fixtures
    # that exercise it). Those files describe the convention or are
    # the test corpus, so they cite `gh api graphql` as prose, not as
    # caller code. An explicit opt-out marker lets future docs/tests
    # opt out without editing this list.
    case "$abs_path" in
        */docs/*) return 0 ;;
        */git/hooks/checks/gh_api_type_check.sh) return 0 ;;
        */tests/bats/lint/gh_api_type_mapping.bats) return 0 ;;
    esac
    if grep -q 'gh-api-type-check: skip-file' "$abs_path" 2>/dev/null; then
        return 0
    fi

    # Skip files that don't even mention `gh api graphql` — keeps the
    # check cheap on the bulk of staged files.
    grep -q 'gh api graphql' "$abs_path" 2>/dev/null || return 0

    # Signal 1: -F with literal non-numeric value.
    # Two patterns — double- and single-quoted forms. Single-quoted
    # added per PR #407 review (gemini): repos may use single quotes for
    # literal IDs since `$VAR` is meaningless inside single quotes
    # anyway. Both quote styles are flagged; unquoted forms are not —
    # the shellcheck linter enforces quoting independently.
    #
    # Each grep is run separately and the results merged. Keeping the
    # regexes split avoids the alternation-with-quote-escaping that
    # makes a combined POSIX BRE/ERE pattern unreadable.
    local matches sq dq sq2 dq2
    dq=$(grep -nE '\-F[[:space:]]+[A-Za-z_][A-Za-z0-9_]*="[^"$]*[A-Za-z_][^"]*"' "$abs_path" 2>/dev/null || true)
    sq=$(grep -nE "\-F[[:space:]]+[A-Za-z_][A-Za-z0-9_]*='[^']*[A-Za-z_][^']*'" "$abs_path" 2>/dev/null || true)
    matches=$(printf '%s\n%s\n' "$dq" "$sq" | grep -v '^$' || true)
    if [ -n "$matches" ]; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            printf '%s:%s [WARN] -F with literal non-numeric value — likely should be -f for String!/ID!\n' \
                "$abs_path" "$line" >>"$warnings_file"
            found=1
        done <<<"$matches"
    fi

    # Signal 2: -f with literal all-digit value.
    # Same dual-pattern approach as Signal 1.
    dq2=$(grep -nE '\-f[[:space:]]+[A-Za-z_][A-Za-z0-9_]*="[0-9]+"' "$abs_path" 2>/dev/null || true)
    sq2=$(grep -nE "\-f[[:space:]]+[A-Za-z_][A-Za-z0-9_]*='[0-9]+'" "$abs_path" 2>/dev/null || true)
    matches=$(printf '%s\n%s\n' "$dq2" "$sq2" | grep -v '^$' || true)
    if [ -n "$matches" ]; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            # Skip query= itself, which is naturally a multi-line string.
            case "$line" in
                *'-f query='*) continue ;;
            esac
            printf '%s:%s [WARN] -f with literal numeric value — likely should be -F for Int!\n' \
                "$abs_path" "$line" >>"$warnings_file"
            found=1
        done <<<"$matches"
    fi

    # Signal 3: `gh api graphql` block without preceding `Variables:`.
    # Look back up to 5 lines from each occurrence for the annotation.
    local line_no
    while IFS=: read -r line_no _; do
        [ -z "$line_no" ] && continue
        local start=$((line_no - 5))
        [ "$start" -lt 1 ] && start=1
        local window
        window=$(sed -n "${start},${line_no}p" "$abs_path" 2>/dev/null)
        case "$window" in
            *Variables:*) ;;
            *)
                # shellcheck disable=SC2016
                # The literal "$x Type!" is part of the convention message;
                # single quotes are intentional to prevent shell expansion.
                printf '%s:%s [WARN] gh api graphql call missing `# Variables: $x Type!, ...` annotation\n' \
                    "$abs_path" "$line_no" >>"$warnings_file"
                found=1
                ;;
        esac
    done < <(grep -nE 'gh api graphql' "$abs_path" 2>/dev/null || true)

    [ "$found" -eq 0 ] && return 0
    return 1
}
