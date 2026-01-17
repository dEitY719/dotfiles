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

    if [ -f "$config_file" ]; then
        ux_info "Config file already exists. Using existing configuration."
        return 0
    fi

    ux_info "Setting up home environment (using default LLM)..."

    # For home, we don't need to create a custom config
    # OpenCode uses its default configuration
    ux_success "Home environment configured (using OpenCode defaults)"
}

# Generate opencode.json for external environment
generate_external_config() {
    local config_file="$HOME/.config/opencode/opencode.json"

    if [ -f "$config_file" ]; then
        ux_info "Config file already exists. Using existing configuration."
        return 0
    fi

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

    if [ -f "$config_file" ]; then
        ux_info "Config file already exists. Using existing configuration."
        return 0
    fi

    ux_info "Setting up internal environment with Samsung DS LiteLLM..."

    cat > "$config_file" << 'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "litellm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "LiteLLM Provider",
      "options": {
        "baseURL": "http://ssai.samsungds.net:9090",
        "apiKey": "925f1053996f6a679f40db2251d2d622a5263731"
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
    # Step 3: Install OpenCode CLI
    # ========================================
    ux_step "3/5" "Installing OpenCode CLI..."

    ux_info "Installing OpenCode using official installer..."
    if curl -fsSL -L https://opencode.ai/install | bash; then
        ux_success "OpenCode installed successfully"
    else
        ux_error "OpenCode installation failed."
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
    ux_bullet "opencode-help        : Show dotfiles OpenCode help"
    ux_bullet "opencode-verify      : Verify LLM configuration"
    ux_bullet "opencode-edit        : Edit configuration file"
    ux_bullet "opencode             : Start OpenCode CLI"
    echo ""
}

main "$@"
