#!/bin/sh
# shell-common/tools/claude.sh
# Claude Code CLI - setup, utilities, and workflow helpers
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# Installation Instructions
# ═══════════════════════════════════════════════════════════════

# Method 1: Global npm prefix (using ~/.npm-global)
# Recommended if you already have this directory from other npm packages
#
# 1) Install:
#    npm install -g @anthropic-ai/claude-code --prefix=$HOME/.npm-global
# 2) Ensure PATH is set (if not already):
#    export PATH="$HOME/.npm-global/bin:$PATH"
#
# Verify:
#    which claude && claude --version
#
#
# Method 2: Using nvm (Node Version Manager) - RECOMMENDED
# Cleaner approach: nvm manages Node.js and npm packages in your home directory
#
# 1) Install nvm:
#    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
#    source ~/.bashrc   # or ~/.zshrc
#
# 2) Install Node.js (e.g., version 20):
#    nvm install 20
#    nvm use 20
#
# 3) Install Claude Code:
#    npm install -g @anthropic-ai/claude-code
#
# Verify:
#    which claude && claude --version

# ═══════════════════════════════════════════════════════════════
# Mount management functions (loaded from shell-common/functions/mount.sh)
# ═══════════════════════════════════════════════════════════════

# Dependency Check: Ensure jq is installed
# ═══════════════════════════════════════════════════════════════

ensure_jq() {
    if command -v jq > /dev/null 2>&1; then
        # jq already installed - silent pass
        return 0
    else
        ux_warning "jq is not installed. Installing..."
        if command -v apt-get > /dev/null 2>&1; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v brew > /dev/null 2>&1; then
            brew install jq
        elif command -v yum > /dev/null 2>&1; then
            sudo yum install -y jq
        else
            ux_error "Cannot determine package manager. Please install jq manually."
            ux_bullet "Ubuntu/Debian: ${UX_BOLD}sudo apt-get install jq${UX_RESET}"
            ux_bullet "macOS: ${UX_BOLD}brew install jq${UX_RESET}"
            ux_bullet "CentOS/RHEL: ${UX_BOLD}sudo yum install jq${UX_RESET}"
            return 1
        fi

        if command -v jq > /dev/null 2>&1; then
            ux_success "jq installed successfully"
            jq --version
            return 0
        else
            ux_error "Failed to install jq"
            return 1
        fi
    fi
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

# Auto-mount skills and agents on shell startup (opt-in only).
# NOTE: Avoid side effects during shell init and during tests.
if [ "${DOTFILES_TEST_MODE:-0}" != "1" ] && [ "${CLAUDE_AUTO_MOUNT_SKILLS:-0}" = "1" ]; then
    claude_mount_skills >/dev/null 2>&1 || true
fi

if [ "${DOTFILES_TEST_MODE:-0}" != "1" ] && [ "${CLAUDE_AUTO_MOUNT_AGENTS:-0}" = "1" ]; then
    claude_mount_agents >/dev/null 2>&1 || true
fi

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

# Auto-mount docs on shell startup (opt-in only).
# NOTE: Avoid side effects during shell init and during tests.
if [ "${DOTFILES_TEST_MODE:-0}" != "1" ] && [ "${CLAUDE_AUTO_MOUNT_DOCS:-0}" = "1" ]; then
    claude_mount_docs >/dev/null 2>&1 || true
fi

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
