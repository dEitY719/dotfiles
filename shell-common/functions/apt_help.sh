#!/bin/sh
# shell-common/functions/apt_help.sh
# apt-help topic (commands live in tools/integrations/apt.sh)

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

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
    ux_table_row "auug" "update+upgrade+cleanup" "Full cleanup (auto-yes)"
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
        --list|list|section|sections)        _apt_help_list_sections ;;
        --all|all)          _apt_help_full ;;
        *)                  _apt_help_section_rows "$1" ;;
    esac
}

alias apt-help='apt_help'
