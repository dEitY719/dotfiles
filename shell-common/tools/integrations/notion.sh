#!/bin/sh
# shell-common/tools/integrations/notion.sh
# Notion API integration for claude-code MCP (Model Context Protocol)

# Load UX library if not already loaded

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

if ! type ux_header >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    . "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/ux_lib/ux_lib.sh" 2>/dev/null || true
fi

# ─────────────────────────────────────────────────────────────────────────────
# Utility Functions
# ─────────────────────────────────────────────────────────────────────────────

# Check if Notion API token is valid
notion_check_token() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
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

    local http_code
    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | head -n-1)

    if [ "$http_code" = "200" ]; then
        local workspace_name
        workspace_name=$(echo "$body" | grep -o '"workspace_name":"[^"]*' | cut -d'"' -f4)
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
        # shellcheck disable=SC2088  # display string, not a path
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

# Verify installation on module load
# Direct-exec guard: ${BASH_SOURCE[0]} is intentionally bash-specific here — it
# is the repo-wide "sourced vs. executed" idiom (see
# git/hooks/checks/direct_exec_guard_check.sh), so the POSIX-dialect warnings
# about it are expected, not drift.
# shellcheck disable=SC3028,SC3054
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    # Being sourced (not directly executed)
    true
else
    # Directly executed (help topic lives in functions/notion_help.sh)
    . "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/functions/notion_help.sh"
    notion_help "$@"
fi
