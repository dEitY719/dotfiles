#!/usr/bin/env bats
# tests/bats/tools/install_helpers.bats
# lib/install_helpers.sh: download-then-run remote installers and verify the
# installed binary actually runs (issue #1801).
#
# Background: `curl | sh` and `sh -c "$(curl ...)"` report success when the
# download fails (the shell reads empty input and exits 0), and the old
# post-install checks only warned when `--version` failed. Installers then
# printed "Setup Complete" for a tool that was never installed.

load '../test_helper'

TOOLS_DIR="${DOTFILES_ROOT}/shell-common/tools/custom"
HELPERS="${TOOLS_DIR}/lib/install_helpers.sh"

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# Run BODY in bash with the helpers sourced. TMPDIR is pinned inside the
# isolated HOME so the temp-file cleanup can be asserted.
run_helpers() {
    mkdir -p "$HOME/tmp"
    run bash -c "
        export HOME='${HOME}' TMPDIR='${HOME}/tmp'
        . '${HELPERS}' || exit 99
        $1
    "
}

# curl double: writes INSTALLER_BODY to the -o target.
CURL_OK='
    curl() {
        out=""
        while [ $# -gt 0 ]; do
            [ "$1" = "-o" ] && out="$2"
            shift
        done
        printf "%s\n" "$INSTALLER_BODY" > "$out"
    }
'

# --- run_remote_installer ------------------------------------------------------

@test "run_remote_installer: download failure fails without running an installer" {
    run_helpers '
        curl() { return 22; }
        bash() { echo installer-ran; }
        run_remote_installer https://example.invalid/install.sh
    '
    assert_failure
    refute_output --partial "installer-ran"
}

@test "run_remote_installer: passes installer args through" {
    run_helpers "
        $CURL_OK
        INSTALLER_BODY='printf \"args:%s\\n\" \"\$*\"'
        run_remote_installer https://example.invalid/install.sh --keep-zshrc
    "
    assert_success
    assert_output "args:--keep-zshrc"
}

@test "run_remote_installer: env prefix is inherited by the installer" {
    run_helpers "
        $CURL_OK
        INSTALLER_BODY='printf \"env:%s\\n\" \"\${UV_NO_MODIFY_PATH-unset}\"'
        UV_NO_MODIFY_PATH=1 run_remote_installer https://example.invalid/install.sh
    "
    assert_success
    assert_output "env:1"
}

@test "run_remote_installer: propagates installer exit code and removes the temp file" {
    run_helpers "
        $CURL_OK
        INSTALLER_BODY='exit 3'
        rc=0
        run_remote_installer https://example.invalid/install.sh || rc=\$?
        echo \"rc=\$rc\"
        ls -A \"\$TMPDIR\" | wc -l
    "
    assert_success
    assert_output "rc=3
0"
}

# --- verify_installed_binary ---------------------------------------------------

@test "verify_installed_binary: rejects an empty path and a missing binary" {
    run_helpers "verify_installed_binary ''"
    assert_failure
    run_helpers "verify_installed_binary '$HOME/nope/tool'"
    assert_failure
}

@test "verify_installed_binary: rejects a non-executable file" {
    local bin="$HOME/noexec/tool"
    mkdir -p "$(dirname "$bin")"
    printf '%s\n' '#!/bin/sh' 'echo 1.0' > "$bin"

    run_helpers "verify_installed_binary '$bin'"
    assert_failure
}

@test "verify_installed_binary: rejects a placeholder that exits 1" {
    local bin="$HOME/placeholder/tool"
    mkdir -p "$(dirname "$bin")"
    printf '%s\n' '#!/bin/sh' 'echo "postinstall not run" >&2' 'exit 1' > "$bin"
    chmod +x "$bin"

    run_helpers "verify_installed_binary '$bin'"
    assert_failure
}

@test "verify_installed_binary: runs --version by default and prints it" {
    local bin="$HOME/good/tool"
    mkdir -p "$(dirname "$bin")"
    printf '%s\n' '#!/bin/sh' 'echo "tool $*"' > "$bin"
    chmod +x "$bin"

    run_helpers "verify_installed_binary '$bin'"
    assert_success
    assert_output "tool --version"
}

@test "verify_installed_binary: custom args replace --version" {
    local bin="$HOME/good/tool"
    mkdir -p "$(dirname "$bin")"
    printf '%s\n' '#!/bin/sh' 'echo "tool $*"' > "$bin"
    chmod +x "$bin"

    run_helpers "verify_installed_binary '$bin' version --short"
    assert_success
    assert_output "tool version --short"
}

# --- pkg_install (#2145) --------------------------------------------------------

# Stub PATH: only the managers named in $1 exist; each logs "<cmd> <args>" to
# $CALL_LOG. sudo logs then runs its args; id reports UID $2 (default 1000).
make_pkg_stubs() {
    STUB_DIR="$HOME/stub-bin"
    CALL_LOG="$HOME/calls.log"
    mkdir -p "$STUB_DIR"
    : >"$CALL_LOG"
    local tool
    for tool in $1; do
        printf '#!/bin/sh\necho "%s $*" >>"%s"\n' "$tool" "$CALL_LOG" >"$STUB_DIR/$tool"
    done
    printf '#!/bin/sh\necho "sudo" >>"%s"\nexec "$@"\n' "$CALL_LOG" >"$STUB_DIR/sudo"
    printf '#!/bin/sh\necho %s\n' "${2:-1000}" >"$STUB_DIR/id"
    chmod +x "$STUB_DIR"/*
}

run_pkg_install() {
    run_helpers "
        ux_info() { :; }
        ux_error() { echo \"ERR: \$*\"; }
        PATH='$STUB_DIR'
        rc=0
        pkg_install $1 || rc=\$?
        echo \"rc=\$rc mgr=\$PKG_INSTALL_MANAGER\"
    "
}

@test "pkg_install: apt-get updates then installs its package under sudo" {
    make_pkg_stubs "apt-get yum brew"
    run_pkg_install "apt=fd-find yum=fd-find brew=fd"
    assert_success
    assert_output "rc=0 mgr=apt"
    run cat "$CALL_LOG"
    assert_output "sudo
apt-get update -qq
sudo
apt-get install -y fd-find"
}

@test "pkg_install: first manager on PATH wins in apt, yum, dnf, pacman, brew order" {
    make_pkg_stubs "pacman yum"
    run_pkg_install "apt=x pacman=p-pkg yum=y-pkg"
    assert_output "rc=0 mgr=yum"
    run cat "$CALL_LOG"
    assert_output "sudo
yum install -y y-pkg"
}

@test "pkg_install: a manager without a spec is skipped" {
    make_pkg_stubs "yum pacman"
    run_pkg_install "apt=z pacman=z-pkg"
    assert_output "rc=0 mgr=pacman"
    run cat "$CALL_LOG"
    assert_output "sudo
pacman -S --noconfirm z-pkg"
}

@test "pkg_install: root runs without sudo, brew never uses sudo" {
    make_pkg_stubs "dnf" 0
    run_pkg_install "dnf=rg"
    assert_output "rc=0 mgr=dnf"
    run cat "$CALL_LOG"
    assert_output "dnf install -y rg"

    make_pkg_stubs "brew"
    run_pkg_install "brew=fd"
    assert_output "rc=0 mgr=brew"
    run cat "$CALL_LOG"
    assert_output "brew install fd"
}

@test "pkg_install: no usable manager errors and returns 2 without installing" {
    make_pkg_stubs "yum"
    run_pkg_install "apt=a brew=b"
    assert_output --partial "ERR: No supported package manager found (need one of: apt brew)"
    assert_output --partial "rc=2 mgr="
    run cat "$CALL_LOG"
    assert_output ""
}

@test "pkg_install: propagates the install command's failure" {
    make_pkg_stubs "pacman"
    printf '#!/bin/sh\nexit 7\n' >"$STUB_DIR/pacman"
    run_pkg_install "pacman=p"
    assert_output "rc=7 mgr=pacman"
}

# zsh_autosuggestions is left out: its "install zsh first" hint names apt-get/brew.
@test "simple install_* scripts call no package manager directly (#2145)" {
    run grep -nE 'OSTYPE|apt-get|(yum|dnf|brew) install|pacman -S' \
        "$TOOLS_DIR"/install_{fd,ripgrep,bat,fzf,fasd,pet}.sh
    assert_output ""
}

# --- callers' fallback contract (#2145 review) ---------------------------------

# Source an install script without running it ($0 is not the script name) and
# replace pkg_install / the fallbacks with doubles.
run_installer_fn() {
    run bash -c "
        cd '$TOOLS_DIR' || exit 99
        export DOTFILES_TEST_MODE=1 HOME='$HOME'
        set -e
        . ./$1 >/dev/null || exit 98
        $2
    "
}

@test "zsh_autosuggestions: git fallback only when no manager (rc 2), real failure aborts" {
    run_installer_fn install_zsh_autosuggestions.sh '
        pkg_install() { return 2; }
        _install_git_method() { echo git-method; }
        _install_zsh_autosuggestions'
    assert_success
    assert_output --partial "git-method"

    run_installer_fn install_zsh_autosuggestions.sh '
        pkg_install() { return 100; }
        _install_git_method() { echo git-method; }
        _install_zsh_autosuggestions'
    assert_failure 100
    refute_output --partial "git-method"
}

@test "pet: any package-manager failure falls back to the GitHub release" {
    run_installer_fn install_pet.sh '
        pkg_install() { return 100; }
        _install_pet_from_github() { echo "github $1"; }
        _install_pet'
    assert_success
    assert_output --partial "github linux"
}

# --- static regression guard ---------------------------------------------------

@test "no install*.sh pipes curl into a shell or runs sh -c \"\$(curl ...)\"" {
    local pattern='curl[^#]*\|[[:space:]]*(ba)?sh\b|sh -c "\$\(curl'
    run bash -c 'grep -nE "$1" "$2"/install*.sh | grep -vE "^[^:]+:[0-9]+:[[:space:]]*#"' \
        _ "$pattern" "$TOOLS_DIR"
    assert_output ""
}
