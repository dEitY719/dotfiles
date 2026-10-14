#!/usr/bin/env bats
# tests/bats/lib_setup/link.bats
# Behavior of shell-common/lib/setup/link.sh (#2137): dotfiles_ensure_link,
# dotfiles_ensure_copy_once, dotfiles_ensure_dir. Every case runs in a
# throwaway sandbox under an isolated $HOME, sourced from plain `sh` so the
# POSIX claim is exercised, not just `sh -n`.

load '../test_helper'

LINK_LIB="${_BATS_REAL_SHELL_COMMON}/lib/setup/link.sh"

setup() {
    setup_isolated_home
    SB="$(mktemp -d)"
    mkdir -p "$SB/src_dir" "$SB/home"
    printf 'ssot\n' >"$SB/src_file"
}

teardown() {
    teardown_isolated_home
    rm -rf "$SB"
}

# Run a snippet under POSIX sh with link.sh sourced.
_lib() {
    run sh -c ". '$LINK_LIB'; $1"
}

@test "ensure_link: creates a missing link (and its parent dir)" {
    _lib "dotfiles_ensure_link '$SB/src_file' '$SB/home/sub/f'"
    assert_success
    [ -L "$SB/home/sub/f" ]
    assert_equal "$(readlink "$SB/home/sub/f")" "$SB/src_file"
}

@test "ensure_link: src is normalized with pwd -P" {
    ln -s "$SB/src_dir" "$SB/alias_dir"
    _lib "dotfiles_ensure_link '$SB/alias_dir' '$SB/home/d'"
    assert_success
    assert_equal "$(readlink "$SB/home/d")" "$(cd -P "$SB/src_dir" && pwd -P)"
}

@test "ensure_link: same link is a silent no-op" {
    ln -s "$SB/src_file" "$SB/home/f"
    _lib "dotfiles_ensure_link '$SB/src_file' '$SB/home/f'"
    assert_success
    assert_output ""
    assert_equal "$(readlink "$SB/home/f")" "$SB/src_file"
}

@test "ensure_link: a link to another target is replaced" {
    ln -s "$SB/elsewhere" "$SB/home/f"
    _lib "dotfiles_ensure_link '$SB/src_file' '$SB/home/f'"
    assert_success
    assert_equal "$(readlink "$SB/home/f")" "$SB/src_file"
}

@test "ensure_link: a real file is backed up once with the .original suffix" {
    printf 'mine\n' >"$SB/home/f"
    _lib "dotfiles_ensure_link '$SB/src_file' '$SB/home/f'; dotfiles_ensure_link '$SB/src_file' '$SB/home/f'"
    assert_success
    [ -L "$SB/home/f" ]
    assert_equal "$(cat "$SB/home/f.original")" "mine"
    assert_equal "$(find "$SB/home" -name 'f.*' | wc -l | tr -d ' ')" 1
}

@test "ensure_link: an existing backup is never overwritten (warn, target kept)" {
    printf 'old backup\n' >"$SB/home/f.original"
    printf 'new local\n' >"$SB/home/f"
    _lib "dotfiles_ensure_link '$SB/src_file' '$SB/home/f'"
    assert_success
    assert_output --partial "f.original"
    [ ! -L "$SB/home/f" ]
    assert_equal "$(cat "$SB/home/f")" "new local"
    assert_equal "$(cat "$SB/home/f.original")" "old backup"
}

@test "ensure_link: a real directory is refused without --allow-dir" {
    mkdir "$SB/home/d"
    _lib "dotfiles_ensure_link '$SB/src_dir' '$SB/home/d'"
    assert_failure
    [ -d "$SB/home/d" ] && [ ! -L "$SB/home/d" ]
}

@test "ensure_link: --allow-dir backs the directory up and links" {
    mkdir "$SB/home/d" && printf 'x\n' >"$SB/home/d/keep"
    _lib "dotfiles_ensure_link '$SB/src_dir' '$SB/home/d' --allow-dir"
    assert_success
    [ -L "$SB/home/d" ]
    [ -f "$SB/home/d.original/keep" ]
}

@test "ensure_link: --on-mismatch keep warns and leaves a mismatch alone" {
    ln -s "$SB/elsewhere" "$SB/home/l"
    printf 'mine\n' >"$SB/home/f"
    _lib "dotfiles_ensure_link '$SB/src_file' '$SB/home/l' --on-mismatch keep && dotfiles_ensure_link '$SB/src_file' '$SB/home/f' --on-mismatch keep"
    assert_success
    assert_output --partial "keep"
    assert_equal "$(readlink "$SB/home/l")" "$SB/elsewhere"
    [ ! -L "$SB/home/f" ] && [ ! -e "$SB/home/f.original" ]
}

@test "ensure_link: missing source and bad options fail" {
    _lib "dotfiles_ensure_link '$SB/nope' '$SB/home/f'"
    assert_failure
    _lib "dotfiles_ensure_link '$SB/src_file' '$SB/home/f' --on-mismatch maybe"
    assert_failure
    [ ! -e "$SB/home/f" ]
}

@test "ensure_link: --unmount-legacy unmounts a bind mount, then links" {
    mkdir -p "$SB/bin" "$SB/home/d"
    printf '#!/bin/sh\n[ "$1" = "%s" ]\n' "$SB/home/d" >"$SB/bin/findmnt"
    printf '#!/bin/sh\necho "sudo $*" >>"%s/sudo.log"\n' "$SB" >"$SB/bin/sudo"
    chmod +x "$SB/bin/findmnt" "$SB/bin/sudo"
    _lib "PATH='$SB/bin':\$PATH; dotfiles_ensure_link '$SB/src_dir' '$SB/home/d' --unmount-legacy"
    assert_success
    assert_equal "$(cat "$SB/sudo.log")" "sudo umount $SB/home/d"
    assert_equal "$(readlink "$SB/home/d")" "$SB/src_dir"
}

@test "ensure_link: --unmount-legacy reports a failed umount" {
    mkdir -p "$SB/bin" "$SB/home/d"
    printf '#!/bin/sh\nexit 0\n' >"$SB/bin/findmnt"
    printf '#!/bin/sh\nexit 1\n' >"$SB/bin/sudo"
    chmod +x "$SB/bin/findmnt" "$SB/bin/sudo"
    _lib "PATH='$SB/bin':\$PATH; dotfiles_ensure_link '$SB/src_dir' '$SB/home/d' --unmount-legacy"
    assert_failure
    assert_output --partial "sudo umount"
}

@test "ensure_copy_once: copies only when the target is absent" {
    _lib "dotfiles_ensure_copy_once '$SB/src_file' '$SB/home/c/settings.json'"
    assert_success
    printf 'edited\n' >"$SB/home/c/settings.json"
    _lib "dotfiles_ensure_copy_once '$SB/src_file' '$SB/home/c/settings.json'"
    assert_success
    assert_equal "$(cat "$SB/home/c/settings.json")" "edited"
    [ ! -L "$SB/home/c/settings.json" ]
}

@test "ensure_dir: creates once, refuses a non-directory" {
    _lib "dotfiles_ensure_dir '$SB/home/a/b' && dotfiles_ensure_dir '$SB/home/a/b'"
    assert_success
    [ -d "$SB/home/a/b" ]
    _lib "dotfiles_ensure_dir '$SB/src_file'"
    assert_failure
}
