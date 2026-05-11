#!/bin/sh
# shell-common/functions/ghostty.sh
# Ghostty terminal configuration management

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# Internal: fallback shim so help / status messages still print when ux_lib
# has not been sourced yet (e.g. running under DOTFILES_FORCE_INIT=1 without
# the loader). The real ux_* functions take precedence when defined.
_ghostty_ux() {
    if type "$1" >/dev/null 2>&1; then
        "$@"
    else
        # printf format strings starting with `--` would be eaten as an end-of-
        # option marker, so route every variant through a single `%s\n` form.
        _ghostty_kind="$1"; shift
        case "$_ghostty_kind" in
            ux_header)  printf '%s\n' "=== $* ===" ;;
            ux_section) printf '%s\n' "-- $* --" ;;
            ux_success) printf '%s\n' "[OK] $*" ;;
            ux_error)   printf '%s\n' "[ERROR] $*" >&2 ;;
            ux_bullet)  printf '%s\n' "  - $*" ;;
            *)          printf '%s\n' "$*" ;;
        esac
        unset _ghostty_kind
    fi
}

_ghostty_help() {
    _ghostty_ux ux_header "ghostty configuration helpers"
    _ghostty_ux ux_section "Commands"
    _ghostty_ux ux_bullet "ghostty_init           Symlink dotfiles/ghostty/config -> ~/.config/ghostty/config"
    _ghostty_ux ux_bullet "ghostty_edit_config    Edit the dotfiles ghostty config (uses \$EDITOR)"
    _ghostty_ux ux_section "Examples"
    _ghostty_ux ux_bullet "ghostty_init"
    _ghostty_ux ux_bullet "ghostty_edit_config"
    _ghostty_ux ux_info "Next: ghostty-help config  # alias/topic help"
}

ghostty_init() {
    case "${1:-}" in
        -h|--help|help) _ghostty_help; return 0 ;;
    esac

    local source="${DOTFILES_ROOT:-$HOME/dotfiles}/ghostty/config"
    local target="$HOME/.config/ghostty/config"
    local target_dir
    target_dir="$(dirname "$target")"

    _ghostty_ux ux_header "Ghostty Init"
    _ghostty_ux ux_info "Initializing Ghostty configuration..."

    # Create directory if needed
    if [ ! -d "$target_dir" ]; then
        _ghostty_ux ux_info "Creating $target_dir directory..."
        mkdir -p "$target_dir"
    fi

    # Ghostty snap auto-generates an empty config.ghostty on first run;
    # remove it to avoid confusion with our managed config file.
    if [ -f "$target_dir/config.ghostty" ] && [ ! -s "$target_dir/config.ghostty" ]; then
        rm "$target_dir/config.ghostty"
        _ghostty_ux ux_info "Removed empty config.ghostty (auto-generated)"
    fi

    # Handle symbolic link (including dangling symlinks)
    if [ -L "$target" ]; then
        if [ -e "$target" ]; then
            _ghostty_ux ux_info "config symbolic link already exists"
        else
            _ghostty_ux ux_info "Removing dangling symbolic link..."
            rm -f "$target"
            ln -s "$source" "$target"
            _ghostty_ux ux_success "Created symbolic link for config"
        fi
    elif [ -f "$target" ]; then
        _ghostty_ux ux_info "config exists as regular file"
        _ghostty_ux ux_info "Backing up to config.backup..."
        mv "$target" "$target.backup"
        ln -s "$source" "$target"
        _ghostty_ux ux_success "Created symbolic link for config"
    else
        ln -s "$source" "$target"
        _ghostty_ux ux_success "Created symbolic link for config"
    fi

    _ghostty_ux ux_section "Summary"
    _ghostty_ux ux_bullet "Symlink: $target -> $source"
    _ghostty_ux ux_success "Ghostty configuration initialization complete"
    _ghostty_ux ux_info "Next: ghostty-help config  # or run \`ghostty_edit_config\` to tweak"
}

ghostty_edit_config() {
    case "${1:-}" in
        -h|--help|help) _ghostty_help; return 0 ;;
    esac

    local config_file="${DOTFILES_ROOT:-$HOME/dotfiles}/ghostty/config"

    if [ ! -f "$config_file" ]; then
        _ghostty_ux ux_error "Config file not found: $config_file"
        return 1
    fi

    _ghostty_ux ux_info "Editing Ghostty configuration..."
    _ghostty_ux ux_info "File: $config_file"

    ${EDITOR:-vim} "$config_file"

    _ghostty_ux ux_success "Configuration file edited"
    _ghostty_ux ux_info "Changes will take effect immediately (symlinked)"
}
