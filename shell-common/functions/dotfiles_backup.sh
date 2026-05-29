#!/bin/sh
# shell-common/functions/dotfiles_backup.sh
# Latest-only backup policy (issue #806).
#
# Every ./setup.sh run used to stamp backups with a timestamp
# (`.backup.<ts>`, `-<ts>-original`). When a dotfiles symlink got
# converted back into a regular file, each subsequent run produced a brand
# new backup — accumulating dozens of files in the home directory.
#
# These helpers use a FIXED suffix instead, so each new backup OVERWRITES
# the previous one. At most one backup file per target survives. This is
# the SSOT for the suffix strings and the backup primitives — setup scripts
# source this file and reference DOTFILES_BACKUP_SUFFIX / DOTFILES_ORIGINAL_SUFFIX.
#
# NOTE: This file only DEFINES functions/constants and produces no output at
# source time, so it deliberately omits the interactive guard (mirrors
# dotfiles_root.sh, gh_host.sh, …). That lets non-interactive setup scripts
# source it and still get the definitions, while the interactive loader can
# auto-source it harmlessly.

# Fixed suffixes (SSOT). Only set if not already defined so a caller may
# override before sourcing.
: "${DOTFILES_BACKUP_SUFFIX:=.backup}"
: "${DOTFILES_ORIGINAL_SUFFIX:=.original}"

# Echo the fixed backup path for a target (no side effects).
# Usage: dotfiles_backup_path <target> [suffix]
dotfiles_backup_path() {
    _dbp_target="$1"
    _dbp_suffix="${2:-$DOTFILES_BACKUP_SUFFIX}"
    printf '%s%s\n' "$_dbp_target" "$_dbp_suffix"
}

# Copy <target> to its fixed backup path, overwriting any prior backup.
# No-op (returns 0) when <target> does not exist.
# Echoes the backup path on success; returns non-zero on copy failure.
# Usage: dotfiles_backup_copy <target> [suffix]
dotfiles_backup_copy() {
    _dbc_target="$1"
    _dbc_suffix="${2:-$DOTFILES_BACKUP_SUFFIX}"
    [ -e "$_dbc_target" ] || return 0
    # Assignment RHS does not word-split, so outer quotes are unneeded here.
    _dbc_dest=$(dotfiles_backup_path "$_dbc_target" "$_dbc_suffix")
    if [ -d "$_dbc_target" ]; then
        # Clear any prior backup first so the recursive copy does not nest
        # the source inside an existing destination directory.
        rm -rf "$_dbc_dest"
        cp -Rf "$_dbc_target" "$_dbc_dest" || return 1
    else
        cp -f "$_dbc_target" "$_dbc_dest" || return 1
    fi
    printf '%s\n' "$_dbc_dest"
}

# Move <target> to its fixed backup path, overwriting any prior backup.
# No-op (returns 0) when <target> does not exist.
# Echoes the backup path on success; returns non-zero on move failure.
# Usage: dotfiles_backup_move <target> [suffix]
dotfiles_backup_move() {
    _dbm_target="$1"
    _dbm_suffix="${2:-$DOTFILES_BACKUP_SUFFIX}"
    [ -e "$_dbm_target" ] || return 0
    _dbm_dest=$(dotfiles_backup_path "$_dbm_target" "$_dbm_suffix")
    rm -rf "$_dbm_dest" 2>/dev/null || true
    mv "$_dbm_target" "$_dbm_dest" || return 1
    printf '%s\n' "$_dbm_dest"
}
