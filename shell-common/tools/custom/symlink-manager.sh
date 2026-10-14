#!/bin/bash
# Symbolic Link Manager for Dotfiles
# Manages all symlinks defined in shell-common/config/symlinks.conf

set -u

DOTFILES_ROOT="${DOTFILES_ROOT:-${HOME}/dotfiles}"
SYMLINKS_CONF="${SHELL_COMMON_ROOT:-${DOTFILES_ROOT}/shell-common}/config/symlinks.conf"
# shellcheck source=init.sh
. "$(dirname "${BASH_SOURCE[0]}")/init.sh" || exit 1
# Physical checkout path for ${DOTFILES_ROOT} in symlinks.conf — matches
# ssh/setup.sh, which links from its own `pwd -P` location.
_SYMLINK_ROOT="$(cd "$DOTFILES_ROOT" && pwd -P)"
# Idempotent link + latest-only backup lib (#2137, #2138).
: "${SHELL_COMMON:=${DOTFILES_ROOT}/shell-common}"
# shellcheck source=../../lib/setup/link.sh
. "${SHELL_COMMON}/lib/setup/link.sh" || exit 1

# ═══════════════════════════════════════════════════════════════════════════
# Helper Functions
# ═══════════════════════════════════════════════════════════════════════════

# Parse and expand symlink configuration
parse_symlink_entry() {
    local entry="$1"
    local target source description

    # Skip comments and empty lines
    [[ "$entry" =~ ^[[:space:]]*# ]] && return 1
    [[ -z "${entry// }" ]] && return 1

    # Parse: TARGET|SOURCE|DESCRIPTION
    target="${entry%%|*}"
    source="${entry#*|}"
    source="${source%%|*}"
    description="${entry##*|}"

    # Expand variables safely
    target="${target//\$\{HOME\}/$HOME}"
    source="${source//\$\{HOME\}/$HOME}"
    source="${source//\$\{DOTFILES_ROOT\}/$_SYMLINK_ROOT}"

    printf '%s\n' "$target|$source|$description"
}

# ═══════════════════════════════════════════════════════════════════════════
# Main Functions
# ═══════════════════════════════════════════════════════════════════════════

# Initialize all symlinks
symlink_init() {
    ux_header "Initializing Dotfiles Symlinks"

    if [[ ! -f "$SYMLINKS_CONF" ]]; then
        ux_error "Configuration file not found: $SYMLINKS_CONF"
        return 1
    fi

    local count=0
    local success=0

    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        local parsed
        parsed=$(parse_symlink_entry "$line")

        local target source description
        IFS='|' read -r target source description <<< "$parsed"

        ((count++))
        ux_info "[${count}] $description"
        ux_bullet_sub "Target: $target"
        ux_bullet_sub "Source: $source"

        # Same link -> no-op; real file -> <target>.original backup; a real
        # directory is refused (error), as before.
        if dotfiles_ensure_link "$source" "$target"; then
            ((success++))
        fi

        # Verify
        if [[ -L "$target" ]] && [[ -e "$target" ]]; then
            # shellcheck disable=SC2012  # ls -la on a single known file to read its symlink arrow
            ux_success "Verified: $(ls -la "$target" | awk '{print $(NF-1), $NF}')"
        else
            ux_error "Verification failed"
        fi
        ux_info ""

    done < "$SYMLINKS_CONF"

    ux_section "Summary"
    ux_table_row "Total symlinks" "$count"
    ux_table_row "Initialized" "$success"
}

# Check symlink status
symlink_check() {
    ux_header "Checking Dotfiles Symlinks Status"

    if [[ ! -f "$SYMLINKS_CONF" ]]; then
        ux_error "Configuration file not found: $SYMLINKS_CONF"
        return 1
    fi

    local count=0
    local ok=0
    local broken=0

    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        local parsed
        parsed=$(parse_symlink_entry "$line")

        local target source description
        IFS='|' read -r target source description <<< "$parsed"

        ((count++))

        if [[ -L "$target" ]]; then
            if [[ -e "$target" ]]; then
                ux_success "$description"
                ux_bullet_sub "Target: $target"
                ux_bullet_sub "-> $(readlink "$target")"
                ((ok++))
            else
                ux_error "BROKEN: $description"
                ux_bullet_sub "Target: $target"
                ux_bullet_sub "-> $(readlink "$target") (target not found)"
                ((broken++))
            fi
        elif [[ -f "$target" ]]; then
            ux_warning "NOT A SYMLINK: $description"
            ux_bullet_sub "Target: $target (regular file)"
            ((broken++))
        else
            ux_warning "MISSING: $description"
            ux_bullet_sub "Target: $target (not found)"
            ((broken++))
        fi
        ux_info ""

    done < "$SYMLINKS_CONF"

    ux_section "Summary"
    ux_table_row "Total configured" "$count"
    ux_table_row "OK" "$ok"
    ux_table_row "Issues" "$broken"
}

# Show configuration
symlink_config() {
    ux_header "Dotfiles Symlinks Configuration"
    ux_info "Configuration file: $SYMLINKS_CONF"
    ux_info ""
    cat "$SYMLINKS_CONF"
}

# ═══════════════════════════════════════════════════════════════════════════
# Main Entry Point
# ═══════════════════════════════════════════════════════════════════════════

main() {
    local command="${1:-help}"

    case "$command" in
        init)
            symlink_init
            ;;
        check)
            symlink_check
            ;;
        config)
            symlink_config
            ;;
        help|--help|-h)
            cat <<'EOF'
Symbolic Link Manager for Dotfiles

Usage: symlink-manager <command>

Commands:
  init      Initialize all configured symlinks
  check     Check status of all symlinks
  config    Show symlinks configuration
  help      Show this help message

Configuration:
  shell-common/config/symlinks.conf

Example:
  symlink-manager init      # Set up all symlinks
  symlink-manager check     # Verify symlink status
EOF
            ;;
        *)
            ux_error "Unknown command: $command"
            ux_info "Run 'symlink-manager help' for usage"
            return 1
            ;;
    esac
}

# Direct execution
if [[ "${BASH_SOURCE[0]}" == "$0" ]] || [[ -z "${BASH_SOURCE[0]}" ]]; then
    main "$@"
fi
