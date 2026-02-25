#!/usr/bin/env bash
# git/hooks/checks/zsh_emulation_check.sh
#
# Detects shell scripts that may have zsh-specific behavior issues.
# Flags shell functions that use bash/zsh extensions without POSIX compatibility.
#
# Key issues:
# 1. Functions that use debug tracing (set -x) but don't account for zsh's
#    stricter variable assignment tracing
# 2. Missing 'emulate -L sh' for zsh compatibility
# 3. POSIX sh shebang but bash-only features used

check_zsh_emulation_issues() {
    local abs_path="$1"
    local violations_file="$2"

    local has_issues=0

    # Check 1: Functions using set +x without emulate -L sh in zsh code
    # (only flag if it's a function file, not a simple script)
    if grep -q "^[a-z_][a-z0-9_]*() {" "$abs_path" 2>/dev/null; then

        # If function uses 'set -x' or 'set +x' but no 'emulate -L sh'
        if grep -q "set +x\|set -x" "$abs_path" 2>/dev/null && \
           ! grep -q "emulate -L sh" "$abs_path" 2>/dev/null; then

            # Warning: may have zsh tracing issues
            # (Only a suggestion, not a blocking error since many scripts work fine)
            echo "$abs_path: [INFO] Function uses debug tracing but no zsh emulation
  Consider adding 'emulate -L sh' at function start if testing in zsh shows
  variable assignment traces appearing in output even with 'set +x'
  Reference: git/doc/ANTI_PATTERNS.md#zsh-set-x-behavior" >>"$violations_file"
            has_issues=1
        fi
    fi

    [ $has_issues -eq 0 ] && return 0
    return 1
}
