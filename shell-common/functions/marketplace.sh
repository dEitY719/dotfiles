#!/bin/sh

# shell-common/functions/marketplace.sh
# Marketplace Skills Management System
# High-performance command system to manage 134 marketplace skills
# Uses cached manifest for instant access (0.1s vs 20s filesystem scan)

# =============================================================================
# Constants
# =============================================================================

MARKETPLACE_BASE_DIR="${HOME}/.claude/plugins/marketplaces"
MANIFEST_CACHE_PATH="${HOME}/.claude/plugins/marketplaces/.skills-manifest.json"
MANIFEST_CACHE_MAX_AGE=86400  # 24 hours

# =============================================================================
# UX Library Loading
# =============================================================================

if ! type ux_header >/dev/null 2>&1; then
    if [ -n "$ZSH_VERSION" ]; then
        _MARKETPLACE_DIR="${0:h}"
    else
        _MARKETPLACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    fi
    SHELL_COMMON="${_MARKETPLACE_DIR%/functions}"
    source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" 2>/dev/null || {
        echo "Error: Cannot load UX library" >&2
        return 1
    }
fi

# =============================================================================
# Internal Helper Functions (snake_case, prefixed with _)
# =============================================================================

# Check if manifest cache is stale
# Returns 0 if fresh, 1 if stale
_check_manifest_staleness() {
    [ ! -f "$MANIFEST_CACHE_PATH" ] && return 1  # Missing = stale

    # Check age (macOS vs Linux compatible)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        age=$(( $(date +%s) - $(stat -f %m "$MANIFEST_CACHE_PATH") ))
    else
        age=$(( $(date +%s) - $(stat -c %Y "$MANIFEST_CACHE_PATH") ))
    fi

    [ "$age" -gt "$MANIFEST_CACHE_MAX_AGE" ] && return 1  # Too old = stale
    return 0  # Fresh
}

# Count skills in all marketplaces
_count_all_skills() {
    find "$MARKETPLACE_BASE_DIR" -type f -name "SKILL.md" 2>/dev/null | wc -l
}

# Extract YAML frontmatter value
# Usage: _get_yaml_value "field_name" < file.md
_get_yaml_value() {
    local field="$1"
    sed -n '/^---$/,/^---$/p' | sed '1d;$d' | grep "^${field}:" | sed "s/^${field}: *//"
}

# Parse a single SKILL.md file and output JSON object
# Usage: _parse_skill_file "/path/to/skill/SKILL.md" "marketplace_name" "plugin_name"
_parse_skill_file() {
    local skill_file="$1"
    local marketplace_name="$2"
    local plugin_name="$3"

    if [ ! -f "$skill_file" ]; then
        return 1
    fi

    local skill_name
    local description
    local license

    skill_name=$(head -20 "$skill_file" | _get_yaml_value "name")
    description=$(head -20 "$skill_file" | _get_yaml_value "description")
    license=$(head -20 "$skill_file" | _get_yaml_value "license")

    # Extract category from plugin name (if available from directory structure)
    local category="${plugin_name}"

    # Output JSON object
    jq -n \
        --arg name "$skill_name" \
        --arg description "$description" \
        --arg license "$license" \
        --arg path "$skill_file" \
        --arg category "$category" \
        --arg marketplace "$marketplace_name" \
        --arg plugin "$plugin_name" \
        '{
            name: $name,
            description: $description,
            license: $license,
            path: $path,
            category: $category,
            marketplace: $marketplace,
            plugin: $plugin
        }'
}

# Generate manifest from filesystem scan
# This is computationally expensive, so only run when cache is stale
_generate_manifest() {
    local manifest_dir
    manifest_dir=$(dirname "$MANIFEST_CACHE_PATH")

    # Ensure directory exists
    mkdir -p "$manifest_dir"

    # Initialize manifest structure
    local skills_array="[]"
    local total_count=0

    # Scan anthropic-agent-skills (skills/ directory structure)
    local mp_path="${MARKETPLACE_BASE_DIR}/anthropic-agent-skills"
    if [ -d "${mp_path}/skills" ]; then
        while IFS= read -r skill_dir; do
            local skill_md="${skill_dir}/SKILL.md"
            if [ -f "$skill_md" ]; then
                local skill_obj
                skill_obj=$(_parse_skill_file "$skill_md" "anthropic-agent-skills" "$(basename "$skill_dir")")
                if [ -n "$skill_obj" ]; then
                    skills_array=$(echo "$skills_array" | jq --argjson obj "$skill_obj" '. += [$obj]')
                    ((total_count++))
                fi
            fi
        done < <(find "${mp_path}/skills" -maxdepth 1 -type d ! -name "skills")
    fi

    # Scan claude-code-workflows (plugins/*/skills/ directory structure)
    local ccw_path="${MARKETPLACE_BASE_DIR}/claude-code-workflows"
    if [ -d "${ccw_path}/plugins" ]; then
        while IFS= read -r plugin_dir; do
            local plugin_name
            plugin_name=$(basename "$plugin_dir")

            if [ -d "${plugin_dir}/skills" ]; then
                while IFS= read -r skill_dir; do
                    local skill_md="${skill_dir}/SKILL.md"
                    if [ -f "$skill_md" ]; then
                        local skill_obj
                        skill_obj=$(_parse_skill_file "$skill_md" "claude-code-workflows" "$plugin_name")
                        if [ -n "$skill_obj" ]; then
                            skills_array=$(echo "$skills_array" | jq --argjson obj "$skill_obj" '. += [$obj]')
                            ((total_count++))
                        fi
                    fi
                done < <(find "${plugin_dir}/skills" -maxdepth 1 -type d ! -name "skills")
            fi
        done < <(find "${ccw_path}/plugins" -maxdepth 1 -type d ! -name "plugins")
    fi

    # Build final manifest
    local manifest
    manifest=$(jq -n \
        --argjson skills "$skills_array" \
        --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg total_skills "$total_count" \
        '{
            version: "1.0",
            generated_at: $generated_at,
            total_skills: ($total_skills | tonumber),
            skills: $skills
        }')

    # Write to cache
    echo "$manifest" > "$MANIFEST_CACHE_PATH"
}

# Ensure manifest is fresh, regenerate if needed
_ensure_manifest_fresh() {
    if ! _check_manifest_staleness; then
        _generate_manifest
    fi
}

# =============================================================================
# User-Facing Functions (snake_case, suffixed with _marketplace)
# =============================================================================

# List all marketplace skills grouped by plugin (default) or all skills by marketplace (--all)
claude_skills_marketplace_list() {
    local show_all=false

    # Parse options
    while [ $# -gt 0 ]; do
        case "$1" in
            --all|-A)
                show_all=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    _ensure_manifest_fresh || {
        ux_error "Failed to generate marketplace manifest"
        return 1
    }

    # Verify manifest exists and is valid
    if [ ! -f "$MANIFEST_CACHE_PATH" ]; then
        ux_error "Manifest cache not found"
        return 1
    fi

    if ! jq empty "$MANIFEST_CACHE_PATH" 2>/dev/null; then
        ux_error "Manifest is corrupted, regenerating..."
        _generate_manifest
    fi

    if [ "$show_all" = true ]; then
        # Show all skills grouped by marketplace
        ux_header "All Marketplace Skills"

        local total
        total=$(jq -r '.total_skills' "$MANIFEST_CACHE_PATH")
        ux_info "Total: $total skills"
        echo ""

        # Group by marketplace
        jq -r '.skills | group_by(.marketplace) | .[] | "\(.[0].marketplace)|\(length)"' "$MANIFEST_CACHE_PATH" | \
        while IFS='|' read -r mp_name count; do
            ux_section "$mp_name ($count skills)"

            jq -r --arg mp "$mp_name" \
                '.skills | map(select(.marketplace == $mp)) | sort_by(.plugin) | .[] |
                 "\(.plugin)|\(.name)|\(.description)"' "$MANIFEST_CACHE_PATH" | \
            while IFS='|' read -r plugin name desc; do
                desc_short="${desc:0:50}"
                [ ${#desc} -gt 50 ] && desc_short="${desc_short}..."
                printf "  ${UX_PRIMARY}%-30s${UX_RESET} ${UX_MUTED}[%-20s]${UX_RESET} %s\n" "$name" "$plugin" "$desc_short"
            done
            echo ""
        done
    else
        # Default: show skills grouped by plugin
        claude_skills_marketplace_group
    fi
}

# Group skills by category/plugin
claude_skills_marketplace_group() {
    local category_filter="${1:-}"

    _ensure_manifest_fresh || {
        ux_error "Failed to generate marketplace manifest"
        return 1
    }

    ux_header "Skills Grouped by Plugin"

    # Extract unique categories/plugins
    local categories
    if [ -n "$category_filter" ]; then
        # Filter by specific category
        categories=$(jq -r --arg cat "$category_filter" \
            '.skills | map(select(.plugin | contains($cat))) | map(.plugin) | unique | .[]' \
            "$MANIFEST_CACHE_PATH")
    else
        categories=$(jq -r '.skills | map(.plugin) | unique | sort | .[]' "$MANIFEST_CACHE_PATH")
    fi

    [ -z "$categories" ] && {
        ux_warning "No plugins found matching filter: $category_filter"
        return 0
    }

    while IFS= read -r plugin; do
        local count
        count=$(jq -r --arg plugin "$plugin" \
            '[.skills | map(select(.plugin == $plugin))] | length' \
            "$MANIFEST_CACHE_PATH")

        ux_section "$plugin ($count skills)"

        # List skills in this plugin
        jq -r --arg plugin "$plugin" \
            '.skills | map(select(.plugin == $plugin)) | sort_by(.name) | .[] |
             "\(.name)|\(.description)"' "$MANIFEST_CACHE_PATH" | \
        while IFS='|' read -r name desc; do
            desc_short="${desc:0:50}"
            [ ${#desc} -gt 50 ] && desc_short="${desc_short}..."
            printf "    ${UX_PRIMARY}•${UX_RESET} %-28s %s\n" "$name" "$desc_short"
        done
        echo ""
    done <<< "$categories"
}

# Show marketplace statistics
claude_skills_marketplace_stats() {
    _ensure_manifest_fresh || {
        ux_error "Failed to generate marketplace manifest"
        return 1
    }

    ux_header "Marketplace Statistics"

    ux_section "Overview"
    local total_skills
    total_skills=$(jq -r '.total_skills' "$MANIFEST_CACHE_PATH")
    ux_table_row "Total Skills" "$total_skills" ""

    local total_marketplaces
    total_marketplaces=$(jq -r '.skills | map(.marketplace) | unique | length' "$MANIFEST_CACHE_PATH")
    ux_table_row "Marketplaces" "$total_marketplaces" ""

    ux_section "By Marketplace"
    jq -r '.skills | group_by(.marketplace) | .[] | "\(.[0].marketplace)|\(length)"' "$MANIFEST_CACHE_PATH" | \
    while IFS='|' read -r name count; do
        ux_table_row "$name" "$count skills" ""
    done

    ux_section "Top Plugins"
    jq -r '.skills | group_by(.plugin) | map([.[0].plugin, length]) | sort_by(.[1]) | reverse | .[0:5] | .[] | "\(.[0])|\(.[1])"' \
        "$MANIFEST_CACHE_PATH" | \
    while IFS='|' read -r plugin count; do
        ux_table_row "$plugin" "$count skills" ""
    done
    echo ""
}

# Search marketplace skills
claude_skills_marketplace_search() {
    local query="$1"

    [ -z "$query" ] && {
        ux_error "Query required: claude-skills-marketplace search <keyword>"
        return 1
    }

    _ensure_manifest_fresh || {
        ux_error "Failed to generate marketplace manifest"
        return 1
    }

    ux_header "Search: '$query'"

    local results
    results=$(jq -r --arg q "${query,,}" \
        '.skills |
         map(select(
             (.name | ascii_downcase | contains($q)) or
             (.description | ascii_downcase | contains($q)) or
             (.plugin | ascii_downcase | contains($q))
         )) |
         sort_by(.name) |
         to_entries | .[] |
         "\(.key)|\(.value.name)|\(.value.description)|\(.value.plugin)"' "$MANIFEST_CACHE_PATH")

    [ -z "$results" ] && {
        ux_warning "No skills found matching query: $query"
        return 0
    }

    local count=0
    while IFS='|' read -r idx name desc plugin; do
        ((count++))
        desc_short="${desc:0:60}"
        [ ${#desc} -gt 60 ] && desc_short="${desc_short}..."

        ux_section "$count. $name"
        ux_table_row "Plugin" "$plugin" ""
        ux_table_row "Description" "$desc_short" ""
        echo ""
    done <<< "$results"

    ux_info "Found $count matching skill(s)"
}

# Display detailed skill information
claude_skills_marketplace_info() {
    local skill_name="$1"

    [ -z "$skill_name" ] && {
        ux_error "Skill name required: claude-skills-marketplace info <skill-name>"
        return 1
    }

    _ensure_manifest_fresh || {
        ux_error "Failed to generate marketplace manifest"
        return 1
    }

    local skill_json
    skill_json=$(jq -r --arg name "$skill_name" \
        '.skills | map(select(.name == $name)) | .[0]' \
        "$MANIFEST_CACHE_PATH")

    if [ "$skill_json" = "null" ] || [ -z "$skill_json" ]; then
        ux_error "Skill not found: $skill_name"
        return 1
    fi

    ux_header "Skill: $skill_name"

    ux_section "Details"
    ux_table_row "Name" "$(echo "$skill_json" | jq -r '.name')" ""
    ux_table_row "Plugin" "$(echo "$skill_json" | jq -r '.plugin')" ""
    ux_table_row "Marketplace" "$(echo "$skill_json" | jq -r '.marketplace')" ""
    ux_table_row "License" "$(echo "$skill_json" | jq -r '.license')" ""
    echo ""

    ux_section "Description"
    echo "$skill_json" | jq -r '.description' | fold -w 70 -s | while read -r line; do
        echo "  $line"
    done
    echo ""

    ux_section "Location"
    echo "  $(echo "$skill_json" | jq -r '.path')"
    echo ""
}

# Force rebuild of manifest cache
claude_skills_marketplace_refresh() {
    ux_section "Rebuilding Skill Manifest"

    rm -f "$MANIFEST_CACHE_PATH"
    _generate_manifest || {
        ux_error "Failed to generate manifest"
        return 1
    }

    local total
    total=$(jq -r '.total_skills' "$MANIFEST_CACHE_PATH")
    ux_success "Manifest regenerated: $total skills indexed"
}

# Help documentation
claude_skills_marketplace_help() {
    ux_header "Marketplace Skills Commands"

    ux_section "Quick Start"
    ux_bullet "Group by plugin (default): ${UX_SUCCESS}csm${UX_RESET}"
    ux_bullet "All skills by marketplace: ${UX_SUCCESS}csm list --all${UX_RESET}"
    ux_bullet "Search skills: ${UX_SUCCESS}csm search python${UX_RESET}"
    ux_bullet "Get details: ${UX_SUCCESS}csm info api-design-principles${UX_RESET}"
    echo ""

    ux_section "Available Commands"

    ux_numbered 1 "list [--all|-A]         - Group by plugin (default), or --all for marketplace view"
    ux_numbered 2 "group [plugin]          - Group skills by plugin (optionally filter)"
    ux_numbered 3 "stats                   - Show marketplace statistics"
    ux_numbered 4 "search <keyword>        - Search skills by keyword"
    ux_numbered 5 "info <skill-name>       - Show detailed skill information"
    ux_numbered 6 "refresh                 - Force rebuild skill manifest"
    ux_numbered 7 "help                    - Show this help message"
    echo ""

    ux_section "Aliases"
    ux_bullet "Long form: ${UX_SUCCESS}claude_skills_marketplace${UX_RESET}"
    ux_bullet "Short form: ${UX_SUCCESS}csm${UX_RESET}"
    echo ""

    ux_section "Examples"

    ux_bullet "Group by plugin: ${UX_SUCCESS}csm${UX_RESET} or ${UX_SUCCESS}csm list${UX_RESET}"
    ux_bullet "All by marketplace: ${UX_SUCCESS}csm list --all${UX_RESET} or ${UX_SUCCESS}csm list -A${UX_RESET}"
    ux_bullet "Search for Python: ${UX_SUCCESS}csm search python${UX_RESET}"
    ux_bullet "Skill details: ${UX_SUCCESS}csm info api-design-principles${UX_RESET}"
    ux_bullet "Statistics: ${UX_SUCCESS}csm stats${UX_RESET}"
    ux_bullet "Filter by plugin: ${UX_SUCCESS}csm group backend${UX_RESET}"
    echo ""

    ux_section "Caching"
    ux_bullet "Manifest cache: ${UX_MUTED}${MANIFEST_CACHE_PATH}${UX_RESET}"
    ux_bullet "Cache TTL: ${UX_MUTED}24 hours${UX_RESET}"
    ux_bullet "Auto-refresh: ${UX_MUTED}When cache expires or manifest missing${UX_RESET}"
    echo ""
}

# Main router function
claude_skills_marketplace() {
    local command="${1:-list}"
    shift || true

    case "$command" in
        list)
            claude_skills_marketplace_list "$@"
            ;;
        group)
            claude_skills_marketplace_group "$@"
            ;;
        stats)
            claude_skills_marketplace_stats "$@"
            ;;
        search)
            claude_skills_marketplace_search "$@"
            ;;
        info)
            claude_skills_marketplace_info "$@"
            ;;
        refresh)
            claude_skills_marketplace_refresh "$@"
            ;;
        help)
            claude_skills_marketplace_help "$@"
            ;;
        *)
            ux_error "Unknown command: $command"
            ux_info "Try: claude-skills-marketplace help"
            return 1
            ;;
    esac
}

# Create short alias for convenience
# This is safe as a function alias (no naming conflicts with my_help.sh pattern)
alias csm='claude_skills_marketplace'
