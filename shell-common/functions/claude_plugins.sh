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

    if mkdir -p "$docs_dir"; then
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
                local skill_count
                skill_count=$(find "$skills_dir" -maxdepth 1 -type d ! -name "skills" | wc -l)
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
# Generate Korean Documentation from Plugin Files (AI-Agnostic)
# ═══════════════════════════════════════════════════════════════

# Default AI tool for documentation generation
# Can be overridden by: CLAUDE_DOC_GENERATOR=gemini, CLAUDE_DOC_GENERATOR=codex, etc.
: "${CLAUDE_DOC_GENERATOR:=claude}"

# Optional styling fallbacks (helps when shell uses `set -u`)
: "${UX_HIGHLIGHT:=${UX_INFO-}}"
: "${UX_CODE:=${UX_BOLD-}${UX_PRIMARY-}}"

# Korean documentation generation prompt template
_generate_plugin_doc_ko_prompt() {
    local plugin_file="$1"

    cat <<'PROMPT_EOF'
다음 에이전트/스킬 파일을 한국어로 요약해줘. 다음 요구사항을 따라줘:

1. YAML 헤더 유지 (name, description, model 등)
2. 주요 기능들을 한국어로 명확하게 설명
3. 마크다운 형식으로 구조화
4. 번역은 정확하고 전문적일 것
5. 끝에 [원본 파일] 섹션 추가하여 원본 파일 경로 명시

원본 파일 내용:
```
PROMPT_EOF

    cat "$plugin_file"

    cat <<'PROMPT_EOF'
```
PROMPT_EOF
}

generate_plugin_doc_ko() {
    local plugin_file="$1"
    local output_file="$2"
    local ai_tool="${CLAUDE_DOC_GENERATOR}"
    local force_overwrite=false

    if [ -z "$plugin_file" ] || [ -z "$output_file" ]; then
        ux_header "generate_plugin_doc_ko"
        ux_usage "generate_plugin_doc_ko" "<source-file> <output-file> [ai-tool] [--force]" "Generate Korean summary from plugin file"
        ux_bullet "Example: ${UX_INFO}generate_plugin_doc_ko file.md output_KO.md${UX_RESET}"
        ux_bullet "With specific AI: ${UX_INFO}generate_plugin_doc_ko file.md output_KO.md gemini${UX_RESET}"
        ux_bullet "Force overwrite: ${UX_INFO}generate_plugin_doc_ko file.md output_KO.md claude --force${UX_RESET}"
        echo ""
        ux_section "Available AI Tools"
        ux_bullet "claude (default) - Anthropic Claude (uses -p flag)"
        ux_bullet "gemini - Google Gemini (uses -p flag)"
        ux_bullet "codex - Codex CLI (uses 'exec' subcommand)"
        ux_bullet "Other tools - Any CLI tool that accepts -p, --prompt, exec, or positional argument"
        echo ""
        ux_section "Options"
        ux_bullet "--force - Overwrite existing files (default: skip if exists)"
        echo ""
        ux_section "Override Default AI Tool"
        ux_bullet "Set environment variable: ${UX_CODE}export CLAUDE_DOC_GENERATOR=gemini${UX_RESET}"
        return 1
    fi

    # Parse optional args: [ai-tool] [--force]
    shift 2
    while [ $# -gt 0 ]; do
        case "$1" in
        --force)
            force_overwrite=true
            ;;
        -h | --help)
            ux_header "generate_plugin_doc_ko"
            ux_usage "generate_plugin_doc_ko" "<source-file> <output-file> [ai-tool] [--force]" "Generate Korean summary from plugin file"
            return 1
            ;;
        *)
            ai_tool="$1"
            ;;
        esac
        shift
    done

    if [ ! -f "$plugin_file" ]; then
        ux_error "Plugin file not found: $plugin_file"
        return 1
    fi

    # Check if output file already exists and skip if not forced
    if [ -f "$output_file" ] && [ "$force_overwrite" != "true" ]; then
        ux_info "File already exists (skipping): ${output_file##*/}"
        return 0
    fi

    # Check if AI tool is available
    if ! command -v "$ai_tool" >/dev/null 2>&1; then
        ux_error "AI tool not found or not in PATH: $ai_tool"
        ux_info "Make sure '$ai_tool' is installed and available in your PATH"
        ux_info "Or specify a different AI tool with: generate_plugin_doc_ko <source> <output> <tool>"
        return 1
    fi

    # Create output directory if not exists
    local output_dir
    output_dir=$(dirname "$output_file")
    mkdir -p "$output_dir"

    if [ -f "$output_file" ] && [ "$force_overwrite" = "true" ]; then
        ux_info "Overwriting existing file: ${output_file##*/}"
    fi

    ux_header "Generating Korean Documentation"
    ux_info "Source: $plugin_file"
    ux_info "Output: $output_file"
    ux_info "AI Tool: ${UX_HIGHLIGHT}$ai_tool${UX_RESET}"
    echo ""
    ux_info "Calling $ai_tool to generate Korean summary..."
    echo ""

    # Generate Korean summary using the specified AI tool
    # Support multiple prompt flag formats: -p, --prompt, positional argument
    local prompt_output
    local rc=0
    case "$ai_tool" in
    claude | gemini)
        # These tools use -p flag
        prompt_output=$(_generate_plugin_doc_ko_prompt "$plugin_file")
        "$ai_tool" -p "$prompt_output" >"$output_file" 2>&1
        rc=$?
        ;;
    codex)
        # Codex uses 'exec' subcommand for non-interactive execution
        # Use --output-last-message to capture only the AI response (not session info)
        _generate_plugin_doc_ko_prompt "$plugin_file" | "$ai_tool" exec --output-last-message "$output_file" - >/dev/null 2>&1
        rc=$?
        ;;
    *)
        # Try common prompt flag patterns
        prompt_output=$(_generate_plugin_doc_ko_prompt "$plugin_file")
        if "$ai_tool" -p "$prompt_output" >"$output_file" 2>&1; then
            : # Success
        elif "$ai_tool" --prompt "$prompt_output" >"$output_file" 2>&1; then
            : # Success
        elif _generate_plugin_doc_ko_prompt "$plugin_file" | "$ai_tool" exec --output-last-message "$output_file" - >/dev/null 2>&1; then
            : # Success (exec subcommand reading prompt from stdin)
        elif "$ai_tool" exec --output-last-message "$output_file" "$prompt_output" >/dev/null 2>&1; then
            : # Success (exec subcommand with output file + prompt arg)
        elif "$ai_tool" exec "$prompt_output" >"$output_file" 2>&1; then
            : # Success (exec subcommand)
        elif "$ai_tool" "$prompt_output" >"$output_file" 2>&1; then
            : # Success (positional argument)
        else
            ux_error "Could not determine correct prompt format for $ai_tool"
            ux_info "Tried: -p flag, --prompt flag, exec subcommand, and positional argument"
            return 1
        fi
        rc=$?
        ;;
    esac

    if [ $rc -eq 0 ] && [ -s "$output_file" ]; then
        ux_success "Korean documentation generated"
        echo ""
        ux_section "Output File"
        ls -lh "$output_file"
        echo ""
        ux_info "Preview (first 30 lines):"
        head -30 "$output_file"
    else
        ux_error "Failed to generate documentation"
        rm -f "$output_file"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# Generate Korean Documentation Recursively for Plugin Directories
# ═══════════════════════════════════════════════════════════════

# Extract brief description from plugin file (YAML or heading fallback)
_get_plugin_description() {
    local file="$1"

    # 1. Try to extract description from YAML frontmatter
    local yaml_desc
    yaml_desc=$(grep "^description:" "$file" 2>/dev/null | head -1 | sed 's/^description: *//; s/"//g' | cut -c1-100)

    if [ -n "$yaml_desc" ]; then
        echo "$yaml_desc"
        return 0
    fi

    # 2. Fallback: Extract first markdown heading (# Title)
    local title_desc
    title_desc=$(grep "^# " "$file" 2>/dev/null | head -1 | sed 's/^# *//; s/#*$//' | cut -c1-100)

    if [ -n "$title_desc" ]; then
        echo "$title_desc"
        return 0
    fi

    # 3. No description found - return empty string
    return 1
}

# Generate README.md summarizing plugin directory structure
_generate_plugin_directory_readme_ko() {
    local plugin_dir="$1"
    local docs_dir="$2"
    local ai_tool="$3"

    local readme_file="$docs_dir/README.md"
    local plugin_name
    plugin_name=$(basename "$plugin_dir")

    ux_info "Generating directory summary: README.md"

    # Create header with basic info
    cat >"$readme_file" <<'README_HEADER'
# 플러그인 폴더 구조 및 요약

README_HEADER

    echo "" >>"$readme_file"

    # Process each subdirectory and file
    local processed=0

    for category_dir in "$plugin_dir"/*; do
        if [ ! -d "$category_dir" ]; then
            continue
        fi

        local category
        category=$(basename "$category_dir")

        # Count direct .md files
        local file_count
        file_count=$(find "$category_dir" -maxdepth 1 -type f -name "*.md" 2>/dev/null | wc -l)

        # Count nested SKILL.md or AGENT.md files in subdirectories
        local nested_count
        nested_count=$(find "$category_dir" -maxdepth 2 -type f \( -name "SKILL.md" -o -name "AGENT.md" \) 2>/dev/null | wc -l)

        # Process only if there are files (direct or nested)
        if [ "$file_count" -gt 0 ] || [ "$nested_count" -gt 0 ]; then
            local total_files=$((file_count + nested_count))
            echo "## $category ($total_files)" >>"$readme_file"
            echo "" >>"$readme_file"

            # List each direct .md file with its description
            for file in "$category_dir"/*.md; do
                if [ -f "$file" ]; then
                    local filename
                    filename=$(basename "$file" .md)
                    local description
                    description=$(_get_plugin_description "$file")

                    if [ -z "$description" ]; then
                        description="[설명 없음]"
                    fi

                    echo "- **$filename**: $description" >>"$readme_file"
                    processed=$((processed + 1))
                fi
            done

            # Process nested directories (like skills/category/SKILL.md or agents/category/AGENT.md)
            for nested_dir in "$category_dir"/*; do
                if [ -d "$nested_dir" ]; then
                    local nested_name
                    nested_name=$(basename "$nested_dir")

                    # Check for SKILL.md, AGENT.md, or any .md file
                    local nested_file=""
                    if [ -f "$nested_dir/SKILL.md" ]; then
                        nested_file="$nested_dir/SKILL.md"
                    elif [ -f "$nested_dir/AGENT.md" ]; then
                        nested_file="$nested_dir/AGENT.md"
                    else
                        # Check for any .md file in this nested directory
                        nested_file=$(find "$nested_dir" -maxdepth 1 -type f -name "*.md" | head -1)
                    fi

                    if [ -f "$nested_file" ]; then
                        local description
                        description=$(_get_plugin_description "$nested_file")

                        if [ -z "$description" ]; then
                            description="[설명 없음]"
                        fi

                        echo "  - **$nested_name**: $description" >>"$readme_file"
                        processed=$((processed + 1))
                    fi
                fi
            done

            echo "" >>"$readme_file"
        fi
    done

    if [ $processed -gt 0 ]; then
        {
            echo ""
            echo "---"
            echo ""
            echo "*Generated: $(date '+%Y-%m-%d %H:%M:%S')*"
            echo ""
            echo "한국어 요약 및 세부 설명은 각 폴더의 \`*_KO.md\` 파일을 참고하세요."
        } >>"$readme_file"

        ux_success "README.md generated successfully"
        return 0
    else
        ux_warning "No markdown files found in directory"
        rm -f "$readme_file"
        return 1
    fi
}

# Process plugin directory recursively and generate Korean docs for all files
process_plugin_directory_ko() {
    local marketplace="$1"
    local plugin_path="$2"
    local ai_tool="${CLAUDE_DOC_GENERATOR}"
    local force_overwrite=false

    if [ -z "$marketplace" ] || [ -z "$plugin_path" ]; then
        ux_header "process_plugin_directory_ko"
        ux_usage "process_plugin_directory_ko" "<marketplace> <plugin-path/> [ai-tool] [--force]" "Recursively generate Korean docs for all files in directory"
        ux_bullet "Example: ${UX_INFO}process_plugin_directory_ko claude-code-workflows plugins/code-refactoring/${UX_RESET}"
        ux_bullet "With Gemini: ${UX_INFO}process_plugin_directory_ko claude-code-workflows plugins/code-refactoring/ gemini${UX_RESET}"
        ux_bullet "Force update: ${UX_INFO}process_plugin_directory_ko claude-code-workflows plugins/code-refactoring/ --force${UX_RESET}"
        echo ""
        ux_section "Options"
        ux_bullet "--force - Overwrite all existing files (default: skip if exists)"
        return 1
    fi

    # Parse optional args: [ai-tool] [--force]
    shift 2
    while [ $# -gt 0 ]; do
        case "$1" in
        --force)
            force_overwrite=true
            ;;
        -h | --help)
            ux_header "process_plugin_directory_ko"
            ux_usage "process_plugin_directory_ko" "<marketplace> <plugin-path/> [ai-tool] [--force]" "Recursively generate Korean docs for all files in directory"
            return 1
            ;;
        *)
            ai_tool="$1"
            ;;
        esac
        shift
    done

    local docs_base="$HOME/.claude/docs/marketplaces/$marketplace"
    local plugins_base="$HOME/.claude/plugins/marketplaces/$marketplace"
    local source_dir="${plugins_base}/${plugin_path%/}" # Remove trailing slash if present
    local docs_dir="${docs_base}/${plugin_path%/}"

    if [ ! -d "$source_dir" ]; then
        ux_error "Plugin directory not found: $source_dir"
        return 1
    fi

    ux_header "Processing Plugin Directory Recursively"
    ux_info "Source: $source_dir"
    ux_info "Docs: $docs_dir"
    ux_info "AI Tool: ${UX_HIGHLIGHT}$ai_tool${UX_RESET}"
    echo ""

    # Create docs directory structure
    mkdir -p "$docs_dir"

    # Find all .md files recursively
    local md_files=()
    while IFS= read -r -d '' file; do
        md_files+=("$file")
    done < <(find "$source_dir" -type f -name "*.md" -print0)

    if [ ${#md_files[@]} -eq 0 ]; then
        ux_error "No markdown files found in: $source_dir"
        return 1
    fi

    ux_section "Found Files"
    ux_info "Total markdown files: ${#md_files[@]}"
    echo ""

    # Process each markdown file
    local success_count=0
    local skipped_count=0
    local failed_count=0
    for source_file in "${md_files[@]}"; do
        # Get relative path
        local relative_path="${source_file#"$source_dir"/}"
        local output_file="$docs_dir/${relative_path%.md}_KO.md"
        local output_dir
        output_dir=$(dirname "$output_file")

        mkdir -p "$output_dir"

        # Generate Korean documentation
        ux_info "Processing: $relative_path"

        # Build command with optional --force flag
        local cmd_output
        if [ "$force_overwrite" = "true" ]; then
            cmd_output=$(generate_plugin_doc_ko "$source_file" "$output_file" "$ai_tool" --force 2>&1)
        else
            cmd_output=$(generate_plugin_doc_ko "$source_file" "$output_file" "$ai_tool" 2>&1)
        fi

        if [ -f "$output_file" ]; then
            # Check if it was skipped (file already exists, not forced)
            if echo "$cmd_output" | grep -q "already exists (skipping)"; then
                skipped_count=$((skipped_count + 1))
                ux_bullet "⊘ Skipped (exists): ${output_file##*/}"
            else
                success_count=$((success_count + 1))
                ux_bullet "✓ Generated: ${output_file##*/}"
            fi
        else
            failed_count=$((failed_count + 1))
            ux_bullet "✗ Failed: $relative_path"
        fi
    done

    echo ""
    ux_section "Summary"
    ux_bullet "Total files: ${#md_files[@]}"
    ux_bullet "Generated: $success_count"
    ux_bullet "Skipped (exists): $skipped_count"
    ux_bullet "Failed: $failed_count"
    echo ""

    # Generate README.md with directory summary
    _generate_plugin_directory_readme_ko "$source_dir" "$docs_dir" "$ai_tool"

    echo ""
    ux_section "Next Steps"
    ux_bullet "Review generated files: ${UX_CODE}code $docs_dir${UX_RESET}"
    ux_bullet "View summary: ${UX_CODE}cat $docs_dir/README.md${UX_RESET}"
    ux_bullet "Commit to git: ${UX_CODE}cd ~/dotfiles && git add claude/docs/ && git commit${UX_RESET}"
}

# ═══════════════════════════════════════════════════════════════

create_plugin_structure_ko() {
    local marketplace="$1"
    local plugin_path="$2"
    local ai_tool="${CLAUDE_DOC_GENERATOR}"
    local force_overwrite=false

    if [ -z "$marketplace" ] || [ -z "$plugin_path" ]; then
        ux_header "create_plugin_structure_ko"
        ux_usage "create_plugin_structure_ko" "<marketplace> <plugin-path|plugin-path/> [ai-tool] [--force]" "Generate Korean docs for file or directory"
        ux_bullet "Single file: ${UX_INFO}create_plugin_structure_ko claude-code-workflows plugins/code-refactoring/agents/code-reviewer.md${UX_RESET}"
        ux_bullet "Full directory: ${UX_INFO}create_plugin_structure_ko claude-code-workflows plugins/code-refactoring/${UX_RESET}"
        ux_bullet "With Gemini: ${UX_INFO}create_plugin_structure_ko claude-code-workflows plugins/code-refactoring/ gemini${UX_RESET}"
        ux_bullet "Force overwrite: ${UX_INFO}create_plugin_structure_ko claude-code-workflows plugins/code-refactoring/ --force${UX_RESET}"
        echo ""
        ux_section "Available AI Tools"
        ux_bullet "claude (default) - Anthropic Claude (uses -p flag)"
        ux_bullet "gemini - Google Gemini (uses -p flag)"
        ux_bullet "codex - Codex CLI (uses 'exec' subcommand)"
        ux_bullet "Other tools - Any CLI tool that accepts -p, --prompt, exec, or positional argument"
        echo ""
        ux_section "Options"
        ux_bullet "--force - Overwrite existing files (default: skip if exists)"
        return 1
    fi

    # Parse optional args: [ai-tool] [--force]
    shift 2
    while [ $# -gt 0 ]; do
        case "$1" in
        --force)
            force_overwrite=true
            ;;
        -h | --help)
            ux_header "create_plugin_structure_ko"
            ux_usage "create_plugin_structure_ko" "<marketplace> <plugin-path|plugin-path/> [ai-tool] [--force]" "Generate Korean docs for file or directory"
            return 1
            ;;
        *)
            ai_tool="$1"
            ;;
        esac
        shift
    done

    local plugins_base="$HOME/.claude/plugins/marketplaces/$marketplace"
    local source_path="${plugins_base}/${plugin_path}"

    # Check if path is a file or directory
    if [ -f "$source_path" ]; then
        # File path - use original single-file processing
        local docs_base="$HOME/.claude/docs/marketplaces/$marketplace"
        local output_file="$docs_base/$plugin_path"
        output_file="${output_file%.md}_KO.md"

        ux_header "Creating Plugin Documentation Structure"
        echo ""

        # Create directory structure
        local output_dir
        output_dir=$(dirname "$output_file")
        mkdir -p "$output_dir"
        ux_success "Created directory: $output_dir"
        echo ""

        # Generate Korean documentation with specified AI tool
        if [ "$force_overwrite" = "true" ]; then
            generate_plugin_doc_ko "$source_path" "$output_file" "$ai_tool" --force
        else
            generate_plugin_doc_ko "$source_path" "$output_file" "$ai_tool"
        fi

        echo ""
        ux_section "Next Steps"
        ux_bullet "Review generated file: ${UX_CODE}code $output_file${UX_RESET}"
        ux_bullet "Add personal notes: ${UX_CODE}code ${output_file%.md}_NOTES.md${UX_RESET}"
        ux_bullet "Commit to git: ${UX_CODE}cd ~/dotfiles && git add claude/docs/ && git commit${UX_RESET}"

    elif [ -d "$source_path" ]; then
        # Directory path - use recursive directory processing
        if [ "$force_overwrite" = "true" ]; then
            process_plugin_directory_ko "$marketplace" "$plugin_path" "$ai_tool" --force
        else
            process_plugin_directory_ko "$marketplace" "$plugin_path" "$ai_tool"
        fi

    else
        ux_error "Path not found: $source_path"
        ux_info "Please check the marketplace and plugin path"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════

claude_plugins_help() {
    ux_header "Claude Marketplace Plugins Management"
    echo ""

    ux_section "Available Commands"
    echo ""

    ux_section "open_claude_plugins"
    ux_info "Open marketplace plugins directory in VSCode"
    ux_bullet "Usage: ${UX_CODE}open_claude_plugins${UX_RESET}"
    echo ""

    ux_section "list_plugins"
    ux_info "List all available marketplaces and their skills"
    ux_bullet "Usage: ${UX_CODE}list_plugins${UX_RESET}"
    echo ""

    ux_section "init_plugins_docs"
    ux_info "Initialize Korean documentation directory structure"
    ux_bullet "Usage: ${UX_CODE}init_plugins_docs${UX_RESET}"
    echo ""

    ux_section "sync_plugins_structure"
    ux_info "Create directory structure mirroring plugins organization"
    ux_bullet "Usage: ${UX_CODE}sync_plugins_structure${UX_RESET}"
    echo ""

    ux_section "view_plugin_info <plugin-name>"
    ux_info "View specific plugin information"
    ux_bullet "Usage: ${UX_CODE}view_plugin_info algorithmic-art${UX_RESET}"
    echo ""

    ux_section "generate_plugin_doc_ko <source-file> <output-file> [ai-tool]"
    ux_info "Generate Korean documentation from plugin file using any AI tool"
    ux_bullet "Usage (default Claude): ${UX_CODE}generate_plugin_doc_ko file.md output_KO.md${UX_RESET}"
    ux_bullet "Usage (Gemini): ${UX_CODE}generate_plugin_doc_ko file.md output_KO.md gemini${UX_RESET}"
    echo ""

    ux_section "create_plugin_structure_ko <marketplace> <plugin-path> [ai-tool]"
    ux_info "Create structure and generate Korean docs in one command (RECOMMENDED)"
    ux_bullet "Usage (default): ${UX_CODE}create_plugin_structure_ko <marketplace> <path/to/file.md>${UX_RESET}"
    ux_bullet "Usage (Gemini): ${UX_CODE}create_plugin_structure_ko <marketplace> <path/to/file.md> gemini${UX_RESET}"
    echo ""

    ux_section "Quick Examples"
    ux_bullet "1. Generate with default AI (Claude):"
    ux_bullet "   ${UX_CODE}create-plugin-ko claude-code-workflows plugins/code-refactoring/agents/code-reviewer.md${UX_RESET}"
    echo ""
    ux_bullet "2. Generate with Gemini:"
    ux_bullet "   ${UX_CODE}create-plugin-ko claude-code-workflows plugins/code-refactoring/agents/code-reviewer.md gemini${UX_RESET}"
    echo ""
    ux_bullet "3. Change default AI tool for session:"
    ux_bullet "   ${UX_CODE}export CLAUDE_DOC_GENERATOR=codex${UX_RESET}"
    ux_bullet "   ${UX_CODE}create-plugin-ko claude-code-workflows plugins/code-refactoring/agents/code-reviewer.md${UX_RESET}"
    echo ""
    ux_bullet "4. Review the generated file:"
    ux_bullet "   ${UX_CODE}code ~/.claude/docs/marketplaces/claude-code-workflows/plugins/code-refactoring/agents/code-reviewer_KO.md${UX_RESET}"
    echo ""
    ux_bullet "5. Commit to git:"
    ux_bullet "   ${UX_CODE}cd ~/dotfiles && git add claude/docs/ && git commit -m 'docs: Add Korean summary'${UX_RESET}"
    echo ""

    ux_section "Supported AI Tools"
    ux_bullet "claude - Anthropic Claude (default)"
    ux_bullet "gemini - Google Gemini"
    ux_bullet "codex - OpenAI Codex"
    ux_bullet "Any CLI tool accepting -p or --prompt flag"
    echo ""

    ux_section "Recommended Workflow"
    ux_bullet "1. ${UX_CODE}init_plugins_docs${UX_RESET} - Initialize docs directory (first time only)"
    ux_bullet "2. ${UX_CODE}open_claude_plugins${UX_RESET} - Review plugin files in VSCode"
    ux_bullet "3. ${UX_CODE}create-plugin-ko <marketplace> <path>${UX_RESET} - Generate Korean summary"
    ux_bullet "4. Edit & customize generated ${UX_CODE}*_KO.md${UX_RESET} file"
    ux_bullet "5. Add personal notes to ${UX_CODE}README.md${UX_RESET}"
    ux_bullet "6. ${UX_CODE}git add && git commit${UX_RESET} - Save to dotfiles repository"
    echo ""

    ux_section "Directory Structure"
    ux_info "Plugins (read-only marketplace):"
    ux_bullet "\$HOME/.claude/plugins/marketplaces/[marketplace]/plugins/[plugin-name]/agents/[agent].md"
    echo ""
    ux_info "Documentation (git-tracked, mounted):"
    ux_bullet "\$HOME/.claude/docs/marketplaces/[marketplace]/plugins/[plugin-name]/agents/"
    ux_bullet "  ├── [agent]_KO.md    (Korean summary, auto-generated)"
    ux_bullet "  └── README.md         (Learning notes, manual)"
    echo ""

    ux_section "Git Integration"
    ux_info "All documentation is mounted and automatically git-tracked:"
    ux_bullet "User location: ${UX_INFO}~/.claude/docs${UX_RESET} (via bind mount)"
    ux_bullet "Git source: ${UX_INFO}~/dotfiles/claude/docs${UX_RESET}"
    ux_bullet "Changes are version-controlled and shareable across machines"
}
