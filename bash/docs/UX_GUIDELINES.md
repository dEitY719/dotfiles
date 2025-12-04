# Dotfiles UX Guidelines

## Design Principles

1.  **Consistency**: All functions use the same color scheme and formatting.
2.  **Discoverability**: Help text is always available with no arguments, and `myhelp` lists all available help topics.
3.  **Safety**: Destructive operations require explicit confirmation.
4.  **Feedback**: Operations provide clear success/error/warning messages and progress indicators.
5.  **Readability**: Output is well-structured, easy to read, and uses semantic colors effectively.

## Color Semantics

-   **Primary (Blue)**: Headers, section titles, command names.
-   **Success (Green)**: Successful operations, valid states, positive feedback.
-   **Warning (Yellow)**: Warnings, confirmations needed, potentially risky actions.
-   **Error (Red)**: Errors, failed operations, critical issues.
-   **Info (Cyan)**: Informational messages, tips, general guidance.
-   **Muted (Gray)**: Secondary information, hints, dividers, less important details.

## Function Structure Template

```bash
my_function() {
    # 1. Load UX library (if not already sourced globally in main.bash)
    #    source "${DOTFILES_BASH_DIR}/core/ux_lib.bash"

    # 2. Show help if no arguments
    if [ -z "$1" ]; then
        ux_header "Function Name"
        ux_usage "my_function" "<arg>" "Description"
        return 0
    fi

    # 3. Validate input (if necessary)
    if ! validate_input "$1"; then
        ux_error "Invalid input: $1"
        return 1
    fi

    # 4. Execute with feedback and error handling
    ux_info "Processing $1..."
    if ux_with_progress "Running task for $1" some_long_command "$1"; then
        ux_success "Operation completed for $1"
    else
        ux_error "Operation failed for $1"
        return 1
    fi
}
```

## Help Function Template

```bash
myhelp_topic_help() {
    # UX library is already loaded globally in main.bash
    ux_header "My Topic Commands"

    ux_section "Category 1"
    ux_table_row "command_alias" "Full Command" "Description"
    ux_table_row "another_cmd" "Another Command" "More details"
    echo ""

    ux_section "Category 2"
    ux_bullet "Item 1"
    ux_bullet "Item 2"
    echo ""

    ux_info "Run ${UX_BOLD}myhelp${UX_RESET} to see all help topics."
}
```

## Interactive Components Usage

### Confirmation (`ux_confirm`)
*   Destructive actions, critical choices.
*   Always provide a default (`y` or `n`).

### Menu Selection (`ux_menu`)
*   When multiple options are available to the user.
*   Requires `python3` with `rich` and `jq` for rich interface, falls back to basic bash menu.

### Progress Indicators (`ux_with_progress`, `ux_spinner`)
*   `ux_with_progress`: For long-running commands that benefit from a visual progress bar. Uses `ux_progress.py`.
*   `ux_spinner`: For simpler background tasks where a spinner is sufficient.

### Log Filtering (`ux_filter_logs`)
*   To highlight important lines (ERROR, WARN, INFO) in log output.
*   Pipe command output to it: `command | ux_filter_logs`

## File Locations

-   **Central UX Library**: `bash/core/ux_lib.bash`
-   **Python Menu Script**: `bash/scripts/ux_menu.py`
-   **Python Progress Script**: `bash/scripts/ux_progress.py`
-   **UX Demo Script**: `bash/scripts/demo_ux.sh` (to be updated)
-   **UX Consistency Checker**: `bash/scripts/check_ux_consistency.sh` (to be created)

## Testing and Validation

*   Use `bash/scripts/demo_ux.sh` to interactively test UX features.
*   Run `bash/scripts/check_ux_consistency.sh` to ensure adherence to guidelines.

## Best Practices

*   **Never hardcode colors**: Always use `UX_PRIMARY`, `UX_SUCCESS`, etc.
*   **Use semantic functions**: Prefer `ux_success` over `echo "${UX_SUCCESS}..."`.
*   **Provide clear feedback**: Inform the user about the state of operations.
*   **Keep it clean**: Remove commented-out `tput` definitions after migration.
*   **Error gracefully**: Use `ux_error` for failures and consider `ux_enable_error_trap`.
