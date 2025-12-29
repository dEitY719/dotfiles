#!/bin/sh
# shell-common/functions/claudehelp.sh
# claudeHelp - shared between bash and zsh

claudehelp() {
    # Load UX library
    source "${DOTFILES_BASH_DIR}/ux_lib/ux_lib.bash"

    ux_header "Claude Code - MCP & Workflow Guide"

    ux_section "MCP (Model Context Protocol) Commands"
    ux_table_row "claude mcp list" "List installed MCP servers" ""
    ux_table_row "claude mcp get <name>" "Show MCP server details" ""
    ux_table_row "claude mcp add <name> ..." "Add MCP server" ""
    ux_table_row "claude mcp remove <name>" "Remove MCP server" ""
    echo ""

    ux_section "Recommended MCP Servers"
    ux_bullet "Playwright MCP: Web browser automation"
    echo "  Install: ${UX_SUCCESS}claude mcp add playwright --transport stdio -- npx -y @playwright/mcp@latest${UX_RESET}"
    ux_bullet "Sequential Thinking MCP: Logical analysis"
    echo "  Install: ${UX_SUCCESS}claude mcp add sequential-thinking --transport stdio -- npx -y @modelcontextprotocol/server-sequential-thinking${UX_RESET}"
    echo ""

    ux_section "Setup & Requirements"
    ux_table_row "clinstall" "Install Claude Code CLI" ""
    ux_table_row "ensure_jq" "Install jq (required for statusline)" ""
    ux_table_row "claude_init" "Initialize config & skills" ""
    ux_table_row "claude_edit_settings" "Edit settings.json" ""
    echo ""

    ux_section "Workflow Patterns"
    ux_bullet "Plan mode (recommended): ${UX_SUCCESS}claude${UX_RESET} → plan → approve → execute"
    ux_bullet "Test workflow: ${UX_SUCCESS}cltest \"test description\"${UX_RESET}}"
    ux_bullet "Skip permissions (caution): ${UX_SUCCESS}clskip \"request\"${UX_RESET}"
    echo ""

    ux_section "Sandbox Mode"
    ux_info "Use in Claude conversation: ${UX_SUCCESS}/sandbox${UX_RESET}"
    ux_bullet "Select Auto-allow mode"
    ux_bullet "pytest, git, npm auto-approved"
    echo ""

    ux_section "Configuration"
    ux_info "Settings file: ~/dotfiles/bash/claude/settings.json"
    ux_bullet "Sandbox: autoAllowBashIfSandboxed"
    ux_bullet "Auto-allow: pytest, ruff, mypy, tox"
    ux_bullet "Block: .env, ~/.aws, ~/.ssh"
    ux_bullet "Block commands: rm -rf, sudo rm"
    echo ""
}
