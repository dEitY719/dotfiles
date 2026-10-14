#!/usr/bin/env bats
# tests/bats/tools/symlink_manager.bats
# symlinks.conf sources must resolve to the physical dotfiles root (pwd -P),
# and symlinks.conf is the only place ssh/obsidian/herdr links come from (#2139).
# The 4th-column options and the failure policy are covered below.
# symlinks.conf used to hardcode ${HOME}/dotfiles, so on a PC whose checkout is
# elsewhere (or reached through a symlink) links pointed at the wrong source.

load '../test_helper'

MANAGER="${DOTFILES_ROOT}/shell-common/tools/custom/symlink-manager.sh"

setup() {
    setup_isolated_home
    REAL_ROOT="$(cd "$DOTFILES_ROOT" && pwd -P)"
    # Reach the checkout through a symlink, as on a PC with ~/dotfiles -> repo.
    ln -s "$REAL_ROOT" "$HOME/dotlink"
}

teardown() {
    teardown_isolated_home
}

_ssh_link() { readlink "$HOME/.ssh/config"; }

@test "symlinks.conf: no hardcoded \${HOME}/dotfiles sources" {
    run grep -c '[$][{]HOME[}]/dotfiles' "${DOTFILES_ROOT}/shell-common/config/symlinks.conf"
    assert_output "0"
}

@test "ssh/obsidian/herdr links come from symlinks.conf, resolved to the physical source" {
    run env -u DOTFILES_TEST_MODE DOTFILES_ROOT="$HOME/dotlink" bash "$HOME/dotlink/shell-common/tools/custom/symlink-manager.sh" init
    assert_success
    [ "$(readlink -f "$HOME/.ssh/config")" = "$REAL_ROOT/ssh/config" ]
    [ "$(readlink -f "$HOME/.local/bin/obsidian")" = "$REAL_ROOT/obsidian/bin/obsidian" ]
    [ "$(readlink -f "$HOME/.config/herdr/config.toml")" = "$REAL_ROOT/herdr/config.toml" ]
    # ssh/setup.sh only sets permissions now (#2139) — the link stays as is.
    first="$(_ssh_link)"
    run bash "$HOME/dotlink/ssh/setup.sh"
    assert_success
    [ "$(_ssh_link)" = "$first" ]
    [ "$(stat -c %a "$HOME/.ssh")" = 700 ]
}

@test "ssh/obsidian/herdr setup.sh carry no link code (#2139)" {
    run grep -n 'ln -s\|dotfiles_ensure_link' "${DOTFILES_ROOT}/ssh/setup.sh" "${DOTFILES_ROOT}/obsidian/setup.sh"
    assert_failure
    # herdr keeps one dotfiles_ensure_link: the batcat -> bat bridge, not its config.
    run grep -c 'dotfiles_ensure_link' "${DOTFILES_ROOT}/herdr/setup.sh"
    assert_output "1"
    run grep -n 'ln -s' "${DOTFILES_ROOT}/herdr/setup.sh"
    assert_failure
}

@test "setup.sh runs the symlinks step as optional, after git and before herdr" {
    run grep -n '^    step_run ' "${DOTFILES_ROOT}/setup.sh"
    assert_success
    assert_output --partial "step_run symlinks optional ./shell-common/tools/custom/symlink-manager.sh init"
    git_line=$(grep -n 'step_run git ' "${DOTFILES_ROOT}/setup.sh" | cut -d: -f1)
    sym_line=$(grep -n 'step_run symlinks ' "${DOTFILES_ROOT}/setup.sh" | cut -d: -f1)
    herdr_line=$(grep -n 'step_run herdr ' "${DOTFILES_ROOT}/setup.sh" | cut -d: -f1)
    [ "$git_line" -lt "$sym_line" ]
    [ "$sym_line" -lt "$herdr_line" ]
}

# Private conf via SHELL_COMMON_ROOT so option tests do not depend on real rows.
_conf() {
    CONF_ROOT="$HOME/conf-root"
    mkdir -p "$CONF_ROOT/config" "$HOME/src"
    printf 'a\n' >"$HOME/src/a"
    printf 'b\n' >"$HOME/src/b"
    cat >"$CONF_ROOT/config/symlinks.conf"
}

_init() {
    run env -u DOTFILES_TEST_MODE -u DOTFILES_SETUP_MODE SHELL_COMMON_ROOT="$CONF_ROOT" "$@" bash "$MANAGER" init
}

@test "4th column: 3-field rows still parse; description is not mistaken for opts" {
    _conf <<'EOF'
${HOME}/la|${HOME}/src/a|three fields
${HOME}/lb|${HOME}/src/b|four fields|on-mismatch=replace
EOF
    _init
    assert_success
    assert_output --partial "three fields"
    assert_output --partial "four fields"
    [ "$(readlink "$HOME/la")" = "$HOME/src/a" ]
    [ "$(readlink "$HOME/lb")" = "$HOME/src/b" ]
}

@test "mode= filter: links only in the listed setup modes" {
    _conf <<'EOF'
${HOME}/la|${HOME}/src/a|ext only|mode=public,external
${HOME}/lb|${HOME}/src/b|int only|mode=internal
EOF
    _init DOTFILES_SETUP_MODE=external
    assert_success
    [ -L "$HOME/la" ]
    [ ! -e "$HOME/lb" ]
    rm -f "$HOME/la"
    run env -u DOTFILES_TEST_MODE -u DOTFILES_SETUP_MODE SHELL_COMMON_ROOT="$CONF_ROOT" bash "$MANAGER" init --mode internal
    assert_success
    [ ! -e "$HOME/la" ]
    [ -L "$HOME/lb" ]
}

@test "mode= filter: an unresolved mode skips mode-restricted rows" {
    _conf <<'EOF'
${HOME}/la|${HOME}/src/a|ext only|mode=external
EOF
    _init
    assert_success
    [ ! -e "$HOME/la" ]
    assert_output --partial "skipped"
}

@test "on-mismatch=keep leaves a real file alone; default backs it up" {
    _conf <<'EOF'
${HOME}/la|${HOME}/src/a|keep|on-mismatch=keep
${HOME}/lb|${HOME}/src/b|replace
EOF
    printf 'mine\n' >"$HOME/la"
    printf 'mine\n' >"$HOME/lb"
    _init
    assert_success
    [ ! -L "$HOME/la" ]
    grep -q mine "$HOME/la"
    [ -L "$HOME/lb" ]
    grep -q mine "$HOME/lb.original"
}

@test "a failing entry does not stop the rest; init exits non-zero" {
    _conf <<'EOF'
${HOME}/dir|${HOME}/src/a|refused dir
${HOME}/lb|${HOME}/src/b|after the failure
${HOME}/lc|${HOME}/src/a|bad opt|frobnicate
EOF
    mkdir -p "$HOME/dir/sub"
    _init
    assert_failure
    [ -d "$HOME/dir/sub" ]
    [ -L "$HOME/lb" ]
    [ ! -e "$HOME/lc" ]
    assert_output --partial "unknown option: frobnicate"
}

@test "allow-dir replaces a real directory (backed up)" {
    _conf <<'EOF'
${HOME}/dir|${HOME}/src/a|dir ok|allow-dir
EOF
    mkdir -p "$HOME/dir"
    _init
    assert_success
    [ -L "$HOME/dir" ]
    [ -d "$HOME/dir.original" ]
}

@test "a missing source outside the checkout is skipped, not a failure" {
    _conf <<'EOF'
${HOME}/la|${HOME}/nowhere/a|per-PC content
EOF
    _init
    assert_success
    [ ! -e "$HOME/la" ]
    assert_output --partial "source not on this PC"
}

@test "symlink-manager init twice: second run changes nothing" {
    run env -u DOTFILES_TEST_MODE bash "$MANAGER" init
    assert_success
    before="$(find "$HOME" -maxdepth 4 -type l -exec sh -c 'printf "%s -> %s\n" "$1" "$(readlink "$1")"' _ {} \; | sort)"
    run env -u DOTFILES_TEST_MODE bash "$MANAGER" init
    assert_success
    refute_output --partial "symlink: "
    after="$(find "$HOME" -maxdepth 4 -type l -exec sh -c 'printf "%s -> %s\n" "$1" "$(readlink "$1")"' _ {} \; | sort)"
    [ "$before" = "$after" ]
    [[ "$after" == *".tmux.conf -> $REAL_ROOT/tmux/tmux.conf"* ]]
}
