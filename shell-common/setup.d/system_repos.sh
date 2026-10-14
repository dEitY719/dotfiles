#!/bin/sh
# shell-common/setup.d/system_repos.sh — rpm/apt system repo files under
# /etc behind the sudo 3-gate (#2140).
#
# Sourced by shell-common/setup.sh only (never auto-sourced, no interactive
# guard): relies on its SHELL_COMMON_DIR / DOTFILES_ROOT / ux_* / constants.

setup_rpm_config() {
    environment="$1"
    repo_target="/etc/yum.repos.d/ds.repo"
    marker="MANAGED_BY_DOTFILES"

    ux_header "Setting up RPM repository configuration for: $environment"

    # Gate 1: Only proceed if yum or dnf is available
    if ! command -v yum >/dev/null 2>&1 && ! command -v dnf >/dev/null 2>&1; then
        ux_info "Skipped: yum/dnf not found (not a RHEL/CentOS system)"
        return 0
    fi

    # Gate 2: Verify RHEL 8 — do not deploy RHEL 8.6 repos to Fedora/Rocky/RHEL 9
    if [ -f /etc/os-release ]; then
        _rpm_os_id="$(. /etc/os-release && echo "${ID:-}")"
        _rpm_os_version="$(. /etc/os-release && echo "${VERSION_ID:-}")"
        case "$_rpm_os_id" in
            rhel|centos)
                case "$_rpm_os_version" in
                    8|8.*) ;; # RHEL 8.x — proceed
                    *)
                        ux_info "Skipped: RHEL ${_rpm_os_version} detected (repo is RHEL 8.6 only)"
                        return 0
                        ;;
                esac
                ;;
            *)
                ux_info "Skipped: ${_rpm_os_id} detected (repo is RHEL 8 only)"
                return 0
                ;;
        esac
    fi

    # Gate 3: Verify privilege — use sudo if needed, skip if unavailable
    _rpm_run_privileged=""
    if [ "$(id -u)" = "0" ]; then
        _rpm_run_privileged=""  # already root, no sudo needed
    elif command -v sudo >/dev/null 2>&1; then
        _rpm_run_privileged="sudo"
        ux_info "Root privileges required for /etc/yum.repos.d/ — sudo will prompt for password"
    else
        ux_warning "Skipped: sudo not available and not running as root"
        return 0
    fi

    case "$environment" in
        internal)
            _rpm_src="$(_internal_src rpm/ds.repo.internal)"
            # A placeholder repo in /etc would break dnf/yum: keep the
            # existing system file instead (_internal_src already warned).
            if grep -Eq "$LOCAL_PLACEHOLDER_ERE" "$_rpm_src" 2>/dev/null; then
                ux_info "Skipped: $repo_target left untouched (placeholder source)"
                return 0
            fi

            # Ensure target directory exists
            if [ ! -d "/etc/yum.repos.d" ]; then
                $_rpm_run_privileged mkdir -p "/etc/yum.repos.d"
                ux_info "Created directory: /etc/yum.repos.d"
            fi

            # Backup existing repo file if present
            if [ -f "$repo_target" ]; then
                backup="${repo_target}.backup.$(date +%Y%m%d%H%M%S)"
                $_rpm_run_privileged mv "$repo_target" "$backup"
                ux_info "Backed up existing file: $backup"
            fi

            # Copy (not symlink) since this is a system-level config in /etc/
            $_rpm_run_privileged cp "$_rpm_src" "$repo_target"
            ux_success "Copied: rpm/ds.repo.internal → $repo_target"
            ux_info "Using: internal repositories (RHEL 8.6)"
            ;;
        external|public)
            # Only remove if the file was deployed by dotfiles (has marker)
            if [ -f "$repo_target" ] && grep -q "$marker" "$repo_target" 2>/dev/null; then
                backup="${repo_target}.backup.$(date +%Y%m%d%H%M%S)"
                $_rpm_run_privileged mv "$repo_target" "$backup"
                ux_info "Backed up and removed dotfiles-managed repo: $backup"
            elif [ -f "$repo_target" ]; then
                ux_info "Existing $repo_target is not managed by dotfiles — leaving untouched"
            fi
            ;;
    esac
}

setup_apt_config() {
    environment="$1"
    sources_target="/etc/apt/sources.list"
    marker="MANAGED_BY_DOTFILES"

    ux_header "Setting up APT sources configuration for: $environment"

    # Gate 1: Only proceed if apt is available
    if ! command -v apt >/dev/null 2>&1; then
        ux_info "Skipped: apt not found (not a Debian/Ubuntu system)"
        return 0
    fi

    # Gate 2: Verify privilege — use sudo if needed, skip if unavailable
    _apt_run_privileged=""
    if [ "$(id -u)" = "0" ]; then
        _apt_run_privileged=""
    elif command -v sudo >/dev/null 2>&1; then
        _apt_run_privileged="sudo"
        ux_info "Root privileges required for /etc/apt/sources.list — sudo will prompt for password"
    else
        ux_warning "Skipped: sudo not available and not running as root"
        return 0
    fi

    # Read OS identity (used by both deploy and restore paths)
    _apt_os_id=""
    _apt_codename=""
    if [ -f /etc/os-release ]; then
        _apt_os_id="$(. /etc/os-release && echo "${ID:-}")"
        _apt_codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
    fi

    case "$environment" in
        internal)
            # Deploy gate: verify Ubuntu + matching config file exists
            if [ "$_apt_os_id" != "ubuntu" ]; then
                ux_info "Skipped: ${_apt_os_id:-unknown} detected (only Ubuntu is supported)"
                return 0
            fi
            _apt_source="${DOTFILES_ROOT}/apt/sources.list.${_apt_codename}"
            if [ -z "$_apt_codename" ] || [ ! -f "$_apt_source" ]; then
                # Listing repo-tracked `apt/sources.list.*` names — all
                # alphanumeric, so `ls` is fine here (SC2012).
                # shellcheck disable=SC2012
                ux_info "Skipped: no apt config for '${_apt_codename:-unknown}' (available: $(ls "${DOTFILES_ROOT}"/apt/sources.list.* 2>/dev/null | sed 's/.*sources\.list\.//' | grep -v '\.internal' | tr '\n' ' ' || echo 'none'))"
                return 0
            fi

            # Backup existing sources.list if present and not already managed
            if [ -f "$sources_target" ]; then
                if ! grep -q "$marker" "$sources_target" 2>/dev/null; then
                    backup="${sources_target}.backup.$(date +%Y%m%d%H%M%S)"
                    $_apt_run_privileged cp "$sources_target" "$backup"
                    ux_info "Backed up original: $backup"
                fi
            fi

            $_apt_run_privileged cp "$_apt_source" "$sources_target"
            ux_success "Copied: apt/sources.list.${_apt_codename} → $sources_target"
            ux_info "Using: official Ubuntu mirrors (Ubuntu ${_apt_codename})"
            ux_info "Run 'sudo apt update' to refresh package lists"
            ;;
        external|public)
            # Restore path: no codename/OS gate — must always reach here
            # to handle post-upgrade scenarios (e.g., jammy → noble)
            if [ -f "$sources_target" ] && grep -q "$marker" "$sources_target" 2>/dev/null; then
                # Backup names are generated by this script, so `ls -t` mtime
                # ordering is safe here (SC2012).
                # shellcheck disable=SC2012
                _apt_latest_backup="$(ls -t "${sources_target}".backup.* 2>/dev/null | head -1)"
                if [ -n "$_apt_latest_backup" ]; then
                    $_apt_run_privileged cp "$_apt_latest_backup" "$sources_target"
                    ux_success "Restored original: $_apt_latest_backup → $sources_target"
                else
                    $_apt_run_privileged rm -f "$sources_target"
                    ux_warning "Removed dotfiles-managed sources.list (no backup found to restore)"
                fi
            elif [ -f "$sources_target" ]; then
                ux_info "Existing $sources_target is not managed by dotfiles — leaving untouched"
            fi
            ;;
    esac
}

