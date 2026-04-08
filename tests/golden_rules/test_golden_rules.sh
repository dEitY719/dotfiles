#!/bin/bash
# tests/test_golden_rules.sh
# Validate golden rules compliance across the dotfiles project
# Run: bash tests/test_golden_rules.sh

DOTFILES_ROOT="${DOTFILES_ROOT:-.}"
failed=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

test_case() {
    local name="$1"
    local result="$2"

    if [ "$result" -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $name"
    else
        echo -e "${RED}✗${NC} $name"
        failed=$((failed + 1))
    fi
}

echo "════════════════════════════════════════════════════════════"
echo "GOLDEN RULES VALIDATION"
echo "════════════════════════════════════════════════════════════"
echo ""

# Rule 1: No hardcoded paths in main shell files
echo "Rule 1: No hardcoded paths (use \$HOME or env vars)"
for file in bash/main.bash zsh/main.zsh; do
    if grep -q "export PATH=/home" "$file" 2>/dev/null; then
        test_case "$file: no hardcoded paths" 1
    else
        test_case "$file: no hardcoded paths" 0
    fi
done
echo ""

# Rule 2: Direct-exec guards in custom tools
echo "Rule 2: Direct-exec guards in custom tools"
total=0
with_guard=0
without_guard=""
for file in shell-common/tools/custom/*.sh; do
    [ -f "$file" ] || continue
    # Skip init.sh — it IS the shared initializer, not a standalone tool
    [ "$(basename "$file")" = "init.sh" ] && continue
    total=$((total + 1))
    # Recognized guard patterns:
    #   BASH_SOURCE[0] = $0   — standard guard
    #   ${0##*/} = "name.sh"  — basename guard
    if grep -qE 'BASH_SOURCE\[0\].*[=]+.*\$\{?0\}?|"\$\{0##\*/\}"' "$file"; then
        with_guard=$((with_guard + 1))
    else
        without_guard="${without_guard}  $(basename "$file")\n"
    fi
done

if [ "$with_guard" -eq "$total" ]; then
    test_case "All $total custom tools have direct-exec guard" 0
else
    test_case "All custom tools have direct-exec guard ($with_guard/$total)" 1
    printf "$without_guard" | head -5
    remaining=$((total - with_guard - 5))
    [ "$remaining" -gt 0 ] && echo "  ... and $remaining more"
fi
echo ""

# Rule 3: No raw echo in shell-common functions (use ux_lib)
# Exclude:
#   - *_help.sh files: help content files use echo for structured text display
#   - blank-line separators: echo "" / echo ''
#   - file writes / pipes: echo ... > file, echo ... | cmd
#   - lines already using UX_* variables (ux_lib colors)
echo "Rule 3: Use ux_lib for output (no raw echo)"
raw_echo_files=0
for file in shell-common/functions/*.sh; do
    [ -f "$file" ] || continue
    # Skip help content files — they display structured text by design
    case "$(basename "$file")" in *_help.sh) continue ;; esac
    if grep "^    echo " "$file" 2>/dev/null \
        | grep -v -e 'echo ""' -e "echo ''" \
        | grep -v -e '> *\$' -e '> *"' -e '| ' \
        | grep -v 'UX_' \
        | grep -vq 'echo "  '; then
        raw_echo_files=$((raw_echo_files + 1))
    fi
done

if [ "$raw_echo_files" -eq 0 ]; then
    test_case "No raw echo in functions/" 0
else
    test_case "No raw echo in functions/ ($raw_echo_files files)" 1
fi
echo ""

# Rule 4: No emojis in code
echo "Rule 4: No emojis in source code"
emoji_files=0
for file in bash/main.bash zsh/main.zsh shell-common/util/*.sh shell-common/config/*; do
    [ -f "$file" ] || continue
    if grep -q "[😊-🙏🚀✨⭐]" "$file" 2>/dev/null; then
        emoji_files=$((emoji_files + 1))
    fi
done

if [ "$emoji_files" -eq 0 ]; then
    test_case "No emojis in source files" 0
else
    test_case "No emojis in source files ($emoji_files files)" 1
fi
echo ""

# Rule 5: No bash-specific variables without fallback in shell-common
echo "Rule 5: POSIX compliance in shell-common"
bashism_files=0
for file in shell-common/util/*.sh shell-common/config/*; do
    [ -f "$file" ] || continue
    # Skip if file already has POSIX shebang
    if grep -q "^#!/bin/sh$" "$file"; then
        if grep -q '\$\{BASH_' "$file" 2>/dev/null; then
            bashism_files=$((bashism_files + 1))
        fi
    fi
done

if [ "$bashism_files" -eq 0 ]; then
    test_case "POSIX compliance in shell-common" 0
else
    test_case "POSIX compliance in shell-common" 1
fi
echo ""

echo "════════════════════════════════════════════════════════════"
if [ "$failed" -eq 0 ]; then
    echo -e "${GREEN}All golden rules validated ✓${NC}"
    exit 0
else
    echo -e "${RED}$failed validation(s) failed${NC}"
    exit 1
fi
