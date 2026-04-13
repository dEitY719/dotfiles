#!/bin/sh
# shell-common/functions/ai_tools_help.sh
# Bundle: AI/LLM tool help functions
#
# Cross-file dependencies (auto-sourced before this file):
#   ollama_backend_detect() — from tools/integrations/ollama.sh
#     Used by: _ollama_help_auto() to detect local vs docker backend
#     Guarded by: command -v check (graceful fallback to docker mode)

# --- claude_help (from claude_help.sh) ---

_claude_help_summary() {
    ux_info "Usage: claude-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "mcp: list | get | add | remove"
    ux_bullet_sub "recommended: Playwright MCP | Sequential Thinking MCP"
    ux_bullet_sub "setup: clinstall | ensure_jq | claude_init | claude_edit_settings"
    ux_bullet_sub "sandbox: /sandbox | Auto-allow | pytest, git, npm"
    ux_bullet_sub "config: settings.json | autoAllow | block paths | block cmds"
    ux_bullet_sub "statusline: time | model | project | context | cost"
    ux_bullet_sub "skills: claude-skills"
    ux_bullet_sub "details: claude-help <section>  (example: claude-help mcp)"
}

_claude_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "mcp"
    ux_bullet_sub "recommended"
    ux_bullet_sub "setup"
    ux_bullet_sub "sandbox"
    ux_bullet_sub "config"
    ux_bullet_sub "statusline"
    ux_bullet_sub "skills"
}

_claude_help_rows_mcp() {
    ux_table_row "claude mcp list" "List installed MCP servers" ""
    ux_table_row "claude mcp get <name>" "Show MCP server details" ""
    ux_table_row "claude mcp add <name> ..." "Add MCP server" ""
    ux_table_row "claude mcp remove <name>" "Remove MCP server" ""
}

_claude_help_rows_recommended() {
    ux_bullet "Playwright MCP: Web browser automation"
    ux_bullet "Install: ${UX_SUCCESS}claude mcp add playwright --transport stdio -- npx -y @playwright/mcp@latest${UX_RESET}"
    ux_bullet "Sequential Thinking MCP: Logical analysis"
    ux_bullet "Install: ${UX_SUCCESS}claude mcp add sequential-thinking --transport stdio -- npx -y @modelcontextprotocol/server-sequential-thinking${UX_RESET}"
}

_claude_help_rows_setup() {
    ux_table_row "clinstall" "Install Claude Code CLI" ""
    ux_table_row "ensure_jq" "Install jq (required for statusline)" ""
    ux_table_row "claude_init" "Initialize config & skills" ""
    ux_table_row "claude_edit_settings" "Edit settings.json" ""
}

_claude_help_rows_sandbox() {
    ux_info "Use in Claude conversation: ${UX_SUCCESS}/sandbox${UX_RESET}"
    ux_bullet "Select Auto-allow mode"
    ux_bullet "pytest, git, npm auto-approved"
}

_claude_help_rows_config() {
    ux_info "Settings file: ${DOTFILES_ROOT:-$HOME/dotfiles}/claude/settings.json"
    ux_bullet "Sandbox: autoAllowBashIfSandboxed"
    ux_bullet "Auto-allow: pytest, ruff, mypy, tox"
    ux_bullet "Block: .env, ~/.aws, ~/.ssh"
    ux_bullet "Block commands: rm -rf, sudo rm"
}

_claude_help_rows_statusline() {
    ux_info "Real-time session information in Claude Code status bar"
    ux_bullet "🕐 Time (morning/afternoon/night emoji + YY-MM-DD HH:MM:SS)"
    ux_bullet "🤖 Model (emoji + display name: 🐰 Haiku, 🎼 Sonnet, 🎭 Opus)"
    ux_bullet "📁 Project (folder name + git branch with emoji)"
    ux_bullet "📊 Context usage percentage + weekly percentage"
    ux_bullet "💰 Session cost (Green <\$5, Orange \$5-20, Red >\$20)"
}

_claude_help_rows_skills() {
    ux_table_row "claude-skills" "List available Claude Code skills" ""
    ux_info "Skills location: ${DOTFILES_ROOT:-$HOME/dotfiles}/claude/skills/"
}

_claude_help_render_section() {
    ux_section "$1"
    "$2"
}

_claude_help_section_rows() {
    case "$1" in
        mcp)
            _claude_help_rows_mcp
            ;;
        recommended|servers)
            _claude_help_rows_recommended
            ;;
        setup|install)
            _claude_help_rows_setup
            ;;
        sandbox)
            _claude_help_rows_sandbox
            ;;
        config|configuration)
            _claude_help_rows_config
            ;;
        statusline|status)
            _claude_help_rows_statusline
            ;;
        skills)
            _claude_help_rows_skills
            ;;
        *)
            ux_error "Unknown claude-help section: $1"
            ux_info "Try: claude-help --list"
            return 1
            ;;
    esac
}

_claude_help_full() {
    ux_header "Claude Code - MCP & Workflow Guide"

    _claude_help_render_section "MCP (Model Context Protocol) Commands" _claude_help_rows_mcp
    _claude_help_render_section "Recommended MCP Servers" _claude_help_rows_recommended
    _claude_help_render_section "Setup & Requirements" _claude_help_rows_setup
    _claude_help_render_section "Sandbox Mode" _claude_help_rows_sandbox
    _claude_help_render_section "Configuration" _claude_help_rows_config
    _claude_help_render_section "Statusline Display" _claude_help_rows_statusline
    _claude_help_render_section "Skills Management" _claude_help_rows_skills
}

claude_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _claude_help_summary
            ;;
        --list|list)
            _claude_help_list_sections
            ;;
        --all|all)
            _claude_help_full
            ;;
        *)
            _claude_help_section_rows "$1"
            ;;
    esac
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

# --- codex_help (from codex_help.sh) ---

_codex_help_summary() {
    ux_info "Usage: codex-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "basic: codex | codex-help | official help | codex-version | codex-yolo"
    ux_bullet_sub "setup: codex-install | codex-uninstall | codex-status | codex-skills-sync | auto sync"
    ux_bullet_sub "interactive: codex | codex prompt"
    ux_bullet_sub "tips: config dir | auth | auto sync env vars"
    ux_bullet_sub "details: codex-help <section>  (example: codex-help setup)"
}

_codex_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "basic"
    ux_bullet_sub "setup"
    ux_bullet_sub "interactive"
    ux_bullet_sub "tips"
}

_codex_help_rows_basic() {
    ux_table_row "codex" "codex" "Base command"
    ux_table_row "codex-help" "codex-help" "Show dotfiles codex commands"
    ux_table_row "Official help" "codex help | --help | -h" "Show CLI help"
    ux_table_row "codex-version" "codex --version" "Check version"
    ux_table_row "codex-yolo" "codex --dangerously-bypass-approvals-and-sandbox" "Bypass guardrails"
}

_codex_help_rows_setup() {
    ux_table_row "codex-install" "Install Script" "Install Codex CLI"
    ux_table_row "codex-uninstall" "Uninstall Script" "Remove Codex CLI"
    ux_table_row "codex-status" "Status Check" "Show installation status"
    ux_table_row "codex-skills-sync" "Skills Sync" "Sync skills symlinks"
    ux_table_row "Auto skill sync" "Enabled by default" "Before codex command"
}

_codex_help_rows_interactive() {
    ux_table_row "codex" "codex" "Start interactive"
    ux_table_row "codex prompt" "codex prompt" "Run with prompt"
}

_codex_help_rows_tips() {
    ux_bullet "Config: ~/.codex/ or ~/.config/codex/"
    ux_bullet "Auth: Use 'codex' to authenticate"
    ux_bullet "Auto sync: before codex command + prompt cycle"
    ux_bullet "Disable auto sync: export CODEX_SKILLS_AUTO_SYNC=0"
    ux_bullet "Verbose auto sync: export CODEX_SKILLS_AUTO_SYNC_VERBOSE=1"
    ux_bullet "Auto sync interval(sec): export CODEX_SKILLS_AUTO_SYNC_INTERVAL=5"
}

_codex_help_render_section() {
    ux_section "$1"
    "$2"
}

_codex_help_section_rows() {
    case "$1" in
        basic|commands)
            _codex_help_rows_basic
            ;;
        setup|install|installation)
            _codex_help_rows_setup
            ;;
        interactive|run)
            _codex_help_rows_interactive
            ;;
        tips|tip)
            _codex_help_rows_tips
            ;;
        *)
            ux_error "Unknown codex-help section: $1"
            ux_info "Try: codex-help --list"
            return 1
            ;;
    esac
}

_codex_help_full() {
    ux_header "Codex Quick Commands"

    _codex_help_render_section "Basic Commands" _codex_help_rows_basic
    _codex_help_render_section "Installation & Setup" _codex_help_rows_setup
    _codex_help_render_section "Interactive Mode" _codex_help_rows_interactive
    _codex_help_render_section "Tips" _codex_help_rows_tips
}

codex_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _codex_help_summary
            ;;
        --list|list)
            _codex_help_list_sections
            ;;
        --all|all)
            _codex_help_full
            ;;
        *)
            _codex_help_section_rows "$1"
            ;;
    esac
}

alias codex-help='codex_help'

# --- gemini_help (from gemini_help.sh) ---

_gemini_help_summary() {
    ux_info "Usage: gemini-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "basic: gg | gflash | gpro | gver | ghelp"
    ux_bullet_sub "setup: ginstall | guninstall"
    ux_bullet_sub "tips: web login auth | ghelp for CLI options"
    ux_bullet_sub "details: gemini-help <section>  (example: gemini-help basic)"
}

_gemini_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "basic"
    ux_bullet_sub "setup"
    ux_bullet_sub "tips"
}

_gemini_help_rows_basic() {
    ux_table_row "gg" "gcloud gemini" "Base command"
    ux_table_row "gflash" "gemini --model flash" "Use Flash model"
    ux_table_row "gpro" "gemini --model pro" "Use Pro model"
    ux_table_row "gver" "gemini --version" "Check version"
    ux_table_row "ghelp" "gemini --help" "Gemini Help"
}

_gemini_help_rows_setup() {
    ux_table_row "ginstall" "Install Script" "Install Gemini CLI"
    ux_table_row "guninstall" "Uninstall Script" "Remove Gemini CLI"
}

_gemini_help_rows_tips() {
    ux_bullet "Auth via web login (no API key file needed)"
    ux_bullet "Use 'ghelp' for detailed CLI options"
}

_gemini_help_render_section() {
    ux_section "$1"
    "$2"
}

_gemini_help_section_rows() {
    case "$1" in
        basic|commands)
            _gemini_help_rows_basic
            ;;
        setup|install|installation)
            _gemini_help_rows_setup
            ;;
        tips|tip)
            _gemini_help_rows_tips
            ;;
        *)
            ux_error "Unknown gemini-help section: $1"
            ux_info "Try: gemini-help --list"
            return 1
            ;;
    esac
}

_gemini_help_full() {
    ux_header "Gemini CLI Quick Commands"

    _gemini_help_render_section "Basic Commands" _gemini_help_rows_basic
    _gemini_help_render_section "Installation & Setup" _gemini_help_rows_setup
    _gemini_help_render_section "Tips" _gemini_help_rows_tips
}

gemini_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _gemini_help_summary
            ;;
        --list|list)
            _gemini_help_list_sections
            ;;
        --all|all)
            _gemini_help_full
            ;;
        *)
            _gemini_help_section_rows "$1"
            ;;
    esac
}

alias gemini-help='gemini_help'

# --- litellm_help (from litellm_help.sh) ---

litellm_help() {
    ux_header "LiteLLM Commands"

    ux_section "Basic Commands"
    ux_table_row "llm-start" "Start Stack" "docker compose up"
    ux_table_row "llm-stop" "Stop Stack" "docker compose down"
    ux_table_row "llm-restart" "Restart" "Stop & Start"
    ux_table_row "llm-status" "Status" "Check health & models"
    ux_table_row "llm-models" "List Models" "Show loaded models"
    ux_table_row "llm-test" "Test Model" "Run basic prompt"

    ux_section "Project Info"
    ux_table_row "Path" "$LITELLM_PROJECT_PATH" ""
    ux_table_row "URL" "$LITELLM_URL" ""
    ux_table_row "Key" "$LITELLM_API_KEY" ""
}

alias litellm-help='litellm_help'
alias llm-help='litellm_help'

# --- ollama_help (from ollama_help.sh) ---

# NOTE: UX library is loaded by the loader before functions/ — no need to reload here

# Main help function with auto-detection
ollama_help() {
    local mode="${1:-auto}"

    case "$mode" in
        --docker)
            _ollama_help_docker
            ;;
        --local)
            _ollama_help_local
            ;;
        --status | --backend)
            _ollama_help_status
            ;;
        --auto | auto | "")
            _ollama_help_auto
            ;;
        --help | -h)
            _ollama_help_usage
            ;;
        *)
            ux_error "Unknown option: $mode"
            _ollama_help_usage
            return 1
            ;;
    esac
}

# Auto-detect and show appropriate help
# Depends on: ollama_backend_detect() from tools/integrations/ollama.sh (auto-sourced)
_ollama_help_auto() {
    if command -v ollama_backend_detect &> /dev/null; then
        local backend=$(ollama_backend_detect 2>/dev/null || echo "docker")
        if [[ "$backend" == "local" ]]; then
            _ollama_help_local
        else
            _ollama_help_docker
        fi
    else
        _ollama_help_docker
    fi
}

# WSL Local Ollama Help
_ollama_help_local() {
    # Check if local ollama is available
    if ! command -v ollama &> /dev/null; then
        ux_header "WSL Ollama — Not Installed"

        ux_section "Current Status"
        ux_error "WSL Ollama is not installed"
        ux_info "Currently using: Docker Ollama only"

        ux_section "Install WSL Ollama"
        ux_info "Run the installation command: install-ollama"

        ux_section "For Now"
        ux_info "Docker Ollama is running and ready to use."
        ux_info "View Docker commands with: ${UX_CODE}ollama-help --docker${UX_RESET}"
        return 0
    fi

    ux_header "Ollama Management (WSL Local)"

    ux_section "Model Management"
    ux_table_row "ollama-models" "List all installed models"
    ux_table_row "ollama-pull <name>" "Download a model (e.g., gpt-oss:20b)"
    ux_table_row "ollama-rm <name>" "Remove a model"
    ux_table_row "ollama-show <name>" "Display model configuration"

    ux_section "Model Usage"
    ux_table_row "ollama-run <model>" "Interactive chat session"
    ux_table_row "ollama-prompt <model> <txt>" "Single prompt execution"

    ux_section "Status & Information"
    ux_table_row "ollama-version" "Display Ollama version"
    ux_table_row "ollama-status" "Check service status and API health"

    ux_section "Server Management"
    ux_table_row "ollama-serve" "Start Ollama server (foreground)"
    ux_table_row "ollama-launch claude" "Connect Claude Code to Ollama"

    ux_section "System Management"
    ux_table_row "ollama-restart" "Restart systemd service and verify all checks"

    ux_section "Popular Models"
    ux_table_row "tinyllama:latest" "637 MB"  "Fast, lightweight"
    ux_table_row "gpt-oss:20b"      "13 GB"   "High-capability model"
    ux_table_row "mistral"          "4.1 GB"  "General-purpose"
    ux_table_row "neural-chat"      "3.8 GB"  "Chat-optimized"
    ux_table_row "bge-m3:latest"    "1.2 GB"  "Embeddings/search"

    ux_section "Quick Reference"
    ux_info "Storage:   ~/.ollama"
    ux_info "API:       http://127.0.0.1:11434"
    ux_info "Use ${UX_CODE}ollama-help --docker${UX_RESET} for Docker commands"
}

# Docker Ollama Help
_ollama_help_docker() {
    ux_header "Ollama Management (Docker Container)"

    ux_section "Model Management"
    ux_table_row "ollama-models [--docker]" "List all models"
    ux_table_row "ollama-pull --docker <name>" "Download a model"
    ux_table_row "ollama-rm --docker <name>" "Remove a model"
    ux_table_row "ollama-show --docker <name>" "Show model details"

    ux_section "Model Usage"
    ux_table_row "ollama-run --docker <model>" "Interactive chat"
    ux_table_row "ollama-prompt --docker <...>" "Single prompt"

    ux_section "Container Operations"
    ux_table_row "ollama-logs" "Follow container logs (real-time)"
    ux_table_row "ollama-stats" "Monitor resource usage"

    ux_section "Popular Models"
    ux_table_row "tinyllama:latest" "637 MB"  "Fast, lightweight"
    ux_table_row "gpt-oss:20b"      "13 GB"   "High-capability model"
    ux_table_row "mistral"          "4.1 GB"  "General-purpose"
    ux_table_row "neural-chat"      "3.8 GB"  "Chat-optimized"
    ux_table_row "bge-m3:latest"    "1.2 GB"  "Embeddings/search"

    ux_section "Quick Reference"
    ux_info "Storage:   /root/.ollama (container volume)"
    ux_info "API:       http://localhost:11434"
    ux_info "Use ${UX_CODE}ollama-help --local${UX_RESET} for WSL commands"
}

# Show current Ollama status
_ollama_help_status() {
    ux_header "Current Ollama Backend Status"

    if command -v ollama_backend_status &> /dev/null; then
        ollama_backend_status
    else
        if command -v ollama &> /dev/null; then
            ux_success "Backend: LOCAL (WSL)"
            ux_info "Version: $(ollama --version 2>/dev/null || echo 'unknown')"
            ux_info "API: http://127.0.0.1:11434"
        elif docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^ollama$"; then
            ux_success "Backend: DOCKER"
            ux_info "Container: ollama (running)"
            ux_info "API: http://ollama:11434"
        else
            ux_error "No Ollama backend available"
            ux_info "Install options:"
            ux_bullet "WSL: bash ~/dotfiles/shell-common/tools/custom/install_ollama.sh"
            ux_bullet "Docker: docker start ollama"
        fi
    fi
}

# Show usage information
_ollama_help_usage() {
    ux_header "ollama-help — Ollama Command Reference"

    ux_section "Usage"
    ux_info "ollama-help [OPTION]"

    ux_section "Options"
    ux_table_row "--auto" "Auto-detect backend (default)"
    ux_table_row "--docker" "Show Docker-specific commands"
    ux_table_row "--local" "Show WSL-specific commands"
    ux_table_row "--status" "Display current Ollama status"
    ux_table_row "-h, --help" "Show this help"
}
