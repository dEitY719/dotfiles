#!/bin/bash
# mytool/docker-configure-proxy.sh
# Docker Proxy 설정 스크립트 (대화형)
# 회사 프록시(Corporate Proxy)가 필요한 환경에서 systemd를 통해 Docker에 proxy 설정

set -e

# Source the UX library

source "$(dirname "$0")/../bash/ux_lib/ux_lib.bash"


# Main script
main() {
    clear
    ux_header "Docker Corporate Proxy Setup"
    ux_info "This script configures Docker to use a corporate proxy via systemd."
    
    ux_section "Setup Process"
    ux_numbered 1 "Get proxy settings from you."
    ux_numbered 2 "Create systemd service drop-in directory."
    ux_numbered 3 "Create 'http-proxy.conf' file."
    ux_numbered 4 "Reload systemd and restart Docker."
    ux_numbered 5 "Verify the configuration."
    echo ""
    ux_warning "This script requires sudo privileges."
    echo ""

    if ! ux_confirm "Do you want to proceed?" "y"; then
        ux_warning "Setup cancelled."
        exit 0
    fi

    # ========================================
    # Step 1: Check Docker installation
    # ========================================
    ux_step "1/5" "Checking Docker installation..."

    if ! ux_require "docker"; then
        ux_error "Docker is not installed. Please install it first."
        return 1
    fi
    ux_success "Docker is installed: $(docker --version)"

    # ========================================
    # Step 2: Get proxy information from user
    # ========================================
    ux_step "2/5" "Enter Proxy Information"
    echo ""

    http_proxy=$(ux_input "Enter HTTP/HTTPS Proxy URL (e.g., http://1.2.3.4:8080):" ".+")
    if [ -z "$http_proxy" ]; then
        ux_error "Proxy URL is required. Aborting."
        return 1
    fi
    https_proxy="$http_proxy"
    
    echo ""
    no_proxy=$(ux_input "Enter NO_PROXY hosts (comma-separated, optional):")

    # ========================================
    # Step 3: Create systemd drop-in directory
    # ========================================
    ux_step "3/5" "Creating systemd service drop-in directory..."

    local drop_in_dir="/etc/systemd/system/docker.service.d"

    sudo mkdir -p "$drop_in_dir"
    if [ $? -ne 0 ]; then
        ux_error "Failed to create directory: $drop_in_dir"
        return 1
    fi
    ux_success "Directory created: $drop_in_dir"

    # ========================================
    # Step 4: Create http-proxy.conf file
    # ========================================
    ux_step "4/5" "Creating http-proxy.conf file..."

    # Using a temporary file to avoid complex sudo+tee+heredoc issues.
    conf_content="[Service]\nEnvironment=\"HTTP_PROXY=${http_proxy}\"\nEnvironment=\"HTTPS_PROXY=${https_proxy}\"\n"
    if [ -n "$no_proxy" ]; then
        conf_content+="Environment=\"NO_PROXY=${no_proxy}\"\n"
    fi
    echo -e "${conf_content}" | sudo tee "$drop_in_dir/http-proxy.conf" > /dev/null

    ux_success "Configuration file created: $drop_in_dir/http-proxy.conf"

    echo ""
    ux_section "Generated Configuration"
    sudo cat "$drop_in_dir/http-proxy.conf" | sed 's/^/  /'
    echo ""

    # ========================================
    # Step 5: Reload systemd and restart Docker
    # ========================================
    ux_step "5/5" "Reloading systemd and restarting Docker..."

    if ! sudo systemctl daemon-reload; then
        ux_error "systemd daemon-reload failed"
        return 1
    fi
    ux_success "systemd daemon reloaded."

    if ! sudo systemctl restart docker; then
        ux_error "Docker restart failed"
        return 1
    fi
    ux_success "Docker restarted."

    # ========================================
    # Verify configuration
    # ========================================
    ux_section "Verifying Configuration"
    systemctl show --property=Environment docker | sed 's/^/  /'
    echo ""

    # ========================================
    # Test proxy with docker pull
    # ========================================
    if ux_confirm "Test the proxy configuration with 'docker pull'?" "y"; then
        ux_info "Attempting to pull a small image (alpine:latest)..."
        if sudo docker pull alpine:latest > /dev/null 2>&1; then
            ux_success "Proxy test successful! The image was pulled."
            sudo docker rmi alpine:latest > /dev/null 2>&1 || true
        else
            ux_error "Proxy test failed. 'docker pull' could not complete."
            ux_warning "Manual verification needed: sudo nano $drop_in_dir/http-proxy.conf"
            return 1
        fi
    fi

    # ========================================
    # Completion
    # =============================================================================
    clear
    ux_header "✅ Docker Proxy Setup Complete!"
    ux_section "Summary"
    ux_table_header "Item" "Value"
    ux_table_row "Configuration File" "$drop_in_dir/http-proxy.conf"
    ux_table_row "To Verify" "systemctl show --property=Environment docker"
    ux_table_row "To Edit" "sudo nano $drop_in_dir/http-proxy.conf"
    ux_table_row "To Remove" "sudo rm -f $drop_in_dir/http-proxy.conf"
    echo ""
    ux_info "After editing or removing, you must reload and restart:"
    ux_bullet "sudo systemctl daemon-reload"
    ux_bullet "sudo systemctl restart docker"
    echo ""
}

main "$@"
