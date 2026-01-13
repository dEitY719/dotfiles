#!/bin/bash
# shell-common/functions/claude_help.sh
# claudeHelp - shared between bash and zsh

claude_help() {
    # Load UX library (unified library at shell-common/tools/ux_lib/)
    source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"

    ux_header "Claude Code - MCP & Workflow Guide"

    ux_section "MCP (Model Context Protocol) Commands"
    ux_table_row "claude mcp list" "List installed MCP servers" ""
    ux_table_row "claude mcp get <name>" "Show MCP server details" ""
    ux_table_row "claude mcp add <name> ..." "Add MCP server" ""
    ux_table_row "claude mcp remove <name>" "Remove MCP server" ""
    echo ""

    ux_section "Recommended MCP Servers"
    ux_bullet "Playwright MCP: Web browser automation"
    echo "  Install: ${UX_SUCCESS}claude mcp add playwright --transport stdio -- npx -y @playwright/mcp@latest${UX_RESET}"
    ux_bullet "Sequential Thinking MCP: Logical analysis"
    echo "  Install: ${UX_SUCCESS}claude mcp add sequential-thinking --transport stdio -- npx -y @modelcontextprotocol/server-sequential-thinking${UX_RESET}"
    echo ""

    ux_section "Setup & Requirements"
    ux_table_row "clinstall" "Install Claude Code CLI" ""
    ux_table_row "ensure_jq" "Install jq (required for statusline)" ""
    ux_table_row "claude_init" "Initialize config & skills" ""
    ux_table_row "claude_edit_settings" "Edit settings.json" ""
    echo ""

    ux_section "Workflow Patterns"
    ux_bullet "Plan mode (recommended): ${UX_SUCCESS}claude${UX_RESET} → plan → approve → execute"
    ux_bullet "Test workflow: ${UX_SUCCESS}cltest \"test description\"${UX_RESET}}"
    ux_bullet "Skip permissions (caution): ${UX_SUCCESS}clskip \"request\"${UX_RESET}"
    echo ""

    ux_section "Sandbox Mode"
    ux_info "Use in Claude conversation: ${UX_SUCCESS}/sandbox${UX_RESET}"
    ux_bullet "Select Auto-allow mode"
    ux_bullet "pytest, git, npm auto-approved"
    echo ""

    ux_section "Configuration"
    ux_info "Settings file: ${DOTFILES_ROOT:-$HOME/dotfiles}/claude/settings.json"
    ux_bullet "Sandbox: autoAllowBashIfSandboxed"
    ux_bullet "Auto-allow: pytest, ruff, mypy, tox"
    ux_bullet "Block: .env, ~/.aws, ~/.ssh"
    ux_bullet "Block commands: rm -rf, sudo rm"
    echo ""

    ux_section "Skills Management"
    ux_table_row "claude-skills" "List available Claude Code skills" ""
    ux_info "Skills location: ${DOTFILES_ROOT:-$HOME/dotfiles}/claude/skills/"
    echo ""
}

# Function to list Claude Code skills
get_claude_skills() {
    local skills_dir="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/skills"

    # Check if skills directory exists
    if [ ! -d "$skills_dir" ]; then
        echo "No skills directory found at: $skills_dir" >&2
        return 1
    fi

    # Load UX library if available
    if command -v ux_header >/dev/null 2>&1; then
        ux_header "Claude Code Skills"
        echo ""
    else
        echo "=== Claude Code Skills ==="
        echo ""
    fi

    # Track if any skills found
    local found_skills=0

    # Iterate through skill directories
    for skill_path in "$skills_dir"/*; do
        # Skip if not a directory
        [ -d "$skill_path" ] || continue

        local skill_name="$(basename "$skill_path")"
        local skill_md="$skill_path/SKILL.md"

        # Skip if SKILL.md doesn't exist
        [ -f "$skill_md" ] || continue

        # Extract YAML content (between --- markers, excluding the markers)
        local yaml_content="$(sed -n '/^---$/,/^---$/p' "$skill_md" | sed '1d;$d')"

        # Extract name and description from YAML frontmatter
        local yaml_name="$(echo "$yaml_content" | grep '^name:' | head -1 | sed 's/^name: *//')"
        local yaml_desc="$(echo "$yaml_content" | grep '^description:' | head -1 | sed 's/^description: *//')"

        # Use directory name as fallback
        [ -n "$yaml_name" ] || yaml_name="$skill_name"
        [ -n "$yaml_desc" ] || yaml_desc="(No description)"

        # Truncate description to 60 chars (more readable than 30)
        if [ ${#yaml_desc} -gt 60 ]; then
            yaml_desc="$(echo "$yaml_desc" | cut -c1-57)..."
        fi

        # Output formatted line
        printf "%-20s | %s\n" "$yaml_name" "$yaml_desc"

        found_skills=1
    done

    # If no skills found
    if [ "$found_skills" -eq 0 ]; then
        echo "No skills found in $skills_dir"
        return 0
    fi

    echo ""
    if command -v ux_info >/dev/null 2>&1; then
        ux_info "Skills location: $skills_dir"
    else
        echo "Skills location: $skills_dir"
    fi
}

# Alias for claude-help format (using dash instead of underscore)
alias claude-help='claude_help'
alias claude-skills='get_claude_skills'
