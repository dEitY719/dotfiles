#!/bin/bash
# shell-common/tools/custom/uninstall_docker.sh
# WSL Docker 제거 스크립트 (대화형)

set -e

usage() {
    cat <<'EOF'
Uninstall Docker Engine, CLI, and Compose (with optional data purge).

Usage:
  uninstall_docker.sh [-h|--help|help] [--dry-run] [--purge|--keep-data]

Options:
  -h, --help     Show this help and exit.
  --dry-run      Print actions without executing them.
  --purge        Pre-answer "yes" to "Completely purge all Docker data".
  --keep-data    Pre-answer "no" (default behaviour anyway).

Verification (after uninstall):
  command -v docker  # expected: not found
EOF
}

# Initialize common tools environment
source "$(dirname "$0")/init.sh" || exit 1

DRY_RUN=0
FORCE_PURGE=""
while [ $# -gt 0 ]; do
    case "$1" in
        help|-h|--help) usage; exit 0 ;;
        --dry-run) DRY_RUN=1 ;;
        --purge) FORCE_PURGE="y" ;;
        --keep-data) FORCE_PURGE="n" ;;
        *) ux_error "Unknown argument: $1"; usage >&2; exit 2 ;;
    esac
    shift
done

main() {
    clear
    ux_header "Docker Uninstaller"
    ux_info "This script uninstalls Docker Engine, CLI, and Compose."
    echo ""
    ux_warning "This is a destructive action that will remove Docker packages from your system."
    ux_error "A full purge will also delete all images, containers, volumes, and networks."
    [ "$DRY_RUN" = "1" ] && ux_info "(dry-run mode: no commands will execute)"
    [ -n "$FORCE_PURGE" ] && ux_info "(pre-answer for purge prompt: $FORCE_PURGE)"
    echo ""

    if ! ux_confirm "Are you sure you want to proceed with Docker uninstallation?" "n"; then
        ux_warning "Uninstallation cancelled."
        exit 0
    fi

    # Request sudo privileges
    ux_info "Requesting sudo privileges for uninstallation..."
    if ! sudo -v; then
        ux_error "Sudo privileges are required. Aborting."
        exit 1
    fi
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done >/dev/null 2>&1 &
    local sudo_keep_alive_pid=$!
    trap 'kill "$sudo_keep_alive_pid" 2>/dev/null' EXIT

    local docker_packages=(
        docker-ce docker-ce-cli containerd.io
        docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
    )

    local removal_failures=0
    local purge_choice="$FORCE_PURGE"

    # ========================================
    # Step 1: Uninstall Docker packages
    # ========================================
    ux_step "1/3" "Uninstalling Docker packages..."
    if [ -z "$purge_choice" ]; then
        if ux_confirm "Completely purge all Docker data (images, volumes, configs)?" "n"; then
            purge_choice="y"
        else
            purge_choice="n"
        fi
    fi

    if [ "$purge_choice" = "y" ]; then
        ux_warning "PURGING all Docker data..."
        if [ "$DRY_RUN" = "1" ]; then
            ux_info "[dry-run] sudo apt-get -y purge ${docker_packages[*]}"
            ux_info "[dry-run] sudo rm -rf /var/lib/docker /var/lib/containerd"
        elif ! ux_with_spinner "Purging packages and data" sudo apt-get -y purge "${docker_packages[@]}"; then
            ux_warning "Could not purge all packages. They may not have been installed."
            removal_failures=$((removal_failures + 1))
        fi
        if [ "$DRY_RUN" != "1" ]; then
            ux_info "Also removing docker data directories..."
            sudo rm -rf /var/lib/docker
            sudo rm -rf /var/lib/containerd
            ux_success "Docker data directories removed."
        fi
    else
        ux_info "Performing a standard removal of Docker packages (keeping data)..."
        if [ "$DRY_RUN" = "1" ]; then
            ux_info "[dry-run] sudo apt-get -y remove ${docker_packages[*]}"
        elif ! ux_with_spinner "Removing apt packages" sudo apt-get -y remove "${docker_packages[@]}"; then
            ux_warning "Could not remove all docker packages. They may not have been installed."
            removal_failures=$((removal_failures + 1))
        fi
    fi
    echo ""

    # ========================================
    # Step 2: Remove Docker repository and GPG key
    # ========================================
    ux_step "2/3" "Removing Docker repository..."
    if ux_confirm "Remove the Docker APT repository and GPG key?" "y"; then
        if [ "$DRY_RUN" = "1" ]; then
            ux_info "[dry-run] sudo rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg"
            ux_info "[dry-run] sudo apt-get update -qq"
        else
            [ -f /etc/apt/sources.list.d/docker.list ] && sudo rm -f /etc/apt/sources.list.d/docker.list && ux_success "Removed docker.list."
            [ -f /etc/apt/keyrings/docker.gpg ] && sudo rm -f /etc/apt/keyrings/docker.gpg && ux_success "Removed docker.gpg."
            ux_with_spinner "Updating apt cache" sudo apt-get update -qq
        fi
    else
        ux_info "Skipped removing Docker repository."
    fi
    echo ""

    # ========================================
    # Step 3: Remove docker group
    # ========================================
    ux_step "3/3" "Removing docker group..."
    if getent group docker >/dev/null 2>&1; then
        if ux_confirm "Remove the 'docker' user group?" "n"; then
            if [ "$DRY_RUN" = "1" ]; then
                ux_info "[dry-run] sudo groupdel docker"
            elif sudo groupdel docker; then
                ux_success "Removed 'docker' group."
            else
                ux_warning "Failed to remove 'docker' group. Is any user still a member?"
                removal_failures=$((removal_failures + 1))
            fi
        fi
    fi
    echo ""

    # Clean up
    kill "$sudo_keep_alive_pid" 2>/dev/null || true
    trap - EXIT

    # ========================================
    # Completion
    # ========================================
    ux_header "Docker Uninstallation Complete"
    if have_command docker; then
        ux_warning "The 'docker' command still exists. You may need to check your PATH or restart your shell."
        removal_failures=$((removal_failures + 1))
    else
        ux_success "The 'docker' command has been successfully removed."
    fi
    if [ "$removal_failures" -eq 0 ]; then
        ux_success "All removal steps completed cleanly."
    else
        ux_warning "Completed with $removal_failures non-fatal warning(s) — see output above."
    fi
    echo ""
    ux_info "Next: command -v docker  # expected: not found"
    echo ""
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
