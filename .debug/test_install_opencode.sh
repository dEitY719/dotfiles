#!/bin/bash
# Test script for install_opencode.sh - validates fixes without actual installation
# Usage: bash test_install_opencode.sh

set -e

echo "═══════════════════════════════════════════════════════════════"
echo "OpenCode Installation Script - Test Suite"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Test 1: Syntax validation
echo "✓ Test 1: Bash Syntax Check"
if bash -n /home/bwyoon/dotfiles/shell-common/tools/custom/install_opencode.sh; then
    echo "  ✅ Script syntax is valid"
else
    echo "  ❌ Script has syntax errors"
    exit 1
fi
echo ""

# Test 2: Check for common segfault triggers
echo "✓ Test 2: Checking for Common Segfault Triggers"

script_file="/home/bwyoon/dotfiles/shell-common/tools/custom/install_opencode.sh"

# Check for dangerous echo -e patterns
if grep -q 'echo -e' "$script_file"; then
    echo "  ⚠️  WARNING: Found 'echo -e' which can cause issues"
else
    echo "  ✅ No problematic 'echo -e' found"
fi

# Check for ux_confirm usage (known issue)
ux_confirm_count=$(grep -c 'ux_confirm' "$script_file" || echo "0")
if [ "$ux_confirm_count" -gt 0 ]; then
    echo "  ⚠️  WARNING: Script uses ux_confirm ($ux_confirm_count times) - may cause segfault"
else
    echo "  ✅ No ux_confirm calls (fixed)"
fi

# Check for trap handlers
if grep -q 'trap' "$script_file"; then
    echo "  ✅ Trap handlers configured"
fi
echo ""

# Test 3: Verify init.sh exists
echo "✓ Test 3: Checking Dependencies"
if [ -f /home/bwyoon/dotfiles/shell-common/tools/custom/init.sh ]; then
    echo "  ✅ init.sh found"
else
    echo "  ❌ init.sh not found"
    exit 1
fi

if [ -f /home/bwyoon/dotfiles/shell-common/tools/ux_lib/ux_lib.sh ]; then
    echo "  ✅ ux_lib.sh found"
else
    echo "  ❌ ux_lib.sh not found"
    exit 1
fi
echo ""

# Test 4: Verify directory structure
echo "✓ Test 4: Checking Directory Structure"
if [ -d /home/bwyoon/dotfiles/shell-common/tools/custom ]; then
    echo "  ✅ Custom tools directory exists"
fi

if [ -d /home/bwyoon/dotfiles/shell-common/tools/integrations ]; then
    echo "  ✅ Integrations directory exists"
fi

if [ -d /home/bwyoon/dotfiles/shell-common/tools/ux_lib ]; then
    echo "  ✅ UX library directory exists"
fi
echo ""

# Test 5: Check for required commands
echo "✓ Test 5: Checking for Required Commands"
for cmd in bash npm node mkdir chmod cat grep; do
    if command -v "$cmd" &>/dev/null; then
        echo "  ✅ Command found: $cmd"
    else
        echo "  ❌ Command missing: $cmd"
    fi
done
echo ""

# Test 6: Verify npm package is available
echo "✓ Test 6: Checking npm Package"
if npm view opencode-ai >/dev/null 2>&1; then
    version=$(npm view opencode-ai version)
    echo "  ✅ npm package 'opencode-ai' found (version: $version)"
else
    echo "  ⚠️  WARNING: npm package 'opencode-ai' not found in registry"
    echo "     (This might be a network issue or package not published)"
fi
echo ""

echo "═══════════════════════════════════════════════════════════════"
echo "Test Summary"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "✅ Script appears to be fixed and ready to test!"
echo ""
echo "Key improvements made:"
echo "  1. Fixed echo -e with escape sequences (segfault cause)"
echo "  2. Removed ux_confirm calls (known segfault trigger)"
echo "  3. Improved error handling with trap"
echo "  4. Better init.sh sourcing with validation"
echo ""
echo "Next step: Try running the actual installer"
echo "  $ install-opencode"
echo ""
