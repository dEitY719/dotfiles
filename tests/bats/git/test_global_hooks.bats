#!/usr/bin/env bats
# tests/bats/git/test_global_hooks.bats
#
# Issue #1664 — `git config --global core.hooksPath` REPLACES .git/hooks for
# every repository on the machine; git does not merge the two and does not
# fall back. git/setup.sh used to link only the pre-commit wrapper, which
# silently disabled pre-push (protected branches, `mise run test`, leak
# guard), commit-msg, prepare-commit-msg and post-commit on every PC that ran
# it.
#
# Covered here:
#   * GIT_GLOBAL_HOOKS (SSOT) and git/global-hooks/ agree
#   * a real git/setup.sh run links every wrapper, idempotently
#   * hook_check.sh reports the whole set and fails on a missing/broken one
#
# Delegation behaviour (does the wrapper forward to the project hook, and stay
# a no-op elsewhere) lives in git/tests/test_hooks.sh.

load '../test_helper'

setup() {
    setup_isolated_home

    REAL_ROOT="$_BATS_REAL_DOTFILES_ROOT"
    GLOBAL_HOOKS_SRC="${REAL_ROOT}/git/global-hooks"
    HOOK_CHECK="${REAL_ROOT}/shell-common/tools/custom/hook_check.sh"

    # SSOT for the expected hook set.
    # shellcheck source=../../../git/config/hook-config.sh
    source "${REAL_ROOT}/git/config/hook-config.sh"
}

teardown() {
    if [ -n "${SANDBOX:-}" ] && [ -d "$SANDBOX" ]; then
        rm -rf "$SANDBOX"
    fi
    teardown_isolated_home
}

# A throwaway dotfiles checkout so the real git/setup.sh can run without
# touching the developer's tree: only git/ and the ux library it sources are
# needed, and the SSH block is neutered (a key file already present, agent
# socket pointed at /dev/null) so it neither generates keys nor spawns an
# ssh-agent.
_stage_sandbox_dotfiles() {
    SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/global-hooks-setup.XXXXXX")"

    mkdir -p "$SANDBOX/repo/shell-common/tools"
    cp -R "${REAL_ROOT}/git" "$SANDBOX/repo/git"
    cp -R "${REAL_ROOT}/shell-common/tools/ux_lib" "$SANDBOX/repo/shell-common/tools/ux_lib"
    git -C "$SANDBOX/repo" init -q

    mkdir -p "$HOME/.ssh"
    : >"$HOME/.ssh/id_ed25519"
    export SSH_AUTH_SOCK=/dev/null
}

# Link every wrapper by hand (what setup.sh ends up doing) so hook_check.sh
# has a complete installation to diagnose.
_link_all_global_hooks() {
    HOOKS_TARGET="$HOME/.config/git/hooks"
    mkdir -p "$HOOKS_TARGET"

    local name
    for name in "${GIT_GLOBAL_HOOKS[@]}"; do
        ln -sf "${GLOBAL_HOOKS_SRC}/${name}" "${HOOKS_TARGET}/${name}"
    done

    git config --global core.hooksPath "$HOOKS_TARGET"
}

_run_hook_check() {
    # init.sh short-circuits under DOTFILES_TEST_MODE=1, which would leave the
    # script without DOTFILES_ROOT or the ux library.
    run env DOTFILES_TEST_MODE=0 bash "$HOOK_CHECK" </dev/null
}

# ---------------------------------------------------------------------------
# SSOT
# ---------------------------------------------------------------------------
@test "global hooks: SSOT covers every hook the dotfiles rely on" {
    local expected name
    for expected in pre-commit pre-push commit-msg prepare-commit-msg post-commit; do
        printf '%s\n' "${GIT_GLOBAL_HOOKS[@]}" | grep -qx "$expected" ||
            fail "GIT_GLOBAL_HOOKS is missing '$expected' — that hook would be dead code"
    done

    for name in "${GIT_GLOBAL_HOOKS[@]}"; do
        [ -f "${GLOBAL_HOOKS_SRC}/${name}" ] ||
            fail "No wrapper at git/global-hooks/${name}"
        [ -x "${GLOBAL_HOOKS_SRC}/${name}" ] ||
            fail "git/global-hooks/${name} is not executable"
    done
}

# ---------------------------------------------------------------------------
# setup.sh installation
# ---------------------------------------------------------------------------
@test "git/setup.sh links every global hook into ~/.config/git/hooks" {
    _stage_sandbox_dotfiles

    run bash "$SANDBOX/repo/git/setup.sh"
    assert_success

    local name target
    for name in "${GIT_GLOBAL_HOOKS[@]}"; do
        target="$HOME/.config/git/hooks/$name"
        [ -L "$target" ] || fail "Not a symlink (hook never linked): $target"
        [ -x "$target" ] || fail "Not executable: $target"
        assert_equal "$(readlink "$target")" "$SANDBOX/repo/git/global-hooks/$name"
    done

    run git config --global core.hooksPath
    assert_success
    assert_output "~/.config/git/hooks"
}

@test "git/setup.sh global hook linking is idempotent" {
    _stage_sandbox_dotfiles

    run bash "$SANDBOX/repo/git/setup.sh"
    assert_success
    run bash "$SANDBOX/repo/git/setup.sh"
    assert_success

    local name target
    for name in "${GIT_GLOBAL_HOOKS[@]}"; do
        target="$HOME/.config/git/hooks/$name"
        [ -L "$target" ] || fail "Not a symlink after re-run: $target"
        assert_equal "$(readlink "$target")" "$SANDBOX/repo/git/global-hooks/$name"
    done

    # A second run must not leave *.original backups behind — that would mean
    # create_symlink saw a real file where a symlink belongs.
    run bash -c "ls '$HOME/.config/git/hooks' | grep -c original || true"
    assert_output "0"
}

# ---------------------------------------------------------------------------
# hook_check.sh diagnostic
# ---------------------------------------------------------------------------
@test "hook_check.sh reports every global hook, not just pre-commit" {
    _link_all_global_hooks

    _run_hook_check
    assert_success

    local name
    for name in "${GIT_GLOBAL_HOOKS[@]}"; do
        assert_output --partial "hooks/${name}"
    done
    assert_output --partial "All hook configurations are valid"
}

@test "hook_check.sh fails when a global hook is missing" {
    _link_all_global_hooks
    rm -f "$HOME/.config/git/hooks/pre-push"

    _run_hook_check
    assert_failure
    assert_output --partial "Missing"
    assert_output --partial "pre-push"
}

@test "hook_check.sh flags a broken global hook symlink" {
    _link_all_global_hooks
    ln -sfn "${SANDBOX:-/nonexistent}/gone/commit-msg" "$HOME/.config/git/hooks/commit-msg"

    _run_hook_check
    assert_failure
    assert_output --partial "Broken symlink"
    assert_output --partial "commit-msg"
}

@test "hook_check.sh fails when a global hook is not executable" {
    _link_all_global_hooks

    # Replace the symlink with a non-executable real file.
    rm -f "$HOME/.config/git/hooks/post-commit"
    printf '#!/usr/bin/env bash\nexit 0\n' >"$HOME/.config/git/hooks/post-commit"
    chmod 644 "$HOME/.config/git/hooks/post-commit"

    _run_hook_check
    assert_failure
    assert_output --partial "Not executable"
    assert_output --partial "post-commit"
}
