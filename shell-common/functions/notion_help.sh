#!/bin/sh
# shell-common/functions/notion_help.sh
# notion-help topic (commands live in tools/integrations/notion.sh)

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

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
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    if [ -n "${NOTION_API_KEY:-}" ]; then
        # POSIX-safe first-10 / last-10 slicing (no ${var:offset:len}).
        # The length guard mirrors bash's "${var: -10}", which yields an empty
        # string when the value is shorter than 10 characters.
        local key_head key_tail key_preview
        key_head=$(printf '%.10s' "$NOTION_API_KEY")
        key_tail=""
        if [ "${#NOTION_API_KEY}" -ge 10 ]; then
            key_tail=$(printf '%s' "$NOTION_API_KEY" | tail -c 10)
        fi
        key_preview="${key_head}...${key_tail}"
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
        --list|list|section|sections)        _notion_help_list_sections ;;
        --all|all)          _notion_help_full ;;
        *)                  _notion_help_section_rows "$1" ;;
    esac
}

alias notion-help='notion_help'
