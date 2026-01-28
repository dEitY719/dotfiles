#!/bin/sh
# shell-common/functions/zsh_autosuggestions.sh
# zsh-autosuggestions helper functions and documentation
# ZSH only plugin - provides intelligent command suggestions
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# zsh-autosuggestions Help and Documentation
# ═══════════════════════════════════════════════════════════════

# Display zsh-autosuggestions help and usage
zsh_autosuggestions_help() {
    ux_header "zsh-autosuggestions - Command History Suggestions"

    ux_section "What is zsh-autosuggestions?"
    ux_info "Auto-suggests commands as you type, based on your history."
    ux_info "Press Tab or Ctrl+Right to accept the suggestion."
    echo ""

    ux_section "Key Bindings"
    ux_table_header "Key" "Action"
    ux_table_row "Tab / Ctrl+Right" "Accept suggestion"
    ux_table_row "Ctrl+F" "Accept next word of suggestion"
    ux_table_row "Ctrl+A" "Accept entire suggestion"
    ux_table_row "Up/Down Arrow" "Navigate history (overrides suggestions)"
    echo ""

    ux_section "How It Works"
    ux_bullet "As you type, suggestions appear in gray text"
    ux_bullet "Suggestions are based on command history"
    ux_bullet "Press Tab (or configured key) to accept"
    ux_bullet "Press Esc or start typing to dismiss"
    echo ""

    ux_section "Example Usage"
    ux_info "Type 'work' and zsh will suggest:"
    ux_bullet "work-log list help"
    ux_bullet "work-log add SWINNOTEAM-906 -t coordination..."
    ux_bullet "work-help"
    ux_info "Press Tab to accept any suggestion"
    echo ""

    ux_section "Environment Variables"
    ux_table_header "Variable" "Description" "Default"
    ux_table_row "ZSH_AUTOSUGGEST_STRATEGY" "Suggestion matching strategy" "history"
    ux_table_row "ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE" "Max command length to suggest" "unbounded"
    ux_table_row "ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE" "Suggestion text color" "fg=8"
    echo ""

    ux_section "Strategies"
    ux_bullet "history - Suggest from command history"
    ux_bullet "completion - Suggest from completion"
    ux_bullet "match_prev_cmd - Suggest matching previous command"
    echo ""

    ux_section "Customization Example"
    ux_info "Add to ~/.zshrc (before sourcing zsh-autosuggestions):"
    echo ""
    ux_code "# Accept suggestion with Tab key"
    ux_code "bindkey '\\t' autosuggest-accept"
    ux_code ""
    ux_code "# Change suggestion highlight color"
    ux_code "export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=10'"
    ux_code ""
    ux_code "# Use history strategy only"
    ux_code "export ZSH_AUTOSUGGEST_STRATEGY=(history)"
    echo ""

    ux_section "Installation Status"
    if [ -d "${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" ]; then
        ux_success "✓ zsh-autosuggestions is installed"
        echo "  Location: ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
    else
        ux_warning "✗ zsh-autosuggestions is not installed"
        echo "  Run: install-zsh-autosuggestions"
    fi
    echo ""
}

# Naming Convention: Support both dash and underscore
alias zsh-autosuggestions-help='zsh_autosuggestions_help'
