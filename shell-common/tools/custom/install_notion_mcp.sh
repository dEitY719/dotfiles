#!/bin/bash
# shell-common/tools/custom/install_notion_mcp.sh
# Install and configure Notion MCP (Model Context Protocol) server for claude-code

set -e

# Initialize common tools environment
source "$(dirname "$0")/init.sh" || exit 1

# ─────────────────────────────────────────────────────────────────────────────
# Pre-Flight Checks
# ─────────────────────────────────────────────────────────────────────────────

# Check if Node.js and npm are installed
_check_nodejs() {
    if ! command -v node &>/dev/null; then
        ux_error "Node.js is not installed"
        ux_info "Install Node.js from: https://nodejs.org"
        return 1
    fi

    if ! command -v npm &>/dev/null; then
        ux_error "npm is not installed"
        return 1
    fi

    local node_version
    node_version=$(node --version)
    local npm_version
    npm_version=$(npm --version)

    ux_success "Node.js $node_version and npm $npm_version are installed"
}

# Check if claude-code CLI is installed
_check_claude_code() {
    if ! command -v claude &>/dev/null; then
        ux_error "claude-code CLI is not installed"
        ux_info "Install from: https://claude.com/claude-code"
        return 1
    fi

    local claude_version
    claude_version=$(claude --version 2>/dev/null || echo "unknown")
    ux_success "claude-code is installed ($claude_version)"
}

# Check if NOTION_API_KEY environment variable is set
_check_notion_key() {
    if [ -z "${NOTION_API_KEY:-}" ]; then
        ux_warning "NOTION_API_KEY is not set in environment"
        ux_info "Steps to get API key:"
        ux_numbered "1" "Visit https://www.notion.so/profile/integrations"
        ux_numbered "2" "Create or select an integration"
        ux_numbered "3" "Copy the API key and export: export NOTION_API_KEY='your_key'"
        return 1
    fi

    ux_success "NOTION_API_KEY is set"
}

# Check if npm install requires sudo
_check_npm_permissions() {
    local test_dir
    test_dir=$(npm config get prefix)

    if [ ! -w "$test_dir" ]; then
        ux_warning "npm global directory requires elevated permissions"
        ux_info "Install will require sudo or npm config changes"
        return 0
    fi

    ux_success "npm global installation is writable"
}

# ─────────────────────────────────────────────────────────────────────────────
# Installation Functions
# ─────────────────────────────────────────────────────────────────────────────

# Install Notion MCP server globally
_install_notion_mcp_server() {
    ux_info "Installing @notionhq/notion-mcp-server globally..."

    local npm_prefix
    npm_prefix=$(npm config get prefix)

    if [ ! -w "$npm_prefix" ]; then
        ux_warning "Installing with sudo (npm requires elevated permissions)..."
        sudo npm install -g @notionhq/notion-mcp-server
    else
        npm install -g @notionhq/notion-mcp-server
    fi

    if npm list -g @notionhq/notion-mcp-server &>/dev/null; then
        ux_success "Notion MCP server installed successfully"
        return 0
    else
        ux_error "Failed to verify Notion MCP server installation"
        return 1
    fi
}

# Register Notion MCP with claude-code
_register_notion_mcp() {
    local api_key="${NOTION_API_KEY:-}"

    if [ -z "$api_key" ]; then
        ux_error "NOTION_API_KEY is not set"
        return 1
    fi

    ux_info "Registering Notion MCP with claude-code..."
    ux_info "Executing: claude mcp add notion --scope user --env NOTION_API_KEY=***"

    claude mcp add notion \
        --scope user \
        --env "NOTION_API_KEY=$api_key" \
        -- npx -y @notionhq/notion-mcp-server

    if [ $? -eq 0 ]; then
        ux_success "Notion MCP registered with claude-code"
        return 0
    else
        ux_error "Failed to register Notion MCP"
        return 1
    fi
}

# Verify MCP registration in ~/.claude.json
_verify_mcp_registration() {
    ux_info "Verifying Notion MCP registration..."

    if [ ! -f ~/.claude.json ]; then
        ux_warning "~/.claude.json not found (may not exist until first use)"
        return 0
    fi

    if grep -q '"notion"' ~/.claude.json; then
        ux_success "Notion MCP found in ~/.claude.json"
        ux_info "Configuration:"

        # Extract and display notion config
        if command -v jq &>/dev/null; then
            jq '.mcp.notion' ~/.claude.json 2>/dev/null || true
        else
            grep -A 2 '"notion"' ~/.claude.json
        fi
        return 0
    else
        ux_warning "Notion MCP not found in ~/.claude.json"
        ux_info "Configuration may take effect after claude-code restart"
        return 0
    fi
}

# Test Notion API token
_test_notion_token() {
    local api_key="${NOTION_API_KEY:-}"

    if [ -z "$api_key" ]; then
        ux_warning "Skipping token test (NOTION_API_KEY not set)"
        return 0
    fi

    ux_info "Testing Notion API token validity..."

    local response
    local http_code
    response=$(curl -s -w "\n%{http_code}" \
        "https://api.notion.com/v1/users/me" \
        -H "Authorization: Bearer $api_key" \
        -H "Notion-Version: 2022-06-28")

    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | head -n-1)

    if [ "$http_code" = "200" ]; then
        local workspace_name
        workspace_name=$(echo "$body" | grep -o '"workspace_name":"[^"]*' | cut -d'"' -f4)
        ux_success "Notion API token is valid!"
        ux_info "Workspace: $workspace_name"
        return 0
    else
        ux_error "Notion API token validation failed (HTTP $http_code)"
        if [ "$http_code" = "401" ]; then
            ux_warning "Invalid or expired API key"
        elif [ "$http_code" = "403" ]; then
            ux_warning "Permission denied - check workspace integration settings"
        fi
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Help Functions
# ─────────────────────────────────────────────────────────────────────────────

_show_usage() {
    ux_section "Notion MCP Installation Help"
    echo ""
    ux_bullet "install-notion-mcp           Install and register Notion MCP server"
    ux_bullet "install-notion-mcp verify    Verify existing installation"
    ux_bullet "install-notion-mcp test      Test Notion API token"
    echo ""

    ux_section "Prerequisites"
    ux_bullet "Node.js 16+ and npm installed"
    ux_bullet "claude-code CLI installed"
    ux_bullet "Notion API key (from https://www.notion.so/profile/integrations)"
    echo ""

    ux_section "Quick Setup"
    ux_numbered "1" "Get Notion API key from integrations page"
    ux_numbered "2" "Export key: export NOTION_API_KEY='your_key_here'"
    ux_numbered "3" "Run: install-notion-mcp"
    echo ""

    ux_section "Environment Variables"
    ux_bullet "NOTION_API_KEY        Notion workspace API token (required)"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Installation Function
# ─────────────────────────────────────────────────────────────────────────────

install_notion_mcp() {
    local action="${1:-install}"

    case "$action" in
        install)
            ux_header "Installing Notion MCP for claude-code"
            echo ""

            ux_section "Pre-Flight Checks"
            _check_nodejs || return 1
            _check_claude_code || return 1
            _check_notion_key || return 1
            _check_npm_permissions
            echo ""

            ux_section "Installation"
            _install_notion_mcp_server || return 1
            echo ""

            ux_section "Registration"
            _register_notion_mcp || return 1
            echo ""

            ux_section "Verification"
            _verify_mcp_registration || return 1
            _test_notion_token || ux_warning "Token test failed - but installation may still succeed"
            echo ""

            ux_success "Notion MCP installation completed!"
            ux_info "For detailed help: notion-help"
            ;;

        verify)
            ux_header "Verifying Notion MCP Installation"
            echo ""
            _check_nodejs || true
            _check_claude_code || true
            _verify_mcp_registration
            ;;

        test)
            ux_header "Testing Notion API Token"
            echo ""
            _check_notion_key || return 1
            _test_notion_token
            ;;

        help)
            _show_usage
            ;;

        *)
            ux_error "Unknown action: $action"
            ux_info "Usage: install-notion-mcp [install|verify|test|help]"
            return 1
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# Direct Execution Handler
# ─────────────────────────────────────────────────────────────────────────────

# Allow direct execution and function sourcing
if [ "${0##*/}" = "install_notion_mcp.sh" ]; then
    install_notion_mcp "$@"
fi
