#!/usr/bin/env bash
# git/hooks/checks/shellcheck_check.sh
# ShellCheck static analysis for shell scripts
#
# Detects:
# - Tilde expansion issues (SC2088)
# - Quoting problems
# - Variable expansion issues
# - Best practice violations

# check_shellcheck VIOLATIONS_FILE STAGED_FILES
# STAGED_FILES is an ARGUMENT (newline-separated repo-relative paths), never
# stdin (#2014: a here-string call silently checked nothing). Appends
# "<file>: <shellcheck line>" to VIOLATIONS_FILE and returns 1 when THIS call
# found something, so per-file callers count only their own file.
#
# Options mirror `mise run lint-sh` (mise.toml, the CI gate) so the hook is
# never stricter than CI (#2014):
# - bash/ and shell-common/ (CI scope): exactly CI's `-x -e SC1090,SC1091`.
# - anything else CI does not lint: `-S error` only (definite bugs, e.g.
#   SC2045), so touching an old script is not blocked by style debt.
# - zsh (*.zsh or a zsh shebang) is skipped: shellcheck cannot parse it
#   (SC1071) and CI does not lint it either.
check_shellcheck() {
    local shellcheck_violations_file="$1"
    local staged_files="$2"
    local before after file line
    local -a shellcheck_args

    # No shellcheck installed: pass. (Guarded here, not by an early `return`
    # at source time, which left the function undefined and made the
    # caller's `! check_shellcheck` count a 127 as a violation.)
    command -v shellcheck >/dev/null 2>&1 || return 0

    before=$(wc -l <"$shellcheck_violations_file" 2>/dev/null || echo 0)

    while IFS= read -r file; do
        [ -f "$file" ] || continue
        case "$file" in
            *.zsh) continue ;;
            *.sh | *.bash) ;;
            *) head -1 "$file" 2>/dev/null | grep -qE '^#!.*\b(bash|sh)\b' || continue ;;
        esac
        head -1 "$file" 2>/dev/null | grep -qE '^#!.*\bzsh\b' && continue

        case "$file" in
            bash/* | shell-common/*) shellcheck_args=(-x -e "SC1090,SC1091") ;;
            *) shellcheck_args=(-S error) ;;
        esac

        # Non-zero exit just means findings; the appended lines decide.
        shellcheck "${shellcheck_args[@]}" "$file" 2>&1 | grep -v '^$' |
            while IFS= read -r line; do
                printf '%s: %s\n' "$file" "$line"
            done >>"$shellcheck_violations_file"
    done <<<"$staged_files"

    after=$(wc -l <"$shellcheck_violations_file" 2>/dev/null || echo 0)
    [ "$after" -eq "$before" ]
}

# Run the check if this script is sourced
if [ -z "$_SHELLCHECK_CHECK_SOURCED" ]; then
    _SHELLCHECK_CHECK_SOURCED=1

    # Only run if we have violations file and staged files
    if [ -n "$SHELLCHECK_VIOLATIONS_FILE" ] && [ -n "$STAGED_FILES" ]; then
        check_shellcheck "$SHELLCHECK_VIOLATIONS_FILE" "$STAGED_FILES"
    fi
fi
