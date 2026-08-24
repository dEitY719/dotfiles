#!/bin/bash
# shell-common/tools/custom/open_in_windows_chrome.sh
# Open links in the Windows-side Chrome from WSL (#1408).
#
# This is the single target the three WSL "default browser" mechanisms point at:
#
#   $BROWSER              <- shell-common/env/browser.sh (resolves chrome.exe
#                            through the same helper this script uses)
#   xdg-open              <- ~/.local/share/applications/windows-chrome.desktop
#   x-www-browser         <- update-alternatives
#
# The last two are machine-local state, so they are registered on demand:
#
#   open_in_windows_chrome.sh --register [--dry-run]
#
# Never auto-sourced (tools/custom/ never is) and never wired into setup.sh —
# registering rewrites this machine's desktop defaults and must stay an
# explicit, per-machine decision.

# --- self location (authoritative; do not trust an inherited DOTFILES_ROOT) ---
_SELF_DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)" || exit 1
_SELF="${_SELF_DIR}/$(basename "$0")"

# ux_lib, via the shared custom-tools initializer. Under DOTFILES_TEST_MODE it
# returns before defining anything, so the fallbacks below are unconditional.
if [ -r "${_SELF_DIR}/init.sh" ]; then
    # shellcheck source=/dev/null
    . "${_SELF_DIR}/init.sh" || true
fi

if ! command -v ux_error >/dev/null 2>&1; then
    ux_error() { echo "Error: $*" >&2; }
    ux_warning() { echo "Warning: $*" >&2; }
    ux_info() { echo "$*"; }
    ux_success() { echo "$*"; }
    ux_bullet() { echo "  $*"; }
    ux_section() { echo "$*"; }
    ux_usage() { echo "Usage: $1 $2${3:+ - $3}"; }
fi

# init.sh derives these too, but it is skipped in test mode and may be absent;
# recompute unconditionally so the resolved helper always belongs to THIS
# checkout rather than to whatever DOTFILES_ROOT the caller happened to export.
DOTFILES_ROOT="${_SELF_DIR%/shell-common/tools/custom}"
SHELL_COMMON="${DOTFILES_ROOT}/shell-common"

_CHROME_HELPER="${SHELL_COMMON}/functions/windows_chrome.sh"
if [ ! -r "$_CHROME_HELPER" ]; then
    ux_error "missing helper: ${_CHROME_HELPER}"
    exit 1
fi
# shellcheck source=/dev/null
. "$_CHROME_HELPER"

_DESKTOP_ID="windows-chrome.desktop"

_usage() {
    ux_usage "open_in_windows_chrome.sh" "[ARG...] | --register [--dry-run] | -h" \
        "Open ARGs in the Windows-side Google Chrome (WSL only)"

    ux_section "Modes"
    ux_info "Only the FIRST argument selects a mode; everything else reaches Chrome unchanged."
    ux_bullet "-h, --help, help  this text"
    ux_bullet "--register        make this wrapper the xdg-open and x-www-browser default here"
    ux_bullet "--dry-run         with --register: print the plan, change nothing"
    ux_bullet "--                stop mode parsing; forward the rest verbatim"

    ux_section "Environment"
    ux_bullet "WINDOWS_CHROME_EXE    pin chrome.exe explicitly (no fallback search)"
    ux_bullet "WINDOWS_CHROME_DRIVE  Windows C: mount point (default /mnt/c)"
}

# Two distinct failures reach here and the fix differs, so say which one it is:
# an explicit override never falls back to the search (see the helper), so a
# broken WINDOWS_CHROME_EXE must not be reported as "Chrome is not installed".
_no_chrome() {
    if [ -n "${WINDOWS_CHROME_EXE:-}" ]; then
        ux_error "WINDOWS_CHROME_EXE is set but not executable: ${WINDOWS_CHROME_EXE}"
        ux_bullet "Fix that path, or unset it to fall back to the default Chrome search."
        return 0
    fi

    ux_error "Windows Chrome not found under ${WINDOWS_CHROME_DRIVE:-/mnt/c}."
    ux_bullet "Install Chrome on Windows, or set WINDOWS_CHROME_EXE to its chrome.exe."
}

_write_desktop_entry() {
    local desktop_file="$1"

    cat > "$desktop_file" <<DESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=Windows Chrome (WSL)
GenericName=Web Browser
Comment=Open links in the Windows-side Google Chrome
Exec=${_SELF} %u
Terminal=false
StartupNotify=false
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
Categories=Network;WebBrowser;
DESKTOP
}

_register() {
    local dry_run="$1"
    local apps_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    local desktop_file="${apps_dir}/${_DESKTOP_ID}"
    local exe

    # Registering a browser that is not installed would leave every path
    # pointing at a dead Exec line, so resolve first and refuse otherwise.
    exe="$(_windows_chrome_exe)" || {
        _no_chrome
        return 1
    }

    # Every registration below hard-codes this file's absolute path, so a
    # register run from a throwaway git worktree leaves dangling defaults once
    # that worktree is torn down.
    ux_info "Registering ${_SELF} - run this from your permanent dotfiles checkout."

    if [ "$dry_run" = "1" ]; then
        ux_info "Dry run - nothing on this machine was changed."
        ux_bullet "chrome.exe:    ${exe}"
        ux_bullet "desktop entry: ${desktop_file}  (Exec=${_SELF} %u)"
        ux_bullet "xdg default:   xdg-settings set default-web-browser ${_DESKTOP_ID}"
        ux_bullet "mime default:  xdg-mime default ${_DESKTOP_ID} x-scheme-handler/http x-scheme-handler/https text/html"
        ux_bullet "alternatives:  sudo update-alternatives --install /usr/bin/x-www-browser x-www-browser ${_SELF} 200"
        return 0
    fi

    mkdir -p "$apps_dir" || return 1
    _write_desktop_entry "$desktop_file" || return 1
    ux_success "wrote ${desktop_file}"

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$apps_dir" >/dev/null 2>&1 || true
    fi

    if command -v xdg-settings >/dev/null 2>&1; then
        if xdg-settings set default-web-browser "$_DESKTOP_ID" >/dev/null 2>&1; then
            ux_success "xdg default-web-browser -> ${_DESKTOP_ID}"
        else
            ux_warning "xdg-settings refused ${_DESKTOP_ID}; xdg-open may still use the old browser."
        fi
    else
        ux_warning "xdg-settings not found - skipped the xdg-open default."
    fi

    if command -v xdg-mime >/dev/null 2>&1; then
        if xdg-mime default "$_DESKTOP_ID" \
            x-scheme-handler/http x-scheme-handler/https text/html >/dev/null 2>&1; then
            ux_success "mimeapps http/https/html -> ${_DESKTOP_ID}"
        else
            ux_warning "xdg-mime failed; check ~/.config/mimeapps.list by hand."
        fi
    else
        ux_warning "xdg-mime not found - skipped the mimeapps defaults."
    fi

    # x-www-browser lives under /usr/bin and needs root. Never assume a
    # password prompt is acceptable here: print the two lines instead.
    if ! command -v update-alternatives >/dev/null 2>&1; then
        ux_warning "update-alternatives not found - x-www-browser left untouched."
    elif sudo -n true >/dev/null 2>&1; then
        if sudo update-alternatives --install /usr/bin/x-www-browser x-www-browser "$_SELF" 200 >/dev/null \
            && sudo update-alternatives --set x-www-browser "$_SELF" >/dev/null; then
            ux_success "x-www-browser -> ${_SELF}"
        else
            ux_warning "update-alternatives failed - x-www-browser left untouched."
        fi
    else
        ux_warning "sudo needs a password - run these two lines to finish x-www-browser:"
        ux_bullet "sudo update-alternatives --install /usr/bin/x-www-browser x-www-browser ${_SELF} 200"
        ux_bullet "sudo update-alternatives --set x-www-browser ${_SELF}"
    fi
}

main() {
    local exe

    case "${1-}" in
    -h | --help | help)
        _usage
        return 0
        ;;
    --register)
        shift
        case "${1-}" in
        --dry-run) _register 1 ;;
        "") _register 0 ;;
        *)
            ux_error "unknown --register option: $1"
            return 2
            ;;
        esac
        return $?
        ;;
    --)
        shift
        ;;
    esac

    exe="$(_windows_chrome_exe)" || {
        _no_chrome
        return 1
    }

    exec "$exe" "$@"
}

# Direct-exec guard: this file is a command, not a library.
if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "${BASH_SOURCE[0]}" ]; then
    main "$@"
fi
