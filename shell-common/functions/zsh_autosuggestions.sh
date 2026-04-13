#!/bin/sh
# shell-common/functions/zsh_autosuggestions.sh
# zsh-autosuggestions helper functions and documentation
# ZSH only plugin - provides intelligent command suggestions
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# Load UX Library (if not already loaded)
# ═══════════════════════════════════════════════════════════════

if ! type ux_header &>/dev/null 2>&1; then
    SHELL_COMMON="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"
    # shellcheck source=/dev/null
    source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" 2>/dev/null || true
fi

# ═══════════════════════════════════════════════════════════════
# zsh-autosuggestions Help and Documentation
# ═══════════════════════════════════════════════════════════════

# SSOT helpers for zsh-autosuggestions-help
_zsh_autosuggestions_help_summary() {
    ux_info "Usage: zsh-autosuggestions-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "about: what is zsh-autosuggestions"
    ux_bullet_sub "keys: Tab | Ctrl+Right | Ctrl+F | Ctrl+A"
    ux_bullet_sub "how: how the suggestions work"
    ux_bullet_sub "example: example usage"
    ux_bullet_sub "env: ZSH_AUTOSUGGEST_* variables"
    ux_bullet_sub "strategies: history | completion | match_prev_cmd"
    ux_bullet_sub "customize: ~/.zshrc snippets"
    ux_bullet_sub "status: installation status"
    ux_bullet_sub "details: zsh-autosuggestions-help <section>"
}

_zsh_autosuggestions_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "about"
    ux_bullet_sub "keys"
    ux_bullet_sub "how"
    ux_bullet_sub "example"
    ux_bullet_sub "env"
    ux_bullet_sub "strategies"
    ux_bullet_sub "customize"
    ux_bullet_sub "status"
}

_zsh_autosuggestions_help_rows_about() {
    ux_info "Auto-suggests commands as you type, based on your history."
    ux_info "Press Tab or Ctrl+Right to accept the suggestion."
}

_zsh_autosuggestions_help_rows_keys() {
    ux_table_header "Key" "Action"
    ux_table_row "Tab / Ctrl+Right" "Accept suggestion"
    ux_table_row "Ctrl+F" "Accept next word of suggestion"
    ux_table_row "Ctrl+A" "Accept entire suggestion"
    ux_table_row "Up/Down Arrow" "Navigate history (overrides suggestions)"
}

_zsh_autosuggestions_help_rows_how() {
    ux_bullet "As you type, suggestions appear in gray text"
    ux_bullet "Suggestions are based on command history"
    ux_bullet "Press Tab (or configured key) to accept"
    ux_bullet "Press Esc or start typing to dismiss"
}

_zsh_autosuggestions_help_rows_example() {
    ux_info "Type 'work' and zsh will suggest:"
    ux_bullet "work-log list help"
    ux_bullet "work-log add SWINNOTEAM-906 -t coordination..."
    ux_bullet "work-help"
    ux_info "Press Tab to accept any suggestion"
}

_zsh_autosuggestions_help_rows_env() {
    ux_table_header "Variable" "Description" "Default"
    ux_table_row "ZSH_AUTOSUGGEST_STRATEGY" "Suggestion matching strategy" "history"
    ux_table_row "ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE" "Max command length to suggest" "unbounded"
    ux_table_row "ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE" "Suggestion text color" "fg=8"
}

_zsh_autosuggestions_help_rows_strategies() {
    ux_bullet "history - Suggest from command history"
    ux_bullet "completion - Suggest from completion"
    ux_bullet "match_prev_cmd - Suggest matching previous command"
}

_zsh_autosuggestions_help_rows_customize() {
    ux_info "Add to ~/.zshrc (before sourcing zsh-autosuggestions):"
    echo "  # Accept suggestion with Tab key"
    echo "  bindkey '\\t' autosuggest-accept"
    echo "  # Change suggestion highlight color"
    echo "  export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=10'"
    echo "  # Use history strategy only"
    echo "  export ZSH_AUTOSUGGEST_STRATEGY=(history)"
}

_zsh_autosuggestions_help_rows_status() {
    if [ -d "${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" ]; then
        ux_success "zsh-autosuggestions is installed"
        echo "  Location: ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
    else
        ux_warning "zsh-autosuggestions is not installed"
        echo "  Run: install-zsh-autosuggestions"
    fi
}

_zsh_autosuggestions_help_render_section() {
    ux_section "$1"
    "$2"
}

_zsh_autosuggestions_help_section_rows() {
    case "$1" in
        about|what)
            _zsh_autosuggestions_help_rows_about
            ;;
        keys|key|bindings|binding)
            _zsh_autosuggestions_help_rows_keys
            ;;
        how|how-it-works)
            _zsh_autosuggestions_help_rows_how
            ;;
        example|examples)
            _zsh_autosuggestions_help_rows_example
            ;;
        env|environment|vars)
            _zsh_autosuggestions_help_rows_env
            ;;
        strategies|strategy)
            _zsh_autosuggestions_help_rows_strategies
            ;;
        customize|custom|config)
            _zsh_autosuggestions_help_rows_customize
            ;;
        status|install)
            _zsh_autosuggestions_help_rows_status
            ;;
        *)
            ux_error "Unknown zsh-autosuggestions-help section: $1"
            ux_info "Try: zsh-autosuggestions-help --list"
            return 1
            ;;
    esac
}

_zsh_autosuggestions_help_full() {
    ux_header "zsh-autosuggestions - Command History Suggestions"
    _zsh_autosuggestions_help_render_section "What is zsh-autosuggestions?" _zsh_autosuggestions_help_rows_about
    _zsh_autosuggestions_help_render_section "Key Bindings" _zsh_autosuggestions_help_rows_keys
    _zsh_autosuggestions_help_render_section "How It Works" _zsh_autosuggestions_help_rows_how
    _zsh_autosuggestions_help_render_section "Example Usage" _zsh_autosuggestions_help_rows_example
    _zsh_autosuggestions_help_render_section "Environment Variables" _zsh_autosuggestions_help_rows_env
    _zsh_autosuggestions_help_render_section "Strategies" _zsh_autosuggestions_help_rows_strategies
    _zsh_autosuggestions_help_render_section "Customization Example" _zsh_autosuggestions_help_rows_customize
    _zsh_autosuggestions_help_render_section "Installation Status" _zsh_autosuggestions_help_rows_status
}

# Display zsh-autosuggestions help and usage
zsh_autosuggestions_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _zsh_autosuggestions_help_summary
            ;;
        --list|list|section|sections)
            _zsh_autosuggestions_help_list_sections
            ;;
        --all|all)
            _zsh_autosuggestions_help_full
            ;;
        *)
            _zsh_autosuggestions_help_section_rows "$1"
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════
# Installation Command (wrapper for mytool.sh function)
# ═══════════════════════════════════════════════════════════════

# Display installation helper
zsh_autosuggestions_install_help() {
    ux_header "zsh-autosuggestions Installation"
    ux_info "Installing command history suggestions for zsh"
    echo ""
    ux_section "Installation"
    ux_bullet "Step 1: Clone plugin from GitHub"
    ux_bullet "Step 2: Register in Oh-My-Zsh plugins array"
    ux_bullet "Step 3: Configure key bindings"
    echo ""
    ux_section "During Installation"
    ux_bullet "You will see step-by-step progress indicators"
    ux_bullet "Any existing plugin references will be cleaned up"
    ux_bullet "Automatic backups are created if needed"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# Naming Convention: Support both dash and underscore
# ═══════════════════════════════════════════════════════════════

alias zsh-autosuggestions-help='zsh_autosuggestions_help'
