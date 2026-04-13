#!/bin/sh
# shell-common/tools/integrations/opencode.sh
# OpenCode CLI - setup, utilities, and workflow helpers
# Shared between bash and zsh
#
# Configuration is managed via symlinks:
#   dotfiles/opencode/opencode.json.internal  → ~/.config/opencode/opencode.json
#   dotfiles/opencode/opencode.json.external  → ~/.config/opencode/opencode.json
#   (public/home: no symlink, uses OpenCode defaults)
# Symlinks are created by setup.sh (setup_opencode_config)

OPENCODE_CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
OPENCODE_CONFIG_FILE="${OPENCODE_CONFIG_FILE:-$OPENCODE_CONFIG_DIR/opencode.json}"

export PATH="$HOME/.opencode/bin:$PATH"

install_opencode() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_opencode.sh"
}

opencode_verify() {
    ux_header "OpenCode Configuration Verification"
    echo ""

    ux_section "Installation Status"
    if command -v opencode >/dev/null 2>&1; then
        ux_success "OpenCode CLI is installed"
        opencode --version
    else
        ux_error "OpenCode CLI is not installed"
        ux_info "Run 'install-opencode' to install it"
        echo ""
        return 1
    fi
    echo ""

    ux_section "Configuration"
    if [ -L "$OPENCODE_CONFIG_FILE" ]; then
        local link_target
        link_target=$(readlink "$OPENCODE_CONFIG_FILE")
        ux_success "Configuration symlink: $OPENCODE_CONFIG_FILE → $link_target"
    elif [ -f "$OPENCODE_CONFIG_FILE" ]; then
        ux_success "Configuration file found: $OPENCODE_CONFIG_FILE"
    fi

    if [ -f "$OPENCODE_CONFIG_FILE" ]; then
        echo ""
        if command -v jq >/dev/null 2>&1; then
            ux_bullet "Provider: $(jq -r '.provider | keys[0]' "$OPENCODE_CONFIG_FILE" 2>/dev/null || echo 'unknown')"

            local provider_name
            provider_name=$(jq -r '.provider.litellm.name // "Unknown"' "$OPENCODE_CONFIG_FILE" 2>/dev/null)
            if [ "$provider_name" != "Unknown" ]; then
                ux_bullet "Name: $provider_name"
            fi

            local base_url
            base_url=$(jq -r '.provider.litellm.options.baseURL // "default"' "$OPENCODE_CONFIG_FILE" 2>/dev/null)
            if [ "$base_url" != "default" ]; then
                ux_bullet "Base URL: $base_url"
            fi

            local model_count
            model_count=$(jq '.provider.litellm.models | length' "$OPENCODE_CONFIG_FILE" 2>/dev/null)
            if [ -n "$model_count" ] && [ "$model_count" -gt 0 ]; then
                ux_bullet "Available Models: $model_count"
                jq -r '.provider.litellm.models | keys[]' "$OPENCODE_CONFIG_FILE" 2>/dev/null | while read -r model; do
                    echo "  - $model"
                done
            fi
        else
            ux_warning "jq not installed - unable to parse configuration details"
            ux_info "Configuration file contents:"
            cat "$OPENCODE_CONFIG_FILE"
        fi
    else
        ux_info "Using OpenCode default configuration"
        ux_info "Run setup.sh to configure environment-specific symlink"
    fi
    echo ""

    ux_section "Runtime Environment"
    if command -v node >/dev/null 2>&1; then
        ux_success "Node.js: $(node --version)"
    else
        ux_error "Node.js not found"
    fi

    if command -v npm >/dev/null 2>&1; then
        ux_success "npm: $(npm --version)"
    else
        ux_error "npm not found"
    fi
    echo ""

    ux_header "Verification Complete"
}

_opencode_help_summary() {
    ux_info "Usage: opencode-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "setup: install-opencode | opencode-verify | uninstall-opencode"
    ux_bullet_sub "utils: bunx oh-my-opencode install | install-bun | bun-help"
    ux_bullet_sub "env: home/public | external | internal"
    ux_bullet_sub "profile: oc-profile dtgpt | oc-profile a2g"
    ux_bullet_sub "config: \$OPENCODE_CONFIG_FILE | opencode-edit"
    ux_bullet_sub "models: Home | External | DTGPT | A2G"
    ux_bullet_sub "usage: opencode | opencode --help | opencode --version"
    ux_bullet_sub "trouble: install-opencode | opencode-verify | uninstall-opencode"
    ux_bullet_sub "details: opencode-help <section>  (example: opencode-help profile)"
}

_opencode_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "setup"
    ux_bullet_sub "utils"
    ux_bullet_sub "env"
    ux_bullet_sub "profile"
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
    ux_bullet "internal                : Samsung DS LiteLLM endpoint"
}

_opencode_help_rows_profile() {
    ux_bullet "${UX_PRIMARY}oc-profile dtgpt${UX_RESET}     : DTGPT  (cloud.dtgpt.samsungds.net)"
    ux_bullet "${UX_PRIMARY}oc-profile a2g${UX_RESET}       : A2G    (a2g.samsungds.net) — Thinking models"
}

_opencode_help_rows_config() {
    ux_bullet "Config file             : ${UX_INFO}$OPENCODE_CONFIG_FILE${UX_RESET}"
    ux_bullet "Edit configuration      : ${UX_PRIMARY}opencode-edit${UX_RESET}"
}

_opencode_help_rows_models() {
    ux_bullet "Home       : OpenCode defaults"
    ux_bullet "External   : gpt-oss-20b"
    ux_bullet "DTGPT      : GLM4.7, Kimi-K2.5, MiniMax-M2.1"
    ux_bullet "A2G        : GLM-5-Thinking, Qwen3.5-Thinking, Kimi-K2.5-Thinking"
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
        profile|profiles)          _opencode_help_rows_profile ;;
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
    _opencode_help_render_section "Profile Management (internal only)" _opencode_help_rows_profile
    _opencode_help_render_section "Configuration" _opencode_help_rows_config
    _opencode_help_render_section "Models (LiteLLM Integration)" _opencode_help_rows_models
    _opencode_help_render_section "Usage" _opencode_help_rows_usage
    _opencode_help_render_section "Troubleshooting" _opencode_help_rows_trouble
}

opencode_help() {
    case "${1:-}" in
        ""|-h|--help|help) _opencode_help_summary ;;
        --list|list)        _opencode_help_list_sections ;;
        --all|all)          _opencode_help_full ;;
        *)                  _opencode_help_section_rows "$1" ;;
    esac
}

oc_profile() {
    local profile="$1"
    local dotfiles_root="${DOTFILES_ROOT:-$HOME/dotfiles}"

    case "$profile" in
        dtgpt)
            local src="$dotfiles_root/opencode/opencode.json.internal"
            ;;
        a2g)
            local src="$dotfiles_root/opencode/opencode.json.internal-a2g"
            ;;
        *)
            ux_usage "oc-profile" "<dtgpt|a2g>" "Switch OpenCode internal profile"
            ux_bullet "  dtgpt : DTGPT  (cloud.dtgpt.samsungds.net) — GLM4.7, Kimi-K2.5, MiniMax-M2.1"
            ux_bullet "  a2g   : A2G    (a2g.samsungds.net)         — GLM-5-Thinking, Kimi-K2.5-Thinking"
            return 1
            ;;
    esac

    if [ ! -f "$src" ]; then
        ux_error "Profile source not found: $src"
        return 1
    fi

    mkdir -p "$(dirname "$OPENCODE_CONFIG_FILE")"
    ln -sf "$src" "$OPENCODE_CONFIG_FILE"
    ux_success "OpenCode profile: $profile"
    ux_bullet "Config → $src"
}

alias oc-profile='oc_profile'

opencode_edit() {
    local config_file="$OPENCODE_CONFIG_FILE"

    if [ ! -f "$config_file" ]; then
        ux_error "Configuration file not found: $config_file"
        ux_info "Run setup.sh to configure environment-specific symlink"
        return 1
    fi

    if [ -L "$config_file" ]; then
        ux_info "Symlink target: $(readlink "$config_file")"
        ux_warning "Editing symlinked file will modify the dotfiles source"
    fi

    ${EDITOR:-vim} "$config_file"
    ux_success "Configuration file edited"
}

alias openplan='opencode'

opentest() {
    if [ -z "$1" ]; then
        ux_usage "opentest" "\"request\"" "Run OpenCode for test writing"
        ux_bullet "Example: ${UX_INFO}opentest \"Write authentication tests\"${UX_RESET}"
        return 1
    fi
    opencode -p "$1"
}

uninstall_opencode() {
    ux_header "OpenCode CLI Uninstaller"
    echo ""

    printf "%sAre you sure you want to uninstall OpenCode? (y/N): %s" "$UX_PRIMARY" "$UX_RESET"
    read -r confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        ux_info "Uninstall cancelled"
        return 0
    fi
    echo ""

    ux_section "Uninstalling OpenCode..."

    if command -v npm >/dev/null 2>&1; then
        ux_info "Removing OpenCode npm package..."
        npm uninstall -g opencode-ai 2>/dev/null || npm uninstall -g opencode 2>/dev/null || true
        ux_success "OpenCode package removed"
    else
        ux_warning "npm not found - skipping npm uninstall"
    fi
    echo ""

    if [ -d "$HOME/.opencode" ]; then
        ux_info "Removing OpenCode installation directory: $HOME/.opencode"
        rm -rf "$HOME/.opencode"
        ux_success "Installation directory removed"
    else
        ux_info "No OpenCode installation directory found"
    fi
    echo ""

    if [ -L "$OPENCODE_CONFIG_FILE" ]; then
        ux_info "Removing configuration symlink: $OPENCODE_CONFIG_FILE"
        rm -f "$OPENCODE_CONFIG_FILE"
        ux_success "Symlink removed"
    elif [ -d "$OPENCODE_CONFIG_DIR" ]; then
        ux_info "Removing configuration directory: $OPENCODE_CONFIG_DIR"
        rm -rf "$OPENCODE_CONFIG_DIR"
        ux_success "Configuration removed"
    else
        ux_info "No configuration directory found"
    fi
    echo ""

    ux_header "OpenCode Uninstallation Complete"
    ux_info "Run 'install-opencode' to reinstall"
    echo ""
}

alias install-opencode='install_opencode'
alias opencode-verify='opencode_verify'
alias opencode-help='opencode_help'
alias opencode-edit='opencode_edit'
alias uninstall-opencode='uninstall_opencode'
alias opencfg='opencode_edit'
alias opencode-yolo='opencode'
