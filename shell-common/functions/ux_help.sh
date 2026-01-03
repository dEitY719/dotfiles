#!/bin/bash
# shell-common/functions/ux_help.sh
# UX library help function

# Alias to run the interactive UX demo
alias ux-demo='bash "${SHELL_COMMON}/tools/custom/demo_ux.sh"'

# =============================================================================
# UX Help Function
# =============================================================================

ux_help() {
    # UX library is already loaded globally in main.bash/main.zsh
    ux_header "UX Library - Styling Guide"

    ux_info "The UX library provides consistent styling across all dotfiles functions"
    echo ""

    # --- Colors Section ---
    ux_section "Semantic Colors"
    ux_table_header "Variable" "Purpose" "Color"
    ux_table_row "UX_PRIMARY" "Headers, titles, commands" "Blue"
    ux_table_row "UX_SUCCESS" "Success states, valid input" "Green"
    ux_table_row "UX_WARNING" "Warnings, confirmations" "Yellow"
    ux_table_row "UX_ERROR" "Errors, failed operations" "Red"
    ux_table_row "UX_INFO" "Info messages, tips" "Cyan"
    ux_table_row "UX_MUTED" "Secondary info, hints" "Gray"
    echo ""

    # --- Output Functions Section ---
    ux_section "Output Functions"
    ux_table_header "Function" "Purpose"
    ux_table_row "ux_header" "Display prominent header with box"
    ux_table_row "ux_section" "Display section title with underline"
    ux_table_row "ux_success" "Success message with ✅"
    ux_table_row "ux_error" "Error message with ❌ (to stderr)"
    ux_table_row "ux_warning" "Warning message with ⚠️"
    ux_table_row "ux_info" "Info message with ℹ️"
    ux_table_row "ux_step" "Step indicator with number"
    echo ""

    # --- Progress Indicators Section ---
    ux_section "Progress Indicators"
    ux_table_header "Function" "Usage"
    ux_table_row "ux_spinner" "ux_spinner <pid> \"message\""
    ux_table_row "ux_with_spinner" "ux_with_spinner \"msg\" command args"
    echo ""

    # --- Interactive Functions Section ---
    ux_section "Interactive Functions"
    ux_table_header "Function" "Usage"
    ux_table_row "ux_confirm" "if ux_confirm \"prompt\" \"y\"; then ..."
    ux_table_row "ux_input" "result=\$(ux_input \"prompt\" \"pattern\")"
    echo ""

    # --- Table/List Functions Section ---
    ux_section "Tables and Lists"
    ux_table_header "Function" "Usage"
    ux_table_row "ux_table_header" "ux_table_header \"Col1\" \"Col2\" [\"Col3\"]"
    ux_table_row "ux_table_row" "ux_table_row \"val1\" \"val2\" [\"val3\"]"
    ux_table_row "ux_bullet" "ux_bullet \"Item description\""
    ux_table_row "ux_numbered" "ux_numbered 1 \"First item\""
    echo ""

    # --- Utilities Section ---
    ux_section "Utility Functions"
    ux_table_header "Function" "Purpose"
    ux_table_row "ux_divider" "Print horizontal line (60 chars)"
    ux_table_row "ux_usage" "Display usage help template"
    ux_table_row "ux_require" "Check if command exists"
    echo ""

    # --- Usage Example Section ---
    ux_section "Example Usage"
    cat <<'EOF'
  #!/bin/bash

  my_function() {
      # Load UX library (unified library at shell-common/tools/ux_lib/)
      source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"

      # Show help if no arguments
      if [ -z "$1" ]; then
          ux_header "My Function"
          ux_usage "my_function" "<arg>" "Description"
          return 0
      fi

      # Check requirements
      if ! ux_require "docker"; then
          return 1
      fi

      # Show progress
      ux_info "Processing $1..."
      ux_with_spinner "Running task" some_command "$1"

      # Show result
      if [ $? -eq 0 ]; then
          ux_success "Task completed"
      else
          ux_error "Task failed"
          return 1
      fi
  }
EOF
    echo ""

    # --- Quick Reference Section ---
    ux_section "Quick Start"
    ux_numbered 1 "Load library: ${UX_BOLD}source \"\${SHELL_COMMON}/tools/ux_lib/ux_lib.sh\"${UX_RESET}"
    ux_numbered 2 "Use semantic colors: ${UX_BOLD}\${UX_PRIMARY}${UX_RESET}, ${UX_BOLD}\${UX_SUCCESS}${UX_RESET}, etc."
    ux_numbered 3 "Use helper functions: ${UX_BOLD}ux_header${UX_RESET}, ${UX_BOLD}ux_success${UX_RESET}, etc."
    ux_numbered 4 "Always end with ${UX_BOLD}\${UX_RESET}${UX_RESET} to reset colors"
    echo ""

    # --- Demo Section ---
    ux_section "Try It Out"
    ux_info "Run the interactive demo to see all features in action:"
    echo "  ${UX_SUCCESS}ux-demo${UX_RESET}  or  ${UX_SUCCESS}bash \${SHELL_COMMON}/tools/custom/demo_ux.sh${UX_RESET}"
    echo ""

    # --- Documentation Section ---
    ux_section "Documentation"
    ux_bullet "Library file: ${UX_BOLD}shell-common/tools/ux_lib/ux_lib.sh${UX_RESET}"
    ux_bullet "Demo script: ${UX_BOLD}shell-common/tools/custom/demo_ux.sh${UX_RESET}"
    ux_bullet "Example migrations: ${UX_BOLD}my_help()${UX_RESET}, ${UX_BOLD}dcl()${UX_RESET}, ${UX_BOLD}dbash()${UX_RESET}"
    echo ""

    ux_divider
    echo ""
    ux_info "For more help topics, run ${UX_BOLD}my-help${UX_RESET}"
    echo ""
}

# Alias for ux-help format (using dash instead of underscore)
alias ux-help='ux_help'

# Note: HELP_DESCRIPTIONS registration is handled by my_help.sh
# which loads before this file and properly initializes the array
