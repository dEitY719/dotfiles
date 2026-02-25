#!/usr/bin/env bash
# git/hooks/checks/pipe_loop_check.sh
#
# Detects anti-pattern: pipes after while/for loops with heredoc redirection
# Example violations:
#   done <<EOF | awk '{...}'
#   done <<EOF | grep '...'
#   done < file | sort
#
# Problem: The pipe creates a subshell that wraps the entire loop,
# breaking variable assignments and making 'set +x' ineffective.
# Variables assigned in the loop will still trace when set -x is enabled.
#
# Fix: Move piped commands inside the loop, or use a temporary variable.

check_pipe_loop_antipattern() {
    local abs_path="$1"
    local violations_file="$2"

    # Detect 'done <<...something... |' patterns directly
    # This catches: done <<EOF | awk, done <<EOF | grep, done < file | sort, etc.
    local matches
    matches=$(grep -nE 'done\s*<<.*\|' "$abs_path" 2>/dev/null || true)

    if [ -z "$matches" ]; then
        # Also try pattern: done < file | command (for input redirection + pipe)
        matches=$(grep -nE 'done\s*<[^<].*\|' "$abs_path" 2>/dev/null || true)
    fi

    if [ -n "$matches" ]; then
        while IFS= read -r line_info; do
            [ -z "$line_info" ] && continue
            local line_num
            line_num=$(echo "$line_info" | cut -d: -f1)
            local line_text
            line_text=$(echo "$line_info" | cut -d: -f2-)

            local pipe_cmd
            pipe_cmd=$(echo "$line_text" | sed 's/.*|\s*//')

            echo "$abs_path:$line_num: [ANTI-PATTERN] Loop with redirection followed by pipe: 'done ... | $pipe_cmd'
  Problem: Pipe creates subshell wrapping entire loop, breaks variable assignments and 'set +x'
  Fix: Move pipe inside loop, or use temporary variable/file
  Example: Instead of 'done <<EOF | awk', use counter inside loop and echo directly
  Reference: git/doc/ANTI_PATTERNS.md#pipe-based-loops" >>"$violations_file"
        done <<<"$matches"
        return 1
    fi

    return 0
}
