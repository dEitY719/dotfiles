#!/usr/bin/env bats
# tests/bats/setup/herdr_setup.bats
# Coverage for herdr/setup.sh — the config symlink is hard-fail, the plugin
# and external-tool bootstraps (Parts 2-3) are soft-fail and must never abort
# the parent `./setup.sh` (which runs under `set -e`).
#
# `gh` and `herdr` are stubbed on PATH so these tests never touch the
# network. The one exception (@test "external tools: failed install is
# reported as failed, not installed") is a direct regression guard for a
# review finding (PR #1372): `install -m 0755`'s exit status went unchecked,
# so a failed install was silently counted as a success.

load '../test_helper'

HERDR_SETUP="${_BATS_REAL_DOTFILES_ROOT}/herdr/setup.sh"

setup() {
    setup_isolated_home
    STUB_BIN="$(mktemp -d)"
    # A tight, real-machine-independent PATH: /usr/bin + /bin cover tar, find,
    # install, mktemp, awk. The dev machine's own ~/.local/bin is deliberately
    # excluded — this repo's earlier herdr work installed real herdr/lazygit/
    # glow/delta/bat there, and an inherited PATH would let those satisfy
    # `command -v` instead of the stubs, silently defeating every test below.
    export PATH="${STUB_BIN}:/usr/bin:/bin"
}

teardown() {
    teardown_isolated_home
    rm -rf "$STUB_BIN"
}

# A `herdr` stub that reports every plugin already installed and accepts
# `server reload-config` — exercises the "nothing to do" plugin path and the
# Part 4 best-effort reload without a real server.
stub_herdr_all_present() {
    cat > "${STUB_BIN}/herdr" <<'EOF'
#!/bin/sh
case "$1 $2" in
    "plugin list")
        echo "3 plugins installed:"
        echo "- herdr-file-viewer (herdr-file-viewer) enabled [github:x@y]"
        echo "- persiyanov.reviewr (reviewr) enabled [github:x@y]"
        echo "- ray.plugin-manager (Plugin Manager) enabled [github:x@y]"
        exit 0
        ;;
    "server reload-config") exit 0 ;;
esac
exit 0
EOF
    chmod +x "${STUB_BIN}/herdr"
}

@test "config symlink: missing source hard-fails with exit 1" {
    # setup.sh resolves both its config.toml AND DOTFILES_ROOT/SHELL_COMMON
    # relative to its own directory ($_SCRIPT_DIR, stripped of a trailing
    # "/herdr"). Mirror that layout — herdr/setup.sh with no sibling
    # config.toml, shell-common symlinked to the real one — so sourcing
    # ux_lib still works and only the "missing source" branch is exercised.
    iso="${TEST_TEMP_HOME}/herdr-src"
    mkdir -p "$iso/herdr"
    cp "${HERDR_SETUP}" "$iso/herdr/setup.sh"
    ln -s "${_BATS_REAL_DOTFILES_ROOT}/shell-common" "$iso/shell-common"
    run bash "$iso/herdr/setup.sh"
    assert_failure
    assert_output --partial "Source config not found"
}

@test "config symlink: fresh HOME creates the symlink to the real source" {
    stub_herdr_all_present
    run env HERDR_SKIP_TOOLS=1 bash "${HERDR_SETUP}"
    assert_success
    [ -L "${HOME}/.config/herdr/config.toml" ]
    real_src="${_BATS_REAL_DOTFILES_ROOT}/herdr/config.toml"
    [ "$(readlink "${HOME}/.config/herdr/config.toml")" = "$real_src" ]
}

@test "config symlink: idempotent re-run reports already correct" {
    stub_herdr_all_present
    run env HERDR_SKIP_TOOLS=1 bash "${HERDR_SETUP}"
    assert_success
    run env HERDR_SKIP_TOOLS=1 bash "${HERDR_SETUP}"
    assert_success
    assert_output --partial "Symlink already correct"
}

@test "config symlink: pre-existing plain file is backed up with fixed .backup suffix" {
    stub_herdr_all_present
    mkdir -p "${HOME}/.config/herdr"
    printf 'old = true\n' > "${HOME}/.config/herdr/config.toml"
    run env HERDR_SKIP_TOOLS=1 bash "${HERDR_SETUP}"
    assert_success
    [ -L "${HOME}/.config/herdr/config.toml" ]
    [ -f "${HOME}/.config/herdr/config.toml.backup" ]
    grep -q 'old = true' "${HOME}/.config/herdr/config.toml.backup"
}

@test "plugin bootstrap: HERDR_SKIP_PLUGINS=1 skips without touching herdr" {
    # No herdr stub at all — if the skip check didn't run first, `command -v
    # herdr` would fail, which is a different (also-skip) message. Assert the
    # SKIP_PLUGINS-specific message to pin the actual branch taken.
    run env HERDR_SKIP_PLUGINS=1 HERDR_SKIP_TOOLS=1 bash "${HERDR_SETUP}"
    assert_success
    assert_output --partial "Plugin bootstrap skipped (HERDR_SKIP_PLUGINS=1)"
}

@test "plugin bootstrap: herdr not on PATH degrades gracefully, does not abort" {
    # Regression guard: a reviewer (agy, PR #1372) misread this branch as an
    # abort. It must return 0 and let Part 3 still run.
    run env HERDR_SKIP_TOOLS=1 bash "${HERDR_SETUP}"
    assert_success
    assert_output --partial "herdr not on PATH — plugin bootstrap skipped"
}

@test "external tools: HERDR_SKIP_TOOLS=1 skips without checking gh" {
    stub_herdr_all_present
    run env HERDR_SKIP_TOOLS=1 bash "${HERDR_SETUP}"
    assert_success
    assert_output --partial "External tool bootstrap skipped (HERDR_SKIP_TOOLS=1)"
}

@test "external tools: unauthenticated gh warns and returns cleanly (exit 0)" {
    stub_herdr_all_present
    cat > "${STUB_BIN}/gh" <<'EOF'
#!/bin/sh
[ "$1 $2" = "auth status" ] && exit 1
exit 0
EOF
    chmod +x "${STUB_BIN}/gh"
    run bash "${HERDR_SETUP}"
    assert_success
    assert_output --partial "gh is not authenticated"
    assert_output --partial "gh auth login"
}

@test "external tools: failed install is reported as failed, not installed" {
    # Regression guard (PR #1372 agy finding): _herdr_install_one_tool used to
    # `return 0` unconditionally after `install -m 0755`, so a failed install
    # (permissions, disk full, ...) was silently counted as a success.
    stub_herdr_all_present
    cat > "${STUB_BIN}/gh" <<'EOF'
#!/bin/sh
if [ "$1" = "auth" ]; then exit 0; fi
if [ "$1" = "release" ] && [ "$2" = "download" ]; then
    # Find --dir's argument and drop a minimal real tarball there so setup.sh's
    # tar/find steps succeed — only the final `install` step is made to fail.
    dir=""
    prev=""
    for arg in "$@"; do
        [ "$prev" = "--dir" ] && dir="$arg"
        prev="$arg"
    done
    work="$(mktemp -d)"
    printf '#!/bin/sh\necho fake\n' > "$work/lazygit"
    chmod +x "$work/lazygit"
    tar czf "${dir}/asset.tar.gz" -C "$work" lazygit
    rm -rf "$work"
    exit 0
fi
exit 0
EOF
    chmod +x "${STUB_BIN}/gh"
    # A read-only ~/.local/bin makes `install -m 0755` fail without touching
    # any real system path.
    mkdir -p "${HOME}/.local/bin"
    chmod 555 "${HOME}/.local/bin"
    run env HERDR_SKIP_PLUGINS=1 bash "${HERDR_SETUP}"
    chmod 755 "${HOME}/.local/bin"
    assert_success
    assert_output --partial "failed: lazygit"
    refute_output --partial "installed: ~/.local/bin/lazygit"
}
