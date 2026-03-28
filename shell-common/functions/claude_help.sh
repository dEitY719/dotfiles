#!/bin/sh
# shell-common/functions/claude_help.sh

claude_help() {
    # Load UX library (unified library at shell-common/tools/ux_lib/)
    source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"

    ux_header "Claude Code - MCP & Workflow Guide"

    ux_section "MCP (Model Context Protocol) Commands"
    ux_table_row "claude mcp list" "List installed MCP servers" ""
    ux_table_row "claude mcp get <name>" "Show MCP server details" ""
    ux_table_row "claude mcp add <name> ..." "Add MCP server" ""
    ux_table_row "claude mcp remove <name>" "Remove MCP server" ""

    ux_section "Recommended MCP Servers"
    ux_bullet "Playwright MCP: Web browser automation"
    ux_bullet "Install: ${UX_SUCCESS}claude mcp add playwright --transport stdio -- npx -y @playwright/mcp@latest${UX_RESET}"
    ux_bullet "Sequential Thinking MCP: Logical analysis"
    ux_bullet "Install: ${UX_SUCCESS}claude mcp add sequential-thinking --transport stdio -- npx -y @modelcontextprotocol/server-sequential-thinking${UX_RESET}"

    ux_section "Setup & Requirements"
    ux_table_row "clinstall" "Install Claude Code CLI" ""
    ux_table_row "ensure_jq" "Install jq (required for statusline)" ""
    ux_table_row "claude_init" "Initialize config & skills" ""
    ux_table_row "claude_edit_settings" "Edit settings.json" ""

    ux_section "Sandbox Mode"
    ux_info "Use in Claude conversation: ${UX_SUCCESS}/sandbox${UX_RESET}"
    ux_bullet "Select Auto-allow mode"
    ux_bullet "pytest, git, npm auto-approved"

    ux_section "Configuration"
    ux_info "Settings file: ${DOTFILES_ROOT:-$HOME/dotfiles}/claude/settings.json"
    ux_bullet "Sandbox: autoAllowBashIfSandboxed"
    ux_bullet "Auto-allow: pytest, ruff, mypy, tox"
    ux_bullet "Block: .env, ~/.aws, ~/.ssh"
    ux_bullet "Block commands: rm -rf, sudo rm"

    ux_section "Statusline Display"
    ux_info "Real-time session information in Claude Code status bar"
    ux_bullet "🕐 Time (morning/afternoon/night emoji + YY-MM-DD HH:MM:SS)"
    ux_bullet "🤖 Model (emoji + display name: 🐰 Haiku, 🎼 Sonnet, 🎭 Opus)"
    ux_bullet "📁 Project (folder name + git branch with emoji)"
    ux_bullet "📊 Context usage percentage + weekly percentage"
    ux_bullet "💰 Session cost (Green <\$5, Orange \$5-20, Red >\$20)"

    ux_section "Skills Management"
    ux_table_row "claude-skills" "List available Claude Code skills" ""
    ux_info "Skills location: ${DOTFILES_ROOT:-$HOME/dotfiles}/claude/skills/"
}

# Function to list Claude Code skills
_extract_skill_field_fallback() {
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

_extract_skill_metadata() {
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
    fallback_name=$(_extract_skill_field_fallback "$skill_md" "name")
    fallback_desc=$(_extract_skill_field_fallback "$skill_md" "description")
    printf '%s\n%s\n' "$fallback_name" "$fallback_desc"
}

get_claude_skills() {
    local skills_dir="${DOTFILES_ROOT:-$HOME/dotfiles}/claude/skills"
    local skill_path skill_name skill_md yaml_name yaml_desc

    # Check if skills directory exists
    if [ ! -d "$skills_dir" ]; then
        ux_error "No skills directory found at: $skills_dir"
        return 1
    fi

    # Load UX library if available
    if command -v ux_header >/dev/null 2>&1; then
        ux_header "Claude Code Skills"
    else
        ux_info "=== Claude Code Skills ==="
    fi

    # Track if any skills found
    local found_skills=0

    # Iterate through skill directories
    for skill_path in "$skills_dir"/*; do
        # Skip if not a directory
        [ -d "$skill_path" ] || continue

        skill_name="$(basename "$skill_path")"
        skill_md="$skill_path/SKILL.md"

        # Skip if SKILL.md doesn't exist
        [ -f "$skill_md" ] || continue

        # Extract name and description from YAML frontmatter
        yaml_name=$(_extract_skill_metadata "$skill_md" | sed -n '1p')
        yaml_desc=$(_extract_skill_metadata "$skill_md" | sed -n '2p')

        # Use directory name as fallback
        [ -n "$yaml_name" ] || yaml_name="$skill_name"
        [ -n "$yaml_desc" ] || yaml_desc="(No description)"

        # Truncate description to 80 chars for readability
        if [ ${#yaml_desc} -gt 80 ]; then
            yaml_desc="$(printf '%s' "$yaml_desc" | cut -c1-77)..."
        fi

        # Output formatted line (ux_bullet preferred for readability)
        if command -v ux_bullet >/dev/null 2>&1; then
            ux_bullet "$(printf '%-20s | %s' "$yaml_name" "$yaml_desc")"
        else
            printf "%-20s | %s\n" "$yaml_name" "$yaml_desc"
        fi

        found_skills=1
    done

    # If no skills found
    if [ "$found_skills" -eq 0 ]; then
        ux_info "No skills found in $skills_dir"
        return 0
    fi

    if command -v ux_info >/dev/null 2>&1; then
        ux_info "Skills location: $skills_dir"
    fi
}

alias claude-help='claude_help'
alias claude-skills='get_claude_skills'
