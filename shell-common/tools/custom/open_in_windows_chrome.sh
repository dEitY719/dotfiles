#!/bin/bash
# shell-common/tools/custom/open_in_windows_chrome.sh
# Open links in the Windows-side Chrome from WSL (#1408).
#
# This is the single target the three WSL "default browser" mechanisms point at:
#
#   $BROWSER              <- shell-common/env/browser.sh (exports THIS file's
#                            path; $BROWSER is word-split by its consumers and
#                            chrome.exe's own path contains a space)
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

# --- self location (authoritative; never trust an inherited SHELL_COMMON) ---
# realpath on BASH_SOURCE, not $0: --register points /usr/bin/x-www-browser at
# this file via update-alternatives, so under that name a $0-derived directory
# would resolve to /usr/bin and miss the helper. Same spelling as the siblings
# that skip init.sh (mirror-pages-activate.sh, gen_command_docs.sh).
_SELF="$(realpath "${BASH_SOURCE[0]}")" || exit 1
SHELL_COMMON="${_SELF%/tools/custom/*}"

# ux_lib directly rather than through init.sh: init.sh returns before loading
# anything under DOTFILES_TEST_MODE, which would leave the bats suite asserting
# against local stubs instead of the output this script actually ships. ux_lib
# has no interactive guard and mutes its own ANSI in test mode, so one source
# covers both. The fallback only matters if ux_lib itself is missing.
if [ -r "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" ]; then
    # shellcheck source=/dev/null
    . "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
else
    ux_error() { printf '[ERROR] %s\n' "$*" >&2; }
    ux_warning() { printf '[WARN] %s\n' "$*"; }
    ux_info() { printf '%s\n' "$*"; }
    ux_success() { printf '[OK] %s\n' "$*"; }
    ux_bullet() { printf '  %s\n' "$*"; }
    ux_section() { printf '\n%s\n' "$*"; }
    ux_usage() { printf 'Usage: %s %s%s\n' "$1" "$2" "${3:+ - $3}"; }
fi

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

# --- argument translation --------------------------------------------------
#
# chrome.exe is a Windows process and cannot see the Linux filesystem, so a
# local path that reaches this wrapper has to be translated first. It does
# reach us: --register claims text/html, which makes `xdg-open ./report.html`
# and a `file:///home/...` URL land here.
#
# Exactly two shapes are translated, both via `wslpath -w`, and both are
# emitted as the bare Windows path (`C:\Users\...\report.html`) rather than a
# rebuilt file:// URL — Chrome accepts a Windows path argument directly, and
# one output shape means one thing to test:
#
#   1. a file:// URL whose decoded local path exists
#   2. a bare argument that names an existing filesystem path
#
# Everything else is forwarded byte-identical: https:// URLs, Chrome's own
# flags (--new-window), and any path that does not exist. Without wslpath on
# PATH nothing is translated at all — passing the argument through unchanged
# is strictly better than failing.
#
# Percent-decoding is deliberately partial: %20 and %25 only, in that order.
# Any other escape (%C3%A9, …) is left alone, so such a URL simply fails the
# existence test below and passes through untouched rather than being mangled.
# Query strings and fragments are not stripped either, for the same reason.
_CONVERTED=""
_convert_arg() {
    local arg="$1"
    local path

    _CONVERTED="$arg"
    command -v wslpath >/dev/null 2>&1 || return 0

    case "$arg" in
    file://*)
        path="${arg#file://}"
        # file://localhost/p and file:///p both name a local path; anything
        # else after the authority is a remote host and must not be touched.
        path="${path#localhost}"
        case "$path" in
        /*) ;;
        *) return 0 ;;
        esac
        path="${path//%20/ }"
        path="${path//%25/%}"
        ;;
    -*)
        # A leading dash is always a flag here, never a relative path.
        return 0
        ;;
    *://*)
        # http, https, chrome, about, … — remote schemes stay verbatim.
        return 0
        ;;
    *)
        path="$arg"
        ;;
    esac

    [ -e "$path" ] || return 0
    _CONVERTED="$(wslpath -w "$path" 2>/dev/null)" || _CONVERTED="$arg"
    [ -n "$_CONVERTED" ] || _CONVERTED="$arg"
}

# --- registration ----------------------------------------------------------

# Desktop Entry spec: the Exec executable is wrapped in double quotes, and
# `"`, backtick, `$` and `\` are backslash-escaped inside them. Without this a
# dotfiles checkout under a path with a space produces an unlaunchable entry.
_desktop_quote() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//\`/\\\`}"
    s="${s//\$/\\\$}"
    printf '"%s"' "$s"
}

# printf %q for the sudo lines we only *print*: the user pastes them into a
# shell, so a space or a metacharacter in the path has to survive that trip.
# The arrays this script actually executes need no quoting — bash arrays
# already pass each element as one argv word.
_quoted_cmd() {
    local out
    out="$(printf '%q ' "$@")"
    printf '%s' "${out% }"
}

# --register bakes $_SELF (absolute) into the .desktop Exec line and into
# update-alternatives. From a linked git worktree that path is temporary:
# tearing the worktree down silently breaks this machine's default browser
# for every one of the three mechanisms. Refuse instead of warning.
#
# A copy that is in no git repo at all is legitimate (an installed copy), so
# only a *linked* worktree refuses — that is exactly where --absolute-git-dir
# (…/.git/worktrees/NAME) and --git-common-dir (…/.git) disagree.
# Prints the main checkout on success so the error can name it.
_linked_worktree_main() {
    local dir="$1" gitdir commondir
    command -v git >/dev/null 2>&1 || return 1
    gitdir="$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null)" || return 1
    commondir="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
    [ -n "$gitdir" ] && [ -n "$commondir" ] || return 1
    [ "$gitdir" != "$commondir" ] || return 1
    printf '%s\n' "${commondir%/.git}"
}

_write_desktop_entry() {
    local desktop_file="$1"
    local exec_field
    exec_field="$(_desktop_quote "$_SELF")"

    cat > "$desktop_file" <<DESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=Windows Chrome (WSL)
GenericName=Web Browser
Comment=Open links in the Windows-side Google Chrome
Exec=${exec_field} %u
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
    local exe main_checkout

    # Defined once and both run and printed from here: the dry run exists to
    # promise what the real run will do, so the two must not drift apart.
    local -a xdg_default=(xdg-settings set default-web-browser "$_DESKTOP_ID")
    local -a xdg_mime=(xdg-mime default "$_DESKTOP_ID"
        x-scheme-handler/http x-scheme-handler/https text/html)
    local -a alt_install=(update-alternatives --install
        /usr/bin/x-www-browser x-www-browser "$_SELF" 200)
    local -a alt_set=(update-alternatives --set x-www-browser "$_SELF")

    # Ahead of the dry-run branch on purpose: --dry-run promises what a real
    # run would do, and a real run from here would do nothing but break.
    if main_checkout="$(_linked_worktree_main "$(dirname "$_SELF")")"; then
        ux_error "refusing to register from a linked git worktree: ${_SELF}"
        ux_bullet "Every registration hard-codes that absolute path, and a worktree is temporary."
        ux_bullet "Run it from the main checkout instead:"
        ux_bullet "${main_checkout}/shell-common/tools/custom/open_in_windows_chrome.sh --register"
        return 1
    fi

    # Registering a browser that is not installed would leave every path
    # pointing at a dead Exec line, so resolve first and refuse otherwise.
    exe="$(_windows_chrome_exe)" || {
        _no_chrome
        return 1
    }

    if [ "$dry_run" = "1" ]; then
        ux_info "Dry run - nothing on this machine was changed."
        ux_bullet "chrome.exe:    ${exe}"
        ux_bullet "desktop entry: ${desktop_file}  (Exec=$(_desktop_quote "$_SELF") %u)"
        ux_bullet "xdg default:   ${xdg_default[*]}"
        ux_bullet "mime default:  ${xdg_mime[*]}"
        ux_bullet "alternatives:  sudo $(_quoted_cmd "${alt_install[@]}")"
        return 0
    fi

    mkdir -p "$apps_dir" || return 1
    _write_desktop_entry "$desktop_file" || return 1
    ux_success "wrote ${desktop_file}"

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$apps_dir" >/dev/null 2>&1 || true
    fi

    if command -v xdg-settings >/dev/null 2>&1; then
        if "${xdg_default[@]}" >/dev/null 2>&1; then
            ux_success "xdg default-web-browser -> ${_DESKTOP_ID}"
        else
            ux_warning "xdg-settings refused ${_DESKTOP_ID}; xdg-open may still use the old browser."
        fi
    else
        ux_warning "xdg-settings not found - skipped the xdg-open default."
    fi

    if command -v xdg-mime >/dev/null 2>&1; then
        if "${xdg_mime[@]}" >/dev/null 2>&1; then
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
        if sudo "${alt_install[@]}" >/dev/null && sudo "${alt_set[@]}" >/dev/null; then
            ux_success "x-www-browser -> ${_SELF}"
        else
            ux_warning "update-alternatives failed - x-www-browser left untouched."
        fi
    else
        ux_warning "sudo needs a password - run these two lines to finish x-www-browser:"
        ux_bullet "sudo $(_quoted_cmd "${alt_install[@]}")"
        ux_bullet "sudo $(_quoted_cmd "${alt_set[@]}")"
    fi
}

main() {
    local exe arg
    local -a forward=()

    case "${1-}" in
    -h | --help | help)
        _usage
        return 0
        ;;
    --register)
        case "${2-}" in
        --dry-run) _register 1 ;;
        "") _register 0 ;;
        *)
            ux_error "unknown --register option: $2"
            return 2
            ;;
        esac
        return
        ;;
    --)
        shift
        ;;
    esac

    exe="$(_windows_chrome_exe)" || {
        _no_chrome
        return 1
    }

    for arg in "$@"; do
        _convert_arg "$arg"
        forward+=("$_CONVERTED")
    done

    exec "$exe" "${forward[@]}"
}

# Direct-exec guard: this file is a command, not a library.
if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "${BASH_SOURCE[0]}" ]; then
    main "$@"
fi
