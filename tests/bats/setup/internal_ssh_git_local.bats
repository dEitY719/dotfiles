#!/usr/bin/env bats
# tests/bats/setup/internal_ssh_git_local.bats
# Issue #2006 — ssh/config and git/.gitconfig no longer carry internal hosts;
# they Include / [include] ~/.ssh/config.internal.local and
# ~/.gitconfig.internal.local, which scripts/internal-ssh-git-migrate.sh
# seeds from the pre-swap version in git history. Fake values only:
# "real" stand-ins use *.corp-fake.test and 203.0.113.x (RFC 5737).

load '../test_helper'

setup() {
    setup_isolated_home
    export GIT_CONFIG_GLOBAL="$HOME/.gitconfig" GIT_CONFIG_SYSTEM=/dev/null
    FX="$TEST_TEMP_HOME/dotfiles"
    R="$_BATS_REAL_DOTFILES_ROOT"
    mkdir -p "$FX/scripts" "$FX/shell-common/tools" "$FX/shell-common/functions" \
        "$FX/shell-common/env" "$FX/ssh" "$FX/git"
    cp "$R/scripts/internal-ssh-git-migrate.sh" "$FX/scripts/"
    cp -R "$R/shell-common/tools/ux_lib" "$FX/shell-common/tools/"
    git -C "$FX" init -q
    git -C "$FX" config user.email t@example.invalid
    git -C "$FX" config user.name t

    # Pre-swap tracked files (the shape main had before #2006), fake values.
    OLD_SSH="$TEST_TEMP_HOME/old_ssh_config"
    cat >"$OLD_SSH" <<'EOF'
Host ghes.corp-fake.test
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

Host fake-gerrit
    HostName 203.0.113.10
    Port 29418
    User fake.user
    HostkeyAlgorithms +ssh-rsa

Host github.com
    Hostname ssh.github.com
    Port 443
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    ConnectTimeout 5

Host *
    PubkeyAcceptedKeyTypes +ssh-rsa
    ServerAliveInterval 60
    ServerAliveCountMax 3
    ConnectTimeout 10
EOF
    OLD_GIT="$TEST_TEMP_HOME/old_gitconfig"
    {
        sed '/^# Machine-local overrides/,$d' "$R/git/.gitconfig"
        printf '[credential "https://ghes.corp-fake.test"]\n\thelper =\n\tuseHttpPath = true\n\thelper = !fake-helper.sh\n'
    } >"$OLD_GIT"
    cp "$OLD_SSH" "$FX/ssh/config"
    cp "$OLD_GIT" "$FX/git/.gitconfig"
    git -C "$FX" add -A && git -C "$FX" commit -qm old
    # The swap: the tracked files as this repo now ships them.
    cp "$R/ssh/config" "$FX/ssh/config"
    cp "$R/git/.gitconfig" "$FX/git/.gitconfig"
    git -C "$FX" add -A && git -C "$FX" commit -qm swap

    MIGRATE="$FX/scripts/internal-ssh-git-migrate.sh"
    # ssh expands `~` from the passwd entry, not $HOME: point the tracked
    # Include at the throwaway HOME for ssh -G.
    NEW_SSH="$TEST_TEMP_HOME/new_ssh_config"
    sed "s|~/.ssh/config.internal.local|$HOME/.ssh/config.internal.local|" "$R/ssh/config" >"$NEW_SSH"
    printf '[include]\n\tpath = %s\n' "$FX/git/.gitconfig" >"$HOME/.gitconfig"
}

teardown() {
    teardown_isolated_home
}

@test "tracked ssh/config and git/.gitconfig include the local files" {
    grep -qx 'Include ~/.ssh/config.internal.local' "$R/ssh/config"
    grep -q 'path = ~/.gitconfig.internal.local' "$R/git/.gitconfig"
}

@test "migrate: dry-run (default) writes nothing" {
    run bash "$MIGRATE"
    assert_success
    assert_output --partial "Would write"
    [ ! -e "$HOME/.ssh/config.internal.local" ]
    [ ! -e "$HOME/.gitconfig.internal.local" ]
}

@test "migrate: --apply seeds both files from history without printing values" {
    run bash "$MIGRATE" --apply
    assert_success
    refute_output --partial "corp-fake"
    refute_output --partial "203.0.113"
    cmp "$OLD_SSH" "$HOME/.ssh/config.internal.local"
    [ "$(stat -c %a "$HOME/.ssh/config.internal.local")" = 600 ]
    run git config -f "$HOME/.gitconfig.internal.local" --get-regexp '^credential\.'
    assert_output --partial "credential.https://ghes.corp-fake.test.helper"
    refute_output --partial "github.com"
}

@test "migrate: never overwrites and is idempotent" {
    mkdir -p "$HOME/.ssh"
    printf 'Host mine\n' >"$HOME/.ssh/config.internal.local"
    run bash "$MIGRATE" --apply
    assert_success
    assert_output --partial "Exists, kept as-is: ~/.ssh/config.internal.local"
    [ "$(cat "$HOME/.ssh/config.internal.local")" = "Host mine" ]
    snap="$(cksum "$HOME/.gitconfig.internal.local")"
    run bash "$MIGRATE" --apply
    assert_success
    refute_output --partial "Written"
    [ "$(cksum "$HOME/.gitconfig.internal.local")" = "$snap" ]
}

@test "migrate: rejects unknown options" {
    run bash "$MIGRATE" --bogus
    [ "$status" -eq 2 ]
}

@test "with local files: ssh -G resolves every host as before the swap" {
    bash "$MIGRATE" --apply >/dev/null
    for h in fake-gerrit ghes.corp-fake.test github.com other.example.invalid; do
        [ "$(ssh -G -F "$OLD_SSH" "$h")" = "$(ssh -G -F "$NEW_SSH" "$h")" ] ||
            fail "ssh -G differs for $h"
    done
}

@test "with local files: git credential config is the same as before the swap" {
    bash "$MIGRATE" --apply >/dev/null
    old="$(git config -f "$OLD_GIT" --get-regexp '^credential\.')"
    new="$(git config --global --includes --get-regexp '^credential\.')"
    [ "$old" = "$new" ]
}

@test "without local files: neutral behavior, no error" {
    run ssh -G -F "$NEW_SSH" fake-gerrit
    assert_success
    assert_line "hostname fake-gerrit"
    run ssh -G -F "$NEW_SSH" github.com
    assert_line "hostname ssh.github.com"
    run git config --global --includes --get-regexp '^credential\.https://ghes'
    assert_failure
    assert_output ""
}

@test "migrate: warns when history has no pre-swap version" {
    rm -rf "$FX/.git"
    git -C "$FX" init -q
    run bash "$MIGRATE" --apply
    assert_success
    assert_output --partial "create it by hand"
    [ ! -e "$HOME/.ssh/config.internal.local" ]
}

# git/setup.sh rewrites an https GHES origin to ssh using DOTFILES_GHES_HOST
# (no host literal in the script). The SSH block is neutered as in
# tests/bats/git/test_global_hooks.bats.
_run_git_setup() {
    SB="$TEST_TEMP_HOME/sb"
    mkdir -p "$SB/shell-common/tools" "$SB/shell-common/functions" "$SB/shell-common/env"
    cp -R "$R/git" "$SB/git"
    cp -R "$R/shell-common/tools/ux_lib" "$SB/shell-common/tools/"
    cp "$R/shell-common/functions/gh_host.sh" "$R/shell-common/functions/dotfiles_root.sh" \
        "$SB/shell-common/functions/"
    git -C "$SB" init -q
    git -C "$SB" remote add origin https://ghes.corp-fake.test/org/repo.git
    mkdir -p "$HOME/.ssh" && : >"$HOME/.ssh/id_ed25519"
    SSH_AUTH_SOCK=/dev/null run bash "$SB/git/setup.sh"
}

@test "git/setup.sh: rewrites the GHES origin from DOTFILES_GHES_HOST" {
    export DOTFILES_GHES_HOST=ghes.corp-fake.test
    _run_git_setup
    assert_success
    [ "$(git -C "$SB" remote get-url origin)" = "git@ghes.corp-fake.test:org/repo.git" ]
}

@test "git/setup.sh: reads the GHES host from internal.local.sh" {
    unset DOTFILES_GHES_HOST
    mkdir -p "$TEST_TEMP_HOME/sb/shell-common/env"
    printf 'export DOTFILES_GHES_HOST="ghes.corp-fake.test"\n' >"$TEST_TEMP_HOME/sb/shell-common/env/internal.local.sh"
    _run_git_setup
    assert_success
    [ "$(git -C "$SB" remote get-url origin)" = "git@ghes.corp-fake.test:org/repo.git" ]
}

@test "git/setup.sh: leaves the origin alone when no GHES host is configured" {
    unset DOTFILES_GHES_HOST
    _run_git_setup
    assert_success
    [ "$(git -C "$SB" remote get-url origin)" = "https://ghes.corp-fake.test/org/repo.git" ]
}
