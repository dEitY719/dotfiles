#!/bin/sh
# shell-common/lib/setup/link.sh — idempotent symlink / copy-once / dir (#2137)
#
# One replacement for the ~15 per-module symlink+backup helpers listed in
# #2127. Guard-free pure lib, POSIX sh, explicit source only (see common.sh
# for the SHELL_COMMON / DOTFILES_ROOT bootstrap). All messages go via ux_*.
#
# API
#   dotfiles_ensure_link <src> <tgt> [--on-mismatch replace|keep] [--allow-dir] [--unmount-legacy]
#       src is resolved with `pwd -P`. tgt already linking to src -> silent
#       no-op. Link elsewhere -> replaced. Real file (or, with --allow-dir, a
#       directory) -> moved to tgt$DOTFILES_ORIGINAL_SUFFIX (#806), then
#       linked; an existing backup is never overwritten (warn, tgt left as is).
#       --on-mismatch keep: warn and leave any mismatch untouched.
#       --unmount-legacy: unmount a pre-#575 bind mount at tgt first.
#   dotfiles_ensure_copy_once <src> <tgt>
#       Copy only when tgt is absent (real-file configs, #940/#924/#1373);
#       a dangling symlink at tgt counts as absent and is replaced.
#   dotfiles_ensure_dir <path>
#
# Returns 0 on success or deliberate skip, 1 on failure, 2 on bad usage.

: "${SHELL_COMMON:=${DOTFILES_ROOT:?export SHELL_COMMON or DOTFILES_ROOT before sourcing lib/setup}/shell-common}"
# shellcheck source=shell-common/lib/setup/common.sh
. "${SHELL_COMMON}/lib/setup/common.sh"

# _dotfiles_physical <path> — absolute physical path of an existing path.
_dotfiles_physical() {
    if [ -d "$1" ]; then
        (cd -P "$1" && pwd -P)
    else
        _dp_dir=$(cd -P "$(dirname "$1")" && pwd -P) || return 1
        printf '%s/%s\n' "$_dp_dir" "$(basename "$1")"
    fi
}

# _dotfiles_is_mountpoint <path> — findmnt when present, else mount(8) output.
_dotfiles_is_mountpoint() {
    if command -v findmnt >/dev/null 2>&1; then
        findmnt "$1" >/dev/null 2>&1
    else
        mount 2>/dev/null | grep -qF " on $1 "
    fi
}

dotfiles_ensure_link() {
    _del_src="${1-}" _del_tgt="${2-}"
    _del_mode=replace _del_allow_dir=0 _del_unmount=0
    if [ -z "$_del_src" ] || [ -z "$_del_tgt" ]; then
        ux_error "usage: dotfiles_ensure_link <src> <tgt> [--on-mismatch replace|keep] [--allow-dir] [--unmount-legacy]"
        return 2
    fi
    shift 2
    while [ $# -gt 0 ]; do
        case "$1" in
            --on-mismatch)
                # dash aborts the whole script on a shift past $#; guard it.
                [ $# -ge 2 ] || { ux_error "dotfiles_ensure_link: --on-mismatch needs a value"; return 2; }
                _del_mode="$2" && shift
                ;;
            --on-mismatch=*) _del_mode="${1#*=}" ;;
            --allow-dir) _del_allow_dir=1 ;;
            --unmount-legacy) _del_unmount=1 ;;
            *) ux_error "dotfiles_ensure_link: unknown option: $1"; return 2 ;;
        esac
        shift
    done
    case "$_del_mode" in
        replace | keep) ;;
        *) ux_error "dotfiles_ensure_link: --on-mismatch must be replace|keep (got: $_del_mode)"; return 2 ;;
    esac
    if [ ! -e "$_del_src" ]; then
        ux_error "link source missing: $_del_src"
        return 1
    fi
    _del_src=$(_dotfiles_physical "$_del_src") || return 1

    if [ -L "$_del_tgt" ]; then
        [ "$(readlink "$_del_tgt")" = "$_del_src" ] && return 0
        if [ "$_del_mode" = keep ]; then
            ux_warning "keep: $_del_tgt links to $(readlink "$_del_tgt"), not $_del_src"
            return 0
        fi
        rm -f "$_del_tgt"
    elif [ -e "$_del_tgt" ]; then
        if [ "$_del_mode" = keep ]; then
            ux_warning "keep: $_del_tgt is a real file/dir, not a link to $_del_src"
            return 0
        fi
        if [ "$_del_unmount" = 1 ] && [ -d "$_del_tgt" ] && _dotfiles_is_mountpoint "$_del_tgt"; then
            # Legacy bind mount (#575): mv would fail with EBUSY. The mount
            # source is the same SSOT, so unmounting is content-neutral.
            ux_warning "bind-mount detected at $_del_tgt — unmounting (sudo may prompt)"
            if ! sudo umount "$_del_tgt"; then
                ux_error "unmount failed: $_del_tgt — manual fix: sudo umount '$_del_tgt' && rmdir '$_del_tgt' && ./setup.sh"
                return 1
            fi
            # The empty underlying mount-point dir must go for ln -s to land.
            rmdir "$_del_tgt" 2>/dev/null || true
        fi
    fi
    if [ -e "$_del_tgt" ] && [ ! -L "$_del_tgt" ]; then
        if [ -d "$_del_tgt" ] && [ "$_del_allow_dir" != 1 ]; then
            ux_error "refusing to replace directory $_del_tgt (pass --allow-dir)"
            return 1
        fi
        _del_bak=$(dotfiles_backup_path "$_del_tgt" "$DOTFILES_ORIGINAL_SUFFIX")
        if [ -e "$_del_bak" ] || [ -L "$_del_bak" ]; then
            ux_warning "backup $_del_bak already exists — not overwriting; $_del_tgt left as is (move one aside, then re-run)"
            return 0
        fi
        dotfiles_backup_move "$_del_tgt" "$DOTFILES_ORIGINAL_SUFFIX" >/dev/null || {
            ux_error "backup failed: $_del_tgt -> $_del_bak"
            return 1
        }
        ux_warning "backed up: $_del_tgt -> $_del_bak"
    fi
    if ! { mkdir -p "$(dirname "$_del_tgt")" && ln -s "$_del_src" "$_del_tgt"; }; then
        ux_error "symlink failed: $_del_tgt -> $_del_src"
        return 1
    fi
    ux_info "symlink: $_del_tgt -> $_del_src"
}

dotfiles_ensure_copy_once() {
    _dco_src="${1-}" _dco_tgt="${2-}"
    if [ -z "$_dco_src" ] || [ -z "$_dco_tgt" ]; then
        ux_error "usage: dotfiles_ensure_copy_once <src> <tgt>"
        return 2
    fi
    [ -e "$_dco_tgt" ] && return 0
    # A dangling link (e.g. into a removed worktree, #589) is not a config.
    [ -L "$_dco_tgt" ] && rm -f "$_dco_tgt"
    if [ ! -f "$_dco_src" ]; then
        ux_error "copy source missing: $_dco_src"
        return 1
    fi
    if ! { mkdir -p "$(dirname "$_dco_tgt")" && cp "$_dco_src" "$_dco_tgt"; }; then
        ux_error "copy failed: $_dco_src -> $_dco_tgt"
        return 1
    fi
    ux_info "copied: $_dco_src -> $_dco_tgt"
}

dotfiles_ensure_dir() {
    [ -n "${1-}" ] || {
        ux_error "usage: dotfiles_ensure_dir <path>"
        return 2
    }
    [ -d "$1" ] && return 0
    if [ -e "$1" ] || [ -L "$1" ]; then
        ux_error "not a directory: $1"
        return 1
    fi
    mkdir -p "$1" || {
        ux_error "mkdir failed: $1"
        return 1
    }
}
