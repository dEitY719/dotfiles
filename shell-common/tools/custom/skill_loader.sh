#!/bin/sh
# shell-common/tools/custom/skill_loader.sh
# Standalone skill loader utility for programmatic access
# Works with Claude Code, Codex, Gemini, and other CLIs
# Usage: skill_loader.sh <skill-name> | skill_loader.sh --list

set -e

# Initialize environment
source "$(dirname "$0")/init.sh" || exit 1

main() {
    # Get skills directory (fallback if not set globally)
    local skills_dir="${CLAUDE_SKILLS_PATH:-${DOTFILES_ROOT}/claude/skills}"

    # Show help if no arguments
    if [ -z "$1" ]; then
        ux_header "Skill Loader Utility"

        ux_section "Usage"
        ux_bullet "./skill_loader.sh <skill-name>: Output absolute path to skill file"
        ux_bullet "./skill_loader.sh --list: Show all available skills"
        ux_bullet "./skill_loader.sh --help: Show this help"

        ux_section "Examples"
        ux_bullet "SKILL=\$(./skill_loader.sh cli-dev) && echo \$SKILL"
        ux_bullet "./skill_loader.sh --list | head -10"
        ux_bullet "cat \"\$(./skill_loader.sh req-define)\""

        ux_section "Programmatic Usage"
        ux_info "Output to stdout only (no messages)"
        ux_bullet "stdout: Absolute path to SKILL.md file"
        ux_bullet "stderr: Error messages and help text"

        ux_section "Environment"
        ux_info "Skills path: $skills_dir"

        return 0
    fi

    # Handle --list flag
    if [ "$1" = "--list" ]; then
        list_skills "$skills_dir"
        return 0
    fi

    # Handle --help flag
    if [ "$1" = "--help" ]; then
        main  # Call with no args to show help
        return 0
    fi

    # Validate skills directory exists
    if [ ! -d "$skills_dir" ]; then
        ux_error "Skills directory not found: $skills_dir" >&2
        return 1
    fi

    # Validate skill name is not empty
    if [ -z "$1" ]; then
        ux_error "Skill name required" >&2
        return 1
    fi

    local skill_name="$1"
    local skill_file="$skills_dir/$skill_name/SKILL.md"

    # Check if skill file exists
    if [ ! -f "$skill_file" ]; then
        ux_error "Skill not found: $skill_name" >&2
        ux_info "Use '$(basename "$0") --list' to see available skills" >&2
        return 1
    fi

    # Output path only to stdout (programmatic usage)
    echo "$skill_file"
    return 0
}

# List all available skills with descriptions
list_skills() {
    local skills_dir="$1"

    # Check if skills directory exists
    if [ ! -d "$skills_dir" ]; then
        ux_error "No skills directory found at: $skills_dir" >&2
        return 1
    fi

    ux_header "Available Claude Code Skills"

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

        # Truncate description to 60 chars for readability
        if [ ${#yaml_desc} -gt 60 ]; then
            yaml_desc="$(echo "$yaml_desc" | cut -c1-57)..."
        fi

        # Output formatted line
        printf "%-20s | %s\n" "$yaml_name" "$yaml_desc"

        found_skills=1
    done

    # If no skills found
    if [ "$found_skills" -eq 0 ]; then
        ux_info "No skills found in $skills_dir" >&2
        return 0
    fi

    ux_info "Skills location: $skills_dir" >&2
}

# Only run main() if script is executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "${BASH_SOURCE[0]}" ]; then
    main "$@"
fi
