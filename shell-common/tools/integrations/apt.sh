#!/bin/sh
# shell-common/tools/apt.sh
# APT package manager - aliases, functions, and help
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# APT Basic Commands (Aliases)
# ═══════════════════════════════════════════════════════════════

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

alias au='sudo apt-get update'        # Update package lists
alias aug='sudo apt-get upgrade'      # Upgrade installed packages
alias afa='sudo apt-get full-upgrade' # Full upgrade (more aggressive)
alias adu='sudo apt-get dist-upgrade' # Distribution upgrade
alias aar='sudo apt-get autoremove'   # Remove unused dependencies
alias aac='sudo apt-get autoclean'    # Remove old .deb files from cache
alias ac='sudo apt-get clean'         # Remove all .deb files from cache

# All-in-one cleanup (update → upgrade → autoremove → autoclean), non-interactive
alias auug='sudo apt-get update && sudo apt-get -y upgrade && sudo apt-get -y autoremove && sudo apt-get autoclean'

# Migration guard: previous versions of this file defined `ai` as an alias.
# In interactive zsh, an active alias causes `ai() { ... }` to fail parsing
# ("defining function based on alias") on reload. Drop any stale alias first.
unalias ai 2>/dev/null || true
ai() { sudo apt-get install "$@"; } # Install package
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
# Migration guard: see note on `ai` above.
unalias afd 2>/dev/null || true
afd() { sudo apt-get install -f "$@"; } # Fix broken dependencies

# Cache/Status check
alias acheck='sudo apt-get check'             # Check system consistency
alias asize='du -sh /var/cache/apt/archives/' # Check cache size

# ═══════════════════════════════════════════════════════════════
# APT Functions
# ═══════════════════════════════════════════════════════════════

# Show package dependencies
adep() {
    case "${1:-}" in -h | --help) apt_help deps; return 0 ;; esac
    if [ $# -eq 0 ]; then
        ux_usage "adep" "<package-name>" "Show package dependencies"
        ux_bullet "adep firefox"
        return 1
    fi
    apt-cache depends "$1"
}

# Show reverse dependencies (which packages need this)
ardep() {
    case "${1:-}" in -h | --help) apt_help deps; return 0 ;; esac
    if [ $# -eq 0 ]; then
        ux_usage "ardep" "<package-name>" "Show reverse dependencies"
        ux_bullet "ardep libc6"
        return 1
    fi
    apt-cache rdepends "$1"
}

# List all files installed by a package
afiles() {
    case "${1:-}" in -h | --help) apt_help deps; return 0 ;; esac
    if [ $# -eq 0 ]; then
        ux_usage "afiles" "<package-name>" "List files installed by package"
        ux_bullet "afiles curl"
        return 1
    fi
    dpkg -L "$1"
}

# Find which package owns a file
awhich() {
    case "${1:-}" in -h | --help) apt_help deps; return 0 ;; esac
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

    current_kernel=$(uname -r)
    ux_table_row "Current kernel" "$current_kernel"

    ux_info ""
    ux_section "Installed kernels"
    dpkg -l | grep linux-image

    ux_info ""
    if ux_confirm "WARNING: This will remove all kernels except the current one. Continue?" "n"; then
        _tmp_kernels=$(mktemp)
        dpkg -l | grep linux-image | grep -v "$current_kernel" | awk '{print $2}' > "$_tmp_kernels"

        if [ -s "$_tmp_kernels" ]; then
            # shellcheck disable=SC2046  # intentional split: one package name per line becomes a separate arg
            sudo apt-get remove --purge $(cat "$_tmp_kernels")
            ux_success "Old kernels removed successfully!"
        else
            ux_info "No old kernels found to remove"
        fi
        rm -f "$_tmp_kernels"
    else
        ux_info "Cancelled"
    fi
}

# PPA Management
appa_add() {
    case "${1:-}" in -h | --help) apt_help ppa; return 0 ;; esac
    if [ $# -eq 0 ]; then
        ux_usage "appa_add" "ppa:username/ppa-name" "Add a PPA and update package lists"
        ux_bullet "appa_add ppa:obsproject/obs-studio"
        return 1
    fi
    sudo add-apt-repository "$1" && sudo apt-get update
}

appa_list() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh # zsh: unmatched glob stays literal like sh
    ux_section "Installed PPAs"
    # deb and deb-src lines from every .list, deduplicated as one result (#1952)
    grep -hE '^deb(-src)? ' "${APT_SOURCES_LIST_DIR:-/etc/apt/sources.list.d}"/*.list 2>/dev/null | sort -u
}

appa_remove() {
    case "${1:-}" in -h | --help) apt_help ppa; return 0 ;; esac
    if [ $# -eq 0 ]; then
        ux_usage "appa_remove" "ppa:username/ppa-name" "Remove a PPA and update package lists"
        ux_bullet "appa_remove ppa:obsproject/obs-studio"
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
    ux_info ""
}

# Show package info with dependencies
ainfo() {
    case "${1:-}" in -h | --help) apt_help search; return 0 ;; esac
    if [ $# -eq 0 ]; then
        ux_usage "ainfo" "<package-name>" "Show package info with dependencies"
        return 1
    fi

    ux_header "Package Info: $1"
    apt-cache show "$1" | head -20
    ux_info ""
    ux_section "Dependencies"
    apt-cache depends "$1" | head -10
    ux_info ""
}
