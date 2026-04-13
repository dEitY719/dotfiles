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

# SSOT helpers for mount-help
_mount_help_summary() {
    ux_info "Usage: mount-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "description: manage bind mounts for Claude environment"
    ux_bullet_sub "commands: addmnt | show-mnt | claude-mount-all"
    ux_bullet_sub "info: per-command --help references"
    ux_bullet_sub "notes: sudo & sudoers configuration"
    ux_bullet_sub "details: mount-help <section>  (example: mount-help commands)"
}

_mount_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "description"
    ux_bullet_sub "commands"
    ux_bullet_sub "info"
    ux_bullet_sub "notes"
}

_mount_help_rows_description() {
    ux_info "Manage bind mounts for Claude environment (skills, agents, etc.)"
}

_mount_help_rows_commands() {
    ux_bullet "addmnt <source> <target>    Create bind mount"
    ux_bullet "show-mnt [path]             Display mount status"
    ux_bullet "claude-mount-all            Mount all Claude directories (skills, agents, docs)"
}

_mount_help_rows_info() {
    ux_bullet "addmnt --help       Usage for addmnt command"
    ux_bullet "show-mnt --help     Usage for show-mnt command"
}

_mount_help_rows_notes() {
    ux_warning "Requires sudo for mount operations"
    ux_info "Configure sudoers for passwordless mounting in /etc/sudoers.d/"
}

_mount_help_render_section() {
    ux_section "$1"
    "$2"
}

_mount_help_section_rows() {
    case "$1" in
        description|desc|about)
            _mount_help_rows_description
            ;;
        commands|cmds|cmd)
            _mount_help_rows_commands
            ;;
        info|more)
            _mount_help_rows_info
            ;;
        notes|note|sudo)
            _mount_help_rows_notes
            ;;
        *)
            ux_error "Unknown mount-help section: $1"
            ux_info "Try: mount-help --list"
            return 1
            ;;
    esac
}

_mount_help_full() {
    ux_header "Mount Management Commands"
    _mount_help_render_section "Description" _mount_help_rows_description
    _mount_help_render_section "Available Commands" _mount_help_rows_commands
    _mount_help_render_section "For More Information" _mount_help_rows_info
    _mount_help_render_section "Notes" _mount_help_rows_notes
}

# Show comprehensive help for mount functions
# Single Responsibility: Only display mount module help information
mount_help() {
    if ! type ux_header >/dev/null 2>&1; then
        cat << 'HELP'
Mount Management Commands

Description:
  Manage bind mounts for Claude environment

Available Commands:
  addmnt <source> <target>       Create bind mount
  show-mnt [path]                Display mount status
  claude-mount-all               Mount all Claude directories (skills, docs)

Notes:
  - Requires sudo for mount operations
  - addmnt --help, show-mnt --help for details
HELP
        return 0
    fi

    case "${1:-}" in
        ""|-h|--help|help)
            _mount_help_summary
            ;;
        --list|list|section|sections)
            _mount_help_list_sections
            ;;
        --all|all)
            _mount_help_full
            ;;
        *)
            _mount_help_section_rows "$1"
            ;;
    esac
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

# Internal: Show help for mount_add function (use _mount_add_help_ prefix for internal functions)
_mount_add_help() {
    if type ux_header >/dev/null 2>&1; then
        ux_header "Mount Bind Usage"

        ux_section "Description"
        ux_info "Create a bind mount from source to target directory"


        ux_section "Usage"
        ux_bullet "mount_add <source> <target>"


        ux_section "Parameters"
        ux_bullet "source  - Source directory path (required, must exist)"
        ux_bullet "target  - Target mount point (required, created if missing)"


        ux_section "Examples"
        ux_bullet "mount_add ${DOTFILES_ROOT:-$HOME/dotfiles}/skills ~/.claude/skills"
        ux_bullet "mount_add ~/projects ~/.local/mounts/projects"


        ux_section "Notes"
        ux_warning "Requires sudo permissions (use sudoers for passwordless mount)"
        ux_info "Target directory is created automatically if it doesn't exist"

    else
        cat << 'HELP'
mount_add - Create bind mount

Usage: mount_add <source> <target>

Parameters:
  source   Source directory path (required, must exist)
  target   Target mount point (required, created if missing)

Examples:
  mount_add $DOTFILES_ROOT/skills ~/.claude/skills
  mount_add ~/projects ~/.local/mounts/projects

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
mount_add() {
    local source="$1"
    local target="$2"

    # Show help if no arguments
    if [ -z "$source" ] || [ -z "$target" ]; then
        _mount_add_help
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

# Internal: Show help for mount_show function
_mount_show_help() {
    if type ux_header >/dev/null 2>&1; then
        ux_header "Mount Status Display"

        ux_section "Description"
        ux_info "Display mount status for Claude environment directories"


        ux_section "Usage"
        ux_bullet "mount_show              Show all Claude mounts under ~/.claude"
        ux_bullet "mount_show <path>       Show specific mount path status"


        ux_section "Examples"
        ux_bullet "mount_show                           All Claude mounts"
        ux_bullet "mount_show ~/.claude/skills          Skills directory mount"
        ux_bullet "mount_show ~/.claude/docs            Docs directory mount"


        ux_section "Notes"
        ux_info "Requires findmnt or mount command to display mount information"

    else
        cat << 'HELP'
mount_show - Display mount status

Usage: mount_show [path]

Examples:
  mount_show                          All Claude mounts
  mount_show ~/.claude/skills         Specific mount status

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
mount_show() {
    local mount_path="${1}"

    # Show help if requested with -h or --help
    if [ "$mount_path" = "-h" ] || [ "$mount_path" = "--help" ]; then
        _mount_show_help
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
                echo "(not mounted)" >&2
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
                ux_bullet "(no mounts under ~/.claude)" >&2
            fi
            return 1
        fi
    fi
}

# ============================================================================
# Backward Compatibility Aliases
# ============================================================================
alias mount-add='mount_add'
alias show-mnt='mount_show'

# Note: Functions are automatically exported in both bash and zsh
# No need for explicit export declarations in POSIX-compatible scripts
