#!/bin/bash
# scripts/debug_pip_config.sh
# Comprehensive pip configuration diagnosis script
# Usage: ./scripts/debug_pip_config.sh

set -e

echo "════════════════════════════════════════════════════════════"
echo "PIP CONFIGURATION DEBUG REPORT"
echo "════════════════════════════════════════════════════════════"
echo ""

echo "📋 1. PIP ENVIRONMENT VARIABLES"
echo "─────────────────────────────────────────────────────────────"
echo "PIP_CONFIG_FILE=${PIP_CONFIG_FILE:-<not set>}"
echo ""

echo "📂 2. PIP CONFIG FILES LOCATION & PRIORITY"
echo "─────────────────────────────────────────────────────────────"
echo "Checking pip config file locations (in priority order):"
echo ""

# Priority order for pip config files
config_paths=(
    "$PIP_CONFIG_FILE"  # Environment variable override
    "$HOME/.pip/pip.conf"  # Legacy location
    "$HOME/.config/pip/pip.conf"  # XDG location (newer)
    "/etc/pip/pip.conf"  # System location
    "/usr/local/etc/pip/pip.conf"  # System location (alternative)
)

for i in "${!config_paths[@]}"; do
    path="${config_paths[$i]}"
    if [ -n "$path" ]; then
        if [ -f "$path" ]; then
            echo "✓ [$((i+1))] EXISTS: $path"
        else
            echo "  [$((i+1))] missing: $path"
        fi
    fi
done
echo ""

echo "📄 3. ACTUAL PIP CONFIG FILE CONTENTS"
echo "─────────────────────────────────────────────────────────────"

if [ -f "$HOME/.pip/pip.conf" ]; then
    echo "📌 ~/.pip/pip.conf (LEGACY - may override ~/.config/pip/pip.conf)"
    echo "───"
    cat "$HOME/.pip/pip.conf"
    echo ""
else
    echo "✓ ~/.pip/pip.conf does NOT exist"
    echo ""
fi

if [ -f "$HOME/.config/pip/pip.conf" ]; then
    echo "📌 ~/.config/pip/pip.conf (XDG - newer standard)"
    echo "───"
    cat "$HOME/.config/pip/pip.conf"
    echo ""
else
    echo "❌ ~/.config/pip/pip.conf does NOT exist"
    echo ""
fi

echo "🔗 4. SYMLINK STATUS"
echo "─────────────────────────────────────────────────────────────"
if [ -L "$HOME/.config/pip/pip.conf" ]; then
    target=$(readlink "$HOME/.config/pip/pip.conf")
    echo "✓ Symlink exists: $HOME/.config/pip/pip.conf"
    echo "  Target: $target"
    echo "  Target exists: $([ -f "$target" ] && echo 'YES' || echo 'NO')"
else
    echo "❌ NOT a symlink: $HOME/.config/pip/pip.conf"
fi
echo ""

echo "⚙️  5. PIP CONFIG LIST (what pip actually uses)"
echo "─────────────────────────────────────────────────────────────"
pip config list
echo ""

echo "🧪 6. PIP DEBUG MODE (see which config file pip loads)"
echo "─────────────────────────────────────────────────────────────"
echo "Running: pip config list --verbose"
echo ""
pip config list --verbose 2>&1 | head -20
echo ""

echo "🔍 7. PIP SEARCH PATH TEST"
echo "─────────────────────────────────────────────────────────────"
echo "Testing if pip can find packages in configured repo:"
pip search tox 2>&1 | head -20 || echo "⚠️  pip search command failed (may be expected)"
echo ""

echo "🌐 8. PROXY & NETWORK"
echo "─────────────────────────────────────────────────────────────"
echo "http_proxy=${http_proxy:-<not set>}"
echo "https_proxy=${https_proxy:-<not set>}"
echo "HTTP_PROXY=${HTTP_PROXY:-<not set>}"
echo "HTTPS_PROXY=${HTTPS_PROXY:-<not set>}"
echo ""

echo "📝 9. PYTHON & PIP VERSION"
echo "─────────────────────────────────────────────────────────────"
python --version
pip --version
echo ""

echo "💾 10. PYENV STATUS"
echo "─────────────────────────────────────────────────────────────"
echo "PYENV_VERSION=${PYENV_VERSION:-<not set>}"
pyenv version
echo ""

echo "════════════════════════════════════════════════════════════"
echo "END OF DEBUG REPORT"
echo "════════════════════════════════════════════════════════════"
