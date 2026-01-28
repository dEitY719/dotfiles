#!/bin/sh
# shell-common/functions/register_help.sh
# registerHelp - shared between bash and zsh

register_help() {
    # Best-effort: if my-help isn't loaded yet, attempt to source it.
    if ! type my_help_impl >/dev/null 2>&1; then
        if [ -n "$SHELL_COMMON" ] && [ -f "${SHELL_COMMON}/functions/my_help.sh" ]; then
            # shellcheck source=/dev/null
            . "${SHELL_COMMON}/functions/my_help.sh"
        fi
    fi

    ux_header "Registering Help Topics"

    if type _register_default_help_descriptions >/dev/null 2>&1; then
        if [ -z "${_HELP_DEFAULTS_REGISTERED:-}" ]; then
            _register_default_help_descriptions
            _HELP_DEFAULTS_REGISTERED=1
        fi
    fi

    ux_section "Add a Help Topic"
    ux_bullet "Create a function ending with: _help"
    ux_bullet "Example: mytool_help() { ... }"

    ux_section "Add a Description"
    ux_bullet "Set: HELP_DESCRIPTIONS[mytool_help]=\"[Development] ...\""

    ux_section "Add to a Category"
    ux_bullet "Edit: HELP_CATEGORY_MEMBERS[development]=\"... mytool\""
    ux_bullet "Then reload your shell (source ~/.bashrc or ~/.zshrc)"
}
