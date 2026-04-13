#!/bin/sh
# shell-common/functions/category_help.sh
# categoryHelp - shared between bash and zsh

_category_help_ensure_loaded() {
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

_category_help_summary() {
    ux_info "Usage: category-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "categories: list all help categories"
    ux_bullet_sub "topics: route to my-help <topic>"
    ux_bullet_sub "details: category-help <section>  (example: category-help categories)"
}

_category_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "categories"
    ux_bullet_sub "topics"
}

_category_help_rows_categories() {
    _category_help_ensure_loaded
    if type _my_help_show_categories >/dev/null 2>&1; then
        _my_help_show_categories
    else
        my_help_impl
    fi
    ux_divider
    ux_info "Use: my-help <category> (example: my-help ai)"
    ux_info "Use: my-help <topic> (example: my-help git)"
}

_category_help_rows_topics() {
    _category_help_ensure_loaded
    ux_bullet "Run: ${UX_BOLD}my-help <topic>${UX_RESET} to view a topic's help"
    ux_bullet "Run: ${UX_BOLD}my-help${UX_RESET} for the full category list"
    ux_bullet "Run: ${UX_BOLD}category-help categories${UX_RESET} to see categories inline"
}

_category_help_render_section() {
    ux_section "$1"
    "$2"
}

_category_help_section_rows() {
    case "$1" in
        categories|category|cats)
            _category_help_rows_categories
            ;;
        topics|topic)
            _category_help_rows_topics
            ;;
        *)
            # Backward compatibility: treat unknown section as a category name
            # passed to my_help_impl (legacy behavior).
            _category_help_ensure_loaded
            my_help_impl "$1"
            ;;
    esac
}

_category_help_full() {
    ux_header "Help Categories"
    _category_help_render_section "Categories" _category_help_rows_categories
    _category_help_render_section "Topics" _category_help_rows_topics
}

category_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _category_help_summary
            ;;
        --list|list)
            _category_help_list_sections
            ;;
        --all|all)
            _category_help_full
            ;;
        *)
            _category_help_section_rows "$1"
            ;;
    esac
}

alias category-help='category_help'
