#!/bin/bash
# shell-common/tools/custom/install_sops_age.sh
# Install sops + age globally (issue #1833). Explicit call only: never wired
# into install.sh/setup.sh, since placing the private key is manual anyway.
#
# Order: already installed -> print versions, exit 0 (no changes)
#        mise present       -> mise use -g sops@<pin> age@<pin>
#        otherwise          -> pinned GitHub release binaries -> ~/.local/bin
#                              (Linux x86_64 only)
# Pins: SOPS_VERSION / AGE_VERSION (no leading v).
#
# Usage: install-sops-age

set -e

source "$(dirname "$0")/init.sh" || exit 1
. "$(dirname "$0")/lib/install_helpers.sh" || exit 1

SOPS_VERSION="${SOPS_VERSION:-3.13.3}"
AGE_VERSION="${AGE_VERSION:-1.3.2}"
SOPS_AGE_BIN_DIR="${HOME}/.local/bin"

sops_age_installed() {
    command -v sops >/dev/null 2>&1 &&
        command -v age >/dev/null 2>&1 &&
        command -v age-keygen >/dev/null 2>&1
}

sops_age_print_versions() {
    ux_success "sops: $(sops --version --disable-version-check 2>/dev/null | head -n 1)"
    ux_success "age:  $(age --version 2>/dev/null | head -n 1)"
}

install_sops_age_via_mise() {
    mise use -g "sops@${SOPS_VERSION}" "age@${AGE_VERSION}"
}

install_sops_age_via_release() {
    local tmp rc=0
    if [ "$(uname -s)/$(uname -m)" != "Linux/x86_64" ]; then
        ux_error "release binaries are Linux x86_64 only (this host: $(uname -s)/$(uname -m))"
        return 1
    fi
    tmp=$(mktemp -d) || return 1
    {
        curl -fsSL -o "$tmp/sops" \
            "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.amd64" &&
            curl -fsSL -o "$tmp/age.tar.gz" \
                "https://github.com/FiloSottile/age/releases/download/v${AGE_VERSION}/age-v${AGE_VERSION}-linux-amd64.tar.gz" &&
            tar -xzf "$tmp/age.tar.gz" -C "$tmp" age/age age/age-keygen &&
            mkdir -p "$SOPS_AGE_BIN_DIR" &&
            install -m 0755 "$tmp/sops" "$SOPS_AGE_BIN_DIR/sops" &&
            install -m 0755 "$tmp/age/age" "$SOPS_AGE_BIN_DIR/age" &&
            install -m 0755 "$tmp/age/age-keygen" "$SOPS_AGE_BIN_DIR/age-keygen" &&
            verify_installed_binary "$SOPS_AGE_BIN_DIR/sops" --version --disable-version-check >/dev/null &&
            verify_installed_binary "$SOPS_AGE_BIN_DIR/age" >/dev/null
    } || rc=$?
    rm -rf "$tmp"
    return "$rc"
}

sops_age_manual_hints() {
    ux_section "Manual install"
    ux_bullet "mise use -g sops@${SOPS_VERSION} age@${AGE_VERSION}"
    ux_bullet "https://github.com/getsops/sops/releases/tag/v${SOPS_VERSION}  (sops-v${SOPS_VERSION}.linux.amd64 -> ~/.local/bin/sops)"
    ux_bullet "https://github.com/FiloSottile/age/releases/tag/v${AGE_VERSION}  (age, age-keygen -> ~/.local/bin/)"
    ux_bullet "Debian/Ubuntu: sudo apt install age  (sops is not in apt; use the release binary)"
}

main() {
    local method

    ux_header "sops + age Installation"

    if sops_age_installed; then
        ux_info "already installed, nothing changed"
        sops_age_print_versions
        return 0
    fi

    if command -v mise >/dev/null 2>&1; then
        method=mise
    else
        method=release
    fi
    ux_info "install via ${method} (sops ${SOPS_VERSION}, age ${AGE_VERSION})"

    if ! "install_sops_age_via_${method}"; then
        ux_error "sops/age install failed (${method})"
        sops_age_manual_hints
        return 1
    fi

    ux_success "sops + age installed (${method})"
    [ "$method" = "release" ] && ux_info "Make sure ${SOPS_AGE_BIN_DIR} is on PATH"
    ux_section "Next"
    ux_bullet "Key + status: sops-help setup, then sops-status"
}

# Direct-exec guard: run main() only if script is executed directly, not sourced
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
