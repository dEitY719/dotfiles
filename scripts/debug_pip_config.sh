#!/bin/bash
# scripts/debug_pip_config.sh
# Comprehensive pip configuration diagnosis script.

set -e

usage() {
    cat <<'EOF'
Diagnose pip's configuration: env vars, config file locations, symlinks,
proxy state, and runtime version.

Usage:
  scripts/debug_pip_config.sh [-h|--help|help]

Options:
  -h, --help    Show this help and exit.

The script takes no positional arguments.
EOF
}

# Reject unknown / positional args; `--help` shortcuts straight to usage.
case "${1:-}" in
    "") ;;
    -h|--help|help) usage; exit 0 ;;
    *) printf 'Error: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
esac

# Best-effort source of the project ux_lib so output is consistent with the
# rest of dotfiles. Fall back to plain echo if ux_lib is not reachable
# (e.g. running this script outside the repo).
_SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_REPO_ROOT=$(cd "${_SCRIPT_DIR}/.." && pwd)
_UX_LIB="${_REPO_ROOT}/shell-common/tools/ux_lib/ux_lib.sh"
if [ -f "$_UX_LIB" ]; then
    # shellcheck source=/dev/null
    . "$_UX_LIB"
else
    ux_header() { echo "=== $* ==="; }
    ux_section() { echo "-- $* --"; }
    ux_info() { echo "$*"; }
    ux_success() { echo "[OK] $*"; }
    ux_warning() { echo "[WARN] $*"; }
    ux_error() { echo "[ERROR] $*" >&2; }
    ux_bullet() { echo "  - $*"; }
fi
unset _SCRIPT_DIR _REPO_ROOT _UX_LIB

ux_header "PIP CONFIGURATION DEBUG REPORT"

ux_section "1. PIP ENVIRONMENT VARIABLES"
ux_bullet "PIP_CONFIG_FILE=${PIP_CONFIG_FILE:-<not set>}"

ux_section "2. PIP CONFIG FILES LOCATION & PRIORITY"
ux_info "Checking pip config file locations (in priority order):"

config_paths=(
    "$PIP_CONFIG_FILE"
    "$HOME/.pip/pip.conf"
    "$HOME/.config/pip/pip.conf"
    "/etc/pip/pip.conf"
    "/usr/local/etc/pip/pip.conf"
)

for i in "${!config_paths[@]}"; do
    path="${config_paths[$i]}"
    if [ -n "$path" ]; then
        if [ -f "$path" ]; then
            ux_success "[$((i+1))] EXISTS: $path"
        else
            ux_bullet "[$((i+1))] missing: $path"
        fi
    fi
done

ux_section "3. ACTUAL PIP CONFIG FILE CONTENTS"

if [ -f "$HOME/.pip/pip.conf" ]; then
    # shellcheck disable=SC2088 # tilde is a display label, not a literal path
    ux_info "~/.pip/pip.conf (LEGACY — may override ~/.config/pip/pip.conf)"
    cat "$HOME/.pip/pip.conf"
else
    # shellcheck disable=SC2088
    ux_success "~/.pip/pip.conf does NOT exist"
fi

if [ -f "$HOME/.config/pip/pip.conf" ]; then
    # shellcheck disable=SC2088
    ux_info "~/.config/pip/pip.conf (XDG — newer standard)"
    cat "$HOME/.config/pip/pip.conf"
else
    # shellcheck disable=SC2088
    ux_warning "~/.config/pip/pip.conf does NOT exist"
fi

ux_section "4. SYMLINK STATUS"
if [ -L "$HOME/.config/pip/pip.conf" ]; then
    target=$(readlink "$HOME/.config/pip/pip.conf")
    ux_success "Symlink exists: $HOME/.config/pip/pip.conf"
    ux_bullet "Target: $target"
    if [ -f "$target" ]; then
        ux_bullet "Target exists: YES"
    else
        ux_bullet "Target exists: NO"
    fi
else
    ux_warning "NOT a symlink: $HOME/.config/pip/pip.conf"
fi

ux_section "5. PIP CONFIG LIST (what pip actually uses)"
pip config list || ux_warning "pip config list failed"

ux_section "6. PIP DEBUG MODE (see which config file pip loads)"
ux_info "Running: pip config list --verbose"
pip config list --verbose 2>&1 | head -20 || true

ux_section "7. PIP SEARCH PATH TEST"
ux_info "Testing if pip can find packages in configured repo:"
pip search tox 2>&1 | head -20 || ux_warning "pip search command failed (may be expected)"

ux_section "8. PROXY & NETWORK"
ux_bullet "http_proxy=${http_proxy:-<not set>}"
ux_bullet "https_proxy=${https_proxy:-<not set>}"
ux_bullet "HTTP_PROXY=${HTTP_PROXY:-<not set>}"
ux_bullet "HTTPS_PROXY=${HTTPS_PROXY:-<not set>}"

ux_section "9. PYTHON & PIP VERSION"
python --version || ux_warning "python --version failed"
pip --version || ux_warning "pip --version failed"

ux_section "10. PYENV STATUS"
ux_bullet "PYENV_VERSION=${PYENV_VERSION:-<not set>}"
pyenv version 2>/dev/null || ux_warning "pyenv not available"

ux_header "END OF DEBUG REPORT"
ux_info "Next: pip config edit  # to fix any config mismatch surfaced above"
