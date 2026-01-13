#!/bin/bash
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

notion_help() {
    ux_header "Notion MCP Setup & Configuration"

    ux_section "1️⃣  Generate API Key from Notion"
    ux_numbered "1" "Visit https://www.notion.so/profile/integrations"
    ux_numbered "2" "Click 'Create new integration' button"
    ux_numbered "3" "Configure integration name and capabilities"
    ux_numbered "4" "Copy the API key"
    ux_numbered "5" "Store in .env: NOTION_API_KEY='your_key_here'"
    echo ""

    ux_section "2️⃣  Install Notion MCP Server Globally"
    ux_bullet "npm install -g @notionhq/notion-mcp-server"
    ux_warning "Requires Node.js and npm to be installed"
    echo ""

    ux_section "3️⃣  Register MCP Server with Claude Code"
    ux_bullet "claude mcp add notion --scope user --env NOTION_API_KEY=\$NOTION_API_KEY -- npx -y @notionhq/notion-mcp-server"
    ux_info "Uses: --scope user (per-user configuration)"
    echo ""

    ux_section "4️⃣  Verify Installation"
    ux_bullet "cat ~/.claude.json | grep notion"
    ux_bullet "Should output: \"notion\": { \"@notionhq/notion-mcp-server\" ... }"
    echo ""

    ux_section "5️⃣  Test API Token Validity"
    ux_bullet "curl https://api.notion.com/v1/users/me -H \"Authorization: Bearer \$NOTION_API_KEY\" -H \"Notion-Version: 2022-06-28\""
    ux_info "Success response: returns workspace and user information"
    echo ""

    ux_section "📋 Environment File Example"
    cat <<'ENV_EXAMPLE'
# .env or shell env file
NOTION_API_KEY='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'

# Optional: Workspace settings
NOTION_WORKSPACE_ID='2bfc8bad-75a1-8144-910a-00030418db4d'
NOTION_WORKSPACE_NAME='Claude-Research'
ENV_EXAMPLE
    echo ""

    ux_section "🔗 Useful Links"
    ux_bullet "Notion Integration Docs: https://developers.notion.com"
    ux_bullet "Claude Code Docs: https://claude.com/claude-code"
    ux_bullet "MCP Specification: https://modelcontextprotocol.io"
    echo ""
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
