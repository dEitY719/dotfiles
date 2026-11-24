#!/usr/bin/env bats
load '../test_helper'

setup() {
    setup_isolated_home
    export PATH="$HOME/bin:/usr/bin:/bin"
    export XDG_CONFIG_HOME="$HOME/.config"
    mkdir -p "$HOME/bin" "$HOME/.local/bin" "$HOME/.config/opencode"
    SCRIPT="$DOTFILES_ROOT/shell-common/tools/custom/ai_cli_manage.sh"
}

teardown() { teardown_isolated_home; }

@test "management dry runs have no network or installer side effects" {
    cat > "$HOME/bin/curl" <<'CURL'
#!/bin/sh
exit 99
CURL
    chmod +x "$HOME/bin/curl"
    for tool in claude opencode hermes; do
        for action in install update uninstall; do
            run bash "$SCRIPT" "$tool" "$action" --dry-run
            assert_success
            [ ! -e "$HOME/.claude" ]
            [ ! -e "$HOME/.hermes" ]
        done
    done
}

@test "status reports broken expected binary without disclosing config" {
    mkdir -p "$HOME/.opencode/bin"
    printf '#!/bin/sh\nexit 1\n' > "$HOME/.opencode/bin/opencode"
    chmod +x "$HOME/.opencode/bin/opencode"
    export PATH="$HOME/.opencode/bin:$PATH"
    printf 'secret-config-value\n' > "$HOME/.config/opencode/opencode.json"
    run bash "$SCRIPT" opencode status
    assert_success
    assert_output --partial 'not runnable'
    refute_output --partial 'secret-config-value'
}

@test "uninstall previews and preserves configuration" {
    mkdir -p "$HOME/.opencode/bin"
    printf '#!/bin/sh\necho 1.0\n' > "$HOME/.opencode/bin/opencode"
    chmod +x "$HOME/.opencode/bin/opencode"
    printf 'keep\n' > "$HOME/.config/opencode/opencode.json"
    run bash "$SCRIPT" opencode uninstall --dry-run
    assert_success
    [ -e "$HOME/.opencode/bin/opencode" ]
    run bash "$SCRIPT" opencode uninstall -y
    assert_success
    [ ! -e "$HOME/.opencode/bin/opencode" ]
    [ "$(cat "$HOME/.config/opencode/opencode.json")" = keep ]
}

@test "unknown symlink is never removed" {
    mkdir -p "$HOME/.opencode/bin"
    printf '#!/bin/sh\necho 1.0\n' > "$HOME/bin/other"
    chmod +x "$HOME/bin/other"
    ln -s "$HOME/bin/other" "$HOME/.opencode/bin/opencode"
    run bash "$SCRIPT" opencode uninstall -y
    assert_failure
    [ -L "$HOME/.opencode/bin/opencode" ]
    [ -f "$HOME/bin/other" ]
}

@test "failed official install retains the existing npm package" {
    mkdir -p "$HOME/npm/node_modules/@anthropic-ai/claude-code" "$HOME/npm/bin"
    printf '#!/bin/sh\necho npm-version\n' > "$HOME/npm/node_modules/@anthropic-ai/claude-code/cli"
    chmod +x "$HOME/npm/node_modules/@anthropic-ai/claude-code/cli"
    ln -s "$HOME/npm/node_modules/@anthropic-ai/claude-code/cli" "$HOME/npm/bin/claude"
    export PATH="$HOME/npm/bin:$PATH"
    cat > "$HOME/bin/npm" <<'NPM'
#!/bin/sh
[ "$1" = root ] && { echo "$HOME/npm/node_modules"; exit 0; }
[ "$1" = prefix ] && { echo "$HOME/npm"; exit 0; }
touch "$HOME/npm-uninstalled"
NPM
    cat > "$HOME/bin/curl" <<'CURL'
#!/bin/sh
exit 22
CURL
    chmod +x "$HOME/bin/npm" "$HOME/bin/curl"
    run bash "$SCRIPT" claude update -y
    assert_failure
    [ -x "$HOME/npm/bin/claude" ]
    [ ! -e "$HOME/npm-uninstalled" ]
}

@test "both shells expose all new and legacy management names" {
    for shell in bash zsh; do
        command -v "$shell" >/dev/null 2>&1 || continue
        run "$shell" -c '
            export DOTFILES_FORCE_INIT=1
            [ -z "${BASH_VERSION:-}" ] || shopt -s expand_aliases
            export SHELL_COMMON="$1/shell-common"
            . "$SHELL_COMMON/tools/integrations/claude.sh"
            . "$SHELL_COMMON/tools/integrations/opencode.sh"
            . "$SHELL_COMMON/tools/integrations/hermes.sh"
            for name in claude-status claude-install claude-update claude-uninstall clinstall opencode-status opencode-install opencode-update opencode-uninstall install-opencode update-opencode uninstall-opencode hermes-status hermes-install hermes-update hermes-uninstall; do
                command -v "$name" >/dev/null || exit 1
            done
        ' _ "$DOTFILES_ROOT"
        assert_success
    done
}

@test "OpenCode config purge is explicit and previews its scope" {
    printf 'keep\n' > "$HOME/.config/opencode/opencode.json"
    run bash "$SCRIPT" opencode uninstall --purge-config --dry-run
    assert_success
    assert_output --partial "Remove OpenCode configuration: $HOME/.config/opencode"
    [ -f "$HOME/.config/opencode/opencode.json" ]
    run bash "$SCRIPT" opencode uninstall --purge-config -y
    assert_success
    [ ! -e "$HOME/.config/opencode" ]
}

@test "npm migration verifies official executable before removing the package" {
    mkdir -p "$HOME/npm/node_modules/@anthropic-ai/claude-code" "$HOME/npm/bin"
    printf '#!/bin/sh\necho old\n' > "$HOME/npm/node_modules/@anthropic-ai/claude-code/cli"
    chmod +x "$HOME/npm/node_modules/@anthropic-ai/claude-code/cli"
    ln -s "$HOME/npm/node_modules/@anthropic-ai/claude-code/cli" "$HOME/npm/bin/claude"
    export PATH="$HOME/npm/bin:$PATH"
    cat > "$HOME/bin/npm" <<'NPM'
#!/bin/sh
[ "$1" = root ] && { echo "$HOME/npm/node_modules"; exit 0; }
[ "$1" = prefix ] && { echo "$HOME/npm"; exit 0; }
[ -x "$HOME/.local/bin/claude" ] || exit 99
"$HOME/.local/bin/claude" --version >/dev/null || exit 99
printf '%s\n' "$*" > "$HOME/npm-called"
NPM
    cat > "$HOME/bin/curl" <<'CURL'
#!/bin/sh
while [ "$1" != -o ]; do shift; done
cat > "$2" <<'INSTALLER'
mkdir -p "$HOME/.local/share/claude/versions" "$HOME/.local/bin"
printf '#!/bin/sh\necho 2.0\n' > "$HOME/.local/share/claude/versions/2.0"
chmod +x "$HOME/.local/share/claude/versions/2.0"
ln -s "$HOME/.local/share/claude/versions/2.0" "$HOME/.local/bin/claude"
INSTALLER
CURL
    chmod +x "$HOME/bin/npm" "$HOME/bin/curl"
    run bash "$SCRIPT" claude update -y
    assert_success
    [ "$(cat "$HOME/npm-called")" = 'uninstall -g @anthropic-ai/claude-code' ]
}

@test "OpenCode uses curl in internal mode without npm fallback" {
    printf 'internal\n' > "$HOME/.dotfiles-setup-mode"
    cat > "$HOME/bin/npm" <<'NPM'
#!/bin/sh
touch "$HOME/npm-called"
exit 99
NPM
    cat > "$HOME/bin/curl" <<'CURL'
#!/bin/sh
exit 22
CURL
    chmod +x "$HOME/bin/npm" "$HOME/bin/curl"
    run bash "$DOTFILES_ROOT/shell-common/tools/custom/install_opencode.sh" -y
    assert_failure
    assert_output --partial 'Installer failed'
    [ ! -e "$HOME/npm-called" ]
}

@test "migration refuses a global npm prefix that owns the target link" {
    mkdir -p "$HOME/.local/lib/node_modules/@anthropic-ai/claude-code" "$HOME/alias-bin"
    printf '#!/bin/sh\necho old\n' > "$HOME/.local/lib/node_modules/@anthropic-ai/claude-code/cli"
    chmod +x "$HOME/.local/lib/node_modules/@anthropic-ai/claude-code/cli"
    ln -s "$HOME/.local/lib/node_modules/@anthropic-ai/claude-code/cli" "$HOME/alias-bin/claude"
    export PATH="$HOME/alias-bin:$PATH"
    cat > "$HOME/bin/npm" <<'NPM'
#!/bin/sh
[ "$1" = prefix ] && { echo "$HOME/.local"; exit 0; }
exit 99
NPM
    chmod +x "$HOME/bin/npm"
    run bash "$SCRIPT" claude update -y
    assert_failure
    assert_output --partial 'npm prefix owns'
    [ -x "$HOME/alias-bin/claude" ]
    [ ! -e "$HOME/.local/bin/claude" ]
}

@test "management entrypoint reports usage without requiring a tool" {
    run bash "$SCRIPT" --help
    assert_success
    assert_output --partial "Usage: ai_cli_manage.sh"
    run bash "$SCRIPT"
    assert_failure 2
    assert_output --partial "Usage: ai_cli_manage.sh"
}

@test "Hermes uninstall preserves shell rc files and user data" {
    mkdir -p "$HOME/.hermes/hermes-agent/.git" "$HOME/.hermes/hermes-agent/.hermes/bin"
    printf '#!/bin/sh\nexit 99\n' > "$HOME/.hermes/hermes-agent/.hermes/bin/hermes"
    chmod +x "$HOME/.hermes/hermes-agent/.hermes/bin/hermes"
    printf '#!/bin/sh\nexec %s/.hermes/hermes-agent/.hermes/bin/hermes "$@"\n' "$HOME" > "$HOME/.local/bin/hermes"
    chmod +x "$HOME/.local/bin/hermes"
    printf 'keep\n' > "$HOME/.hermes/config.yaml"
    printf 'shell rc\n' > "$HOME/managed_rc"
    ln -s "$HOME/managed_rc" "$HOME/.bashrc"
    cat > "$HOME/bin/git" <<'GIT'
#!/bin/sh
case "$*" in
  *'remote get-url origin') echo 'https://github.com/NousResearch/hermes-agent.git' ;;
  *'status --porcelain --untracked-files=normal') : ;;
  *) exit 1 ;;
esac
GIT
    chmod +x "$HOME/bin/git"
    run bash "$SCRIPT" hermes uninstall -y
    assert_success
    [ ! -e "$HOME/.local/bin/hermes" ]
    [ ! -e "$HOME/.hermes/hermes-agent" ]
    [ -f "$HOME/.hermes/config.yaml" ]
    [ -L "$HOME/.bashrc" ]
    [ "$(cat "$HOME/managed_rc")" = 'shell rc' ]
}

@test "Hermes uninstall refuses locally modified source" {
    mkdir -p "$HOME/.hermes/hermes-agent/.git" "$HOME/.hermes/hermes-agent/.hermes/bin"
    printf '#!/bin/sh\nexit 99\n' > "$HOME/.hermes/hermes-agent/.hermes/bin/hermes"
    chmod +x "$HOME/.hermes/hermes-agent/.hermes/bin/hermes"
    printf '#!/bin/sh\nexec %s/.hermes/hermes-agent/.hermes/bin/hermes "$@"\n' "$HOME" > "$HOME/.local/bin/hermes"
    chmod +x "$HOME/.local/bin/hermes"
    cat > "$HOME/bin/git" <<'GIT'
#!/bin/sh
case "$*" in
  *'remote get-url origin') echo 'https://github.com/NousResearch/hermes-agent.git' ;;
  *'status --porcelain --untracked-files=normal') echo ' M user-file' ;;
  *) exit 1 ;;
esac
GIT
    chmod +x "$HOME/bin/git"
    run bash "$SCRIPT" hermes uninstall -y
    assert_failure
    assert_output --partial 'source has local changes'
    [ -f "$HOME/.local/bin/hermes" ]
    [ -d "$HOME/.hermes/hermes-agent" ]
}

@test "status resolves relative npm links without readlink -f" {
    mkdir -p "$HOME/npm/bin" "$HOME/npm/node_modules/@anthropic-ai/claude-code"
    printf '#!/bin/sh\necho 1.0\n' > "$HOME/npm/node_modules/@anthropic-ai/claude-code/cli"
    chmod +x "$HOME/npm/node_modules/@anthropic-ai/claude-code/cli"
    ln -s ../node_modules/@anthropic-ai/claude-code/cli "$HOME/npm/bin/claude"
    printf '#!/bin/sh\nexit 1\n' > "$HOME/bin/readlink"
    chmod +x "$HOME/bin/readlink"
    export PATH="$HOME/bin:$HOME/npm/bin:/usr/bin:/bin"
    run bash "$SCRIPT" claude status
    assert_success
    assert_output --partial 'npm'
}

@test "OpenCode config purge removes the configured link, not its target" {
    mkdir -p "$HOME/custom-config"
    printf 'keep\n' > "$HOME/config-source"
    ln -s "$HOME/config-source" "$HOME/custom-config/opencode.json"
    export OPENCODE_CONFIG_DIR="$HOME/custom-config"
    export OPENCODE_CONFIG_FILE="$HOME/custom-config/opencode.json"
    run bash "$SCRIPT" opencode uninstall --purge-config -y
    assert_success
    [ ! -e "$HOME/custom-config/opencode.json" ]
    [ "$(cat "$HOME/config-source")" = keep ]
    [ -d "$HOME/custom-config" ]
}
