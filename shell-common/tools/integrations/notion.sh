#!/bin/sh
# shell-common/tools/integrations/notion.sh
# Notion API integration for claude-code MCP (Model Context Protocol)

# Load UX library if not already loaded
if ! declare -f ux_header >/dev/null 2>&1; then
    source "${BASH_SOURCE[0]%/*}/../ux_lib/ux_lib.sh" 2>/dev/null || true
fi

# ─────────────────────────────────────────────────────────────────────────────
# Notion Help Documentation
# ─────────────────────────────────────────────────────────────────────────────

: <<'NOTION_HELP'
Notion MCP (Model Context Protocol) Integration

The Notion MCP server enables Claude to interact with your Notion workspace
through a structured API. This integration manages:

1. API Key configuration and validation
2. MCP server installation and registration
3. Workspace permissions and access verification

For detailed setup instructions, run: notion-help
NOTION_HELP

# ─────────────────────────────────────────────────────────────────────────────
# Notion Help Function
# ─────────────────────────────────────────────────────────────────────────────

_notion_help_summary() {
    ux_info "Usage: notion-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "status: NOTION_API_KEY environment check"
    ux_bullet_sub "apikey: generate API key from Notion integrations"
    ux_bullet_sub "install: npm install -g @notionhq/notion-mcp-server"
    ux_bullet_sub "register: claude mcp add notion --scope user"
    ux_bullet_sub "verify: cat ~/.claude.json | grep notion"
    ux_bullet_sub "test: curl api.notion.com/v1/users/me"
    ux_bullet_sub "env: .env example (NOTION_API_KEY | WORKSPACE_ID | WORKSPACE_NAME)"
    ux_bullet_sub "links: developers.notion.com | claude.com/claude-code | modelcontextprotocol.io"
    ux_bullet_sub "details: notion-help <section>  (example: notion-help install)"
}

_notion_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "status"
    ux_bullet_sub "apikey"
    ux_bullet_sub "install"
    ux_bullet_sub "register"
    ux_bullet_sub "verify"
    ux_bullet_sub "test"
    ux_bullet_sub "env"
    ux_bullet_sub "links"
}

_notion_help_rows_status() {
    if [ -n "${NOTION_API_KEY:-}" ]; then
        local key_preview="${NOTION_API_KEY:0:10}...${NOTION_API_KEY: -10}"
        ux_success "NOTION_API_KEY is set"
        ux_info "Key preview: $key_preview"
    else
        ux_warning "NOTION_API_KEY is not set"
        ux_info "Run: export NOTION_API_KEY='your_key_here' or source ~/.env"
    fi
}

_notion_help_rows_apikey() {
    ux_numbered "1" "Visit https://www.notion.so/profile/integrations"
    ux_numbered "2" "Click 'Create new integration' button"
    ux_numbered "3" "Configure integration name and capabilities"
    ux_numbered "4" "Copy the API key"
    ux_numbered "5" "Store in .env: NOTION_API_KEY='your_key_here'"
}

_notion_help_rows_install() {
    ux_bullet "npm install -g @notionhq/notion-mcp-server"
    ux_warning "Requires Node.js and npm to be installed"
}

_notion_help_rows_register() {
    ux_bullet "claude mcp add notion --scope user --env NOTION_API_KEY=\$NOTION_API_KEY -- npx -y @notionhq/notion-mcp-server"
    ux_info "Uses: --scope user (per-user configuration)"
}

_notion_help_rows_verify() {
    ux_bullet "cat ~/.claude.json | grep notion"
    ux_bullet "Should output: \"notion\": { \"@notionhq/notion-mcp-server\" ... }"
}

_notion_help_rows_test() {
    ux_bullet "curl https://api.notion.com/v1/users/me -H \"Authorization: Bearer \$NOTION_API_KEY\" -H \"Notion-Version: 2022-06-28\" | jq"
    ux_info "Success response: returns workspace and user information (formatted with jq)"
}

_notion_help_rows_env() {
    cat <<'ENV_EXAMPLE'
# .env or shell env file
NOTION_API_KEY='ntn_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'

# Optional: Workspace settings
NOTION_WORKSPACE_ID='xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
NOTION_WORKSPACE_NAME='Your-Workspace-Name'
ENV_EXAMPLE
}

_notion_help_rows_links() {
    ux_bullet "Notion Integration Docs: https://developers.notion.com"
    ux_bullet "Claude Code Docs: https://claude.com/claude-code"
    ux_bullet "MCP Specification: https://modelcontextprotocol.io"
}

_notion_help_render_section() {
    ux_section "$1"
    "$2"
}

_notion_help_section_rows() {
    case "$1" in
        status|env-status)        _notion_help_rows_status ;;
        apikey|api-key|key)       _notion_help_rows_apikey ;;
        install|setup)            _notion_help_rows_install ;;
        register|mcp)             _notion_help_rows_register ;;
        verify|check)             _notion_help_rows_verify ;;
        test|token)               _notion_help_rows_test ;;
        env|environment)          _notion_help_rows_env ;;
        links|docs|references)    _notion_help_rows_links ;;
        *)
            ux_error "Unknown notion-help section: $1"
            ux_info "Try: notion-help --list"
            return 1
            ;;
    esac
}

_notion_help_full() {
    ux_header "Notion MCP Setup & Configuration"
    _notion_help_render_section "Current Environment Status" _notion_help_rows_status
    _notion_help_render_section "Generate API Key from Notion" _notion_help_rows_apikey
    _notion_help_render_section "Install Notion MCP Server Globally" _notion_help_rows_install
    _notion_help_render_section "Register MCP Server with Claude Code" _notion_help_rows_register
    _notion_help_render_section "Verify Installation" _notion_help_rows_verify
    _notion_help_render_section "Test API Token Validity" _notion_help_rows_test
    _notion_help_render_section "Environment File Example" _notion_help_rows_env
    _notion_help_render_section "Useful Links" _notion_help_rows_links
}

notion_help() {
    case "${1:-}" in
        ""|-h|--help|help) _notion_help_summary ;;
        --list|list)        _notion_help_list_sections ;;
        --all|all)          _notion_help_full ;;
        *)                  _notion_help_section_rows "$1" ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# Utility Functions
# ─────────────────────────────────────────────────────────────────────────────

# Check if Notion API token is valid
notion_check_token() {
    local api_key="${NOTION_API_KEY:-}"

    if [ -z "$api_key" ]; then
        ux_error "NOTION_API_KEY is not set"
        ux_info "Run: notion-help for setup instructions"
        return 1
    fi

    ux_info "Validating Notion API token..."

    local response
    response=$(curl -s -w "\n%{http_code}" \
        "https://api.notion.com/v1/users/me" \
        -H "Authorization: Bearer $api_key" \
        -H "Notion-Version: 2022-06-28")

    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n-1)

    if [ "$http_code" = "200" ]; then
        local workspace_name=$(echo "$body" | grep -o '"workspace_name":"[^"]*' | cut -d'"' -f4)
        ux_success "Token is valid!"
        ux_info "Workspace: $workspace_name"
        return 0
    else
        ux_error "Token validation failed (HTTP $http_code)"
        echo "$body" | head -n 1 >&2
        return 1
    fi
}

# Check if MCP server is registered
notion_check_mcp() {
    if [ ! -f ~/.claude.json ]; then
        ux_error "~/.claude.json not found"
        ux_info "MCP servers not configured yet"
        return 1
    fi

    if grep -q '"notion"' ~/.claude.json; then
        ux_success "Notion MCP is registered in ~/.claude.json"
        return 0
    else
        ux_warning "Notion MCP not found in ~/.claude.json"
        return 1
    fi
}

# Register alias for notion-help
alias notion-help='notion_help'

# Verify installation on module load
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    # Being sourced (not directly executed)
    true
else
    # Directly executed
    notion_help
fi
