#!/usr/bin/env bats
# tests/bats/setup/internal_config_local.bats
# Issue #1968 — internal-mode configs prefer a gitignored *.internal.local
# sibling; scripts/internal-config-migrate.sh seeds those siblings.
# Runs against a fixture copy of the repo under a throwaway HOME, with fake
# values only: "real" stand-ins use *.corp-fake.test, placeholders use
# *.example.invalid (the shape the later swap will commit).

load '../test_helper'

setup() {
    setup_isolated_home
    FX="$TEST_TEMP_HOME/dotfiles"
    mkdir -p "$FX/scripts" "$FX/shell-common/tools/ux_lib" "$FX/shell-common/env" \
        "$FX/npm" "$FX/pip" "$FX/uv" "$FX/cargo" "$FX/bun"
    cp "$_BATS_REAL_DOTFILES_ROOT/scripts/internal-config-migrate.sh" "$FX/scripts/"
    cp "$_BATS_REAL_DOTFILES_ROOT/shell-common/tools/ux_lib/ux_lib.sh" "$FX/shell-common/tools/ux_lib/"
    cp "$_BATS_REAL_DOTFILES_ROOT/shell-common/setup.sh" "$FX/shell-common/"
    for f in npm/npmrc.internal pip/pip.conf.internal uv/uv.toml.internal \
        cargo/config.toml.internal bun/bunfig.toml.internal; do
        printf 'registry=https://registry.corp-fake.test/%s\nproxy=http://proxy.corp-fake.test:8080\n' "$f" >"$FX/$f"
    done
    printf 'registry=https://registry.example.invalid/npm-public\n' >"$FX/npm/npmrc.public"
    MIGRATE="$FX/scripts/internal-config-migrate.sh"
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

@test "migrate: dry-run (default) writes nothing" {
    run bash "$MIGRATE"
    assert_success
    assert_output --partial "Would copy: npm/npmrc.internal -> npm/npmrc.internal.local"
    [ -z "$(find "$FX" -name '*.internal.local')" ]
    run bash "$MIGRATE" --dry-run
    assert_success
    [ -z "$(find "$FX" -name '*.internal.local')" ]
}

@test "migrate: --apply copies byte-identical siblings without printing contents" {
    run bash "$MIGRATE" --apply
    assert_success
    assert_output --partial "Copied and verified: npm/npmrc.internal -> npm/npmrc.internal.local"
    refute_output --partial "corp-fake.test"
    cmp "$FX/npm/npmrc.internal" "$FX/npm/npmrc.internal.local"
    cmp "$FX/uv/uv.toml.internal" "$FX/uv/uv.toml.internal.local"
}

@test "migrate: never overwrites an existing sibling and is idempotent" {
    printf 'my-real-value\n' >"$FX/npm/npmrc.internal.local"
    run bash "$MIGRATE" --apply
    assert_success
    [ "$(cat "$FX/npm/npmrc.internal.local")" = "my-real-value" ]
    assert_output --partial "kept as-is"

    snapshot="$(cd "$FX" && find . -name '*.internal.local' -exec cksum {} + | sort)"
    run bash "$MIGRATE" --apply
    assert_success
    refute_output --partial "Copied"
    [ "$(cd "$FX" && find . -name '*.internal.local' -exec cksum {} + | sort)" = "$snapshot" ]
}

@test "migrate: rejects unknown options" {
    run bash "$MIGRATE" --bogus
    [ "$status" -eq 2 ]
    [ -z "$(find "$FX" -name '*.internal.local')" ]
}

@test "setup: falls back to the tracked *.internal file when no .local exists" {
    run_setup_fn "setup_npm_symlink internal; setup_pip_config internal; setup_uv_config internal"
    assert_success
    [ "$(readlink "$HOME/.npmrc")" = "$FX/npm/npmrc.internal" ]
    [ "$(readlink "$HOME/.config/pip/pip.conf")" = "$FX/pip/pip.conf.internal" ]
    [ "$(readlink "$HOME/.config/uv/uv.toml")" = "$FX/uv/uv.toml.internal" ]
    grep -q 'registry.corp-fake.test' "$HOME/.npmrc"
}

@test "setup: prefers *.internal.local after migration, links keep working" {
    run_setup_fn "setup_npm_symlink internal"
    assert_success
    run bash "$MIGRATE" --apply
    assert_success
    run_setup_fn "setup_npm_symlink internal; setup_pip_config internal; setup_uv_config internal; setup_cargo_config internal; setup_bun_config internal"
    assert_success
    [ "$(readlink "$HOME/.npmrc")" = "$FX/npm/npmrc.internal.local" ]
    [ "$(readlink "$HOME/.config/pip/pip.conf")" = "$FX/pip/pip.conf.internal.local" ]
    [ "$(readlink "$HOME/.config/uv/uv.toml")" = "$FX/uv/uv.toml.internal.local" ]
    [ "$(readlink "$HOME/.cargo/config.toml")" = "$FX/cargo/config.toml.internal.local" ]
    [ "$(readlink "$HOME/.bunfig.toml")" = "$FX/bun/bunfig.toml.internal.local" ]
    # Simulate the later placeholder swap of the tracked file: the deployed
    # link must still resolve to the untouched real-value sibling.
    printf 'registry=https://registry.example.invalid/\n' >"$FX/npm/npmrc.internal"
    grep -q 'registry.corp-fake.test/npm/npmrc.internal' "$HOME/.npmrc"
}

@test "setup: public mode is unaffected by a present .local sibling" {
    printf 'x\n' >"$FX/npm/npmrc.internal.local"
    run_setup_fn "setup_npm_symlink public"
    assert_success
    [ "$(readlink "$HOME/.npmrc")" = "$FX/npm/npmrc.public" ]
}

@test "migrate: skips a tracked file that already holds placeholders" {
    printf 'registry=https://registry.example.invalid/\n' >"$FX/pip/pip.conf.internal"
    run bash "$MIGRATE" --apply
    assert_success
    assert_output --partial "Skipped (tracked file holds placeholders): pip/pip.conf.internal"
    [ ! -e "$FX/pip/pip.conf.internal.local" ]
    [ -f "$FX/npm/npmrc.internal.local" ]
}
