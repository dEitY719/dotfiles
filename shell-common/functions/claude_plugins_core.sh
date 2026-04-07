#!/bin/sh
# shell-common/functions/claude_plugins_core.sh
# Core plugin management functions (split from claude_plugins.sh)

# ═══════════════════════════════════════════════════════════════
# Initialize Plugin Documentation Structure
# ═══════════════════════════════════════════════════════════════

init_plugins_docs() {
    local docs_base_dir="$HOME/.claude/docs"
    local docs_dir="$docs_base_dir/marketplaces"

    ux_header "Initializing Plugin Documentation Directory"
    ux_info "Creating: $docs_dir"


    # Check if docs is mounted
    if declare -f _is_mounted >/dev/null 2>&1; then
        _is_mounted "$docs_base_dir" && {
            ux_success "docs directory is mounted"
            ux_info "Source: ~/dotfiles/claude/docs"
            ux_info "Target: ~/.claude/docs"

        }
    fi

    if mkdir -p "$docs_dir"; then
        ux_success "Documentation directory created"

        ux_section "Directory Structure"
        ux_bullet "Marketplace plugins: ${UX_INFO}\$HOME/.claude/plugins/marketplaces${UX_RESET}"
        ux_bullet "Documentation (mounted): ${UX_INFO}$docs_base_dir${UX_RESET}"
        ux_bullet "Marketplace docs: ${UX_INFO}$docs_dir${UX_RESET}"
        ux_bullet "Git tracked in: ${UX_INFO}~/dotfiles/claude/docs${UX_RESET}"

        ux_section "Quick Commands"
        ux_bullet "Open plugins: ${UX_HIGHLIGHT}open_claude_plugins${UX_RESET}"
        ux_bullet "List available plugins: ${UX_HIGHLIGHT}list-plugins${UX_RESET}"
        ux_bullet "Create structure from plugins: ${UX_HIGHLIGHT}sync-plugins-structure${UX_RESET}"
    else
        ux_error "Failed to create documentation directory"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# List Available Plugins with Marketplace Organization
# ═══════════════════════════════════════════════════════════════

list_plugins() {
    local plugins_dir="$HOME/.claude/plugins/marketplaces"

    if [ ! -d "$plugins_dir" ]; then
        ux_error "Plugins directory not found: $plugins_dir"
        return 1
    fi

    ux_header "Available Marketplaces"


    local marketplace_count=0
    local total_agents=0
    local total_commands=0
    local total_skills=0

    for marketplace in "$plugins_dir"/*; do
        if [ ! -d "$marketplace" ]; then
            continue
        fi

        marketplace_name=$(basename "$marketplace")
        marketplace_count=$((marketplace_count + 1))

        ux_section "$marketplace_name"
        ux_bullet "Path: ${UX_INFO}$marketplace${UX_RESET}"


        # Counters for this marketplace
        local mp_agents=0
        local mp_commands=0
        local mp_skills=0

        # Count direct category folders at marketplace level
        if [ -d "$marketplace/agents" ]; then
            mp_agents=$(find "$marketplace/agents" -maxdepth 1 -type f -name "*.md" 2>/dev/null | wc -l)
            total_agents=$((total_agents + mp_agents))
        fi

        if [ -d "$marketplace/commands" ]; then
            mp_commands=$(find "$marketplace/commands" -maxdepth 1 -type f -name "*.md" 2>/dev/null | wc -l)
            total_commands=$((total_commands + mp_commands))
        fi

        if [ -d "$marketplace/skills" ]; then
            mp_skills=$(find "$marketplace/skills" -maxdepth 1 -type d ! -name "skills" 2>/dev/null | wc -l)
            total_skills=$((total_skills + mp_skills))
        fi

        # Check for plugins directory structure (nested plugins with their own agents/commands/skills)
        if [ -d "$marketplace/plugins" ]; then
            local plugin_count=0
            local plugin_agents=0
            local plugin_commands=0
            local plugin_skills=0

            # Count plugins
            plugin_count=$(find "$marketplace/plugins" -maxdepth 1 -type d ! -name "plugins" 2>/dev/null | wc -l)

            # Recursively count agents, commands, skills in all plugins
            if [ "$plugin_count" -gt 0 ]; then
                plugin_agents=$(find "$marketplace/plugins" -name "agents" -type d -exec find {} -maxdepth 1 -type f -name "*.md" \; 2>/dev/null | wc -l)
                plugin_commands=$(find "$marketplace/plugins" -name "commands" -type d -exec find {} -maxdepth 1 -type f -name "*.md" \; 2>/dev/null | wc -l)
                plugin_skills=$(find "$marketplace/plugins" -name "skills" -type d -exec find {} -maxdepth 1 -type d ! -name "skills" \; 2>/dev/null | wc -l)

                mp_agents=$((mp_agents + plugin_agents))
                mp_commands=$((mp_commands + plugin_commands))
                mp_skills=$((mp_skills + plugin_skills))

                total_agents=$((total_agents + plugin_agents))
                total_commands=$((total_commands + plugin_commands))
                total_skills=$((total_skills + plugin_skills))

                ux_bullet "Plugins: ${UX_HIGHLIGHT}$plugin_count${UX_RESET}"
            fi
        fi

        # Display counts for this marketplace
        if [ "$mp_agents" -gt 0 ]; then
            ux_bullet "Agents: ${UX_HIGHLIGHT}$mp_agents${UX_RESET}"
        fi
        if [ "$mp_commands" -gt 0 ]; then
            ux_bullet "Commands: ${UX_HIGHLIGHT}$mp_commands${UX_RESET}"
        fi
        if [ "$mp_skills" -gt 0 ]; then
            ux_bullet "Skills: ${UX_HIGHLIGHT}$mp_skills${UX_RESET}"
        fi

        if [ "$mp_agents" -eq 0 ] && [ "$mp_commands" -eq 0 ] && [ "$mp_skills" -eq 0 ]; then
            ux_warning "No agents, commands, or skills found"
        fi


    done

    ux_section "Summary"
    ux_bullet "Total Marketplaces: ${UX_HIGHLIGHT}$marketplace_count${UX_RESET}"
    ux_bullet "Total Agents: ${UX_HIGHLIGHT}$total_agents${UX_RESET}"
    ux_bullet "Total Commands: ${UX_HIGHLIGHT}$total_commands${UX_RESET}"
    ux_bullet "Total Skills: ${UX_HIGHLIGHT}$total_skills${UX_RESET}"
}

# ═══════════════════════════════════════════════════════════════
# Create Documentation Directory Structure from Plugins
# ═══════════════════════════════════════════════════════════════

sync_plugins_structure() {
    local plugins_dir="$HOME/.claude/plugins/marketplaces"
    local docs_base_dir="$HOME/.claude/docs"
    local docs_dir="$docs_base_dir/marketplaces"

    if [ ! -d "$plugins_dir" ]; then
        ux_error "Plugins directory not found"
        return 1
    fi

    ux_header "Syncing Plugin Structure to Documentation"


    mkdir -p "$docs_dir"

    for marketplace in "$plugins_dir"/*; do
        if [ -d "$marketplace" ]; then
            marketplace_name=$(basename "$marketplace")
            marketplace_docs="$docs_dir/$marketplace_name"

            mkdir -p "$marketplace_docs"
            ux_success "Created: $marketplace_name/"

            # Create skills subdirectory
            local skills_dir="$marketplace/skills"
            if [ -d "$skills_dir" ]; then
                skills_docs="$marketplace_docs/skills"
                mkdir -p "$skills_docs"

                for skill in "$skills_dir"/*; do
                    if [ -d "$skill" ]; then
                        skill_name=$(basename "$skill")
                        mkdir -p "$skills_docs/$skill_name"
                        ux_bullet "  Created: skills/$skill_name/"
                    fi
                done
            fi
        fi
    done


    ux_section "Structure Created"
    ux_info "Documentation directory: $docs_dir"
    ux_info "Mounted from: ~/dotfiles/claude/docs/marketplaces"

    ux_section "Git Integration"
    ux_bullet "Files are automatically tracked in: ${UX_HIGHLIGHT}~/dotfiles/claude/docs/${UX_RESET}"
    ux_bullet "Ready for version control and team collaboration"

    ux_info "Next steps:"
    ux_bullet "1. Review plugin descriptions in VSCode"
    ux_bullet "2. Create Korean README.md files in each skill directory"
    ux_bullet "3. Use 'claude' command to help translate descriptions"
    ux_bullet "4. Commit changes to dotfiles git repository"
}

# ═══════════════════════════════════════════════════════════════
# Quick Lookup: Find and View Specific Plugin Info
# ═══════════════════════════════════════════════════════════════

view_plugin_info() {
    local plugin_name="$1"

    if [ -z "$plugin_name" ]; then
        ux_header "view-plugin-info"
        ux_usage "view-plugin-info" "<plugin-name>" "Find and display plugin information"
        ux_bullet "Example: ${UX_INFO}view-plugin-info algorithmic-art${UX_RESET}"
        return 1
    fi

    local plugins_dir="$HOME/.claude/plugins/marketplaces"
    local found=0

    for marketplace in "$plugins_dir"/*; do
        if [ -d "$marketplace" ]; then
            local skill_dir="$marketplace/skills/$plugin_name"
            if [ -d "$skill_dir" ]; then
                found=1
                marketplace_name=$(basename "$marketplace")

                ux_header "$plugin_name"


                ux_section "Marketplace"
                ux_info "$marketplace_name"


                if [ -f "$skill_dir/SKILL.md" ]; then
                    ux_section "Description (SKILL.md)"
                    head -20 "$skill_dir/SKILL.md"

                    ux_bullet "Full file: ${UX_INFO}$skill_dir/SKILL.md${UX_RESET}"
                fi

                break
            fi
        fi
    done

    if [ $found -eq 0 ]; then
        ux_error "Plugin not found: $plugin_name"
        ux_info "Available plugins can be listed with: ${UX_HIGHLIGHT}list-plugins${UX_RESET}"
        return 1
    fi
}

# Extract brief description from plugin file (YAML or heading fallback)
_get_plugin_description() {
    local file="$1"

    _extract_yaml_field_fallback() {
        local yaml_file="$1"
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
' "$yaml_file" 2>/dev/null
    }

    # 1. Try to extract description from YAML frontmatter
    local yaml_desc=""

    # Prefer robust YAML parsing for multiline descriptions (>- and |)
    if command -v ruby >/dev/null 2>&1; then
        yaml_desc="$(ruby -ryaml -e '
path = ARGV[0]
content = File.read(path)
match = content.match(/\A---\n(.*?)\n---\n/m)
exit 0 unless match
data = YAML.safe_load(match[1]) || {}
desc = data["description"].to_s.gsub(/\s+/, " ").strip
puts desc
' "$file" 2>/dev/null || true)"
    fi

    # Fallback for environments without ruby
    if [ -z "$yaml_desc" ]; then
        yaml_desc=$(_extract_yaml_field_fallback "$file" "description")
    fi

    if [ -n "$yaml_desc" ]; then
        if [ ${#yaml_desc} -gt 100 ]; then
            yaml_desc="$(echo "$yaml_desc" | cut -c1-100)"
        fi
        ux_info "$yaml_desc"
        return 0
    fi

    # 2. Fallback: Extract first markdown heading (# Title)
    local title_desc
    title_desc=$(grep "^# " "$file" 2>/dev/null | head -1 | sed 's/^# *//; s/#*$//' | cut -c1-100)

    if [ -n "$title_desc" ]; then
        ux_info "$title_desc"
        return 0
    fi

    # 3. No description found - return empty string
    return 1
}
