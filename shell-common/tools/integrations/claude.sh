#!/bin/sh
# shell-common/tools/claude.sh
# Claude Code CLI - setup, utilities, and workflow helpers
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# Claude Code Installation
# Reference: https://code.claude.com/docs/en/getting-started
# ═══════════════════════════════════════════════════════════════
#
# Use: clinstall (runs official native installer)
# Use: delete_claude (uninstall and clean)

# ═══════════════════════════════════════════════════════════════
# Mount management functions (loaded from shell-common/functions/mount.sh)
# ═══════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════
# Dependency Check: Ensure jq is installed
# ═══════════════════════════════════════════════════════════════

ensure_jq() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/ensure_jq.sh"
}

# NOTE: Do not auto-install dependencies at shell init time.
# If jq is required for a specific workflow, call `ensure_jq` explicitly.

# ═══════════════════════════════════════════════════════════════
# Claude Code Installation
# ═══════════════════════════════════════════════════════════════

clinstall() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_claude.sh"
}

# ═══════════════════════════════════════════════════════════════
# Claude Code Uninstallation
# ═══════════════════════════════════════════════════════════════

delete_claude() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/delete_claude.sh"
}

# ═══════════════════════════════════════════════════════════════
# Claude Code Configuration Initialization
# ═══════════════════════════════════════════════════════════════

claude_init() {
    local settings_source="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/settings.json"
    local settings_target="$HOME/.claude/settings.json"
    local statusline_source="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/statusline-command.sh"
    local statusline_target="$HOME/.claude/statusline-command.sh"
    local skills_source_dir="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/skills"
    local skills_target_dir="$HOME/.claude/skills"

    ux_info "Initializing Claude Code configuration..."
    echo ""

    # Create ~/.claude directory if not exists
    if [ ! -d "$HOME/.claude" ]; then
        ux_info "Creating ~/.claude directory..."
        mkdir -p "$HOME/.claude"
    fi

    # Create ~/.claude/skills directory if not exists
    if [ ! -d "$skills_target_dir" ]; then
        ux_info "Creating ~/.claude/skills directory..."
        mkdir -p "$skills_target_dir"
    fi

    # Handle settings.json
    ux_section "Settings Configuration"
    if [ -L "$settings_target" ]; then
        ux_success "settings.json symbolic link already exists"
    elif [ -f "$settings_target" ]; then
        ux_warning "settings.json exists as regular file"
        ux_info "Backing up to settings.json.backup..."
        mv "$settings_target" "$settings_target.backup"
        ln -s "$settings_source" "$settings_target"
        ux_success "Created symbolic link for settings.json"
    else
        ln -s "$settings_source" "$settings_target"
        ux_success "Created symbolic link for settings.json"
    fi
    echo ""

    # Handle statusline-command.sh
    ux_section "Statusline Configuration"
    if [ -L "$statusline_target" ]; then
        ux_success "statusline-command.sh symbolic link already exists"
    elif [ -f "$statusline_target" ]; then
        ux_warning "statusline-command.sh exists as regular file"
        ux_info "Backing up to statusline-command.sh.backup..."
        mv "$statusline_target" "$statusline_target.backup"
        ln -s "$statusline_source" "$statusline_target"
        ux_success "Created symbolic link for statusline-command.sh"
    else
        ln -s "$statusline_source" "$statusline_target"
        ux_success "Created symbolic link for statusline-command.sh"
    fi
    echo ""

    # Handle skills directory
    ux_section "Claude Code Skills"
    skill_count=0
    if [ -d "$skills_source_dir" ]; then
        for skill_file in "$skills_source_dir"/*.md; do
            if [ -f "$skill_file" ]; then
                skill_name=$(basename "$skill_file")
                skill_target="$skills_target_dir/$skill_name"

                if [ -L "$skill_target" ]; then
                    ux_success "$skill_name (already linked)"
                elif [ -f "$skill_target" ]; then
                    ux_warning "$skill_name exists as regular file"
                    ux_info "Backing up to $skill_name.backup..."
                    mv "$skill_target" "$skill_target.backup"
                    ln -s "$skill_file" "$skill_target"
                    ux_success "$skill_name (linked)"
                else
                    ln -s "$skill_file" "$skill_target"
                    ux_success "$skill_name (linked)"
                fi
                skill_count=$((skill_count + 1))
            fi
        done

        if [ "$skill_count" -eq 0 ]; then
            ux_info "No skill files found in $skills_source_dir"
        else
            ux_success "Total: $skill_count skill(s) linked"
        fi
    else
        ux_warning "Skills source directory not found: $skills_source_dir"
    fi
    echo ""

    ux_header "Claude Code Initialization Complete"
    echo ""

    ux_section "Configuration Files"
    for config_target in "$settings_target" "$statusline_target"; do
        if [ -e "$config_target" ]; then
            ls -la -- "$config_target"
        fi
    done
    echo ""

    ux_section "Skills"
    if [ -d "$skills_target_dir" ]; then
        linked_skill_found=0
        for skill_target_file in "$skills_target_dir"/*.md; do
            if [ -e "$skill_target_file" ]; then
                ls -la -- "$skill_target_file"
                linked_skill_found=1
            fi
        done
        if [ "$linked_skill_found" -eq 0 ]; then
            ux_info "(no skills found)"
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════
# Claude Code Settings Editor
# ═══════════════════════════════════════════════════════════════

claude_edit_settings() {
    local settings_file="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/settings.json"

    if [ ! -f "$settings_file" ]; then
        ux_error "Settings file not found: $settings_file"
        return 1
    fi

    ux_header "Claude Code Settings"
    ux_info "File: $settings_file"
    echo ""

    ${EDITOR:-vim} "$settings_file"

    echo ""
    ux_success "Settings file edited"
    ux_info "Changes will take effect immediately (settings.json is symlinked)"
}

# ═══════════════════════════════════════════════════════════════
# Claude Code Skills Directory Bind Mount
# ═══════════════════════════════════════════════════════════════

claude_mount_skills() {
    local skills_source="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/skills"
    local skills_target="$HOME/.claude/skills"

    # Check if source directory exists
    if [ ! -d "$skills_source" ]; then
        return 0
    fi

    # Create target directory if not exists
    if [ ! -d "$skills_target" ]; then
        mkdir -p "$skills_target"
    fi

    # Check if already mounted (using unified _is_mounted function if available)
    if declare -f _is_mounted >/dev/null 2>&1; then
        _is_mounted "$skills_target" && return 0
    else
        # Fallback: Check if already mounted using findmnt
        if command -v findmnt > /dev/null 2>&1; then
            findmnt "$skills_target" > /dev/null 2>&1 && return 0
        else
            # Final fallback to mount command
            mount | grep -q "${skills_target}" && return 0
        fi
    fi

    # Perform bind mount (will prompt for sudo password if needed)
    sudo mount --bind "$skills_source" "$skills_target" 2>/dev/null

    if [ $? -eq 0 ]; then
        return 0
    else
        # Silent fail - don't spam errors on every shell startup
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# Claude Code Agents Directory Bind Mount
# ═══════════════════════════════════════════════════════════════

claude_mount_agents() {
    local agents_source="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/agents"
    local agents_target="$HOME/.claude/agents"

    # Check if source directory exists
    if [ ! -d "$agents_source" ]; then
        return 0
    fi

    # Create target directory if not exists
    if [ ! -d "$agents_target" ]; then
        mkdir -p "$agents_target"
    fi

    # Check if already mounted (using unified _is_mounted function if available)
    if declare -f _is_mounted >/dev/null 2>&1; then
        _is_mounted "$agents_target" && return 0
    else
        # Fallback: Check if already mounted using findmnt
        if command -v findmnt > /dev/null 2>&1; then
            findmnt "$agents_target" > /dev/null 2>&1 && return 0
        else
            # Final fallback to mount command
            mount | grep -q "${agents_target}" && return 0
        fi
    fi

    # Perform bind mount (will prompt for sudo password if needed)
    sudo mount --bind "$agents_source" "$agents_target" 2>/dev/null

    if [ $? -eq 0 ]; then
        return 0
    else
        # Silent fail - don't spam errors on every shell startup
        return 1
    fi
}

# NOTE: Auto-mount functionality removed from shell init to prevent sudo prompts
# during shell startup. Use explicit functions instead:
#   claude_mount_skills   - Mount skills directory
#   claude_mount_agents   - Mount agents directory
#   claude_mount_docs     - Mount docs directory

# ═══════════════════════════════════════════════════════════════
# Claude Code Documentation Directory Bind Mount
# ═══════════════════════════════════════════════════════════════

claude_mount_docs() {
    local docs_source="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/docs"
    local docs_target="$HOME/.claude/docs"

    # Check if source directory exists
    if [ ! -d "$docs_source" ]; then
        return 0
    fi

    # Create target directory if not exists
    if [ ! -d "$docs_target" ]; then
        mkdir -p "$docs_target"
    fi

    # Check if already mounted (using unified _is_mounted function if available)
    if declare -f _is_mounted >/dev/null 2>&1; then
        _is_mounted "$docs_target" && return 0
    else
        # Fallback: Check if already mounted using findmnt
        if command -v findmnt > /dev/null 2>&1; then
            findmnt "$docs_target" > /dev/null 2>&1 && return 0
        else
            # Final fallback to mount command
            mount | grep -q "${docs_target}" && return 0
        fi
    fi

    # Perform bind mount (will prompt for sudo password if needed)
    sudo mount --bind "$docs_source" "$docs_target" 2>/dev/null

    if [ $? -eq 0 ]; then
        return 0
    else
        # Silent fail - don't spam errors on every shell startup
        return 1
    fi
}

# NOTE: Auto-mount functionality removed from shell init to prevent sudo prompts
# during shell startup. Use explicit function instead:
#   claude_mount_docs - Mount docs directory

# ═══════════════════════════════════════════════════════════════
# Claude Code Mount All Helper
# ═══════════════════════════════════════════════════════════════

# Mount all Claude directories at once (for manual initialization)
claude_mount_all() {
    ux_header "Claude Code Directory Mounts"

    local mounted_count=0
    local failed_count=0

    # Try mounting skills
    ux_info "Mounting skills directory..."
    if claude_mount_skills; then
        ux_success "skills directory mounted"
        mounted_count=$((mounted_count + 1))
    else
        ux_warning "skills directory mount failed or already mounted"
        failed_count=$((failed_count + 1))
    fi

    # Try mounting agents
    ux_info "Mounting agents directory..."
    if claude_mount_agents; then
        ux_success "agents directory mounted"
        mounted_count=$((mounted_count + 1))
    else
        ux_warning "agents directory mount failed or already mounted"
        failed_count=$((failed_count + 1))
    fi

    # Try mounting docs
    ux_info "Mounting docs directory..."
    if claude_mount_docs; then
        ux_success "docs directory mounted"
        mounted_count=$((mounted_count + 1))
    else
        ux_warning "docs directory mount failed or already mounted"
        failed_count=$((failed_count + 1))
    fi

    echo ""
    ux_section "Summary"
    echo "Successfully mounted: $mounted_count"
    echo "Failed or already mounted: $failed_count"
}

# ═══════════════════════════════════════════════════════════════
# Claude Code Marketplace Plugins Management
# ═══════════════════════════════════════════════════════════════

open_claude_plugins() {
    local plugins_dir="$HOME/.claude/plugins/marketplaces"

    if [ ! -d "$plugins_dir" ]; then
        ux_error "Plugins directory not found: $plugins_dir"
        ux_info "Plugins will be available after Claude Code marketplace setup"
        return 1
    fi

    ux_header "Opening Claude Marketplace Plugins"
    ux_info "Location: $plugins_dir"
    echo ""

    # Open in VSCode
    code "$plugins_dir"
}

# ═══════════════════════════════════════════════════════════════
# Claude Code Workflow Helpers
# ═══════════════════════════════════════════════════════════════

# Plan mode: Interactive mode (recommended)
alias clplan='claude'

# Test writing helper
cltest() {
    if [ -z "$1" ]; then
        ux_header "cltest"
        ux_usage "cltest" "\"request\"" "Run Claude with prompt for test writing"
        ux_bullet "Example: ${UX_INFO}cltest \"Write authentication tests\"${UX_RESET}"
        return 1
    fi
    claude -p "$1"
}

# Skip permissions mode (use with caution)
clskip() {
    if [ -z "$1" ]; then
        ux_header "clskip"
        ux_usage "clskip" "\"request\"" "Run Claude skipping permission prompts (caution)"
        ux_bullet "Example: ${UX_INFO}clskip \"Refactor this module\"${UX_RESET}"
        echo ""
        ux_warning "This will skip all permission prompts"
        ux_bullet "Start with small scopes and use carefully"
        return 1
    fi

    ux_warning "Running in skip permissions mode"
    ux_info "Request: $1"
    echo ""
    claude --dangerously-skip-permissions -p "$1"
}

# ═══════════════════════════════════════════════════════════════
# Claude Code Direct Permission Bypass Alias
# ═══════════════════════════════════════════════════════════════

alias claude-skip='claude --dangerously-skip-permissions'
alias claude-yolo='claude --dangerously-skip-permissions'
