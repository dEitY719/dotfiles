#!/bin/sh
# shell-common/functions/category_help.sh
# categoryHelp - shared between bash and zsh

category_help() {
    # Best-effort: if my-help isn't loaded yet, attempt to source it.
    if ! type my_help_impl >/dev/null 2>&1; then
        if [ -n "$SHELL_COMMON" ] && [ -f "${SHELL_COMMON}/functions/my_help.sh" ]; then
            # shellcheck source=/dev/null
            . "${SHELL_COMMON}/functions/my_help.sh"
        fi
    fi

    ux_header "Help Categories"

    if type _register_default_help_descriptions >/dev/null 2>&1; then
        if [ -z "${_HELP_DEFAULTS_REGISTERED:-}" ]; then
            _register_default_help_descriptions
            _HELP_DEFAULTS_REGISTERED=1
        fi
    fi

    if [ -z "$1" ]; then
        if type _my_help_show_categories >/dev/null 2>&1; then
            _my_help_show_categories
        else
            my_help_impl
        fi

        ux_divider
        ux_info "Use: my-help <category> (example: my-help ai)"
        ux_info "Use: my-help <topic> (example: my-help git)"
        return 0
    fi

    my_help_impl "$1"
}
