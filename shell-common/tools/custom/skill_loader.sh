#!/bin/bash
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

# Extract skill name and description from YAML frontmatter.
# Outputs two lines: name then description.
extract_skill_field_fallback() {
    local skill_md="$1"
    local field="$2"

    awk -v field="$field" '
BEGIN { in_fm=0; capturing=0; value="" }
NR==1 && $0=="---" { in_fm=1; next }
in_fm && $0=="---" {
    if (capturing) {
        gsub(/[[:space:]]+/, " ", value)
        sub(/^ /, "", value)
        sub(/ $/, "", value)
        capturing = 0
        print value
    }
    exit
}
!in_fm { next }
capturing {
    if ($0 ~ /^[^[:space:]][^:]*:[[:space:]]*/) {
        gsub(/[[:space:]]+/, " ", value)
        sub(/^ /, "", value)
        sub(/ $/, "", value)
        capturing = 0
        print value
        exit
    }
    line=$0
    sub(/^[[:space:]]+/, "", line)
    if (line != "") {
        if (value != "") value = value " " line
        else value = line
    }
    next
}
{
    pattern = "^" field ":[[:space:]]*(.*)$"
    if (match($0, pattern, m)) {
        raw = m[1]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", raw)
        if (raw ~ /^[>|]/) {
            capturing = 1
            value = ""
            next
        }
        sub(/^"/, "", raw)
        sub(/"$/, "", raw)
        print raw
        exit
    }
}
END {
    if (capturing) {
        gsub(/[[:space:]]+/, " ", value)
        sub(/^ /, "", value)
        sub(/ $/, "", value)
        print value
    }
}
' "$skill_md" 2>/dev/null
}

extract_skill_metadata() {
    local skill_md="$1"
    local parsed=""

    # Prefer robust YAML parsing for multiline descriptions (>- and |)
    if command -v ruby >/dev/null 2>&1; then
        parsed="$(ruby -ryaml -e '
path = ARGV[0]
content = File.read(path)
match = content.match(/\A---\n(.*?)\n---\n/m)
exit 0 unless match
data = YAML.safe_load(match[1]) || {}
name = data["name"].to_s.gsub(/\s+/, " ").strip
desc = data["description"].to_s.gsub(/\s+/, " ").strip
puts name
puts desc
' "$skill_md" 2>/dev/null || true)"
    fi

    if [ -n "$parsed" ]; then
        printf '%s\n' "$parsed"
        return 0
    fi

    # Fallback for environments without ruby
    local fallback_name fallback_desc
    fallback_name="$(extract_skill_field_fallback "$skill_md" "name")"
    fallback_desc="$(extract_skill_field_fallback "$skill_md" "description")"
    printf '%s\n%s\n' "$fallback_name" "$fallback_desc"
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

        # Extract name and description from YAML frontmatter
        local metadata
        metadata="$(extract_skill_metadata "$skill_md")"
        local yaml_name
        yaml_name="$(printf '%s\n' "$metadata" | sed -n '1p')"
        local yaml_desc
        yaml_desc="$(printf '%s\n' "$metadata" | sed -n '2p')"

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

# Execute only if run directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "$0" ] || [ "${0##*/}" = "skill_loader.sh" ]; then
    main "$@"
fi
