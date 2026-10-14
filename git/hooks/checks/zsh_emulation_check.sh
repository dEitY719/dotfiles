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

        # If function uses 'set -x' or 'set +x' but neither 'emulate -L sh'
        # nor zsh's own 'unsetopt xtrace' (it already handles zsh tracing)
        if grep -q "set +x\|set -x" "$abs_path" 2>/dev/null &&
            ! grep -q "emulate -L sh\|unsetopt xtrace" "$abs_path" 2>/dev/null; then

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

# --- pre-commit registry adapter (contract: git/doc/CHECK_REGISTRY.md, #2143) ---
# per-shell-file: the runner only passes shell-common/functions/*.sh and
# shell-common/tools/integrations/*.sh paths that exist in the worktree.
CHECK_NAME=zsh_emulation
CHECK_SCOPE=per-shell-file
CHECK_SEVERITY=warning
CHECK_LABEL=INFO
CHECK_TITLE="Zsh compatibility suggestions"
CHECK_REPORT_LINES=2
check_run() { check_zsh_emulation_issues "$1/$3" "$4" 2>/dev/null; }
