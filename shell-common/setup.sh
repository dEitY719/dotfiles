#!/bin/sh
# shell-common/setup.sh
# Environment-specific configuration setup for shell-common

set -e

# Get the directory where this script is located (sh-compatible)
SHELL_COMMON_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_ROOT="$(cd "$SHELL_COMMON_DIR/.." && pwd)"

# Source UX library for consistent output styling (sh-compatible: use . instead of source)
if [ -f "${SHELL_COMMON_DIR}/tools/ux_lib/ux_lib.sh" ]; then
    . "${SHELL_COMMON_DIR}/tools/ux_lib/ux_lib.sh"
else
    # Fallback: define basic functions if ux_lib is not available
    ux_header() { echo "=== $1 ==="; }
    ux_section() { echo ""; echo "$1"; }
    ux_success() { echo "✓ $1"; }
    ux_info() { echo "ℹ $1"; }
    ux_error() { echo "✗ $1" >&2; }
fi

# Idempotent link lib (#2137, #2138); also loads dotfiles_backup.sh, the
# latest-only backup SSOT (#806) for DOTFILES_BACKUP_SUFFIX.
SHELL_COMMON="${SHELL_COMMON_DIR}"
. "${SHELL_COMMON_DIR}/lib/setup/link.sh" || exit 1
# dotfiles_setup_mode_resolve: canonical mode from --mode / env (#2137).
. "${SHELL_COMMON_DIR}/lib/setup/mode.sh" || exit 1

# ============================================================================
# Configuration Values (SSOT - Single Source of Truth)
# ============================================================================
# These are extracted settings values for maintainability
# If values change, update only here (not in sed patterns)
# Note: Using sh-compatible variable naming (no associative arrays)

# Security configuration: the CA / SSL certificate paths are NOT kept here.
# Their SSOT is env/security.local.sh (gitignored; template
# env/security.local.example carries placeholders only, #1969) — read back
# via _local_value (setup.d/local_files.sh), the same way tools/custom/setup_crt.sh does.

# Placeholder marker of the tracked *.local.example templates (#1944/#1969):
# fake hosts end in `.example.invalid`, fake cert files are `example-*.crt`;
# non-domain fakes (SSH key name, usage id, review model id) are listed one by
# one — keep in sync with the templates (#2021).
LOCAL_PLACEHOLDER_ERE='example\.invalid|/example-[a-z-]*\.crt|id_rsa_example|"EMP00000"|EXAMPLEPROXYCAFINGERPRINT|example-corp/example-model'

# Registry/tool configs applied in every mode, in this order. Adding a manager
# = `{dir}/{config}.internal` + `setup_<name>_config <mode>` in setup.d/ + one
# word here (#2140).
SETUP_REGISTRY_TOOLS="npm bun opencode pip uv cargo nuget rpm apt"

# SRP fragments (#2140): sourced only from here, never auto-sourced.
for _setup_frag in local_files account_prompts registry_configs system_repos; do
    . "${SHELL_COMMON_DIR}/setup.d/${_setup_frag}.sh" || exit 1
done
unset _setup_frag

# ============================================================================
# Main
# ============================================================================

# Interactive menu (no --mode and no DOTFILES_SETUP_MODE): prints the mode.
_setup_menu_mode() {
    {
        echo ""
        ux_header "Shell-Common Environment Setup"
        echo ""
        echo "Select your environment:"
        echo ""
        echo "1) Public PC (home environment)"
        echo "2) Internal company PC (direct connection)"
        echo "3) External company PC (VPN)"
        echo ""
        printf "Enter your choice (1-3): "
    } >&2
    read -r _smm_choice || _smm_choice=""
    echo "" >&2
    case "$_smm_choice" in
        1) echo public ;;
        2) echo internal ;;
        3) echo external ;;
        *)
            ux_error "Invalid choice. Please run again and select 1, 2, or 3."
            return 1
            ;;
    esac
}

main() {
    # Mode source: --mode arg > DOTFILES_SETUP_MODE env > interactive menu
    # (#2140). Never the saved file: re-running must ask or be told.
    _setup_arg=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --mode)
                [ $# -ge 2 ] || { ux_error "--mode needs a value (public|internal|external)"; exit 2; }
                _setup_arg="$2" && shift
                ;;
            --mode=*) _setup_arg="${1#*=}" ;;
            -h | --help)
                ux_usage "shell-common/setup.sh" "[--mode public|internal|external]" "Environment-specific config (registries, .local.sh, CA)"
                return 0
                ;;
            *) ux_error "unknown option: $1"; exit 2 ;;
        esac
        shift
    done
    if [ -n "$_setup_arg" ]; then
        setup_mode=$(DOTFILES_SETUP_MODE="$_setup_arg" dotfiles_setup_mode_resolve) || exit 1
    elif [ -n "${DOTFILES_SETUP_MODE-}" ]; then
        setup_mode=$(dotfiles_setup_mode_resolve) || exit 1
    else
        setup_mode=$(_setup_menu_mode) || exit 1
    fi

    # Persist the symbolic mode right after it is known, before any step can
    # fail under `set -e`: a mid-run failure used to leave the OLD mode on
    # disk, so the next shell and setup run defaulted to the wrong
    # environment. Every step below re-runs on the next ./setup.sh, so writing
    # first keeps setup idempotent (util/setup_mode_read.sh reads it back).
    echo "$setup_mode" >"$HOME/.dotfiles-setup-mode"
    ux_info "Selected: $setup_mode"

    "_pre_${setup_mode}"
    for _setup_tool in $SETUP_REGISTRY_TOOLS; do
        "setup_${_setup_tool}_config" "$setup_mode"
    done

    echo ""
    ux_success "Setup complete for $setup_mode PC"
    ux_info "Setup mode saved to: ~/.dotfiles-setup-mode"
    if [ "$setup_mode" != public ]; then
        ux_section "IMPORTANT: Reload your shell to apply changes"
        ux_bullet "Option 1 (Current shell): source ~/.bashrc"
        ux_bullet "Option 2 (New shell): exec bash  or  exec zsh"
        ux_bullet "Verify: ssl-help  (or: echo \$SSL_CERT_FILE)"
    fi
}

# Direct-exec guard: only invoke main() when executed directly. When this
# script is sourced (e.g. by bats tests), `$0` reflects the parent shell
# instead of `setup.sh`, so the pattern below won't match and main() is
# skipped — letting tests call individual setup_* functions in isolation.
case "$0" in
    *setup.sh) main "$@" ;;
esac
