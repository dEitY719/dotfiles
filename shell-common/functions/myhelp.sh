#!/bin/sh
# shell-common/functions/myhelp.sh
# Shared Help System for bash and zsh
# Automatically detects and lists all *help() functions
# Modules can register descriptions via HELP_DESCRIPTIONS array

# Initialize help descriptions (works in both bash and zsh)
if [ -z "${HELP_DESCRIPTIONS+x}" ]; then
    # Bash: associative array
    # Zsh: will use typeset -A if needed
    HELP_DESCRIPTIONS=""
fi

# Register all help descriptions (shared across shells)
_register_help_descriptions() {
    # These descriptions appear in myhelp output
    # Modules can override by setting before sourcing

    HELP_DESCRIPTIONS="${HELP_DESCRIPTIONS}
apthelp:APT package manager commands
bat-help:bat - Cat replacement with syntax highlighting
cchelp:Claude Code usage help
claudehelp:Claude Code MCP help
clihelp:Custom Project CLI list
codexhelp:Codex CLI commands and aliases
dirhelp:Directory navigation aliases
dockerhelp:Docker commands and aliases
dproxyhelp:Docker Proxy(Corporate) commands
duhelp:Disk usage help
fasd-help:fasd - Fast access to directories and files
fd-help:fd - Fast file finder tool
fzf-help:fzf (Fuzzy Finder) key bindings and usage
gc_help:git-crypt (Transparent Git encryption)
geminihelp:Gemini CLI commands and aliases
githelp:Git shortcuts and aliases
gpuhelp:GPU monitoring commands (WSL2 universal)
litellm_help:LiteLLM commands and aliases
myhelp:Main help system
mysql_help:MySQL Service Management
mytool_help:MyTool - Personal Utility Commands
npmhelp:NPM package manager commands
nvmhelp:NVM (Node Version Manager) commands
pphelp:Python package and code quality tools
psqlhelp:PostgreSQL command helper
pyhelp:Python virtual environment commands
ripgrep-help:ripgrep (rg) fast text search tool
syshelp:System management commands
uvhelp:UV package manager commands
zsh-help:Zsh shell management commands
"
}

# Main help function - works in both bash and zsh
myhelp() {
    _register_help_descriptions

    # Show help header
    if type ux_header >/dev/null 2>&1; then
        ux_header "Dotfiles Help Functions"
    else
        echo ""
        echo "Dotfiles Help Functions"
        echo ""
    fi

    if type ux_section >/dev/null 2>&1; then
        ux_section "Available help commands"
    else
        echo "Available help commands"
        echo "───────────────────────"
    fi

    # Display all registered help topics
    echo "$HELP_DESCRIPTIONS" | grep -v '^$' | sort | while IFS=':' read -r cmd desc; do
        if [ -n "$cmd" ] && [ -n "$desc" ]; then
            printf "  %-20s :  %s\n" "$cmd" "$desc"
        fi
    done

    echo ""

    # Show usage
    if type ux_section >/dev/null 2>&1; then
        ux_section "Usage"
        ux_bullet "myhelp - Show this help"
        ux_bullet "myhelp [command] - Show specific help (e.g., myhelp githelp)"
    else
        echo "Usage"
        echo "─────"
        echo "  myhelp - Show this help"
        echo "  myhelp [command] - Show specific help"
    fi

    echo ""
}
