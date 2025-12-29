#!/bin/bash

# bash/app/apt.bash

# -------------------------------
# APT Basic Commands
# -------------------------------
alias au='sudo apt-get update'        # Update package lists
alias aug='sudo apt-get upgrade'      # Upgrade installed packages
alias afa='sudo apt-get full-upgrade' # Full upgrade (more aggressive)
alias adu='sudo apt-get dist-upgrade' # Distribution upgrade
alias aar='sudo apt-get autoremove'   # Remove unused dependencies
alias aac='sudo apt-get autoclean'    # Remove old .deb files from cache
alias ac='sudo apt-get clean'         # Remove all .deb files from cache

# All-in-one cleanup (update → upgrade → autoremove → autoclean)
alias auug='sudo apt-get update && sudo apt-get upgrade && sudo apt-get autoremove && sudo apt-get autoclean'

alias ai='sudo apt-get install' # Install package
alias ar='sudo apt-get remove'  # Remove package (keep config)
alias arp='sudo apt-get purge'  # Remove package (delete config)
alias as='apt-cache search'     # Search packages
alias ash='apt-cache show'      # Show package details

# List installed packages
alias alist='apt list --installed'   # List all installed packages
alias aulist='apt list --upgradable' # List upgradable packages
alias ahold='apt-mark hold'          # Hold package version
alias aunhold='apt-mark unhold'      # Unhold package version

# Low-level commands
alias adpkg='sudo dpkg -i'          # Install .deb file directly
alias afd='sudo apt-get install -f' # Fix broken dependencies

# Cache/Status check
alias acheck='sudo apt-get check'             # Check system consistency
alias asize='du -sh /var/cache/apt/archives/' # Check cache size

# =======================================
# Single Command Functions
# =======================================

# Show package dependencies
adep() {
    if [ $# -eq 0 ]; then
        ux_usage "adep" "<package-name>" "Show package dependencies"
        ux_bullet "adep firefox"
        return 1
    fi
    apt-cache depends "$1"
}

# Show reverse dependencies (which packages need this)
ardep() {
    if [ $# -eq 0 ]; then
        ux_usage "ardep" "<package-name>" "Show reverse dependencies"
        ux_bullet "ardep libc6"
        return 1
    fi
    apt-cache rdepends "$1"
}

# List all files installed by a package
afiles() {
    if [ $# -eq 0 ]; then
        ux_usage "afiles" "<package-name>" "List files installed by package"
        ux_bullet "afiles curl"
        return 1
    fi
    dpkg -L "$1"
}

# Find which package owns a file
awhich() {
    if [ $# -eq 0 ]; then
        ux_usage "awhich" "<file-path>" "Find which package owns a file"
        ux_bullet "awhich /usr/bin/curl"
        return 1
    fi
    dpkg -S "$1"
}

# Remove old kernels (Ubuntu only)
aclean_kernel() {
    ux_header "Cleaning Old Kernels"

    local current_kernel
    current_kernel=$(uname -r)
    echo "Current kernel: ${UX_SUCCESS}$current_kernel${UX_RESET}"

    echo ""
    ux_section "Installed kernels"
    dpkg -l | grep linux-image

    echo ""
    if ux_confirm "WARNING: This will remove all kernels except the current one. Continue?" "n"; then
        local -a kernels_to_remove=()
        while IFS= read -r kernel; do
            kernels_to_remove+=("$kernel")
        done < <(dpkg -l | grep linux-image | grep -v "$current_kernel" | awk '{print $2}')

        if [[ ${#kernels_to_remove[@]} -gt 0 ]]; then
            sudo apt-get remove --purge "${kernels_to_remove[@]}"
            ux_success "Old kernels removed successfully!"
        else
            ux_info "No old kernels found to remove"
        fi
    else
        ux_info "Cancelled"
    fi
}

# PPA Management
appa_add() {
    if [ $# -eq 0 ]; then
        echo "Usage: appa_add ppa:username/ppa-name"
        echo "Example: appa_add ppa:obsproject/obs-studio"
        return 1
    fi
    sudo add-apt-repository "$1" && sudo apt-get update
}

appa_list() {
    echo "Installed PPAs:"
    grep -h '^deb-src' /etc/apt/sources.list.d/*.list 2>/dev/null || grep -h '^deb ' /etc/apt/sources.list.d/*.list 2>/dev/null | sort -u
}

appa_remove() {
    if [ $# -eq 0 ]; then
        echo "Usage: appa_remove ppa:username/ppa-name"
        echo "Example: appa_remove ppa:obsproject/obs-studio"
        return 1
    fi
    sudo add-apt-repository --remove "$1" && sudo apt-get update
}

# System package statistics
astat() {
    ux_header "System Package Statistics"
    ux_table_row "Total Installed" "$(dpkg -l | grep -c '^ii')" ""
    ux_table_row "Upgradable" "$(apt list --upgradable 2>/dev/null | grep -v -c 'WARNING\|Listing')" ""
    ux_table_row "Cache Size" "$(du -sh /var/cache/apt/archives/ 2>/dev/null | cut -f1)" ""
    ux_table_row "Held Packages" "$(apt-mark showhold | wc -l)" ""
    echo ""
}

# Show package info with dependencies
ainfo() {
    if [ $# -eq 0 ]; then
        echo "Usage: ainfo <package-name>"
        return 1
    fi

    ux_header "Package Info: $1"
    apt-cache show "$1" | head -20
    echo ""
    ux_section "Dependencies"
    apt-cache depends "$1" | head -10
    echo ""
}

# =======================================
# Help Function
# =======================================
