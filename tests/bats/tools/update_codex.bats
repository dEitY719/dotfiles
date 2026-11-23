#!/usr/bin/env bats
# codex-update (issue #2426): method detection, mocked official installer,
# npm -> standalone migration and --release pass-through.
load '../test_helper'

TOOLS_DIR="${DOTFILES_ROOT}/shell-common/tools/custom"

setup() {
    setup_isolated_home
    unset CODEX_HOME CODEX_INSTALL_DIR
    mkdir -p "$HOME/bin" "$HOME/.local/bin" "$HOME/tmp"
    export TMPDIR="$HOME/tmp"
    # npm mock: records every call; root -g points at $HOME/npm/node_modules.
    cat > "$HOME/bin/npm" <<'NPM'
#!/bin/sh
printf '%s\n' "$*" >> "$HOME/npm.calls"
case "$*" in
    'root -g') printf '%s\n' "$HOME/npm/node_modules" ;;
    'uninstall -g @openai/codex') rm -rf "$HOME/npm/node_modules/@openai/codex" "$HOME/npm/bin/codex" ;;
    *) exit 99 ;;
esac
NPM
    chmod +x "$HOME/bin/npm"
    # curl mock: "downloads" a fake official installer that records its args
    # and installs standalone $NEW_VERSION (exits $INSTALLER_RC when set).
    # Tests needing another curl define a curl() function in their body.
    cat > "$HOME/bin/curl" <<'CURL'
#!/bin/sh
out="" prev=""
for a in "$@"; do [ "$prev" = -o ] && out="$a"; prev="$a"; done
cat > "$out" <<'INSTALLER'
printf '%s\n' "$*" > "$HOME/installer.args"
printf '%s\n' "${CODEX_NON_INTERACTIVE:-}" > "$HOME/installer.env"
[ -z "${INSTALLER_RC:-}" ] || exit "$INSTALLER_RC"
cur="$HOME/.codex/packages/standalone/current/bin"
mkdir -p "$cur" "$HOME/.local/bin"
printf '#!/bin/sh\necho "codex-cli %s"\n' "$NEW_VERSION" > "$cur/codex"
chmod +x "$cur/codex"
ln -sfn "$cur/codex" "$HOME/.local/bin/codex"
INSTALLER
CURL
    chmod +x "$HOME/bin/curl"
    # A real codex on the host PATH must not leak into method detection.
    export PATH="$HOME/bin:/usr/local/bin:/usr/bin:/bin"
}

teardown() {
    teardown_isolated_home
}

run_update() {
    run_sourced_tool_script "$TOOLS_DIR" "$TOOLS_DIR/update_codex.sh" "$1"
}

run_install() {
    run_sourced_tool_script "$TOOLS_DIR" "$TOOLS_DIR/install_codex.sh" "$1"
}

# Standalone layout as the official installer leaves it, at version $1.
make_standalone() {
    local cur="$HOME/.codex/packages/standalone/current/bin"
    mkdir -p "$cur"
    printf '#!/bin/sh\necho "codex-cli %s"\n' "$1" > "$cur/codex"
    chmod +x "$cur/codex"
    ln -sfn "$cur/codex" "$HOME/.local/bin/codex"
}

make_npm_install() {
    mkdir -p "$HOME/npm/node_modules/@openai/codex/bin" "$HOME/npm/bin"
    printf '#!/bin/sh\nprintf "codex-cli 0.171.0\\n"\n' > "$HOME/npm/node_modules/@openai/codex/bin/codex.js"
    chmod +x "$HOME/npm/node_modules/@openai/codex/bin/codex.js"
    ln -s "$HOME/npm/node_modules/@openai/codex/bin/codex.js" "$HOME/npm/bin/codex"
    # After $HOME/bin, before any host codex (e.g. /usr/bin/codex).
    export PATH="$HOME/bin:$HOME/npm/bin:$PATH"
}


@test "codex-update help and dry-run never download, call npm or change files" {
    make_standalone 0.170.0
    run_update '
        curl() { exit 99; }
        npm() { exit 99; }
        main --help
        main --dry-run
    '
    assert_success
    assert_output --partial 'Usage: codex-update'
    assert_output --partial 'Install method: standalone'
    assert_output --partial '[dry-run]'
    [ ! -e "$HOME/npm.calls" ]
    [ ! -e "$HOME/installer.args" ]
}

@test "codex-update dry-run recognises an npm install from PATH without running npm" {
    make_npm_install
    run_update '
        export PATH="$HOME/npm/bin:$PATH"
        curl() { exit 99; }
        main --dry-run
    '
    assert_success
    assert_output --partial 'Install method: npm'
    assert_output --partial 'npm uninstall -g @openai/codex'
    [ ! -e "$HOME/npm.calls" ]
    [ -d "$HOME/npm/node_modules/@openai/codex" ]
}

@test "codex-update reports A -> B when the installer raises the version" {
    make_standalone 0.170.0
    run_update '
        export NEW_VERSION=0.172.0
        main
    '
    assert_success
    assert_output --partial 'codex-cli 0.170.0 -> codex-cli 0.172.0'
    [ "$(cat "$HOME/installer.env")" = 1 ]
    [ -z "$(ls -A "$HOME/tmp")" ]
}

@test "codex-update reports already up to date when the version is unchanged" {
    make_standalone 0.170.0
    run_update '
        export NEW_VERSION=0.170.0
        main
    '
    assert_success
    assert_output --partial 'already up to date (codex-cli 0.170.0)'
}

@test "codex-update --release passes the version to the official installer" {
    make_standalone 0.172.0
    run_update '
        export NEW_VERSION=0.170.0
        main --release 0.170.0
    '
    assert_success
    [ "$(cat "$HOME/installer.args")" = '--release 0.170.0' ]
    assert_output --partial 'codex-cli 0.172.0 -> codex-cli 0.170.0'
}

@test "codex-install --release passes the version to the official installer" {
    run_install '
        export NEW_VERSION=0.170.0
        type() { return 1; }
        ux_confirm() { return 0; }
        main --release 0.170.0
    '
    assert_success
    [ "$(cat "$HOME/installer.args")" = '--release 0.170.0' ]
    assert_output --partial 'Codex CLI is working: codex-cli 0.170.0'
}

@test "codex-update npm migration declined changes nothing" {
    make_npm_install
    run_update '
        ux_confirm() { return 1; }
        main
    '
    assert_success
    assert_output --partial 'nothing was changed'
    [ -d "$HOME/npm/node_modules/@openai/codex" ]
    [ ! -e "$HOME/installer.args" ]
    run grep -c uninstall "$HOME/npm.calls"
    [ "$output" = 0 ]
}

@test "codex-update npm migration with -y uninstalls npm once then installs standalone" {
    make_npm_install
    run_update '
        export NEW_VERSION=0.172.0
        ux_confirm() { exit 99; }
        main -y
    '
    assert_success
    assert_output --partial 'Migrated npm -> standalone'
    [ "$(grep -c 'uninstall -g @openai/codex' "$HOME/npm.calls")" = 1 ]
    [ ! -d "$HOME/npm/node_modules/@openai/codex" ]
    [ -L "$HOME/.local/bin/codex" ]
}

@test "codex-update npm migration stops when npm uninstall fails" {
    make_npm_install
    run_update '
        npm() { [ "$1" = root ] && { printf "%s\n" "$HOME/npm/node_modules"; return 0; }; return 1; }
        main -y
    '
    assert_failure 1
    assert_output --partial 'standalone install was not attempted'
    [ ! -e "$HOME/installer.args" ]
}

@test "codex-update npm migration install failure points at codex-install" {
    make_npm_install
    run_update '
        export INSTALLER_RC=3
        main -y --release 0.170.0
    '
    assert_failure 1
    assert_output --partial 'official Codex installer failed (exit 3)'
    assert_output --partial 'no Codex CLI is installed right now'
    assert_output --partial 'codex-install --release 0.170.0'
}

@test "codex-update none state points at codex-install and exits 1" {
    run_update '
        # Hide any codex the host has in /usr/bin.
        type() { [ "$1 $2" = "-P codex" ] && return 1; builtin type "$@"; }
        curl() { exit 99; }
        main
    '
    assert_failure 1
    assert_output --partial 'Run codex-install first'
}

@test "codex-update other state changes nothing and exits 1" {
    printf '#!/bin/sh\nprintf "codex-cli brew\\n"\n' > "$HOME/bin/codex"
    chmod +x "$HOME/bin/codex"
    run_update '
        curl() { exit 99; }
        main
    '
    assert_failure 1
    assert_output --partial "not a standalone or npm install: $HOME/bin/codex"
    [ -x "$HOME/bin/codex" ]
}

@test "codex-update distinguishes download, installer and verify failures" {
    make_standalone 0.170.0
    run_update '
        curl() { return 22; }
        main
    '
    assert_failure 1
    assert_output --partial 'Failed to download the official Codex installer.'

    run_update '
        export INSTALLER_RC=5
        main
    '
    assert_failure 1
    assert_output --partial 'official Codex installer failed (exit 5)'

    run_update '
        curl() {
            local out="" prev=""
            for a in "$@"; do [ "$prev" = -o ] && out="$a"; prev="$a"; done
            printf "rm -f %s\n" "$HOME/.codex/packages/standalone/current/bin/codex" > "$out"
        }
        main
    '
    assert_failure 1
    assert_output --partial 'not runnable after install'
    [ -z "$(ls -A "$HOME/tmp")" ]
}

@test "codex-update rejects unknown arguments and a missing --release value" {
    run_update 'main --invalid'
    assert_failure 2
    assert_output --partial 'Usage: codex-update'
    run_update 'main --release'
    assert_failure 2
    run_install 'main --release --dry-run'
    assert_failure 2
}

@test "codex-update dry-run works through the wrapper in bash and zsh" {
    make_standalone 0.170.0
    for shell in bash zsh; do
        run "$shell" -c '
            export DOTFILES_FORCE_INIT=1 CODEX_SKILLS_AUTO_SYNC=0
            export SHELL_COMMON="$1/shell-common"
            . "$SHELL_COMMON/tools/ux_lib/ux_lib.sh"
            . "$SHELL_COMMON/tools/integrations/codex.sh"
            . "$SHELL_COMMON/functions/ai_tools_help.sh"
            codex_update --dry-run
            codex_help setup
            codex_help
        ' _ "$DOTFILES_ROOT"
        assert_success
        assert_output --partial 'Install method: standalone'
        assert_output --partial 'codex-update'
    done
    [ ! -e "$HOME/npm.calls" ]
}

@test "codex status shows the standalone install method in both shells" {
    make_standalone 0.170.0
    for shell in bash zsh; do
        run "$shell" -c '
            export DOTFILES_FORCE_INIT=1 CODEX_SKILLS_AUTO_SYNC=0
            export SHELL_COMMON="$1/shell-common"
            export PATH="$HOME/.local/bin:$PATH"
            . "$SHELL_COMMON/tools/ux_lib/ux_lib.sh"
            . "$SHELL_COMMON/tools/integrations/codex.sh"
            codex_status
        ' _ "$DOTFILES_ROOT"
        assert_success
        assert_output --partial 'Install method'
        assert_output --partial 'standalone'
    done
    [ ! -e "$HOME/npm.calls" ]
}

@test "codex-update warns when a legacy npm package remains next to standalone" {
    make_standalone 0.170.0
    make_npm_install
    run_update '
        export NEW_VERSION=0.172.0
        main
    '
    assert_success
    assert_output --partial 'codex-cli 0.170.0 -> codex-cli 0.172.0'
    assert_output --partial 'legacy npm @openai/codex is still installed'
    [ "$(grep -c uninstall "$HOME/npm.calls")" = 0 ]
}

@test "codex-update leaves an active non-npm codex alone even when an npm package exists" {
    make_npm_install
    printf '#!/bin/sh\necho "codex-cli brew"\n' > "$HOME/bin/codex"
    chmod +x "$HOME/bin/codex"
    run_update '
        curl() { exit 99; }
        main -y
    '
    assert_failure 1
    assert_output --partial 'Install method: other'
    [ "$(grep -c uninstall "$HOME/npm.calls")" = 0 ]
    [ -d "$HOME/npm/node_modules/@openai/codex" ]
}

@test "codex-update npm migration downloads before uninstalling npm" {
    make_npm_install
    run_update '
        curl() { return 22; }
        main -y
    '
    assert_failure 1
    assert_output --partial 'Failed to download the official Codex installer.'
    [ "$(grep -c uninstall "$HOME/npm.calls")" = 0 ]
    [ -d "$HOME/npm/node_modules/@openai/codex" ]
    [ -z "$(ls -A "$HOME/tmp")" ]
}

@test "codex-update refuses an npm migration when the npm root needs sudo" {
    make_npm_install
    chmod a-w "$HOME/npm/node_modules"
    run_update '
        curl() { exit 99; }
        ux_confirm() { exit 99; }
        main
    '
    chmod u+w "$HOME/npm/node_modules"
    assert_failure 1
    assert_output --partial 'npm global root is not writable'
    assert_output --partial 'sudo npm uninstall -g @openai/codex'
    [ "$(grep -c uninstall "$HOME/npm.calls")" = 0 ]
}

@test "codex-update treats a relative link into a symlinked CODEX_HOME as standalone" {
    mkdir -p "$HOME/real-codex/packages/standalone/current/bin" "$HOME/.local/bin"
    printf '#!/bin/sh\necho "codex-cli 0.170.0"\n' > "$HOME/real-codex/packages/standalone/current/bin/codex"
    chmod +x "$HOME/real-codex/packages/standalone/current/bin/codex"
    ln -s "$HOME/real-codex" "$HOME/.codex"
    ln -s ../../.codex/packages/standalone/current/bin/codex "$HOME/.local/bin/codex"
    run_update 'main --dry-run'
    assert_success
    assert_output --partial 'Install method: standalone'
}

@test "codex status classifies the binary it shows and hints at migration for npm" {
    make_npm_install
    for shell in bash zsh; do
        run "$shell" -c '
            export DOTFILES_FORCE_INIT=1 CODEX_SKILLS_AUTO_SYNC=0
            export SHELL_COMMON="$1/shell-common"
            export PATH="$HOME/npm/bin:$PATH"
            . "$SHELL_COMMON/tools/ux_lib/ux_lib.sh"
            . "$SHELL_COMMON/tools/integrations/codex.sh"
            codex_status
        ' _ "$DOTFILES_ROOT"
        assert_success
        assert_output --partial 'Migrate to standalone: codex-update'
        refute_output --partial 'Standalone Installation'
    done
    [ ! -e "$HOME/npm.calls" ]
}
