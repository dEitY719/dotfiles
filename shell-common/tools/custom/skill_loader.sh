#!/bin/bash
# shell-common/tools/custom/skill_loader.sh
# Cross-CLI skill loader for Claude Code, Codex, Gemini, etc.
# Provides interactive and programmatic access to AI agent skills.
#
# PATH executable since #2195 (~/.local/bin/skill-loader via config/symlinks.conf).
# shell-common/functions/skill_loader.sh is the thin wrapper that keeps the
# `skill_loader` function and `skill-loader` alias.
#
# Usage: skill-loader <skill-name> | skill-loader --list | skill-loader --help

# Resolve the symlink: ~/.local/bin/skill-loader -> this file, so init.sh is a sibling.
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/init.sh" || exit 1

main() {
    # Get skills directory
    local skills_dir="${CLAUDE_SKILLS_PATH:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills}"

    # Detect if output is piped or redirected (smart output mode)
    # If stdout is NOT a terminal (not -t 1), we're in a pipeline → quiet mode
    local is_interactive=true
    if [ ! -t 1 ]; then
        is_interactive=false
    fi

    # Show help when called with no arguments or an explicit help flag
    if [ -z "$1" ] || [ "$1" = "--help" ] || [ "$1" = "-h" ] || [ "$1" = "help" ]; then
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
        ux_bullet "Antigravity (agy): ${UX_SUCCESS}agy --print \"\$(cat \"\$(skill-loader agents-md)\")\"${UX_RESET}"

        ux_section "Environment"
        ux_info "Skills path: $skills_dir"

        return 0
    fi

    # Handle --list flag
    if [ "$1" = "--list" ]; then
        # shellcheck source=/dev/null
        DOTFILES_FORCE_INIT=1 . "${SHELL_COMMON}/functions/ai_tools_help.sh"
        get_claude_skills
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
        ux_info "Use 'skill-loader --list' to see available skills" >&2
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
        elif [ -n "$AGY_CLI" ]; then
            cli_type="agy"
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

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
