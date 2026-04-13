#!/bin/sh
# shell-common/functions/ux_help.sh
# UX library help function

# Alias target function to run the interactive UX demo
ux_demo() {
    bash "${SHELL_COMMON}/tools/custom/demo_ux.sh" "$@"
}
alias ux-demo='ux_demo'

# =============================================================================
# UX Help Function (SSOT pattern)
# =============================================================================

_ux_help_summary() {
    ux_info "Usage: ux-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "colors: semantic color variables"
    ux_bullet_sub "output: ux_header | ux_section | ux_success | ux_error"
    ux_bullet_sub "progress: ux_spinner | ux_with_spinner"
    ux_bullet_sub "interactive: ux_confirm | ux_input"
    ux_bullet_sub "tables: ux_table_header | ux_table_row | ux_bullet"
    ux_bullet_sub "utilities: ux_divider | ux_usage | ux_require"
    ux_bullet_sub "example: usage example template"
    ux_bullet_sub "quickstart: load library and use"
    ux_bullet_sub "demo: ux-demo"
    ux_bullet_sub "docs: library and demo locations"
    ux_bullet_sub "details: ux-help <section>  (example: ux-help colors)"
}

_ux_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "colors"
    ux_bullet_sub "output"
    ux_bullet_sub "progress"
    ux_bullet_sub "interactive"
    ux_bullet_sub "tables"
    ux_bullet_sub "utilities"
    ux_bullet_sub "example"
    ux_bullet_sub "quickstart"
    ux_bullet_sub "demo"
    ux_bullet_sub "docs"
}

_ux_help_rows_colors() {
    ux_table_header "Variable" "Purpose" "Color"
    ux_table_row "UX_PRIMARY" "Headers, titles, commands" "Blue"
    ux_table_row "UX_SUCCESS" "Success states, valid input" "Green"
    ux_table_row "UX_WARNING" "Warnings, confirmations" "Yellow"
    ux_table_row "UX_ERROR" "Errors, failed operations" "Red"
    ux_table_row "UX_INFO" "Info messages, tips" "Cyan"
    ux_table_row "UX_MUTED" "Secondary info, hints" "Gray"
}

_ux_help_rows_output() {
    ux_table_header "Function" "Purpose"
    ux_table_row "ux_header" "Display prominent header with box"
    ux_table_row "ux_section" "Display section title with underline"
    ux_table_row "ux_success" "Success message with check"
    ux_table_row "ux_error" "Error message (to stderr)"
    ux_table_row "ux_warning" "Warning message"
    ux_table_row "ux_info" "Info message"
    ux_table_row "ux_step" "Step indicator with number"
}

_ux_help_rows_progress() {
    ux_table_header "Function" "Usage"
    ux_table_row "ux_spinner" "ux_spinner <pid> \"message\""
    ux_table_row "ux_with_spinner" "ux_with_spinner \"msg\" command args"
}

_ux_help_rows_interactive() {
    ux_table_header "Function" "Usage"
    ux_table_row "ux_confirm" "if ux_confirm \"prompt\" \"y\"; then ..."
    ux_table_row "ux_input" "result=\$(ux_input \"prompt\" \"pattern\")"
}

_ux_help_rows_tables() {
    ux_table_header "Function" "Usage"
    ux_table_row "ux_table_header" "ux_table_header \"Col1\" \"Col2\" [\"Col3\"]"
    ux_table_row "ux_table_row" "ux_table_row \"val1\" \"val2\" [\"val3\"]"
    ux_table_row "ux_bullet" "ux_bullet \"Item description\""
    ux_table_row "ux_numbered" "ux_numbered 1 \"First item\""
}

_ux_help_rows_utilities() {
    ux_table_header "Function" "Purpose"
    ux_table_row "ux_divider" "Print horizontal line (60 chars)"
    ux_table_row "ux_usage" "Display usage help template"
    ux_table_row "ux_require" "Check if command exists"
}

_ux_help_rows_example() {
    cat <<'EOF'
  #!/bin/bash

  my_function() {
      # Load UX library (unified library at shell-common/tools/ux_lib/)
      source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"

      # Show help if no arguments
      if [ -z "$1" ]; then
          ux_header "My Function"
          ux_usage "my-function" "<arg>" "Description"
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
}

_ux_help_rows_quickstart() {
    ux_numbered 1 "Load library: ${UX_BOLD}source \"\${SHELL_COMMON}/tools/ux_lib/ux_lib.sh\"${UX_RESET}"
    ux_numbered 2 "Use semantic colors: ${UX_BOLD}\${UX_PRIMARY}${UX_RESET}, ${UX_BOLD}\${UX_SUCCESS}${UX_RESET}, etc."
    ux_numbered 3 "Use helper functions: ${UX_BOLD}ux_header${UX_RESET}, ${UX_BOLD}ux_success${UX_RESET}, etc."
    ux_numbered 4 "Always end with ${UX_BOLD}\${UX_RESET}${UX_RESET} to reset colors"
}

_ux_help_rows_demo() {
    ux_info "Run the interactive demo to see all features in action:"
    ux_bullet "${UX_SUCCESS}ux-demo${UX_RESET}  or  ${UX_SUCCESS}bash \${SHELL_COMMON}/tools/custom/demo_ux.sh${UX_RESET}"
}

_ux_help_rows_docs() {
    ux_bullet "Library file: ${UX_BOLD}shell-common/tools/ux_lib/ux_lib.sh${UX_RESET}"
    ux_bullet "Demo script: ${UX_BOLD}shell-common/tools/custom/demo_ux.sh${UX_RESET}"
    ux_bullet "Example migrations: ${UX_BOLD}my_help()${UX_RESET}, ${UX_BOLD}dcl()${UX_RESET}, ${UX_BOLD}dbash()${UX_RESET}"
}

_ux_help_render_section() {
    ux_section "$1"
    "$2"
}

_ux_help_section_rows() {
    case "$1" in
        colors|color)
            _ux_help_rows_colors
            ;;
        output|out)
            _ux_help_rows_output
            ;;
        progress|spinner)
            _ux_help_rows_progress
            ;;
        interactive|prompt)
            _ux_help_rows_interactive
            ;;
        tables|table|lists)
            _ux_help_rows_tables
            ;;
        utilities|utility|util)
            _ux_help_rows_utilities
            ;;
        example|examples)
            _ux_help_rows_example
            ;;
        quickstart|quick|start)
            _ux_help_rows_quickstart
            ;;
        demo|try)
            _ux_help_rows_demo
            ;;
        docs|doc|documentation)
            _ux_help_rows_docs
            ;;
        *)
            ux_error "Unknown ux-help section: $1"
            ux_info "Try: ux-help --list"
            return 1
            ;;
    esac
}

_ux_help_full() {
    ux_header "UX Library - Styling Guide"
    ux_info "The UX library provides consistent styling across all dotfiles functions"
    _ux_help_render_section "Semantic Colors" _ux_help_rows_colors
    _ux_help_render_section "Output Functions" _ux_help_rows_output
    _ux_help_render_section "Progress Indicators" _ux_help_rows_progress
    _ux_help_render_section "Interactive Functions" _ux_help_rows_interactive
    _ux_help_render_section "Tables and Lists" _ux_help_rows_tables
    _ux_help_render_section "Utility Functions" _ux_help_rows_utilities
    _ux_help_render_section "Example Usage" _ux_help_rows_example
    _ux_help_render_section "Quick Start" _ux_help_rows_quickstart
    _ux_help_render_section "Try It Out" _ux_help_rows_demo
    _ux_help_render_section "Documentation" _ux_help_rows_docs
    ux_divider
    ux_info "For more help topics, run ${UX_BOLD}my-help${UX_RESET}"
}

ux_help() {
    # UX library is already loaded globally in main.bash/main.zsh
    case "${1:-}" in
        ""|-h|--help|help)
            _ux_help_summary
            ;;
        --list|list)
            _ux_help_list_sections
            ;;
        --all|all)
            _ux_help_full
            ;;
        *)
            _ux_help_section_rows "$1"
            ;;
    esac
}

# Alias for ux-help format (using dash instead of underscore)
alias ux-help='ux_help'

# Note: HELP_DESCRIPTIONS registration is handled by my_help.sh
# which loads before this file and properly initializes the array
