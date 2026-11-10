#!/usr/bin/env bats
# Codex lifecycle commands: hermetic previews and mocked failure paths.
load '../test_helper'

TOOLS_DIR="${DOTFILES_ROOT}/shell-common/tools/custom"

setup() {
    setup_isolated_home
    unset CODEX_HOME CODEX_INSTALL_DIR
    mkdir -p "$HOME/bin" "$HOME/npm/@openai/codex"
    cat > "$HOME/bin/npm" <<'NPM'
#!/bin/sh
case "$*" in
    'root -g') printf '%s\n' "$HOME/npm" ;;
    *) printf 'unexpected npm operation\n' >&2; exit 99 ;;
esac
NPM
    chmod +x "$HOME/bin/npm"
    export PATH="$HOME/bin:$PATH"
}

teardown() {
    teardown_isolated_home
}

run_codex_script() {
    run_sourced_tool_script "$TOOLS_DIR" "$TOOLS_DIR/$1" "$2"
}

@test "codex install help and preview never download or use npm" {
    run_codex_script install_codex.sh '
        curl() { exit 99; }
        npm() { exit 99; }
        main --help
        main --dry-run
    '
    assert_success
    assert_output --partial 'https://chatgpt.com/codex/install.sh'
    assert_output --partial "$HOME/.local/bin/codex"
    [ ! -e "$HOME/.codex" ]
}

@test "codex uninstall help has no package-manager side effects" {
    run_codex_script uninstall_codex.sh '
        npm() { exit 99; }
        main --help
    '
    assert_success
    assert_output --partial 'Preserve configuration, authentication, sessions, and skills'
}

@test "codex uninstall preview finds npm even when its executable is absent" {
    run_codex_script uninstall_codex.sh '
        ux_confirm() { exit 99; }
        main --dry-run
    '
    assert_success
    assert_output --partial 'npm uninstall -g @openai/codex'
    [ -d "$HOME/npm/@openai/codex" ]
}

@test "codex uninstall preview handles standalone packages and broken installer links" {
    mkdir -p "$HOME/.local/bin" "$HOME/.codex/packages/standalone/releases" "$HOME/.codex/skills"
    touch "$HOME/.codex/auth.json" "$HOME/.codex/config.toml"
    ln -s "$HOME/.codex/packages/standalone/current/bin/codex" "$HOME/.local/bin/codex"
    ln -s "$HOME/.codex/packages/standalone/current/bin/codex-code-mode-host" "$HOME/.local/bin/codex-code-mode-host"
    run_codex_script uninstall_codex.sh 'main --dry-run'
    assert_success
    assert_output --partial "Remove standalone link: $HOME/.local/bin/codex"
    assert_output --partial "Remove standalone link: $HOME/.local/bin/codex-code-mode-host"
    assert_output --partial "Remove standalone packages: $HOME/.codex/packages/standalone"
    [ -L "$HOME/.local/bin/codex" ]
    [ -d "$HOME/.codex/packages/standalone/releases" ]
    [ -f "$HOME/.codex/auth.json" ]
    [ -f "$HOME/.codex/config.toml" ]
    [ -d "$HOME/.codex/skills" ]
}

@test "codex uninstall respects custom directories and preserves unrelated links" {
    export CODEX_HOME="$HOME/custom codex" CODEX_INSTALL_DIR="$HOME/custom bin"
    mkdir -p "$CODEX_HOME/packages/standalone" "$CODEX_INSTALL_DIR"
    ln -s "$HOME/unrelated" "$CODEX_INSTALL_DIR/codex"
    run_codex_script uninstall_codex.sh 'main --dry-run'
    assert_success
    assert_output --partial "Remove standalone packages: $CODEX_HOME/packages/standalone"
    assert_output --partial "Preserving unrelated link: $CODEX_INSTALL_DIR/codex"
    [ -L "$CODEX_INSTALL_DIR/codex" ]
}

@test "codex installer rejects existing npm copy before downloading or changing rc files" {
    run_codex_script install_codex.sh '
        type() { printf "%s\n" "$HOME/npm/bin/codex"; }
        curl() { exit 99; }
        main
    '
    assert_failure 1
    assert_output --partial 'Run codex-uninstall first'
}

@test "codex installer download failure does not execute sh or report success" {
    run_codex_script install_codex.sh '
        mkdir -p "$HOME/tmp"
        export TMPDIR="$HOME/tmp"
        type() { return 1; }
        ux_confirm() { return 0; }
        curl() { return 22; }
        sh() { exit 99; }
        main
    '
    assert_failure 1
    assert_output --partial 'Failed to download'
    refute_output --partial 'Codex CLI is working'
    [ -z "$(ls -A "$HOME/tmp")" ]
}

@test "codex lifecycle commands reject unknown options" {
    run_codex_script install_codex.sh 'main --invalid'
    assert_failure 2
    run_codex_script uninstall_codex.sh 'main --invalid'
    assert_failure 2
}

@test "codex wrappers pass help arguments through in bash and zsh" {
    for shell in bash zsh; do
        run "$shell" -c '
            export DOTFILES_FORCE_INIT=1 CODEX_SKILLS_AUTO_SYNC=0
            export SHELL_COMMON="$1/shell-common"
            . "$SHELL_COMMON/tools/ux_lib/ux_lib.sh"
            . "$SHELL_COMMON/tools/integrations/codex.sh"
            . "$SHELL_COMMON/functions/ai_tools_help.sh"
            codex_install --help
            codex_uninstall --help
            codex_help setup
        ' _ "$DOTFILES_ROOT"
        assert_success
        assert_output --partial 'Usage: codex-install'
        assert_output --partial 'Usage: codex-uninstall'
        assert_output --partial 'Official standalone installer'
    done
}

@test "codex status resolves the executable behind its wrapper without npm in both shells" {
    printf '#!/bin/sh\nprintf "codex-cli fixture\\n"\n' > "$HOME/bin/codex"
    chmod +x "$HOME/bin/codex"
    for shell in bash zsh; do
        run "$shell" -c '
            export DOTFILES_FORCE_INIT=1 CODEX_SKILLS_AUTO_SYNC=0
            export SHELL_COMMON="$1/shell-common"
            . "$SHELL_COMMON/tools/ux_lib/ux_lib.sh"
            . "$SHELL_COMMON/tools/integrations/codex.sh"
            npm() { exit 99; }
            codex_status
        ' _ "$DOTFILES_ROOT"
        assert_success
        assert_output --partial 'codex-cli fixture'
        assert_output --partial "$HOME/bin/codex"
    done
}
