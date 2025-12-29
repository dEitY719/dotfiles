#!/bin/sh
# shell-common/functions/apthelp.sh
# APT package manager help - shared between bash and zsh

apthelp() {
    if type ux_header >/dev/null 2>&1; then
        ux_header "APT Quick Commands"
    else
        echo ""
        echo "APT Quick Commands"
        echo ""
    fi

    if type ux_section >/dev/null 2>&1; then
        ux_section "Basic Update & Upgrade"
        ux_table_row "au" "apt-get update" "Update lists"
        ux_table_row "aug" "apt-get upgrade" "Safe upgrade"
        ux_table_row "afa" "apt-get full-upgrade" "Aggressive upgrade"
        ux_table_row "adu" "apt-get dist-upgrade" "Dist upgrade"
        ux_table_row "auug" "update+upgrade+clean" "Full cleanup"
        echo ""

        ux_section "Cleanup & Remove"
        ux_table_row "aar" "apt-get autoremove" "Remove unused deps"
        ux_table_row "aac" "apt-get autoclean" "Clean old cache"
        ux_table_row "ac" "apt-get clean" "Clean all cache"
        ux_table_row "afd" "apt-get install -f" "Fix broken deps"
        ux_table_row "acheck" "apt-get check" "Verify consistency"
        echo ""

        ux_section "Install & Remove"
        ux_table_row "ai" "apt-get install" "Install package"
        ux_table_row "ar" "apt-get remove" "Remove (keep config)"
        ux_table_row "arp" "apt-get purge" "Remove completely"
        ux_table_row "adpkg" "dpkg -i" "Install .deb file"
        echo ""

        ux_section "Search & Info"
        ux_table_row "as" "apt-cache search" "Search packages"
        ux_table_row "ash" "apt-cache show" "Show details"
        ux_table_row "ainfo" "ainfo <pkg>" "Info + deps"
        ux_table_row "alist" "list --installed" "List installed"
        ux_table_row "aulist" "list --upgradable" "List upgradable"
        echo ""

        ux_section "Dependencies & Files"
        ux_table_row "adep" "depends <pkg>" "Show deps"
        ux_table_row "ardep" "rdepends <pkg>" "Show reverse deps"
        ux_table_row "afiles" "dpkg -L <pkg>" "List files"
        ux_table_row "awhich" "dpkg -S <file>" "Find owner pkg"
        echo ""

        ux_section "Version & Hold"
        ux_table_row "ahold" "apt-mark hold" "Lock version"
        ux_table_row "aunhold" "apt-mark unhold" "Unlock version"
        echo ""

        ux_section "PPA & System"
        ux_table_row "appa_add" "add-apt-repository" "Add PPA"
        ux_table_row "appa_list" "List PPAs" "Show installed PPAs"
        ux_table_row "appa_remove" "remove PPA" "Remove PPA"
        ux_table_row "aclean_kernel" "Clean kernels" "Remove old kernels"
        ux_table_row "astat" "Stats" "System pkg stats"
        ux_table_row "asize" "Cache size" "Check cache size"
        echo ""

        ux_info "Note: Commands prefixed with sudo require elevated privileges"
    else
        echo "APT Quick Commands"
        echo "────────────────────────"
        echo "Basic Update & Upgrade:"
        echo "  au      - apt-get update"
        echo "  aug     - apt-get upgrade"
        echo "  afa     - apt-get full-upgrade"
        echo "Cleanup & Remove:"
        echo "  aar     - apt-get autoremove"
        echo "  aac     - apt-get autoclean"
        echo "  ac      - apt-get clean"
        echo "Install & Remove:"
        echo "  ai      - apt-get install"
        echo "  ar      - apt-get remove"
        echo "  arp     - apt-get purge"
        echo "Search & Info:"
        echo "  as      - apt-cache search"
        echo "  ash     - apt-cache show"
        echo "Note: Commands prefixed with sudo require elevated privileges"
    fi
}
