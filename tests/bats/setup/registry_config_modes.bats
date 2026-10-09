#!/usr/bin/env bats
# tests/bats/setup/registry_config_modes.bats
# Characterization of the mode-switched package-registry config setup in
# shell-common/setup.sh (npm / bun / uv / pip / cargo / nuget) across all
# three modes (internal / external / public). Pins behavior before the
# table-driven refactor so it stays identical. Fake values only.

load '../test_helper'

setup() {
    setup_isolated_home
    FX="$TEST_TEMP_HOME/dotfiles"
    mkdir -p "$FX/shell-common/tools/ux_lib" "$FX/shell-common/env" \
        "$FX/npm" "$FX/bun" "$FX/uv" "$FX/pip" "$FX/cargo" "$FX/nuget"
    cp "$_BATS_REAL_DOTFILES_ROOT/shell-common/tools/ux_lib/ux_lib.sh" "$FX/shell-common/tools/ux_lib/"
    cp "$_BATS_REAL_DOTFILES_ROOT/shell-common/setup.sh" "$FX/shell-common/"
    for f in npm/npmrc.internal npm/npmrc.external npm/npmrc.public \
        bun/bunfig.toml.internal bun/bunfig.toml.external uv/uv.toml.internal \
        pip/pip.conf.internal pip/pip.conf.external cargo/config.toml.internal \
        nuget/NuGet.Config.internal; do
        printf 'registry=https://registry.corp-fake.test/%s\n' "$f" >"$FX/$f"
    done
    NUGET1="$HOME/.nuget/NuGet/NuGet.Config"
    NUGET2="$HOME/.config/NuGet/NuGet.Config"
}

teardown() {
    teardown_isolated_home
}

run_setup_fn() {
    run bash --noprofile --norc -c "
        set -e
        cd '$FX/shell-common'
        . './setup.sh'
        $*
    "
}

# --- nuget ------------------------------------------------------------------

@test "nuget internal: links both NuGet.Config paths to the tracked file" {
    run_setup_fn "setup_nuget_config internal"
    assert_success
    assert_output --partial "Created symlinks: NuGet.Config → nuget/NuGet.Config.internal"
    assert_output --partial "Using: internal Nexus proxy for NuGet"
    [ "$(readlink "$NUGET1")" = "$FX/nuget/NuGet.Config.internal" ]
    [ "$(readlink "$NUGET2")" = "$FX/nuget/NuGet.Config.internal" ]
}

@test "nuget internal: prefers NuGet.Config.internal.local when present" {
    printf 'real\n' >"$FX/nuget/NuGet.Config.internal.local"
    run_setup_fn "setup_nuget_config internal"
    assert_success
    [ "$(readlink "$NUGET1")" = "$FX/nuget/NuGet.Config.internal.local" ]
    [ "$(readlink "$NUGET2")" = "$FX/nuget/NuGet.Config.internal.local" ]
}

@test "nuget internal: backs up a user file and is idempotent on rerun" {
    mkdir -p "$(dirname "$NUGET1")"
    printf 'user\n' >"$NUGET1"
    run_setup_fn "setup_nuget_config internal"
    assert_success
    [ "$(cat "$NUGET1.backup")" = "user" ]
    snapshot="$(cd "$HOME" && find . -printf '%y %p %l\n' | sort)"
    run_setup_fn "setup_nuget_config internal"
    assert_success
    [ "$(cd "$HOME" && find . -printf '%y %p %l\n' | sort)" = "$snapshot" ]
}

@test "nuget external/public: restore user backup, create no dirs when absent" {
    for mode in external public; do
        run_setup_fn "setup_nuget_config $mode"
        assert_success
        assert_output --partial "NuGet config restored to defaults"
        [ ! -e "$HOME/.nuget" ]
        [ ! -e "$HOME/.config/NuGet" ]
    done
    mkdir -p "$(dirname "$NUGET1")"
    printf 'user\n' >"$NUGET1"
    run_setup_fn "setup_nuget_config internal; setup_nuget_config external"
    assert_success
    [ ! -L "$NUGET1" ]
    [ "$(cat "$NUGET1")" = "user" ]
    [ ! -e "$NUGET2" ]
}

# --- single-target configs: external / public modes -------------------------

@test "npm: external and public link their tracked files" {
    run_setup_fn "setup_npm_symlink external"
    assert_success
    [ "$(readlink "$HOME/.npmrc")" = "$FX/npm/npmrc.external" ]
    run_setup_fn "setup_npm_symlink public"
    assert_success
    assert_output --partial "Created symlink: ~/.npmrc → npm/npmrc.public"
    [ "$(readlink "$HOME/.npmrc")" = "$FX/npm/npmrc.public" ]
}

@test "bun: external links, public restores the backup" {
    printf 'user\n' >"$HOME/.bunfig.toml"
    run_setup_fn "setup_bun_config external"
    assert_success
    [ "$(readlink "$HOME/.bunfig.toml")" = "$FX/bun/bunfig.toml.external" ]
    run_setup_fn "setup_bun_config public"
    assert_success
    [ "$(cat "$HOME/.bunfig.toml")" = "user" ]
}

@test "uv: external/public remove a stale link and write nothing" {
    run_setup_fn "setup_uv_config internal; setup_uv_config external"
    assert_success
    assert_output --partial "No uv.toml needed (using default public PyPI)"
    [ ! -e "$HOME/.config/uv/uv.toml" ]
    [ -d "$HOME/.config/uv" ]
}

@test "pip: external and public both link pip.conf.external" {
    for mode in external public; do
        run_setup_fn "setup_pip_config $mode"
        assert_success
        assert_output --partial "Created symlink: ~/.config/pip/pip.conf → pip/pip.conf.external"
        [ "$(readlink "$HOME/.config/pip/pip.conf")" = "$FX/pip/pip.conf.external" ]
    done
}

@test "cargo: internal then public restores the user config" {
    mkdir -p "$HOME/.cargo"
    printf 'user\n' >"$HOME/.cargo/config.toml"
    run_setup_fn "setup_cargo_config internal"
    assert_success
    assert_output --partial "Created symlink: ~/.cargo/config.toml → cargo/config.toml.internal"
    run_setup_fn "setup_cargo_config public"
    assert_success
    [ ! -L "$HOME/.cargo/config.toml" ]
    [ "$(cat "$HOME/.cargo/config.toml")" = "user" ]
}
