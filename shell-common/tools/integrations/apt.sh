#!/bin/sh
# shell-common/tools/apt.sh
# APT package manager - aliases, functions, and help
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# APT Basic Commands (Aliases)
# ═══════════════════════════════════════════════════════════════

alias au='sudo apt-get update'        # Update package lists
alias aug='sudo apt-get upgrade'      # Upgrade installed packages
alias afa='sudo apt-get full-upgrade' # Full upgrade (more aggressive)
alias adu='sudo apt-get dist-upgrade' # Distribution upgrade
alias aar='sudo apt-get autoremove'   # Remove unused dependencies
alias aac='sudo apt-get autoclean'    # Remove old .deb files from cache
alias ac='sudo apt-get clean'         # Remove all .deb files from cache

# All-in-one cleanup (update → upgrade → autoremove → autoclean)
alias auug='sudo apt-get update && sudo apt-get upgrade && sudo apt-get autoremove && sudo apt-get autoclean'

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
afd() { sudo apt-get install -f "$@"; } # Fix broken dependencies

# Cache/Status check
alias acheck='sudo apt-get check'             # Check system consistency
alias asize='du -sh /var/cache/apt/archives/' # Check cache size

# ═══════════════════════════════════════════════════════════════
# APT Functions
# ═══════════════════════════════════════════════════════════════

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

    current_kernel=$(uname -r)
    echo "Current kernel: ${UX_SUCCESS}$current_kernel${UX_RESET}"

    echo ""
    ux_section "Installed kernels"
    dpkg -l | grep linux-image

    echo ""
    if ux_confirm "WARNING: This will remove all kernels except the current one. Continue?" "n"; then
        _tmp_kernels=$(mktemp)
        dpkg -l | grep linux-image | grep -v "$current_kernel" | awk '{print $2}' > "$_tmp_kernels"

        if [ -s "$_tmp_kernels" ]; then
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

# ═══════════════════════════════════════════════════════════════
# APT Help Function
# ═══════════════════════════════════════════════════════════════

_apt_help_summary() {
    ux_info "Usage: apt-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "update: au | aug | afa | adu | auug"
    ux_bullet_sub "cleanup: aar | aac | ac | afd | acheck"
    ux_bullet_sub "install: ai | ar | arp | adpkg"
    ux_bullet_sub "search: as | ash | ainfo | alist | aulist"
    ux_bullet_sub "deps: adep | ardep | afiles | awhich"
    ux_bullet_sub "hold: ahold | aunhold"
    ux_bullet_sub "ppa: appa_add | appa_list | appa_remove | aclean_kernel | astat | asize"
    ux_bullet_sub "details: apt-help <section>  (example: apt-help install)"
}

_apt_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "update"
    ux_bullet_sub "cleanup"
    ux_bullet_sub "install"
    ux_bullet_sub "search"
    ux_bullet_sub "deps"
    ux_bullet_sub "hold"
    ux_bullet_sub "ppa"
}

_apt_help_rows_update() {
    ux_table_row "au" "apt-get update" "Update lists"
    ux_table_row "aug" "apt-get upgrade" "Safe upgrade"
    ux_table_row "afa" "apt-get full-upgrade" "Aggressive upgrade"
    ux_table_row "adu" "apt-get dist-upgrade" "Dist upgrade"
    ux_table_row "auug" "update+upgrade+clean" "Full cleanup"
}

_apt_help_rows_cleanup() {
    ux_table_row "aar" "apt-get autoremove" "Remove unused deps"
    ux_table_row "aac" "apt-get autoclean" "Clean old cache"
    ux_table_row "ac" "apt-get clean" "Clean all cache"
    ux_table_row "afd" "apt-get install -f" "Fix broken deps"
    ux_table_row "acheck" "apt-get check" "Verify consistency"
}

_apt_help_rows_install() {
    ux_table_row "ai" "apt-get install" "Install package"
    ux_table_row "ar" "apt-get remove" "Remove (keep config)"
    ux_table_row "arp" "apt-get purge" "Remove completely"
    ux_table_row "adpkg" "dpkg -i" "Install .deb file"
}

_apt_help_rows_search() {
    ux_table_row "as" "apt-cache search" "Search packages"
    ux_table_row "ash" "apt-cache show" "Show details"
    ux_table_row "ainfo" "ainfo <pkg>" "Info + deps"
    ux_table_row "alist" "list --installed" "List installed"
    ux_table_row "aulist" "list --upgradable" "List upgradable"
}

_apt_help_rows_deps() {
    ux_table_row "adep" "depends <pkg>" "Show deps"
    ux_table_row "ardep" "rdepends <pkg>" "Show reverse deps"
    ux_table_row "afiles" "dpkg -L <pkg>" "List files"
    ux_table_row "awhich" "dpkg -S <file>" "Find owner pkg"
}

_apt_help_rows_hold() {
    ux_table_row "ahold" "apt-mark hold" "Lock version"
    ux_table_row "aunhold" "apt-mark unhold" "Unlock version"
}

_apt_help_rows_ppa() {
    ux_table_row "appa_add" "add-apt-repository" "Add PPA"
    ux_table_row "appa_list" "List PPAs" "Show installed PPAs"
    ux_table_row "appa_remove" "remove PPA" "Remove PPA"
    ux_table_row "aclean_kernel" "Clean kernels" "Remove old kernels"
    ux_table_row "astat" "Stats" "System pkg stats"
    ux_table_row "asize" "Cache size" "Check cache size"
}

_apt_help_render_section() {
    ux_section "$1"
    "$2"
}

_apt_help_section_rows() {
    case "$1" in
        update|upgrade)        _apt_help_rows_update ;;
        cleanup|clean|remove)  _apt_help_rows_cleanup ;;
        install)               _apt_help_rows_install ;;
        search|info)           _apt_help_rows_search ;;
        deps|dependencies|files) _apt_help_rows_deps ;;
        hold|version)          _apt_help_rows_hold ;;
        ppa|system)            _apt_help_rows_ppa ;;
        *)
            ux_error "Unknown apt-help section: $1"
            ux_info "Try: apt-help --list"
            return 1
            ;;
    esac
}

_apt_help_full() {
    ux_header "APT Quick Commands"
    _apt_help_render_section "Basic Update & Upgrade" _apt_help_rows_update
    _apt_help_render_section "Cleanup & Remove" _apt_help_rows_cleanup
    _apt_help_render_section "Install & Remove" _apt_help_rows_install
    _apt_help_render_section "Search & Info" _apt_help_rows_search
    _apt_help_render_section "Dependencies & Files" _apt_help_rows_deps
    _apt_help_render_section "Version & Hold" _apt_help_rows_hold
    _apt_help_render_section "PPA & System" _apt_help_rows_ppa
    ux_info "Note: Commands prefixed with sudo require elevated privileges"
}

apt_help() {
    case "${1:-}" in
        ""|-h|--help|help) _apt_help_summary ;;
        --list|list)        _apt_help_list_sections ;;
        --all|all)          _apt_help_full ;;
        *)                  _apt_help_section_rows "$1" ;;
    esac
}

# Alias for apt-help format (using dash instead of underscore)
alias apt-help='apt_help'
