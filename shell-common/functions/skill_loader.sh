#!/bin/sh
# shell-common/functions/skill_loader.sh
# Cross-CLI skill loader for Claude Code, Codex, Gemini, etc.
# Provides interactive and programmatic access to AI agent skills

_skill_loader() {
    # Load UX library (unified library at shell-common/tools/ux_lib/)
    source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"

    # Get skills directory
    local skills_dir="${CLAUDE_SKILLS_PATH:-${DOTFILES_ROOT:-$HOME/dotfiles}/claude/skills}"

    # Detect if output is piped or redirected (smart output mode)
    # If stdout is NOT a terminal (not -t 1), we're in a pipeline → quiet mode
    local is_interactive=true
    if [ ! -t 1 ]; then
        is_interactive=false
    fi

    # Show help if no arguments
    if [ -z "$1" ]; then
        ux_header "Skill Loader - Get AI Agent Skills"

        ux_section "Usage"
        ux_bullet "skill-loader <skill-name>: Get absolute path to skill file"
        ux_bullet "skill-loader --list: Show all available skills"
        ux_bullet "skill-loader --help: Show this help"

        ux_section "Examples"
        ux_bullet "skill-loader cli-dev"
        ux_bullet "skill-loader req-define"
        ux_bullet "skill-loader --list"

        ux_section "Cross-CLI Integration"
        ux_bullet "Claude Code: Use ${UX_SUCCESS}/skill <name>${UX_RESET} within Claude Code"
        ux_bullet "View skill content: ${UX_SUCCESS}cat \"\$(skill-loader req-define)\"${UX_RESET}"
        ux_bullet "Codex: ${UX_SUCCESS}codex -p \"\$(cat \"\$(skill-loader cli-dev)\")\"${UX_RESET}"
        ux_bullet "Gemini: ${UX_SUCCESS}gemini -p @\"\$(skill-loader agents-md)\"${UX_RESET}"

        ux_section "Environment"
        ux_info "Skills path: $skills_dir"

        return 0
    fi

    # Handle --list flag
    if [ "$1" = "--list" ]; then
        get_claude_skills
        return 0
    fi

    # Handle --help flag
    if [ "$1" = "--help" ]; then
        _skill_loader  # Call with no args to show help
        return 0
    fi

    # Validate skills directory exists
    if [ ! -d "$skills_dir" ]; then
        ux_error "Skills directory not found: $skills_dir"
        return 1
    fi

    # Validate skill name is not empty
    if [ -z "$1" ]; then
        ux_error "Skill name required"
        return 1
    fi

    local skill_name="$1"
    local skill_file="$skills_dir/$skill_name/SKILL.md"

    # Check if skill file exists
    if [ ! -f "$skill_file" ]; then
        ux_error "Skill not found: $skill_name"
        ux_info "Use 'skill-loader --list' to see available skills"
        return 1
    fi

    # Output skill file path (always to stdout)
    printf '%s\n' "$skill_file"

    # Show context-aware message only in interactive mode (not piped/redirected)
    if [ "$is_interactive" = true ]; then
        # Detect CLI type using environment variables
        local cli_type="unknown"

        if [ -n "$CLAUDECODE" ] || [ -n "$CLAUDE_CODE_ENTRYPOINT" ]; then
            cli_type="claude-code"
        elif [ -n "$CODEX_CLI" ] || [ -n "$CODEX_MANAGED_BY_NPM" ]; then
            cli_type="codex"
        elif [ -n "$GEMINI_CLI" ]; then
            cli_type="gemini"
        elif command -v claude >/dev/null 2>&1; then
            cli_type="claude-code"
        fi

        # Show helpful message for Claude Code (interactive mode only)
        if [ "$cli_type" = "claude-code" ]; then
            printf '\n' >&2
            ux_info "To load this skill in Claude Code, use:" >&2
            ux_success "/skill $skill_name" >&2
        fi
    fi

    return 0
}

# Alias for skill-loader format (using dash instead of underscore)
alias skill-loader='_skill_loader'
