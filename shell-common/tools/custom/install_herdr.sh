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
. "$(dirname "$0")/lib/install_helpers.sh" || exit 1

HERDR_INSTALL_URL="${HERDR_INSTALL_URL:-https://herdr.dev/install.sh}"
HERDR_RELEASE_BASE="https://github.com/ogulcancelik/herdr/releases"
HERDR_BIN="${HOME}/.local/bin/herdr"

# Read ~/.dotfiles-setup-mode: trim stray whitespace/newline, and fall back to
# public when the file does not exist yet. Legacy numeric values (1|2|3,
# written by pre-#571 setup.sh) are passed straight through to the case below.
#
# Same trim as claude.sh's _dotfiles_setup_mode, kept local rather than sourcing
# that file for one function. The repo has ~9 such copies, so hoisting one
# canonicaliser into a shared lib is its own change, not this one.
herdr_setup_mode() {
    tr -d ' \t\n\r' 2>/dev/null < "$HOME/.dotfiles-setup-mode" || echo public
}

# internal (legacy 2) -> release binary; everything else -> installer.
herdr_install_method() {
    case "$1" in
        2|internal) echo "release" ;;
        *) echo "installer" ;;
    esac
}

install_herdr_via_installer() {
    run_remote_installer "$HERDR_INSTALL_URL"
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
    local mode method version

    ux_header "herdr Installation"

    # ~/.local/bin may not be on this shell's PATH yet, and an older copy
    # earlier in PATH must not pass for this one — check the file directly.
    if [ "${1:-}" != "--force" ] && version=$(verify_installed_binary "$HERDR_BIN" 2>&1); then
        ux_success "herdr already installed: $version"
        ux_info "Reinstall/upgrade: install-herdr --force"
        return 0
    fi

    mode=$(herdr_setup_mode)
    method=$(herdr_install_method "$mode")
    ux_info "setup mode: ${mode} -> install via ${method}"

    if ! "install_herdr_via_${method}"; then
        ux_error "herdr install failed (${method})"
        [ "$method" = "release" ] && ux_bullet "Proxy blocked? Request an exception: https://gsams.samsungds.net"
        return 1
    fi

    if ! version=$(verify_installed_binary "$HERDR_BIN" 2>&1); then
        ux_error "herdr installed but does not run: $HERDR_BIN"
        printf '%s\n' "$version" | sed 's/^/  /'
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
