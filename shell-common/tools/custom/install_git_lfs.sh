#!/bin/bash
# install_git_lfs.sh
# Install and initialize Git LFS (Ubuntu/Debian)

set -e

# Try to load ux_lib when executed outside initialized shell.
if ! type ux_header >/dev/null 2>&1; then
    if [ -n "$SHELL_COMMON" ] && [ -f "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" ]; then
        # shellcheck source=/dev/null
        source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
    elif [ -f "${HOME}/dotfiles/shell-common/tools/ux_lib/ux_lib.sh" ]; then
        # shellcheck source=/dev/null
        source "${HOME}/dotfiles/shell-common/tools/ux_lib/ux_lib.sh"
    fi
fi

main() {
    ux_header "Git LFS Install"
    ux_info "Updating package index"
    sudo apt-get update

    ux_info "Installing git-lfs package"
    sudo apt-get install -y git-lfs

    ux_info "Initializing git-lfs"
    git lfs install

    if command -v git-lfs >/dev/null 2>&1; then
        ux_success "Git LFS installed successfully"
        git lfs version
        return 0
    fi

    ux_error "Git LFS installation failed"
    return 1
}

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "$BASH_SOURCE" ]; then
    main "$@"
fi
