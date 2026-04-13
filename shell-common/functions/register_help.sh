#!/bin/sh
# shell-common/functions/register_help.sh
# registerHelp - shared between bash and zsh

_register_help_summary() {
    ux_info "Usage: register-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "topic: function ending with _help"
    ux_bullet_sub "description: HELP_DESCRIPTIONS[<name>_help]"
    ux_bullet_sub "category: HELP_CATEGORY_MEMBERS[<category>]"
    ux_bullet_sub "details: register-help <section>  (example: register-help topic)"
}

_register_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "topic"
    ux_bullet_sub "description"
    ux_bullet_sub "category"
}

_register_help_rows_topic() {
    ux_bullet "Create a function ending with: _help"
    ux_bullet "Example: mytool_help() { ... }"
}

_register_help_rows_description() {
    ux_bullet "Set: HELP_DESCRIPTIONS[mytool_help]=\"[Development] ...\""
}

_register_help_rows_category() {
    ux_bullet "Edit: HELP_CATEGORY_MEMBERS[development]=\"... mytool\""
    ux_bullet "Then reload your shell (source ~/.bashrc or ~/.zshrc)"
}

_register_help_render_section() {
    ux_section "$1"
    "$2"
}

_register_help_section_rows() {
    case "$1" in
        topic|topics)       _register_help_rows_topic ;;
        description|descriptions|desc) _register_help_rows_description ;;
        category|categories) _register_help_rows_category ;;
        *)
            ux_error "Unknown register-help section: $1"
            ux_info "Try: register-help --list"
            return 1
            ;;
    esac
}

_register_help_full() {
    ux_header "Registering Help Topics"
    _register_help_render_section "Add a Help Topic" _register_help_rows_topic
    _register_help_render_section "Add a Description" _register_help_rows_description
    _register_help_render_section "Add to a Category" _register_help_rows_category
}

_register_help_bootstrap() {
    # Best-effort: if my-help isn't loaded yet, attempt to source it.
    if ! type my_help_impl >/dev/null 2>&1; then
        if [ -n "$SHELL_COMMON" ] && [ -f "${SHELL_COMMON}/functions/my_help.sh" ]; then
            # shellcheck source=/dev/null
            . "${SHELL_COMMON}/functions/my_help.sh"
        fi
    fi

    if type _register_default_help_descriptions >/dev/null 2>&1; then
        if [ -z "${_HELP_DEFAULTS_REGISTERED:-}" ]; then
            _register_default_help_descriptions
            _HELP_DEFAULTS_REGISTERED=1
        fi
    fi
}

register_help() {
    _register_help_bootstrap
    case "${1:-}" in
        ""|-h|--help|help) _register_help_summary ;;
        --list|list|section|sections)        _register_help_list_sections ;;
        --all|all)          _register_help_full ;;
        *)                  _register_help_section_rows "$1" ;;
    esac
}

alias register-help='register_help'
