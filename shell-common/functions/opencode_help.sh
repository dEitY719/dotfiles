#!/bin/sh
# shell-common/functions/opencode_help.sh
# opencode-help topic (commands live in tools/integrations/opencode.sh)

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_opencode_help_summary() {
    ux_info "Usage: opencode-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "setup: install-opencode | opencode-verify | uninstall-opencode"
    ux_bullet_sub "utils: bunx oh-my-opencode install | install-bun | bun-help"
    ux_bullet_sub "env: home/public | external | internal"
    ux_bullet_sub "config: \$OPENCODE_CONFIG_FILE | opencode-edit"
    ux_bullet_sub "models: Home | External | Internal"
    ux_bullet_sub "usage: opencode | opencode --help | opencode --version"
    ux_bullet_sub "trouble: install-opencode | opencode-verify | uninstall-opencode"
    ux_bullet_sub "details: opencode-help <section>  (example: opencode-help models)"
}

_opencode_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "setup"
    ux_bullet_sub "utils"
    ux_bullet_sub "env"
    ux_bullet_sub "config"
    ux_bullet_sub "models"
    ux_bullet_sub "usage"
    ux_bullet_sub "trouble"
}

_opencode_help_rows_setup() {
    ux_bullet "${UX_PRIMARY}install-opencode${UX_RESET}             : Interactive OpenCode installer"
    ux_bullet "${UX_PRIMARY}opencode-verify${UX_RESET}              : Verify installation & configuration"
    ux_bullet "${UX_PRIMARY}uninstall-opencode${UX_RESET}           : Remove OpenCode and configuration"
}

_opencode_help_rows_utils() {
    ux_bullet "${UX_PRIMARY}bunx oh-my-opencode install${UX_RESET}   : Oh My OpenCode (OMO) 인터페이스 설치"
    ux_bullet "bunx 없을 때             : ${UX_PRIMARY}install-bun${UX_RESET} 또는 ${UX_PRIMARY}bun-help${UX_RESET} 참고"
}

_opencode_help_rows_env() {
    ux_bullet "home/public             : OpenCode defaults (no symlink)"
    ux_bullet "external                : localhost:4444 LiteLLM proxy"
    ux_bullet "internal                : internal LLM gateway (URL: DOTFILES_OPENCODE_BASE_URL)"
}

_opencode_help_rows_config() {
    ux_bullet "Config file             : ${UX_INFO}$OPENCODE_CONFIG_FILE${UX_RESET}"
    ux_bullet "Edit configuration      : ${UX_PRIMARY}opencode-edit${UX_RESET}"
}

_opencode_help_rows_models() {
    ux_bullet "Home       : OpenCode defaults"
    ux_bullet "External   : gpt-oss-20b"
    ux_bullet "Internal   : Qwen3.6-27B"
}

_opencode_help_rows_usage() {
    ux_bullet "${UX_PRIMARY}opencode${UX_RESET}                     : Launch OpenCode interactive CLI"
    ux_bullet "${UX_PRIMARY}opencode --help${UX_RESET}              : Show OpenCode help"
    ux_bullet "${UX_PRIMARY}opencode --version${UX_RESET}           : Show OpenCode version"
}

_opencode_help_rows_trouble() {
    ux_bullet "Not installed?          : Run ${UX_PRIMARY}install-opencode${UX_RESET}"
    ux_bullet "LLM not working?        : Run ${UX_PRIMARY}opencode-verify${UX_RESET}"
    ux_bullet "Want to remove?         : Run ${UX_PRIMARY}uninstall-opencode${UX_RESET}"
}

_opencode_help_render_section() {
    ux_section "$1"
    "$2"
}

_opencode_help_section_rows() {
    case "$1" in
        setup|install)             _opencode_help_rows_setup ;;
        utils|util|utilities)      _opencode_help_rows_utils ;;
        env|environments|environment) _opencode_help_rows_env ;;
        config|configuration)      _opencode_help_rows_config ;;
        models|model)              _opencode_help_rows_models ;;
        usage|commands|cmds)       _opencode_help_rows_usage ;;
        trouble|troubleshooting)   _opencode_help_rows_trouble ;;
        *)
            ux_error "Unknown opencode-help section: $1"
            ux_info "Try: opencode-help --list"
            return 1
            ;;
    esac
}

_opencode_help_full() {
    ux_header "OpenCode CLI Reference"
    _opencode_help_render_section "Installation & Setup" _opencode_help_rows_setup
    _opencode_help_render_section "필수 유틸리티" _opencode_help_rows_utils
    _opencode_help_render_section "Environments (managed by setup.sh)" _opencode_help_rows_env
    _opencode_help_render_section "Configuration" _opencode_help_rows_config
    _opencode_help_render_section "Models (LiteLLM Integration)" _opencode_help_rows_models
    _opencode_help_render_section "Usage" _opencode_help_rows_usage
    _opencode_help_render_section "Troubleshooting" _opencode_help_rows_trouble
}

opencode_help() {
    case "${1:-}" in
        ""|-h|--help|help) _opencode_help_summary ;;
        --list|list|section|sections)        _opencode_help_list_sections ;;
        --all|all)          _opencode_help_full ;;
        *)                  _opencode_help_section_rows "$1" ;;
    esac
}

alias opencode-help='opencode_help'
