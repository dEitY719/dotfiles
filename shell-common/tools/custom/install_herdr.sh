#!/bin/bash
# shell-common/tools/custom/install_herdr.sh
# Install herdr (terminal workspace manager) into ~/.local/bin
#
# public/external: official installer (https://herdr.dev/install.sh).
# internal: herdr.dev is blocked by the corporate proxy, so download the GitHub
#   release binary directly (Linux x86_64 only). Pin with HERDR_VERSION=v0.9.0.
#
# Config symlink, plugins and external tools (lazygit/glow/delta/bat) are
# herdr/setup.sh's job — this script installs the binary only.
#
# Usage: install-herdr [--force]

set -e

source "$(dirname "$0")/init.sh" || exit 1

HERDR_INSTALL_URL="${HERDR_INSTALL_URL:-https://herdr.dev/install.sh}"
HERDR_RELEASE_BASE="https://github.com/ogulcancelik/herdr/releases"
HERDR_BIN="${HOME}/.local/bin/herdr"

# internal -> release binary; everything else (public/external/unset) -> installer.
herdr_install_method() {
    case "$1" in
        internal) echo "release" ;;
        *) echo "installer" ;;
    esac
}

# Downloaded to a file first: `curl | sh` reports success on a failed download
# because sh just reads empty input.
install_herdr_via_installer() {
    local installer rc=0
    installer=$(mktemp) || return 1
    if ! curl -fsSL "$HERDR_INSTALL_URL" -o "$installer"; then
        rm -f "$installer"
        return 1
    fi
    sh "$installer" || rc=$?
    rm -f "$installer"
    return "$rc"
}

herdr_release_url() {
    if [ -n "${HERDR_VERSION:-}" ]; then
        echo "${HERDR_RELEASE_BASE}/download/${HERDR_VERSION}/herdr-linux-x86_64"
    else
        echo "${HERDR_RELEASE_BASE}/latest/download/herdr-linux-x86_64"
    fi
}

install_herdr_via_release() {
    local tmp rc=0
    if [ "$(uname -s)/$(uname -m)" != "Linux/x86_64" ]; then
        echo "release binary is Linux x86_64 only (this host: $(uname -s)/$(uname -m))" >&2
        return 1
    fi
    tmp=$(mktemp) || return 1
    if ! curl -fsSL -o "$tmp" "$(herdr_release_url)"; then
        rm -f "$tmp"
        return 1
    fi
    mkdir -p "$(dirname "$HERDR_BIN")"
    install -m 0755 "$tmp" "$HERDR_BIN" || rc=$?
    rm -f "$tmp"
    return "$rc"
}

main() {
    local mode method

    ux_header "herdr Installation"

    if [ "${1:-}" != "--force" ] && command -v herdr >/dev/null 2>&1; then
        ux_success "herdr already installed: $(herdr --version 2>&1)"
        ux_info "Reinstall/upgrade: install-herdr --force"
        return 0
    fi

    mode=$(cat "$HOME/.dotfiles-setup-mode" 2>/dev/null || echo public)
    method=$(herdr_install_method "$mode")
    ux_info "setup mode: ${mode} -> install via ${method}"

    if ! "install_herdr_via_${method}"; then
        ux_error "herdr install failed (${method})"
        [ "$method" = "release" ] && ux_bullet "Proxy blocked? Request an exception: https://gsams.samsungds.net"
        return 1
    fi

    # ~/.local/bin may not be on this shell's PATH yet; check the file directly.
    if ! "$HERDR_BIN" --version; then
        ux_error "herdr installed but does not run: $HERDR_BIN"
        return 1
    fi

    ux_success "herdr installed: $HERDR_BIN"
    ux_section "Next"
    ux_bullet "Plugins + external tools: bash ${DOTFILES_ROOT}/herdr/setup.sh"
    ux_bullet "Help: herdr-help"
}

# Direct-exec guard: run main() only if script is executed directly, not sourced
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
