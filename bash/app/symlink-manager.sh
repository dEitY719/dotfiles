#!/bin/bash
# Symbolic Link Manager for Dotfiles
# Manages all symlinks defined in bash/config/symlinks.conf

set -u

DOTFILES_ROOT="${DOTFILES_ROOT:-${HOME}/dotfiles}"
SYMLINKS_CONF="${DOTFILES_ROOT}/bash/config/symlinks.conf"

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

    echo "$target|$source|$description"
}

# ═══════════════════════════════════════════════════════════════════════════
# Main Functions
# ═══════════════════════════════════════════════════════════════════════════

# Initialize all symlinks
symlink_init() {
    echo "=== Initializing Dotfiles Symlinks ==="
    echo ""

    if [[ ! -f "$SYMLINKS_CONF" ]]; then
        echo "Error: Configuration file not found: $SYMLINKS_CONF"
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
        echo "[${count}] $description"
        echo "    Target: $target"
        echo "    Source: $source"

        # Create parent directory if needed
        local target_dir
        target_dir=$(dirname "$target")
        if [[ ! -d "$target_dir" ]]; then
            echo "    Creating directory: $target_dir"
            mkdir -p "$target_dir"
        fi

        # Handle existing file/symlink
        if [[ -L "$target" ]]; then
            local current_target
            current_target=$(readlink "$target")
            if [[ "$current_target" == "$source" ]]; then
                echo "    ✓ Symlink already correct"
                ((success++))
            else
                echo "    ⚠ Updating symlink (was: $current_target)"
                rm "$target"
                ln -s "$source" "$target"
                ((success++))
            fi
        elif [[ -f "$target" ]]; then
            echo "    ⚠ File exists, backing up to ${target}.backup"
            mv "$target" "${target}.backup"
            ln -s "$source" "$target"
            ((success++))
        elif [[ -e "$target" ]]; then
            echo "    ✗ Path exists but is not a regular file or symlink"
        else
            echo "    Creating symlink..."
            ln -s "$source" "$target"
            ((success++))
        fi

        # Verify
        if [[ -L "$target" ]] && [[ -e "$target" ]]; then
            echo "    ✓ Verified: $(ls -la "$target" | awk '{print $(NF-1), $NF}')"
        else
            echo "    ✗ Verification failed"
        fi
        echo ""

    done < "$SYMLINKS_CONF"

    echo "=== Summary ==="
    echo "Total symlinks: $count"
    echo "Initialized: $success"
    echo ""
}

# Check symlink status
symlink_check() {
    echo "=== Checking Dotfiles Symlinks Status ==="
    echo ""

    if [[ ! -f "$SYMLINKS_CONF" ]]; then
        echo "Error: Configuration file not found: $SYMLINKS_CONF"
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
                echo "[✓] $description"
                echo "    Target: $target"
                echo "    → $(readlink "$target")"
                ((ok++))
            else
                echo "[✗] BROKEN: $description"
                echo "    Target: $target"
                echo "    → $(readlink "$target") (target not found)"
                ((broken++))
            fi
        elif [[ -f "$target" ]]; then
            echo "[!] NOT A SYMLINK: $description"
            echo "    Target: $target (regular file)"
            ((broken++))
        else
            echo "[?] MISSING: $description"
            echo "    Target: $target (not found)"
            ((broken++))
        fi
        echo ""

    done < "$SYMLINKS_CONF"

    echo "=== Summary ==="
    echo "Total configured: $count"
    echo "OK: $ok"
    echo "Issues: $((broken))"
    echo ""
}

# Show configuration
symlink_config() {
    echo "=== Dotfiles Symlinks Configuration ==="
    echo ""
    echo "Configuration file: $SYMLINKS_CONF"
    echo ""
    cat "$SYMLINKS_CONF"
    echo ""
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
  ~/dotfiles/bash/config/symlinks.conf

Example:
  symlink-manager init      # Set up all symlinks
  symlink-manager check     # Verify symlink status
EOF
            ;;
        *)
            echo "Unknown command: $command"
            echo "Run 'symlink-manager help' for usage"
            return 1
            ;;
    esac
}

# Direct execution
if [[ "${BASH_SOURCE[0]}" == "$0" ]] || [[ -z "${BASH_SOURCE[0]}" ]]; then
    main "$@"
fi
