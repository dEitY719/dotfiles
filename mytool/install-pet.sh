#!/bin/bash
# mytool/install-pet.sh
# Install and configure pet (command snippet manager)

set -e

# Source the UX library
DOTFILES_ROOT="/home/bwyoon/dotfiles"
source "${DOTFILES_ROOT}/bash/ux_lib/ux_lib.bash"

# Check if pet is already installed
_check_installed() {
    if command -v pet &>/dev/null; then
        ux_warning "pet is already installed."
        pet version
        return 0
    fi
    return 1
}

# Detect system architecture
_get_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        *)
            echo "$arch"
            ;;
    esac
}

# Install pet from GitHub releases
_install_pet_from_github() {
    local os_type="$1"
    local arch="$(_get_arch)"
    local version="0.4.0"
    local temp_dir="/tmp/pet-install"

    mkdir -p "$temp_dir"
    cd "$temp_dir"

    local filename=""
    if [ "$os_type" = "linux" ]; then
        filename="pet_linux_${arch}.tar.gz"
    else
        filename="pet_darwin_${arch}.tar.gz"
    fi

    local url="https://github.com/knqyf263/pet/releases/download/v${version}/${filename}"

    ux_info "Downloading pet from GitHub: $filename"
    if ! curl -sSL "$url" -o "$filename"; then
        ux_error "Failed to download pet from GitHub"
        return 1
    fi

    ux_info "Extracting pet..."
    tar -xzf "$filename"

    if [ ! -f "pet" ]; then
        ux_error "Extraction failed - pet binary not found"
        return 1
    fi

    ux_info "Installing pet to /usr/local/bin..."
    sudo mv pet /usr/local/bin/
    sudo chmod +x /usr/local/bin/pet

    cd -
    rm -rf "$temp_dir"

    ux_success "pet installed successfully from GitHub."
}

# Install pet via system package manager or from releases
_install_pet() {
    local os_type=""

    # Detect OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        os_type="linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        os_type="macos"
    else
        ux_error "Unsupported OS: $OSTYPE"
        return 1
    fi

    ux_info "Installing pet for $os_type..."

    if [ "$os_type" = "linux" ]; then
        # For Linux (including WSL2) - try package manager first
        if command -v apt-get &>/dev/null; then
            ux_info "Trying to install pet via apt-get..."
            if sudo apt-get update -qq && sudo apt-get install -y pet 2>/dev/null; then
                ux_success "pet installed via apt-get."
                return 0
            fi
            ux_info "apt-get package not available, trying GitHub..."
        elif command -v yum &>/dev/null; then
            ux_info "Trying to install pet via yum..."
            if sudo yum install -y pet 2>/dev/null; then
                ux_success "pet installed via yum."
                return 0
            fi
            ux_info "yum package not available, trying GitHub..."
        elif command -v pacman &>/dev/null; then
            ux_info "Trying to install pet via pacman..."
            if sudo pacman -S --noconfirm pet 2>/dev/null; then
                ux_success "pet installed via pacman."
                return 0
            fi
            ux_info "pacman package not available, trying GitHub..."
        fi

        # Fallback to GitHub release
        _install_pet_from_github "$os_type"

    elif [ "$os_type" = "macos" ]; then
        # For macOS
        if command -v brew &>/dev/null; then
            ux_info "Installing pet via Homebrew..."
            brew install pet
            ux_success "pet installed via Homebrew."
        else
            ux_warning "Homebrew not found, trying GitHub..."
            _install_pet_from_github "$os_type"
        fi
    fi
}

# Display pet usage examples
_show_usage() {
    ux_section "pet Quick Reference"
    echo ""
    ux_info "Basic commands:"
    ux_bullet "pet new - Create a new snippet"
    ux_bullet "pet search - Search and execute snippet (interactive)"
    ux_bullet "pet list - List all snippets"
    ux_bullet "pet edit - Edit snippets in editor"
    echo ""
    ux_info "Common usage:"
    ux_bullet "Store frequently used commands as snippets"
    ux_bullet "Search by description or command pattern"
    ux_bullet "Snippets stored in ~/.config/pet/snippets.toml"
    echo ""
}

# Main installation flow
install-pet() {
    ux_header "pet Installation"

    if _check_installed; then
        ux_info "pet is ready to use!"
        _show_usage
        return 0
    fi

    _install_pet

    ux_success "pet installation complete!"
    echo ""
    ux_info "Start using pet now:"
    echo "  ${UX_BOLD}pet new${UX_RESET} - Create your first snippet"
    echo "  ${UX_BOLD}pet search${UX_RESET} - Search existing snippets"
    echo ""
    _show_usage
}

# Run installation if script is executed directly
if [ "${0##*/}" = "install-pet.sh" ]; then
    install-pet
fi
