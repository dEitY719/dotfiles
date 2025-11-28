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
        echo "Usage: adep <package-name>"
        echo "Example: adep firefox"
        return 1
    fi
    apt-cache depends "$1"
}

# Show reverse dependencies (which packages need this)
ardep() {
    if [ $# -eq 0 ]; then
        echo "Usage: ardep <package-name>"
        echo "Example: ardep libc6"
        return 1
    fi
    apt-cache rdepends "$1"
}

# List all files installed by a package
afiles() {
    if [ $# -eq 0 ]; then
        echo "Usage: afiles <package-name>"
        echo "Example: afiles curl"
        return 1
    fi
    dpkg -L "$1"
}

# Find which package owns a file
awhich() {
    if [ $# -eq 0 ]; then
        echo "Usage: awhich <file-path>"
        echo "Example: awhich /usr/bin/curl"
        return 1
    fi
    dpkg -S "$1"
}

# Remove old kernels (Ubuntu only)
aclean_kernel() {
    printf "[Cleaning Old Kernels]\n\n"

    local current_kernel
    current_kernel=$(uname -r)
    echo "Current kernel: $current_kernel"

    printf "\nInstalled kernels:\n"
    dpkg -l | grep linux-image

    printf "\nWARNING: This will remove all kernels except the current one.\n"
    read -p "Continue? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        local kernels_to_remove
        kernels_to_remove=$(dpkg -l | grep linux-image | grep -v "$current_kernel" | awk '{print $2}')
        # shellcheck disable=SC2086
        sudo apt-get remove --purge $kernels_to_remove
        echo "[Complete] Old kernels removed successfully!"
    else
        echo "[Cancelled]"
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
    echo "[System Package Statistics]"
    echo "Total installed packages: $(dpkg -l | grep -c '^ii')"
    echo "Upgradable packages: $(apt list --upgradable 2>/dev/null | grep -v -c 'WARNING\|Listing')"
    echo "Cache size: $(du -sh /var/cache/apt/archives/ 2>/dev/null | cut -f1)"
    echo "Held packages: $(apt-mark showhold | wc -l)"
}

# Show package info with dependencies
ainfo() {
    if [ $# -eq 0 ]; then
        echo "Usage: ainfo <package-name>"
        return 1
    fi

    echo "[Package Info: $1]"
    apt-cache show "$1" | head -20
    echo ""
    echo "[Dependencies]"
    apt-cache depends "$1" | head -10
}

# =======================================
# Help Function
# =======================================
apthelp() {
    # Color definitions
    local bold blue green yellow reset
    bold=$(tput bold 2>/dev/null || echo "")
    blue=$(tput setaf 4 2>/dev/null || echo "")
    green=$(tput setaf 2 2>/dev/null || echo "")
    yellow=$(tput setaf 3 2>/dev/null || echo "")
    reset=$(tput sgr0 2>/dev/null || echo "")

    cat <<EOF

${bold}${blue}[APT Quick Commands]${reset}

  ${bold}${blue}Basic Update & Upgrade:${reset}
    ${green}au${reset}        : apt-get update
    ${green}aug${reset}       : apt-get upgrade (safe update)
    ${green}afa${reset}       : apt-get full-upgrade (more aggressive)
    ${green}adu${reset}       : apt-get dist-upgrade (major version update)
    ${green}auug${reset}      : Complete cleanup (update + upgrade + autoremove + autoclean)

  ${bold}${blue}Cleanup & Remove:${reset}
    ${green}aar${reset}       : apt-get autoremove (remove unused dependencies)
    ${green}aac${reset}       : apt-get autoclean (remove old cache files)
    ${green}ac${reset}        : apt-get clean (remove all cache files)
    ${green}afd${reset}       : apt-get install -f (fix broken dependencies)
    ${green}acheck${reset}    : apt-get check (verify system consistency)

  ${bold}${blue}Install & Remove:${reset}
    ${green}ai${reset}        : apt-get install (install package)
    ${green}ar${reset}        : apt-get remove (remove package, keep config)
    ${green}arp${reset}       : apt-get purge (remove package completely)
    ${green}adpkg${reset}     : dpkg -i (install local .deb file)

  ${bold}${blue}Search & Info:${reset}
    ${green}as${reset}        : apt-cache search (search packages)
    ${green}ash${reset}       : apt-cache show (show package details)
    ${green}ainfo${reset}     : ainfo <package> (package info + dependencies)
    ${green}alist${reset}     : apt list --installed (list installed packages)
    ${green}aulist${reset}    : apt list --upgradable (list upgradable packages)

  ${bold}${blue}Dependencies & Files:${reset}
    ${green}adep${reset}      : adep <package> (show package dependencies)
    ${green}ardep${reset}     : ardep <package> (show reverse dependencies)
    ${green}afiles${reset}    : afiles <package> (list files from package)
    ${green}awhich${reset}    : awhich <filepath> (find package that owns file)

  ${bold}${blue}Version & Hold:${reset}
    ${green}ahold${reset}     : ahold <package> (lock package version)
    ${green}aunhold${reset}   : aunhold <package> (unlock package)

  ${bold}${blue}PPA Management:${reset}
    ${green}appa_add${reset}    : appa_add ppa:user/ppa-name (add PPA and update)
    ${green}appa_list${reset}   : appa_list (list installed PPAs)
    ${green}appa_remove${reset} : appa_remove ppa:user/ppa-name (remove PPA)

  ${bold}${blue}Kernel & System:${reset}
    ${green}aclean_kernel${reset} : Remove old kernels (Ubuntu only)
    ${green}astat${reset}        : Show system package statistics
    ${green}asize${reset}        : Check cache directory size

  ${bold}${yellow}Note: Commands prefixed with sudo require elevated privileges${reset}

EOF
}
