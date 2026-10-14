#!/bin/bash
# Symbolic Link Manager for Dotfiles
# Manages all symlinks defined in shell-common/config/symlinks.conf

set -u

DOTFILES_ROOT="${DOTFILES_ROOT:-${HOME}/dotfiles}"
# shellcheck source=init.sh
. "$(dirname "${BASH_SOURCE[0]}")/init.sh" || exit 1
# After init.sh, which re-derives DOTFILES_ROOT from this script's checkout.
SYMLINKS_CONF="${SHELL_COMMON_ROOT:-${DOTFILES_ROOT}/shell-common}/config/symlinks.conf"
# Physical checkout path for ${DOTFILES_ROOT} in symlinks.conf, so a checkout
# reached through a symlink (~/dotfiles -> repo) links the same sources.
_SYMLINK_ROOT="$(cd "$DOTFILES_ROOT" && pwd -P)"
# Idempotent link + latest-only backup lib (#2137, #2138).
: "${SHELL_COMMON:=${DOTFILES_ROOT}/shell-common}"
# shellcheck source=../../lib/setup/link.sh
. "${SHELL_COMMON}/lib/setup/link.sh" || exit 1
# shellcheck source=../../lib/setup/mode.sh
. "${SHELL_COMMON}/lib/setup/mode.sh" || exit 1

# ═══════════════════════════════════════════════════════════════════════════
# Helper Functions
# ═══════════════════════════════════════════════════════════════════════════

# Parse and expand symlink configuration
# Format: TARGET|SOURCE|DESCRIPTION[|OPTS] — a 3-field row means no options.
parse_symlink_entry() {
    local entry="$1"
    local target source description opts

    # Skip comments and empty lines
    [[ "$entry" =~ ^[[:space:]]*# ]] && return 1
    [[ -z "${entry// }" ]] && return 1

    IFS='|' read -r target source description opts <<<"$entry"

    # Expand variables safely
    target="${target//\$\{HOME\}/$HOME}"
    source="${source//\$\{HOME\}/$HOME}"
    source="${source//\$\{DOTFILES_ROOT\}/$_SYMLINK_ROOT}"

    printf '%s\n' "$target|$source|$description|$opts"
}

# _symlink_opts_mode_ok <opts> <mode> — 0 unless opts carries mode=<csv> and
# <mode> is not in it. An unresolved mode ("") never matches a mode= list.
_symlink_opts_mode_ok() {
    local opt
    for opt in $1; do
        case "$opt" in
            mode=*) case ",${opt#mode=}," in *",$2,"*) ;; *) return 1 ;; esac ;;
        esac
    done
    return 0
}

# _symlink_opts_link_args <opts> — dotfiles_ensure_link flags, one per line.
# Unknown options are rejected so a typo in symlinks.conf is not silently ignored.
_symlink_opts_link_args() {
    local opt
    for opt in $1; do
        case "$opt" in
            mode=*) ;;
            on-mismatch=*) printf '%s\n' "--$opt" ;;
            allow-dir) printf '%s\n' --allow-dir ;;
            *)
                ux_error "symlinks.conf: unknown option: $opt"
                return 1
                ;;
        esac
    done
}

# ═══════════════════════════════════════════════════════════════════════════
# Main Functions
# ═══════════════════════════════════════════════════════════════════════════

# Initialize all symlinks
# symlink_init [--mode <m>] — non-interactive. A failing entry does not stop
# the rest; the return code is non-zero when any entry failed, so ./setup.sh's
# optional `symlinks` step reports it as a warning.
symlink_init() {
    ux_header "Initializing Dotfiles Symlinks"

    if [[ ! -f "$SYMLINKS_CONF" ]]; then
        ux_error "Configuration file not found: $SYMLINKS_CONF"
        return 1
    fi

    local mode
    mode=$(dotfiles_setup_mode_resolve "$@") || return 1

    local count=0 success=0 skipped=0 failed=0

    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        local parsed
        parsed=$(parse_symlink_entry "$line")

        local target source description opts
        IFS='|' read -r target source description opts <<< "$parsed"

        ((count++))
        ux_info "[${count}] $description"
        ux_bullet_sub "Target: $target"
        ux_bullet_sub "Source: $source"

        if ! _symlink_opts_mode_ok "$opts" "$mode"; then
            ux_info "skipped: not for setup mode '${mode:-unset}' ($opts)"
            ((skipped++))
            continue
        fi
        # A source outside the checkout (e.g. the playbook work log) is
        # per-PC content: absent means "not on this PC", not a failure.
        if [[ ! -e "$source" && "$source" != "$_SYMLINK_ROOT"/* ]]; then
            ux_info "skipped: source not on this PC"
            ((skipped++))
            continue
        fi

        local link_args
        if ! link_args=$(_symlink_opts_link_args "$opts"); then
            ((failed++))
            continue
        fi
        # Same link -> no-op; real file -> <target>.original backup; a real
        # directory is refused (error) unless allow-dir.
        # shellcheck disable=SC2086  # link_args is a newline list of plain flags
        if dotfiles_ensure_link "$source" "$target" $link_args; then
            ((success++))
        else
            ((failed++))
        fi
        ux_info ""

    done < "$SYMLINKS_CONF"

    ux_section "Summary"
    ux_table_row "Total symlinks" "$count"
    ux_table_row "Initialized" "$success"
    ux_table_row "Skipped" "$skipped"
    ux_table_row "Failed" "$failed"
    [ "$failed" -eq 0 ]
}

# Check symlink status
symlink_check() {
    ux_header "Checking Dotfiles Symlinks Status"

    if [[ ! -f "$SYMLINKS_CONF" ]]; then
        ux_error "Configuration file not found: $SYMLINKS_CONF"
        return 1
    fi

    local mode
    mode=$(dotfiles_setup_mode_resolve) || return 1

    local count=0
    local ok=0
    local broken=0

    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        local parsed
        parsed=$(parse_symlink_entry "$line")

        local target source description opts
        IFS='|' read -r target source description opts <<< "$parsed"

        # Rows init skips on purpose (other setup mode, per-PC source absent)
        # are not issues here either.
        _symlink_opts_mode_ok "$opts" "$mode" || continue
        [[ ! -e "$source" && "$source" != "$_SYMLINK_ROOT"/* && ! -L "$target" ]] && continue

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
            shift
            symlink_init "$@"
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
  init [--mode public|internal|external]
            Initialize all configured symlinks (non-interactive; a failing
            entry does not stop the rest, exit 1 if any failed)
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
