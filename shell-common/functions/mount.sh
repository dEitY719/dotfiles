#!/bin/sh
# shell-common/functions/mount.sh
# Mount management functions following SOLID principles
# Single Responsibility: addmnt() mounts, show_mnt() displays status

# Load UX library if not already loaded (bash/zsh compatible)
if ! type ux_bullet >/dev/null 2>&1; then
    # Detect script directory in bash/zsh compatible way
    if [ -n "$ZSH_VERSION" ]; then
        _SCRIPT_DIR="${0:h}"
    else
        _SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    fi
    [ -f "$_SCRIPT_DIR/../tools/ux_lib/ux_lib.sh" ] && source "$_SCRIPT_DIR/../tools/ux_lib/ux_lib.sh" 2>/dev/null
fi

# Show comprehensive help for mount functions
# Single Responsibility: Only display mount module help information
mount_help() {
    if type ux_header >/dev/null 2>&1; then
        ux_header "Mount Management Commands"

        ux_section "Description"
        ux_info "Manage bind mounts for Claude environment (skills, agents, etc.)"
        echo ""

        ux_section "Available Commands"
        ux_bullet "addmnt <source> <target>    Create bind mount"
        ux_bullet "show_mnt [path]             Display mount status"
        ux_bullet "claude_mount_all            Mount all Claude directories (skills, agents, docs)"
        ux_bullet "mount_help                  Show this help message"
        echo ""

        ux_section "Quick Examples"
        ux_numbered 1 "Mount all Claude directories at once:"
        echo "  claude_mount_all"
        echo ""

        ux_numbered 2 "View all Claude mounts:"
        echo "  show_mnt"
        echo ""

        ux_numbered 3 "View specific mount:"
        echo "  show_mnt ~/.claude/skills"
        echo ""

        ux_numbered 4 "Add new bind mount:"
        echo "  addmnt ${DOTFILES_ROOT:-$HOME/dotfiles}/claude/agents ~/.claude/agents"
        echo ""

        ux_section "For More Information"
        ux_bullet "addmnt --help       Usage for addmnt command"
        ux_bullet "show_mnt --help     Usage for show_mnt command"
        echo ""

        ux_warning "Requires sudo for mount operations"
        ux_info "Configure sudoers for passwordless mounting in /etc/sudoers.d/"
        echo ""
    else
        cat << 'HELP'
Mount Management Commands

Description:
  Manage bind mounts for Claude environment

Available Commands:
  addmnt <source> <target>       Create bind mount
  show_mnt [path]                Display mount status
  claude_mount_all               Mount all Claude directories (skills, agents, docs)
  mount_help                     Show this help message

Examples:
  claude_mount_all                              Mount all Claude directories
  show_mnt                                      View all mounts
  show_mnt ~/.claude/skills                     View specific mount
  addmnt $DOTFILES_ROOT/claude/agents ~/.claude/agents  Add new mount

Notes:
  - Requires sudo for mount operations
  - Alias: show-mnt, mount-help
HELP
    fi
}

alias mount-help='mount_help'

# Validate that required command exists
# Single Responsibility: Check availability of a command
_check_command() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# Check if a path is mounted
# Single Responsibility: Only check if path is mounted
# Parameters:
#   $1: mount path to check (required)
# Returns: 0 if mounted, 1 if not mounted
_is_mounted() {
    local mount_path="$1"

    # Validate input
    if [ -z "$mount_path" ]; then
        return 1
    fi

    # Expand home directory if present
    mount_path="${mount_path/#\~/$HOME}"

    # Use findmnt if available (faster, more reliable)
    if _check_command findmnt; then
        findmnt "$mount_path" >/dev/null 2>&1
        return $?
    fi

    # Fallback to mount command
    mount | grep -q "on ${mount_path} " 2>/dev/null
    return $?
}

# Internal: Show help for addmnt function (use _addmnt_help_ prefix for internal functions)
_addmnt_help() {
    if type ux_header >/dev/null 2>&1; then
        ux_header "Mount Bind Usage"

        ux_section "Description"
        ux_info "Create a bind mount from source to target directory"
        echo ""

        ux_section "Usage"
        ux_bullet "addmnt <source> <target>"
        echo ""

        ux_section "Parameters"
        ux_bullet "source  - Source directory path (required, must exist)"
        ux_bullet "target  - Target mount point (required, created if missing)"
        echo ""

        ux_section "Examples"
        ux_bullet "addmnt ${DOTFILES_ROOT:-$HOME/dotfiles}/skills ~/.claude/skills"
        ux_bullet "addmnt ~/projects ~/.local/mounts/projects"
        echo ""

        ux_section "Notes"
        ux_warning "Requires sudo permissions (use sudoers for passwordless mount)"
        ux_info "Target directory is created automatically if it doesn't exist"
        echo ""
    else
        cat << 'HELP'
addmnt - Create bind mount

Usage: addmnt <source> <target>

Parameters:
  source   Source directory path (required, must exist)
  target   Target mount point (required, created if missing)

Examples:
  addmnt $DOTFILES_ROOT/skills ~/.claude/skills
  addmnt ~/projects ~/.local/mounts/projects

Notes:
  - Requires sudo permissions
  - Target directory is created automatically
HELP
    fi
}

# Mount source to target using bind option
# Single Responsibility: Only handle mounting operation
# Parameters:
#   $1: source path (required)
#   $2: target path (required)
# Returns: 0 on success, 1 on failure
addmnt() {
    local source="$1"
    local target="$2"

    # Show help if no arguments
    if [ -z "$source" ] || [ -z "$target" ]; then
        _addmnt_help
        return 1
    fi

    # Expand home directory if present
    source="${source/#\~/$HOME}"
    target="${target/#\~/$HOME}"

    # Check if source exists
    if [ ! -e "$source" ]; then
        if type ux_error >/dev/null 2>&1; then
            ux_error "Source path does not exist: $source"
        else
            echo "Error: Source path does not exist: $source" >&2
        fi
        return 1
    fi

    # Create target directory if it doesn't exist
    if [ ! -e "$target" ]; then
        mkdir -p "$target" || {
            if type ux_error >/dev/null 2>&1; then
                ux_error "Failed to create target directory: $target"
            else
                echo "Error: Failed to create target directory: $target" >&2
            fi
            return 1
        }
    fi

    # Check if already mounted
    if _is_mounted "$target"; then
        if type ux_info >/dev/null 2>&1; then
            ux_info "Target is already mounted: $target"
        else
            echo "Note: $target is already mounted" >&2
        fi
        return 0
    fi

    # Perform mount operation with sudo
    if sudo mount --bind "$source" "$target" 2>/dev/null; then
        if type ux_success >/dev/null 2>&1; then
            ux_success "Successfully mounted $source to $target"
        fi
        return 0
    else
        if type ux_error >/dev/null 2>&1; then
            ux_error "Failed to mount $source to $target"
        else
            echo "Error: Failed to mount $source to $target" >&2
        fi
        return 1
    fi
}

# Internal: Show help for show_mnt function
_show_mnt_help() {
    if type ux_header >/dev/null 2>&1; then
        ux_header "Mount Status Display"

        ux_section "Description"
        ux_info "Display mount status for Claude environment directories"
        echo ""

        ux_section "Usage"
        ux_bullet "show_mnt              Show all Claude mounts under ~/.claude"
        ux_bullet "show_mnt <path>       Show specific mount path status"
        echo ""

        ux_section "Examples"
        ux_bullet "show_mnt                           All Claude mounts"
        ux_bullet "show_mnt ~/.claude/skills          Skills directory mount"
        ux_bullet "show_mnt ~/.claude/agents          Agents directory mount"
        echo ""

        ux_section "Notes"
        ux_info "Requires findmnt or mount command to display mount information"
        echo ""
    else
        cat << 'HELP'
show_mnt - Display mount status

Usage: show_mnt [path]

Examples:
  show_mnt                          All Claude mounts
  show_mnt ~/.claude/skills         Specific mount status

Notes:
  - Requires findmnt or mount command
  - Alias: show-mnt
HELP
    fi
}

# Display mount status for Claude paths
# Single Responsibility: Only display mount information
# Parameters:
#   $1: mount path to check (optional, defaults to all ~/.claude mounts)
# Returns: 0 if mounted and displayed, 1 if command not available or error
show_mnt() {
    local mount_path="${1}"

    # Show help if requested with -h or --help
    if [ "$mount_path" = "-h" ] || [ "$mount_path" = "--help" ]; then
        _show_mnt_help
        return 0
    fi

    # Check if findmnt is available
    if ! _check_command findmnt; then
        if type ux_error >/dev/null 2>&1; then
            ux_error "findmnt or mount command not found"
        else
            echo "Error: findmnt or mount command not found" >&2
        fi
        return 1
    fi

    # Expand home directory if present
    if [ -n "$mount_path" ]; then
        mount_path="${mount_path/#\~/$HOME}"

        # Show single mount status with UX formatting
        if type ux_section >/dev/null 2>&1; then
            ux_section "Mount Status: $mount_path"
        else
            echo "Mount Status: $mount_path"
        fi

        # Display mount information with indentation
        findmnt "$mount_path" 2>/dev/null | sed 's/^/  /' || {
            if type ux_info >/dev/null 2>&1; then
                ux_info "Not mounted: $mount_path"
            else
                echo "  (not mounted)" >&2
            fi
            return 1
        }
    else
        # Show all Claude-related mounts under ~/.claude
        if type ux_section >/dev/null 2>&1; then
            ux_section "Claude Mount Locations"
        else
            echo "Claude Mount Locations:"
        fi

        # Get all mounts under ~/.claude and display them (list format + grep)
        local mounts
        mounts=$(findmnt -l 2>/dev/null | grep "$HOME/.claude")

        if [ -n "$mounts" ]; then
            echo "$mounts" | sed 's/^/  /'
            return 0
        else
            if type ux_info >/dev/null 2>&1; then
                ux_info "No mounts found under ~/.claude"
            else
                echo "  (no mounts under ~/.claude)" >&2
            fi
            return 1
        fi
    fi
}
alias show-mnt='show_mnt'

# Note: Functions are automatically exported in both bash and zsh
# No need for explicit export declarations in POSIX-compatible scripts
