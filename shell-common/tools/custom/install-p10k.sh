#!/bin/bash
# mytool/install-p10k.sh
# Install and configure powerlevel10k theme for zsh

set -e

# Source the UX library
DOTFILES_ROOT="${HOME}/dotfiles"
source "${DOTFILES_ROOT}/bash/ux_lib/ux_lib.bash"

# Check dependencies
_check_dependencies() {
    if ! command -v git &>/dev/null; then
        ux_error "git is not installed."
        return 1
    fi

    if [ ! -d "${HOME}/.oh-my-zsh" ]; then
        ux_error "oh-my-zsh is not installed."
        ux_info "Install with: ${UX_BOLD}install-zsh${UX_RESET}"
        return 1
    fi

    return 0
}

# Check if powerlevel10k is already installed
_check_installed() {
    if [ -d "${HOME}/.oh-my-zsh/custom/themes/powerlevel10k" ]; then
        ux_warning "powerlevel10k is already installed."
        return 0
    fi
    return 1
}

# Install powerlevel10k
_install_powerlevel10k() {
    ux_info "Cloning powerlevel10k repository..."

    mkdir -p "${HOME}/.oh-my-zsh/custom/themes"

    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
        "${HOME}/.oh-my-zsh/custom/themes/powerlevel10k"

    ux_success "powerlevel10k installed successfully."
}

# Update zshrc theme
_update_zshrc() {
    local zshrc="${HOME}/.zshrc"

    if [ ! -f "$zshrc" ]; then
        ux_error "zshrc not found at $zshrc"
        return 1
    fi

    ux_info "Updating ZSH_THEME in zshrc..."

    # Use sed to replace ZSH_THEME
    if sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$zshrc"; then
        ux_success "ZSH_THEME updated successfully."
    else
        ux_error "Failed to update ZSH_THEME."
        return 1
    fi
}

# List available Nerd Fonts
_list_nerd_fonts() {
    ux_section "Available Nerd Fonts"
    ux_numbered 1 "FiraCode Nerd Font (recommended)"
    ux_numbered 2 "Meslo LG Nerd Font (powerlevel10k default)"
    ux_numbered 3 "JetBrains Mono Nerd Font"
    ux_numbered 4 "Ubuntu Mono Nerd Font"
    ux_numbered 5 "Hack Nerd Font"
    ux_numbered 6 "Skip Nerd Font installation"
    echo ""
}

# Download and install Nerd Font
_install_nerd_font() {
    local font_name="$1"
    local font_url="$2"
    local fonts_dir="${HOME}/.local/share/fonts"

    mkdir -p "$fonts_dir"

    ux_info "Downloading ${font_name}..."

    # Create temporary directory
    local temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT

    # Download font zip
    if ! wget -q -O "${temp_dir}/font.zip" "$font_url"; then
        ux_error "Failed to download ${font_name}."
        return 1
    fi

    ux_info "Extracting font files..."
    unzip -q -o "${temp_dir}/font.zip" -d "$fonts_dir"

    # Update font cache
    if command -v fc-cache &>/dev/null; then
        ux_info "Updating font cache..."
        fc-cache -fv "$fonts_dir" > /dev/null 2>&1
    fi

    ux_success "${font_name} installed to ${fonts_dir}"
}

# Prompt user for font selection
_select_nerd_font() {
    _list_nerd_fonts

    read -p "Select font to install (1-6): " font_choice

    case "$font_choice" in
        1)
            _install_nerd_font "FiraCode Nerd Font" \
                "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/FiraCode.zip"
            ;;
        2)
            _install_nerd_font "Meslo LG Nerd Font" \
                "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/Meslo.zip"
            ;;
        3)
            _install_nerd_font "JetBrains Mono Nerd Font" \
                "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/JetBrainsMono.zip"
            ;;
        4)
            _install_nerd_font "Ubuntu Mono Nerd Font" \
                "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/UbuntuMono.zip"
            ;;
        5)
            _install_nerd_font "Hack Nerd Font" \
                "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/Hack.zip"
            ;;
        6)
            ux_info "Skipping Nerd Font installation."
            ;;
        *)
            ux_error "Invalid selection."
            return 1
            ;;
    esac
}

# Check if wget is available for font download
_check_wget() {
    if ! command -v wget &>/dev/null; then
        ux_warning "wget is not installed."
        ux_info "Install with: ${UX_BOLD}sudo apt-get install wget${UX_RESET}"
        return 1
    fi
    return 0
}

# Main installation flow
install-p10k() {
    ux_info "Installing powerlevel10k..."

    if ! _check_dependencies; then
        return 1
    fi

    if _check_installed; then
        ux_info "Updating powerlevel10k to latest version..."
        git -C "${HOME}/.oh-my-zsh/custom/themes/powerlevel10k" pull
        ux_success "powerlevel10k updated successfully."
    else
        _install_powerlevel10k
    fi

    _update_zshrc

    # Offer to install Nerd Font
    ux_info ""
    if ux_confirm "Install a Nerd Font for better visual appearance?" "y"; then
        if _check_wget; then
            _select_nerd_font
        else
            ux_warning "Cannot install Nerd Font without wget."
            ux_info "You can manually download fonts from: https://www.nerdfonts.com"
        fi
    fi

    ux_info ""
    ux_success "powerlevel10k installation complete!"
    ux_info "Restart your shell or run: ${UX_BOLD}exec zsh${UX_RESET}"
    ux_info ""
    ux_info "After restarting zsh, you may see a configuration wizard."
    ux_info "Follow the prompts to configure powerlevel10k to your preference."
}

# Run installation if script is executed directly
if [ "${0##*/}" = "install-powerlevel10k.sh" ]; then
    install-p10k
fi
