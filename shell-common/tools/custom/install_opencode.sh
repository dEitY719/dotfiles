#!/bin/bash
# shell-common/tools/custom/install_opencode.sh
# OpenCode CLI Installation Script (Interactive)
# Installs OpenCode using the official npm installation method
# Reference: https://opencode.ai/
#
# Shell Compatibility:
#   - Shebang: #!/bin/bash (explicitly requires bash)
#   - Reason: This script sources init.sh which uses bash features
#   - Usage: Can be invoked from both bash and zsh environments
#   - How: The shebang ensures execution in bash, regardless of parent shell
#
# Compatible with:
#   - bash 4.0+
#   - zsh (when executed via this script's shebang)
#   - Linux, macOS, WSL

# More conservative error handling to prevent segfaults
set -e
trap 'echo "Installation interrupted"; exit 1' INT TERM

# Initialize common tools environment with error handling
_INIT_PATH="$(dirname "$0")/init.sh"
if [ ! -f "$_INIT_PATH" ]; then
    echo "Error: Cannot find init.sh at $_INIT_PATH" >&2
    exit 1
fi

if ! source "$_INIT_PATH" 2>/dev/null; then
    echo "Error: Failed to source init.sh" >&2
    exit 1
fi

# Load environment variables from dotfiles/.env (SSOT - Single Source of Truth)
# This ensures that environment-specific variables like SSAI_LLM_API_KEY are available
# for expansion into configuration files (e.g., opencode.json)
_dotfiles_env="${DOTFILES_ROOT:-$HOME/dotfiles}/.env"
if [ -f "$_dotfiles_env" ]; then
    # shellcheck source=/dev/null
    set -a  # Export all variables
    source "$_dotfiles_env"
    set +a  # Stop exporting
fi
unset _dotfiles_env

# ═══════════════════════════════════════════════════════════════
# Helper Functions
# ═══════════════════════════════════════════════════════════════

# Display environment-specific help
show_environment_info() {
    local env=$1
    echo ""
    case "$env" in
        home)
            ux_section "Home Environment"
            ux_bullet "Personal PC with local development"
            ux_bullet "SSL verification enabled"
            ux_bullet "Uses OpenCode's default LLM"
            ux_bullet "No custom configuration needed"
            ;;
        external)
            ux_section "External Environment"
            ux_bullet "External PC or public network access"
            ux_bullet "Can access public GitHub"
            ux_bullet "Uses configured LiteLLM models (gpt-oss-20b)"
            ux_bullet "Proxy and SSL verification may be needed"
            ;;
        internal)
            ux_section "Internal Environment"
            ux_bullet "Internal corporate PC (Samsung DS Network)"
            ux_bullet "Proxy enabled (required)"
            ux_bullet "SSL verification disabled"
            ux_bullet "CA certificate may be required"
            ux_bullet "Available models: GLM-4.6, gpt-oss-120b, DeepSeek-V3.2"
            ;;
    esac
    echo ""
}

# Create OpenCode config directory
create_config_dir() {
    local config_dir="$HOME/.config/opencode"
    if [ ! -d "$config_dir" ]; then
        mkdir -p "$config_dir"
        ux_success "Created configuration directory: $config_dir"
    else
        ux_info "Configuration directory already exists: $config_dir"
    fi
}

# Generate opencode.json for home environment (no custom config)
generate_home_config() {
    local config_file="$HOME/.config/opencode/opencode.json"

    ux_info "Setting up home environment (using default LLM)..."

    # Create a minimal config for home environment using OpenCode defaults
    cat > "$config_file" << 'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "default": {
      "name": "OpenCode Default Provider"
    }
  }
}
EOF
    chmod 600 "$config_file"
    ux_success "Home environment configured: $config_file"
}

# Generate opencode.json for external environment
generate_external_config() {
    local config_file="$HOME/.config/opencode/opencode.json"

    ux_info "Setting up external environment with LiteLLM..."

    cat > "$config_file" << 'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "litellm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "LiteLLM Provider",
      "options": {
        "baseURL": "http://localhost:4444/v1",
        "apiKey": "sk-4444"
      },
      "models": {
        "gpt-oss-20b": {
          "name": "gpt-oss-20b"
        }
      }
    }
  }
}
EOF
    chmod 600 "$config_file"
    ux_success "External environment configured: $config_file"
}

# Generate opencode.json for internal environment
generate_internal_config() {
    local config_file="$HOME/.config/opencode/opencode.json"

    ux_info "Setting up internal environment with Samsung DS LiteLLM..."

    # Use unquoted EOF to enable variable expansion (SSAI_LLM_API_KEY from .env)
    # Note: This is safe because we control the content, not user input
    cat > "$config_file" << EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "provider": {
    "litellm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "LiteLLM Provider",
      "options": {
        "baseURL": "http://ssai.samsungds.net:9090",
        "apiKey": "${SSAI_LLM_API_KEY}"
      },
      "models": {
        "GLM-4.6": {
          "name": "GLM-4.6"
        },
        "gpt-oss-120b": {
          "name": "gpt-oss-120b"
        },
        "DeepSeek-V3.2": {
          "name": "DeepSeek-V3.2"
        }
      }
    }
  }
}
EOF
    chmod 600 "$config_file"
    ux_success "Internal environment configured: $config_file"
}

# ═══════════════════════════════════════════════════════════════
# Main Installation Script
# ═══════════════════════════════════════════════════════════════

main() {
    clear
    ux_header "OpenCode CLI Installer"
    ux_info "This script installs the OpenCode global npm package"
    ux_info "and configures it for your environment."
    echo ""

    # Simple confirmation without ux_confirm to avoid segfault
    printf "Do you want to proceed with the installation? (Y/n): "
    read -r proceed
    if [ -n "$proceed" ] && [ "$proceed" != "Y" ] && [ "$proceed" != "y" ]; then
        ux_warning "Installation cancelled."
        exit 0
    fi
    echo ""

    # ========================================
    # Step 1: Environment Selection
    # ========================================
    ux_step "1/5" "Select your environment"
    echo ""
    ux_section "Available Environments"

    local environment

    # Display environment options
    printf "  %s1)%s 📱 Home - Personal PC (local development, SSL verified)\n" "$UX_PRIMARY" "$UX_RESET"
    printf "  %s2)%s 🌐 External - Public network (GitHub accessible)\n" "$UX_PRIMARY" "$UX_RESET"
    printf "  %s3)%s 🏢 Internal - Corporate network (Samsung DS proxy)\n" "$UX_PRIMARY" "$UX_RESET"
    echo ""

    # Simple read-based selection (stable, no external dependencies)
    local choice
    printf "%sSelect (1-3):%s " "$UX_PRIMARY" "$UX_RESET"
    read choice
    case "$choice" in
        1) environment="home" ;;
        2) environment="external" ;;
        3) environment="internal" ;;
        *) environment="home" ;;
    esac

    # Validate environment selection
    case "$environment" in
        home|external|internal)
            show_environment_info "$environment"
            ;;
        *)
            ux_warning "Invalid selection. Using 'home' environment."
            environment="home"
            show_environment_info "$environment"
            ;;
    esac
    echo ""

    # ========================================
    # Step 2: Check for curl
    # ========================================
    ux_step "2/5" "Checking for curl..."
    if ! ux_require "curl"; then
        ux_error "curl is required for OpenCode installation"
        exit 1
    fi
    ux_success "curl is installed: $(curl --version | head -1)"
    echo ""

    # ========================================
    # Step 3: Install OpenCode CLI via npm
    # ========================================
    ux_step "3/6" "Installing OpenCode CLI via npm..."

    ux_info "Using npm registry (corporate proxy settings auto-applied)..."
    echo ""

    # Create temp file for error capture
    local install_log=$(mktemp)

    # Use npm directly instead of curl | bash:
    # - Avoids NewGenAI domain blocking (opencode.ai → 403)
    # - Uses whitelisted internal Nexus repository
    # - npm config (including no-proxy) is auto-synced from proxy.local.sh
    ux_with_spinner "Installing opencode-ai package..." npm install -g opencode-ai 2>"$install_log" >>"$install_log"

    if [ $? -eq 0 ]; then
        ux_success "OpenCode installed successfully"
        rm -f "$install_log"
    else
        ux_error "OpenCode installation failed."
        ux_warning "Installation error details:"
        cat "$install_log" 2>/dev/null | sed 's/^/  /' || echo "  (No error details available)"
        echo ""
        ux_info "Troubleshooting:"
        ux_bullet "Check proxy settings: npm-config"
        ux_bullet "Verify registry: npm info opencode-ai"
        ux_bullet "Check no-proxy: npm config get noproxy"
        ux_bullet "For manual config: npm config set noproxy \"<value>\""
        rm -f "$install_log"
        exit 1
    fi
    echo ""

    # ========================================
    # Step 4: Create Configuration
    # ========================================
    ux_step "4/5" "Configuring OpenCode for $environment environment..."
    create_config_dir

    case "$environment" in
        home)
            generate_home_config
            ;;
        external)
            generate_external_config
            ;;
        internal)
            generate_internal_config
            ;;
    esac
    echo ""

    # ========================================
    # Step 5: Verify Installation
    # ========================================
    ux_step "5/5" "Verifying installation..."
    if command -v opencode &>/dev/null; then
        ux_success "OpenCode CLI is installed."
        opencode --version || ux_warning "Could not determine OpenCode version."
    else
        ux_warning "OpenCode command not found after installation."
        ux_info "Please restart your terminal or run 'source ~/.bashrc' to update your PATH."
    fi
    echo ""

    # ========================================
    # Completion
    # ========================================
    ux_header "✅ OpenCode Setup Complete!"
    echo ""

    ux_section "Configuration Summary"
    ux_bullet "Environment: ${UX_PRIMARY}$environment${UX_RESET}"
    if [ -f "$HOME/.config/opencode/opencode.json" ]; then
        ux_bullet "Config file: ${UX_SUCCESS}$HOME/.config/opencode/opencode.json${UX_RESET}"
    else
        ux_bullet "Config file: ${UX_INFO}Using OpenCode defaults${UX_RESET}"
    fi
    echo ""

    ux_section "Next Steps"
    ux_bullet "View help: ${UX_PRIMARY}opencode-help${UX_RESET}"
    ux_bullet "Start coding: ${UX_PRIMARY}opencode${UX_RESET}"
    if [ "$environment" != "home" ]; then
        ux_bullet "Verify LLM config: ${UX_PRIMARY}opencode-verify${UX_RESET}"
    fi
    echo ""

    ux_section "Useful Commands"
    ux_bullet "install-opencode     : Run the installer again"
    ux_bullet "opencode-help        : Show OpenCode help and commands"
    ux_bullet "opencode-verify      : Verify installation & configuration"
    ux_bullet "opencode-edit        : Edit configuration file"
    ux_bullet "uninstall-opencode   : Remove OpenCode and configuration"
    ux_bullet "opencode             : Start OpenCode CLI"
    echo ""
}

# Direct-exec guard: run main() only if script is executed directly, not sourced
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
