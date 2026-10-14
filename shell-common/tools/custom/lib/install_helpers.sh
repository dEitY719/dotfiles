#!/bin/sh
# shell-common/tools/custom/lib/install_helpers.sh
# Remote-installer, package-manager and post-install verification helpers for
# install*.sh (issues #1801, #2145). Sourced by ../install*.sh after init.sh.
#
# run_remote_installer / verify_installed_binary print nothing, so they stay
# usable without ux_lib. pkg_install reports through ux_info / ux_error, which
# init.sh always provides (ux_lib, or its own fallback) -- even under
# DOTFILES_TEST_MODE=1 since #2144.

# run_remote_installer <url> [installer-args...]
# Download to a temp file first: `curl | sh` reports success on a failed
# download because the shell just reads empty input. Env for the installer is
# passed as a call prefix (UV_NO_MODIFY_PATH=1 run_remote_installer ...).
# bash, not sh: claude's install.sh uses the bash =~ test; the POSIX ones run too.
run_remote_installer() {
    local url="$1" installer rc=0
    shift
    installer=$(mktemp) || return 1
    if ! curl -fsSL "$url" -o "$installer"; then
        rm -f "$installer"
        return 1
    fi
    bash "$installer" "$@" || rc=$?
    rm -f "$installer"
    return "$rc"
}

# verify_installed_binary <path> [args...]   (default args: --version)
# Succeeds (printing the output) only if the binary actually runs. Takes the
# install location, not `command -v`, so an older copy earlier in PATH can't
# pass for the one just installed.
verify_installed_binary() {
    local bin="$1"
    shift
    if [ -z "$bin" ] || [ ! -x "$bin" ]; then
        return 1
    fi
    [ $# -gt 0 ] || set -- --version
    "$bin" "$@"
}

# pkg_install <manager>=<package>...
#   e.g. pkg_install apt=fd-find yum=fd-find pacman=fd brew=fd
# Installs with the first manager that is both on PATH and given a spec, in
# the order the old per-script branches checked them: apt(-get), yum, dnf,
# pacman, brew. System managers run under sudo unless already root; brew never
# does. Sets PKG_INSTALL_MANAGER to the manager used. No usable manager:
# ux_error + return 1; otherwise returns the install command's status.
pkg_install() {
    local mgr bin spec pkg sudo=""
    PKG_INSTALL_MANAGER=""
    [ "$(id -u)" -eq 0 ] || sudo=sudo
    for mgr in apt yum dnf pacman brew; do
        pkg=""
        for spec in "$@"; do
            case "$spec" in "$mgr="*) pkg="${spec#*=}" ;; esac
        done
        bin="$mgr"
        [ "$mgr" = apt ] && bin=apt-get
        if [ -z "$pkg" ] || ! command -v "$bin" >/dev/null 2>&1; then
            continue
        fi
        PKG_INSTALL_MANAGER="$mgr"
        ux_info "Installing $pkg via $bin..."
        case "$mgr" in
            apt) $sudo apt-get update -qq && $sudo apt-get install -y "$pkg" ;;
            yum | dnf) $sudo "$bin" install -y "$pkg" ;;
            pacman) $sudo pacman -S --noconfirm "$pkg" ;;
            brew) brew install "$pkg" ;;
        esac
        return
    done
    ux_error "No supported package manager found (need one of: $*)"
    return 1
}
