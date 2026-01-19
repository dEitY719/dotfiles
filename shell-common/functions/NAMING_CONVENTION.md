# Naming Convention for shell-common/functions/

This directory contains **auto-sourced shell functions** that users interact with directly.

## Critical Rule

**ALL user-facing text (help, examples, usage, errors) MUST use dash-form, NEVER snake_case.**

This is non-negotiable. See AGENTS.md:174-178.

## Pattern

```bash
# INTERNAL (Function definitions, variable names)
clear_doc() { ... }                          # Function: snake_case
show_doc_help() { ... }                      # Function: snake_case

# USER-FACING (Aliases, help text, examples, messages)
alias clear-doc='clear_doc'                  # Alias: dash-form
alias doc-help='show_doc_help'               # Alias: dash-form

# Inside help functions:
ux_info "Usage: clear-doc <file|pattern>"   # Dash-form
echo "  clear-doc docs/file.md"              # Dash-form
```

## Verification Checklist

When adding or modifying a function in this directory:

- [ ] Function name is snake_case: `my_function()`
- [ ] Alias is dash-form: `alias my-command='my_function'`
- [ ] Help text uses dash-form: `"Usage: my-command <args>"`
- [ ] All examples use dash-form: `"my-command docs/file.md"`
- [ ] Error messages use dash-form: `"my-command failed"`
- [ ] Verify: `grep "my_function" help_function_output` returns 0 results

## Template

Use this template when creating a new function file:

```bash
#!/bin/bash
# shell-common/functions/my_command.sh
# Brief description
#
# ═══════════════════════════════════════════════════════════════════════════════
# DEVELOPER NOTES - NAMING CONVENTION (See AGENTS.md:174-178)
# ═══════════════════════════════════════════════════════════════════════════════
# User-facing command: my-command (dash-form)
# Internal function: my_command() (snake_case)
# Always use dash-form in help text, examples, and error messages
# ═══════════════════════════════════════════════════════════════════════════════

# Source UX library
_UX_LIB_PATH="${SHELL_COMMON:-${HOME}/.local/dotfiles/shell-common}/tools/ux_lib/ux_lib.sh"
if [ -f "$_UX_LIB_PATH" ]; then
    source "$_UX_LIB_PATH"
else
    # Fallback: basic implementations
    ux_error() { echo "✗ $1" >&2; }
    ux_info() { echo "ℹ $1"; }
fi
unset _UX_LIB_PATH

# ═══════════════════════════════════════════════════════════════
# my_command() - Main function
# ═══════════════════════════════════════════════════════════════

my_command() {
    if [ $# -eq 0 ]; then
        ux_error "Usage: my-command <argument>"
        echo ""
        return 1
    fi

    # ... implementation ...
}

# ═══════════════════════════════════════════════════════════════
# show_my_command_help() - Help function
# ═══════════════════════════════════════════════════════════════

show_my_command_help() {
    ux_header "My Command"
    echo ""
    ux_info "Usage: my-command <argument>"
    echo ""
    ux_info "Examples:"
    echo "  my-command option1    // Description"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# Aliases
# ═══════════════════════════════════════════════════════════════

alias my-command='my_command'
alias my-help='show_my_command_help'

# Export for subshells
export -f my_command show_my_command_help
```

## Common Mistakes

| Mistake | Problem | Fix |
|---------|---------|-----|
| Help shows: "Usage: clear_doc" | Users confused about command name | Change to: "Usage: clear-doc" |
| Example: "clear_doc file.md" | Users copy-paste and fail | Change to: "clear-doc file.md" |
| Error: "clear_doc not found" | Breaks user trust | Change to: "clear-doc not found" |
| Internal grep doesn't find snake_case in help | False confidence | Verify: search function name in help output |

## References

- AGENTS.md:174-178 - Project naming convention rules
- manage_doc.sh - Full example of correct implementation
- Test command: `grep "snake_case_name" function_help_output` (should return 0)

## Why This Matters

- **Consistency**: Users see ONE command form everywhere
- **Usability**: No confusion about what to type
- **Professionalism**: Shows attention to detail
- **Maintainability**: Clear separation of internal vs external APIs
