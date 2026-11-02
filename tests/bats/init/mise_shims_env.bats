#!/usr/bin/env bats
# tests/bats/init/mise_shims_env.bats
# Issue #2342 — shell-common/env/mise.sh puts the mise shims dir on PATH so
# mise-installed tools resolve in bash and zsh without `mise activate`.

load '../test_helper'

MISE_ENV="${SHELL_COMMON}/env/mise.sh"

setup() {
    setup_isolated_home
    unset MISE_DATA_DIR XDG_DATA_HOME
}

teardown() {
    teardown_isolated_home
}

_make_shims() {
    local dir="$1" tool
    mkdir -p "$dir"
    for tool in sops age uv; do
        printf '#!/bin/sh\nexit 0\n' >"$dir/$tool"
        chmod +x "$dir/$tool"
    done
}

# Count how many PATH entries equal $1 in the PATH given on $2.
_path_count() {
    printf '%s\n' "$2" | tr ':' '\n' | grep -cxF "$1"
}

_source_with_path() {
    run env PATH="/usr/bin:/bin" DOTFILES_FORCE_INIT=1 \
        bash --noprofile --norc -c ". '$MISE_ENV'; printf '%s' \"\$PATH\""
}

@test "mise.sh: adds the default shims dir when it exists" {
    _make_shims "$HOME/.local/share/mise/shims"
    _source_with_path
    assert_success
    assert_output "$HOME/.local/share/mise/shims:/usr/bin:/bin"
}

@test "mise.sh: XDG_DATA_HOME relocates the shims dir" {
    _make_shims "$HOME/xdg/mise/shims"
    export XDG_DATA_HOME="$HOME/xdg"
    _source_with_path
    assert_success
    assert_output "$HOME/xdg/mise/shims:/usr/bin:/bin"
}

@test "mise.sh: MISE_DATA_DIR wins over XDG_DATA_HOME" {
    _make_shims "$HOME/custom/shims"
    _make_shims "$HOME/xdg/mise/shims"
    export MISE_DATA_DIR="$HOME/custom" XDG_DATA_HOME="$HOME/xdg"
    _source_with_path
    assert_success
    assert_output "$HOME/custom/shims:/usr/bin:/bin"
}

@test "mise.sh: no shims dir leaves PATH alone and prints nothing" {
    _source_with_path
    assert_success
    assert_output "/usr/bin:/bin"
}

@test "mise.sh: sourcing twice adds the dir once" {
    shims="$HOME/.local/share/mise/shims"
    _make_shims "$shims"
    run env PATH="/usr/bin:/bin" DOTFILES_FORCE_INIT=1 \
        bash --noprofile --norc -c ". '$MISE_ENV'; . '$MISE_ENV'; printf '%s' \"\$PATH\""
    assert_success
    assert_output "$shims:/usr/bin:/bin"
}

@test "mise.sh: keeps a shims dir that is already on PATH where it is" {
    shims="$HOME/.local/share/mise/shims"
    _make_shims "$shims"
    run env PATH="/usr/bin:$shims:/bin" DOTFILES_FORCE_INIT=1 \
        bash --noprofile --norc -c ". '$MISE_ENV'; printf '%s' \"\$PATH\""
    assert_success
    assert_output "/usr/bin:$shims:/bin"
}

@test "mise.sh: leaves no helper variable behind" {
    _make_shims "$HOME/.local/share/mise/shims"
    run env DOTFILES_FORCE_INIT=1 bash --noprofile --norc -c \
        "before=\$(set | cut -d= -f1 | grep -v '^_\$\\|^before\$\\|^BASH_\\|^PIPESTATUS\$' | sort)
         . '$MISE_ENV'
         after=\$(set | cut -d= -f1 | grep -v '^_\$\\|^before\$\\|^BASH_\\|^PIPESTATUS\$' | sort)
         [ \"\$before\" = \"\$after\" ]"
    assert_success
}

@test "mise.sh: non-interactive shell without DOTFILES_FORCE_INIT is a no-op" {
    _make_shims "$HOME/.local/share/mise/shims"
    run env -u DOTFILES_FORCE_INIT PATH="/usr/bin:/bin" \
        bash --noprofile --norc -c ". '$MISE_ENV'; printf '%s' \"\$PATH\""
    assert_success
    assert_output "/usr/bin:/bin"
}

@test "mise.sh: parses and runs under POSIX sh" {
    _make_shims "$HOME/.local/share/mise/shims"
    run env PATH="/usr/bin:/bin" DOTFILES_FORCE_INIT=1 \
        sh -c ". '$MISE_ENV'; printf '%s' \"\$PATH\""
    assert_success
    assert_output "$HOME/.local/share/mise/shims:/usr/bin:/bin"
}

@test "bash: the full loader resolves sops, age and uv from the shims dir" {
    shims="$HOME/.local/share/mise/shims"
    _make_shims "$shims"
    run_in_bash 'command -v sops age uv'
    assert_success
    assert_output --partial "$shims/sops"
    assert_output --partial "$shims/age"
    assert_output --partial "$shims/uv"
}

@test "zsh: the full loader resolves sops, age and uv from the shims dir" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
    shims="$HOME/.local/share/mise/shims"
    _make_shims "$shims"
    run_in_zsh 'command -v sops age uv'
    assert_success
    assert_output --partial "$shims/sops"
    assert_output --partial "$shims/age"
    assert_output --partial "$shims/uv"
}

@test "bash: a nested shell keeps a single shims entry after clean_paths" {
    shims="$HOME/.local/share/mise/shims"
    _make_shims "$shims"
    run_in_bash 'printf "PATH=%s\n" "$PATH"'
    assert_success
    first=$(printf '%s\n' "$output" | sed -n 's/^PATH=//p')
    PATH="$first" run_in_bash 'printf "PATH=%s\n" "$PATH"'
    assert_success
    nested=$(printf '%s\n' "$output" | sed -n 's/^PATH=//p')
    [ "$(_path_count "$shims" "$nested")" -eq 1 ]
}

@test "secret_run.sh: a script sourcing it finds sops in the shims dir" {
    # hermes/mcporter setup and secret-run are non-interactive children: they
    # skip the env/ loader, so a PATH without shims must not cost them sops.
    shims="$HOME/.local/share/mise/shims"
    _make_shims "$shims"
    printf 'data\n' >"$HOME/enc"
    run env PATH="/usr/bin:/bin" DOTFILES_FORCE_INIT=1 DOTFILES_ENC_ENV="$HOME/enc" \
        bash --noprofile --norc -c "
            . '${SHELL_COMMON}/tools/ux_lib/ux_lib.sh'
            . '${SHELL_COMMON}/functions/secret_run.sh'
            _dotfiles_secret_decrypt
        " 2>&1
    refute_output --partial "sops not installed"
}

@test "secret_run.sh: hermes-style prefix DOTFILES_FORCE_INIT=1 source still loads the shims" {
    # hermes/setup.sh and the custom tools use `DOTFILES_FORCE_INIT=1 source`
    # (not exported): env/mise.sh's own guard must still pass inside it.
    shims="$HOME/.local/share/mise/shims"
    _make_shims "$shims"
    run env -u DOTFILES_FORCE_INIT PATH="/usr/bin:/bin" \
        bash --noprofile --norc -c "
            DOTFILES_FORCE_INIT=1 source '${SHELL_COMMON}/functions/secret_run.sh'
            command -v sops
        "
    assert_success
    assert_output "$shims/sops"
}
