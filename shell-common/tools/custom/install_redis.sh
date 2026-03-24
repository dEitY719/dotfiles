#!/bin/bash
# shell-common/tools/custom/install_redis.sh
# Redis server installer for WSL/Ubuntu (interactive)

set -e

# Initialize common tools environment
source "$(dirname "$0")/init.sh" || exit 1

_installer_has_systemd() {
    command -v systemctl >/dev/null 2>&1 && [ "$(ps -p 1 -o comm=)" = "systemd" ]
}

_installer_restart_redis() {
    if _installer_has_systemd; then
        sudo systemctl restart redis-server
    else
        sudo service redis-server restart
    fi
}

# Safely write requirepass to redis.conf.
# Uses grep + printf to avoid sed special-character injection (/, &, \).
# Temp file is created in /etc/redis/ for atomic mv on same filesystem.
_installer_set_requirepass() {
    local redis_conf="$1"
    local password="$2"
    local conf_dir
    conf_dir=$(dirname "$redis_conf")
    local tmp_conf
    tmp_conf=$(sudo mktemp "${conf_dir}/redis.conf.XXXXXX")
    trap 'sudo rm -f "$tmp_conf"' RETURN

    grep -v "^requirepass " "$redis_conf" | sudo tee "$tmp_conf" >/dev/null
    printf "requirepass %s\n" "$password" | sudo tee -a "$tmp_conf" >/dev/null
    sudo chmod 640 "$tmp_conf"
    sudo mv "$tmp_conf" "$redis_conf"
}

main() {
    clear
    ux_header "Redis Server Installer for WSL/Ubuntu"
    ux_info "This script installs Redis server and CLI tools."

    ux_section "Installation Steps"
    ux_numbered 1 "Update package sources"
    ux_numbered 2 "Install Redis server"
    ux_numbered 3 "Start and enable Redis service"
    ux_numbered 4 "Configure Redis (optional)"
    ux_numbered 5 "Verify installation"
    echo ""
    ux_warning "This script requires sudo privileges."
    echo ""

    if ! ux_confirm "Do you want to proceed with the installation?" "y"; then
        ux_warning "Installation cancelled."
        exit 0
    fi

    ux_info "Requesting sudo privileges for the installation..."
    if ! sudo -v; then
        ux_error "Sudo privileges are required. Aborting."
        exit 1
    fi
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done &>/dev/null &
    local sudo_keep_alive_pid=$!
    trap 'kill "$sudo_keep_alive_pid" 2>/dev/null' EXIT

    ux_step "1/5" "Updating package sources..."
    if ! ux_with_spinner "Updating apt cache" sudo apt-get update -qq; then
        exit 1
    fi

    ux_step "2/5" "Installing Redis server..."
    if ! ux_with_spinner "Installing redis-server" sudo apt-get install -y -qq redis-server redis-tools; then
        ux_error "Redis installation failed."
        exit 1
    fi

    ux_step "3/5" "Starting and enabling Redis service..."

    if _installer_has_systemd; then
        if ! sudo systemctl start redis-server; then
            ux_warning "Failed to start Redis service via systemctl."
        else
            ux_success "Redis service started."
        fi
        if ! sudo systemctl enable redis-server; then
            ux_warning "Failed to enable Redis service on boot."
        else
            ux_success "Redis service enabled on boot."
        fi
    else
        if ! sudo service redis-server start; then
            ux_warning "Failed to start Redis service."
        else
            ux_success "Redis service started."
        fi
        ux_info "systemd not detected. To auto-start Redis, enable systemd in /etc/wsl.conf:"
        echo "  [boot]"
        echo "  systemd=true"
        echo ""
        ux_info "Then restart WSL: ${UX_PRIMARY}wsl --shutdown${UX_RESET}"
    fi
    echo ""

    ux_step "4/5" "Configuring Redis (optional)..."

    local redis_conf="/etc/redis/redis.conf"
    local password_was_set=false

    if [[ -f "$redis_conf" ]]; then
        ux_info "Redis config file: $redis_conf"

        if ux_confirm "Set maxmemory to 256mb (recommended for dev)?" "y"; then
            if grep -q "^maxmemory " "$redis_conf"; then
                sudo sed -i 's/^maxmemory .*/maxmemory 256mb/' "$redis_conf"
            else
                echo "maxmemory 256mb" | sudo tee -a "$redis_conf" >/dev/null
            fi
            if grep -q "^maxmemory-policy " "$redis_conf"; then
                sudo sed -i 's/^maxmemory-policy .*/maxmemory-policy allkeys-lru/' "$redis_conf"
            else
                echo "maxmemory-policy allkeys-lru" | sudo tee -a "$redis_conf" >/dev/null
            fi
            ux_success "maxmemory set to 256mb with allkeys-lru eviction."
            _installer_restart_redis
        else
            ux_info "Configuration skipped. Using defaults."
        fi

        if ux_confirm "Set a password for Redis? (recommended for security)" "n"; then
            printf "%s> %sEnter Redis password: " "${UX_PRIMARY}" "${UX_RESET}"
            read -r -s redis_pass
            echo ""
            if [[ -n "$redis_pass" ]]; then
                _installer_set_requirepass "$redis_conf" "$redis_pass"
                password_was_set=true
                ux_success "Password set."
                _installer_restart_redis
            fi
        fi
    else
        ux_warning "Redis config file not found at $redis_conf"
    fi
    echo ""

    ux_step "5/5" "Verifying installation..."

    if command -v redis-server &>/dev/null; then
        ux_info "Redis Server Version:"
        redis-server --version
    else
        ux_error "redis-server command not found after installation."
    fi

    if command -v redis-cli &>/dev/null; then
        ux_info "Redis CLI Version:"
        redis-cli --version

        local ping_result
        if [[ "$password_was_set" = "true" ]]; then
            ping_result=$(REDISCLI_AUTH="$redis_pass" redis-cli ping 2>/dev/null)
        else
            ping_result=$(redis-cli ping 2>/dev/null)
        fi
        if [[ "$ping_result" == "PONG" ]]; then
            ux_success "Redis is responding to PING."
        else
            ux_warning "Redis did not respond to PING. Service may not be running."
        fi
    else
        ux_error "redis-cli command not found."
    fi

    kill "$sudo_keep_alive_pid" 2>/dev/null || true
    trap - EXIT

    echo ""
    ux_header "Redis Installation Complete!"

    if [[ "$password_was_set" = "true" ]]; then
        ux_section "Authentication"
        ux_info "Password was configured. Add this to your shell profile:"
        echo "  ${UX_PRIMARY}export REDISCLI_AUTH=\"<your-password>\"${UX_RESET}"
        echo ""
        ux_info "All redis-* helper commands will authenticate automatically via REDISCLI_AUTH."
    fi

    ux_section "Next Steps"
    ux_numbered 1 "Check status: ${UX_PRIMARY}redis-server-ctl status${UX_RESET}"
    ux_numbered 2 "Test connection: ${UX_PRIMARY}redis-ping${UX_RESET}"
    ux_numbered 3 "View all helpers: ${UX_PRIMARY}redis-help${UX_RESET}"
    echo ""
}

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "$BASH_SOURCE" ]; then
    main "$@"
fi
