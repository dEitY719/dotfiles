# Claude Code Marketplace Plugins Management
# Advanced utilities for managing and translating marketplace plugins

# ═══════════════════════════════════════════════════════════════
# Initialize Plugin Documentation Structure
# ═══════════════════════════════════════════════════════════════

init_plugins_docs() {
    local docs_base_dir="$HOME/.claude/docs"
    local docs_dir="$docs_base_dir/marketplaces"

    ux_header "Initializing Plugin Documentation Directory"
    ux_info "Creating: $docs_dir"
    echo ""

    # Check if docs is mounted
    if declare -f _is_mounted >/dev/null 2>&1; then
        _is_mounted "$docs_base_dir" && {
            ux_success "docs directory is mounted"
            ux_info "Source: ~/dotfiles/claude/docs"
            ux_info "Target: ~/.claude/docs"
            echo ""
        }
    fi

    mkdir -p "$docs_dir"

    if [ $? -eq 0 ]; then
        ux_success "Documentation directory created"
        echo ""
        ux_section "Directory Structure"
        ux_bullet "Marketplace plugins: ${UX_INFO}\$HOME/.claude/plugins/marketplaces${UX_RESET}"
        ux_bullet "Documentation (mounted): ${UX_INFO}$docs_base_dir${UX_RESET}"
        ux_bullet "Marketplace docs: ${UX_INFO}$docs_dir${UX_RESET}"
        ux_bullet "Git tracked in: ${UX_INFO}~/dotfiles/claude/docs${UX_RESET}"
        echo ""
        ux_section "Quick Commands"
        ux_bullet "Open plugins: ${UX_HIGHLIGHT}open_claude_plugins${UX_RESET}"
        ux_bullet "List available plugins: ${UX_HIGHLIGHT}list_plugins${UX_RESET}"
        ux_bullet "Create structure from plugins: ${UX_HIGHLIGHT}sync_plugins_structure${UX_RESET}"
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
    echo ""

    local marketplace_count=0
    local total_skills=0

    for marketplace in "$plugins_dir"/*; do
        if [ -d "$marketplace" ]; then
            marketplace_name=$(basename "$marketplace")
            marketplace_count=$((marketplace_count + 1))

            # Count skills in this marketplace
            local skills_dir="$marketplace/skills"
            if [ -d "$skills_dir" ]; then
                local skill_count=$(find "$skills_dir" -maxdepth 1 -type d ! -name "skills" | wc -l)
                total_skills=$((total_skills + skill_count))

                ux_section "$marketplace_name"
                ux_bullet "Path: ${UX_INFO}$marketplace${UX_RESET}"
                ux_bullet "Skills: ${UX_HIGHLIGHT}$skill_count${UX_RESET}"
            else
                ux_section "$marketplace_name"
                ux_warning "No skills directory found"
            fi
            echo ""
        fi
    done

    ux_section "Summary"
    ux_bullet "Total Marketplaces: ${UX_HIGHLIGHT}$marketplace_count${UX_RESET}"
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
    echo ""

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

    echo ""
    ux_section "Structure Created"
    ux_info "Documentation directory: $docs_dir"
    ux_info "Mounted from: ~/dotfiles/claude/docs/marketplaces"
    echo ""
    ux_section "Git Integration"
    ux_bullet "Files are automatically tracked in: ${UX_HIGHLIGHT}~/dotfiles/claude/docs/${UX_RESET}"
    ux_bullet "Ready for version control and team collaboration"
    echo ""
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
        ux_header "view_plugin_info"
        ux_usage "view_plugin_info" "<plugin-name>" "Find and display plugin information"
        ux_bullet "Example: ${UX_INFO}view_plugin_info algorithmic-art${UX_RESET}"
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
                echo ""

                ux_section "Marketplace"
                ux_info "$marketplace_name"
                echo ""

                if [ -f "$skill_dir/SKILL.md" ]; then
                    ux_section "Description (SKILL.md)"
                    head -20 "$skill_dir/SKILL.md"
                    echo ""
                    ux_bullet "Full file: ${UX_INFO}$skill_dir/SKILL.md${UX_RESET}"
                fi

                break
            fi
        fi
    done

    if [ $found -eq 0 ]; then
        ux_error "Plugin not found: $plugin_name"
        ux_info "Available plugins can be listed with: ${UX_HIGHLIGHT}list_plugins${UX_RESET}"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# Help & Documentation
# ═══════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════
# Generate Korean Documentation from Plugin Files (Claude-Assisted)
# ═══════════════════════════════════════════════════════════════

generate_plugin_doc_ko() {
    local plugin_file="$1"
    local output_file="$2"

    if [ -z "$plugin_file" ] || [ -z "$output_file" ]; then
        ux_header "generate_plugin_doc_ko"
        ux_usage "generate_plugin_doc_ko" "<source-file> <output-file>" "Generate Korean summary from plugin file"
        ux_bullet "Example: ${UX_INFO}generate_plugin_doc_ko ~/.claude/plugins/marketplaces/claude-code-workflows/plugins/code-refactoring/agents/code-reviewer.md ~/.claude/docs/marketplaces/claude-code-workflows/plugins/code-refactoring/agents/code-reviewer_KO.md${UX_RESET}"
        return 1
    fi

    if [ ! -f "$plugin_file" ]; then
        ux_error "Plugin file not found: $plugin_file"
        return 1
    fi

    # Create output directory if not exists
    output_dir=$(dirname "$output_file")
    mkdir -p "$output_dir"

    ux_header "Generating Korean Documentation"
    ux_info "Source: $plugin_file"
    ux_info "Output: $output_file"
    echo ""
    ux_info "Calling Claude to generate Korean summary..."
    echo ""

    # Generate Korean summary using Claude
    claude -p "다음 에이전트/스킬 파일을 한국어로 요약해줘. YAML 헤더와 주요 기능들을 포함해서 마크다운 형식으로 작성해줘. 번역은 정확하고 전문적이어야 해. 그리고 [원본 파일] 섹션에 원본 파일 경로를 추가해줘.

원본 파일 내용:
\`\`\`
$(cat "$plugin_file")
\`\`\`" > "$output_file"

    if [ $? -eq 0 ]; then
        ux_success "Korean documentation generated"
        echo ""
        ux_section "Output File"
        ls -lh "$output_file"
        echo ""
        ux_info "Preview (first 30 lines):"
        head -30 "$output_file"
    else
        ux_error "Failed to generate documentation"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════

create_plugin_structure_ko() {
    local marketplace="$1"
    local plugin_path="$2"

    if [ -z "$marketplace" ] || [ -z "$plugin_path" ]; then
        ux_header "create_plugin_structure_ko"
        ux_usage "create_plugin_structure_ko" "<marketplace> <plugin-path>" "Create directory structure and generate Korean docs"
        ux_bullet "Example: ${UX_INFO}create_plugin_structure_ko claude-code-workflows plugins/code-refactoring/agents/code-reviewer.md${UX_RESET}"
        return 1
    fi

    local docs_base="$HOME/.claude/docs/marketplaces/$marketplace"
    local plugins_base="$HOME/.claude/plugins/marketplaces/$marketplace"
    local source_file="$plugins_base/$plugin_path"
    local output_file="$docs_base/$plugin_path"
    output_file="${output_file%.md}_KO.md"

    if [ ! -f "$source_file" ]; then
        ux_error "Plugin file not found: $source_file"
        return 1
    fi

    ux_header "Creating Plugin Documentation Structure"
    echo ""

    # Create directory structure
    output_dir=$(dirname "$output_file")
    mkdir -p "$output_dir"
    ux_success "Created directory: $output_dir"
    echo ""

    # Generate Korean documentation
    generate_plugin_doc_ko "$source_file" "$output_file"

    echo ""
    ux_section "Next Steps"
    ux_bullet "Review generated file: ${UX_CODE}code $output_file${UX_RESET}"
    ux_bullet "Add personal notes: ${UX_CODE}code ${output_file%.md}_NOTES.md${UX_RESET}"
    ux_bullet "Commit to git: ${UX_CODE}cd ~/dotfiles && git add claude/docs/ && git commit -m 'docs: Add Korean summary...'${UX_RESET}"
}

# ═══════════════════════════════════════════════════════════════

claude_plugins_help() {
    ux_header "Claude Marketplace Plugins Management"
    echo ""

    ux_section "Available Commands"
    echo ""

    ux_highlight "open_claude_plugins"
    ux_info "Open marketplace plugins directory in VSCode"
    ux_bullet "Usage: ${UX_CODE}open_claude_plugins${UX_RESET}"
    echo ""

    ux_highlight "list_plugins"
    ux_info "List all available marketplaces and their skills"
    ux_bullet "Usage: ${UX_CODE}list_plugins${UX_RESET}"
    echo ""

    ux_highlight "init_plugins_docs"
    ux_info "Initialize Korean documentation directory structure"
    ux_bullet "Usage: ${UX_CODE}init_plugins_docs${UX_RESET}"
    echo ""

    ux_highlight "sync_plugins_structure"
    ux_info "Create directory structure mirroring plugins organization"
    ux_bullet "Usage: ${UX_CODE}sync_plugins_structure${UX_RESET}"
    echo ""

    ux_highlight "view_plugin_info <plugin-name>"
    ux_info "View specific plugin information"
    ux_bullet "Usage: ${UX_CODE}view_plugin_info algorithmic-art${UX_RESET}"
    echo ""

    ux_highlight "generate_plugin_doc_ko <source-file> <output-file>"
    ux_info "Generate Korean documentation from plugin file using Claude"
    ux_bullet "Usage: ${UX_CODE}generate_plugin_doc_ko ~/.claude/plugins/[path]/file.md ~/.claude/docs/[path]/file_KO.md${UX_RESET}"
    echo ""

    ux_highlight "create_plugin_structure_ko <marketplace> <plugin-path>"
    ux_info "Create structure and generate Korean docs in one command"
    ux_bullet "Usage: ${UX_CODE}create_plugin_structure_ko claude-code-workflows plugins/code-refactoring/agents/code-reviewer.md${UX_RESET}"
    echo ""

    ux_section "Documentation Workflow"
    ux_bullet "1. ${UX_CODE}init_plugins_docs${UX_RESET} - Initialize documentation directory"
    ux_bullet "2. ${UX_CODE}open_claude_plugins${UX_RESET} - Review plugin descriptions"
    ux_bullet "3. ${UX_CODE}create_plugin_structure_ko <marketplace> <path>/${UX_RESET} - Generate Korean docs"
    ux_bullet "4. Review and customize generated documentation"
    ux_bullet "5. Commit changes to ~/dotfiles/claude/docs/"

    echo ""
    ux_section "Directory Structure"
    ux_info "Plugins (read-only):"
    ux_bullet "~/.claude/plugins/marketplaces/[marketplace]/plugins/[plugin-name]/agents/[agent].md"
    echo ""
    ux_info "Documentation (git-tracked, mounted):"
    ux_bullet "~/.claude/docs/marketplaces/[marketplace]/plugins/[plugin-name]/agents/[agent]_KO.md"
    echo ""

    ux_section "Git Integration"
    ux_info "All documentation is mounted and automatically git-tracked:"
    ux_bullet "User location: ${UX_INFO}~/.claude/docs${UX_RESET} (via bind mount)"
    ux_bullet "Git source: ${UX_INFO}~/dotfiles/claude/docs${UX_RESET}"
    ux_bullet "Changes are version-controlled and shareable"
}
