#!/usr/bin/env bats
# tests/bats/tools/install_opencode.bats
# install_opencode.sh install-path routing and post-install verification.
#
# Background: npm 12 blocks dependency install scripts by default
# (allow-scripts), so `npm install -g opencode-ai` silently skipped the
# postinstall that swaps bin/opencode.exe for the real binary. The installer
# still reported success while `opencode` was a placeholder that exits 1.
# Fix: public/external use the official curl installer (~/.opencode/bin),
# internal keeps npm (opencode.ai is blocked there) with an explicit
# --allow-scripts, and both paths verify `opencode --version` actually runs.

load '../test_helper'

TOOLS_DIR="${DOTFILES_ROOT}/shell-common/tools/custom"
INSTALL_OPENCODE_SCRIPT="${TOOLS_DIR}/install_opencode.sh"

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

run_opencode_tool() {
    run_sourced_tool_script "$TOOLS_DIR" "$INSTALL_OPENCODE_SCRIPT" "$1"
}

# --- install method routing --------------------------------------------------

@test "opencode_install_method: internal routes to npm" {
    run_opencode_tool 'opencode_install_method internal'
    assert_success
    assert_output "npm"
}

@test "opencode_install_method: public, external and legacy home route to curl" {
    run_opencode_tool '
        opencode_install_method public
        opencode_install_method external
        opencode_install_method home
    '
    assert_success
    assert_output "curl
curl
curl"
}

# --- environment selection (F4) -----------------------------------------------
# Same numbering/value names as ./setup.sh (1=public 2=internal 3=external);
# Enter keeps the current setup mode read via util/setup_mode_read.sh.
# ux_* are stubbed: BODY defines them after init.sh loads ux_lib, so they win.

_select_env() {
    run_opencode_tool "
        ux_section() { printf '%s\n' \"\$*\"; }
        ux_bullet() { printf '%s\n' \"\$*\"; }
        ux_error() { printf '%s\n' \"\$*\" >&2; }
        ux_input() { printf '%s\n' \"\$1\" >&2; read -r r; printf '%s\n' \"\$r\"; }
        printf '%s\n' '$1' | opencode_select_environment 2>'$HOME/menu'
    "
}

@test "opencode_select_environment: 2 is internal and 3 is external (setup.sh order)" {
    rm -f "$HOME/.dotfiles-setup-mode"
    _select_env 2
    assert_success
    assert_output "internal"
    _select_env 3
    assert_output "external"
    _select_env 1
    assert_output "public"
}

@test "opencode_select_environment: Enter keeps the current setup mode (CRLF, legacy numeric)" {
    printf '2\r\n' >"$HOME/.dotfiles-setup-mode"
    _select_env ""
    assert_success
    assert_output "internal"
    run cat "$HOME/menu"
    assert_output --partial "Enter=current: internal"
}

@test "opencode_select_environment: menu has public/internal/external and no emoji" {
    printf 'external\n' >"$HOME/.dotfiles-setup-mode"
    _select_env ""
    assert_output "external"
    run cat "$HOME/menu"
    assert_output --partial "1) Public PC"
    assert_output --partial "2) Internal company PC"
    assert_output --partial "3) External company PC (VPN)"
    refute_output --partial "Home"
    run bash -c "LC_ALL=C grep -c '[^[:print:][:space:]]' '$HOME/menu'"
    assert_output "0"
}

# --- npm path ------------------------------------------------------------------

@test "install_opencode_via_npm: allows opencode-ai install scripts explicitly" {
    run_opencode_tool '
        npm() { printf "%s\n" "$*"; }
        install_opencode_via_npm
    '
    assert_success
    assert_output --partial "--allow-scripts=opencode-ai"
    assert_output --partial "opencode-ai"
}

# --- curl path -----------------------------------------------------------------

@test "install_opencode_via_curl: runs the official installer with --no-modify-path" {
    run_opencode_tool '
        curl() {
            out=""
            while [ $# -gt 0 ]; do
                [ "$1" = "-o" ] && out="$2"
                shift
            done
            printf "%s\n" "printf \"installer-args:%s\\n\" \"\$*\"" > "$out"
        }
        install_opencode_via_curl
    '
    assert_success
    assert_output --partial "installer-args:--no-modify-path"
}

@test "install_opencode_via_curl: download failure fails without running an installer" {
    run_opencode_tool '
        curl() { return 22; }
        install_opencode_via_curl
    '
    assert_failure
    refute_output --partial "installer-args"
}

@test "opencode_binary_path: curl installs land in ~/.opencode/bin" {
    run_opencode_tool 'opencode_binary_path curl'
    assert_success
    assert_output "$HOME/.opencode/bin/opencode"
}

@test "opencode_binary_path: npm installs land under npm prefix -g" {
    run_opencode_tool '
        npm() { echo /fake/npm-prefix; }
        opencode_binary_path npm
    '
    assert_success
    assert_output "/fake/npm-prefix/bin/opencode"
}

# Swallowing npm's stderr left only the misleading "/bin/opencode" path behind.
@test "opencode_binary_path: a failing npm prefix -g surfaces npm's own error" {
    run_opencode_tool '
        npm() { echo "npm ERR! cannot determine prefix" >&2; return 1; }
        opencode_binary_path npm
    '
    assert_failure
    assert_output --partial "npm ERR! cannot determine prefix"
    refute_output --partial "/bin/opencode"
}

# --- verification --------------------------------------------------------------

@test "verify_opencode_binary: rejects the npm postinstall placeholder" {
    local bin="$HOME/placeholder/opencode"
    mkdir -p "$(dirname "$bin")"
    printf '%s\n' \
        "echo \"Error: opencode-ai's postinstall script was not run.\" >&2" \
        'exit 1' > "$bin"
    chmod +x "$bin"

    run_opencode_tool "verify_opencode_binary '$bin'"
    assert_failure
}

@test "verify_opencode_binary: rejects a missing binary" {
    run_opencode_tool "verify_opencode_binary '$HOME/nope/opencode'"
    assert_failure
}

@test "verify_opencode_binary: accepts a binary whose --version succeeds" {
    local bin="$HOME/good/opencode"
    mkdir -p "$(dirname "$bin")"
    printf '%s\n' '#!/bin/sh' 'echo 1.18.30' > "$bin"
    chmod +x "$bin"

    run_opencode_tool "verify_opencode_binary '$bin'"
    assert_success
    assert_output "1.18.30"
}

# --- structural guard: main() consumes the helpers -----------------------------

@test "main routes through opencode_install_method and verify_opencode_binary" {
    run grep -c 'opencode_install_method "\$environment"' "$INSTALL_OPENCODE_SCRIPT"
    assert_success
    run grep -c 'verify_opencode_binary' "$INSTALL_OPENCODE_SCRIPT"
    assert_success
    run grep -c 'npm install -g opencode-ai 2>' "$INSTALL_OPENCODE_SCRIPT"
    assert_failure
}

# --- internal config (#1967) ----------------------------------------------------

@test "generate_internal_config: delegates to setup.sh and writes the config" {
    run_opencode_tool 'ux_info() { :; }; generate_internal_config'
    assert_success
    assert_output --partial "Setting up OpenCode configuration for: internal"
    [ -f "$HOME/.config/opencode/opencode.json" ]
}

@test "opencode_select_environment: closed stdin with no mode file falls back to public (no input loop)" {
    rm -f "$HOME/.dotfiles-setup-mode"
    # Real ux_input (not stubbed): EOF must end the prompt instead of looping.
    run_opencode_tool "
        DOTFILES_FORCE_INIT=1 . '${DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh'
        opencode_select_environment </dev/null 2>/dev/null
    "
    assert_success
    assert_output "public"
}

# --- update-opencode (#2419) ----------------------------------------------------
# update_main reruns the install path chosen by the setup mode (no menu).
# run_remote_installer is stubbed to record its args and drop a fake binary
# that prints $NEW_VERSION; npm is stubbed the same way for internal.

_update() {
    local mode="$1" body="$2"
    run_opencode_tool "
        export DOTFILES_SETUP_MODE='$mode'
        log='$HOME/calls'
        _fake_bin() {
            mkdir -p \"\$(dirname \"\$1\")\"
            printf '#!/bin/sh\necho %s\n' \"\$2\" > \"\$1\"
            chmod +x \"\$1\"
        }
        run_remote_installer() {
            printf 'installer %s\n' \"\$*\" >> \"\$log\"
            _fake_bin '$HOME/.opencode/bin/opencode' \"\${NEW_VERSION:-1.2.0}\"
        }
        npm() {
            printf 'npm %s\n' \"\$*\" >> \"\$log\"
            case \"\$1\" in
                prefix) echo '$HOME/npm' ;;
                install) _fake_bin '$HOME/npm/bin/opencode' \"\${NEW_VERSION:-1.2.0}\" ;;
                root) return 1 ;;
            esac
        }
        export PATH='$HOME/.opencode/bin:$HOME/npm/bin':\"\$PATH\"
        $body
    "
}

@test "update_main: curl modes rerun the official installer with --no-modify-path" {
    for mode in external public ""; do
        rm -f "$HOME/calls"
        _update "$mode" 'update_main'
        assert_success
        run cat "$HOME/calls"
        assert_line "installer https://opencode.ai/install --no-modify-path"
        refute_output --partial "npm install"
    done
}

@test "update_main: internal uses npm opencode-ai@latest and never curl" {
    _update internal 'update_main'
    assert_success
    run cat "$HOME/calls"
    assert_line "npm install -g --allow-scripts=opencode-ai opencode-ai@latest"
    refute_output --partial "installer"
}

@test "update_main: prints old and new versions, or already latest" {
    _update external '_fake_bin "$HOME/.opencode/bin/opencode" 1.1.0; update_main'
    assert_success
    assert_output --partial "Current version: 1.1.0"
    assert_output --partial "OpenCode updated: 1.1.0 -> 1.2.0"

    _update external '_fake_bin "$HOME/.opencode/bin/opencode" 1.2.0; update_main'
    assert_success
    assert_output --partial "OpenCode 1.2.0 (already latest)"
}

@test "update_main: no prior install reports (not installed) and installs" {
    _update external 'update_main'
    assert_success
    assert_output --partial "Current version: (not installed)"
    assert_output --partial "OpenCode updated: (not installed) -> 1.2.0"
}

@test "update_main: unrunnable binary after update fails without success message" {
    _update external '
        run_remote_installer() {
            mkdir -p "$HOME/.opencode/bin"
            printf "#!/bin/sh\nexit 1\n" > "$HOME/.opencode/bin/opencode"
            chmod +x "$HOME/.opencode/bin/opencode"
        }
        update_main
    '
    assert_failure 1
    assert_output --partial "not runnable after update"
    refute_output --partial "update complete"
}

@test "update_main: installer failure keeps its exit code and prints access hint" {
    _update external 'run_remote_installer() { return 22; }; update_main'
    assert_failure 22
    assert_output --partial "curl -fsSI https://opencode.ai/install"
    refute_output --partial "update complete"
}

@test "update_main: arguments are rejected with usage" {
    _update external 'update_main 1.2.3'
    assert_failure 1
    assert_output --partial "update-opencode"
    refute_output --partial "installer"
    [ ! -f "$HOME/calls" ]
}

@test "update_main: warns with the real path when PATH resolves another opencode" {
    _update external '
        _fake_bin "$HOME/shadow/opencode" 0.9.0
        export PATH="$HOME/shadow:$PATH"
        update_main
    '
    assert_success
    assert_output --partial "'opencode' on PATH is $HOME/shadow/opencode"
    assert_output --partial "$HOME/.opencode/bin must come first in PATH"
    assert_output --partial "Or remove the other copy: $HOME/shadow/opencode"
}

@test "update_main: internal npm update warns when an old ~/.opencode/bin copy shadows it" {
    _update internal '
        _fake_bin "$HOME/.opencode/bin/opencode" 0.9.0
        update_main
    '
    assert_success
    assert_output --partial "'opencode' on PATH is $HOME/.opencode/bin/opencode, not $HOME/npm/bin/opencode"
    assert_output --partial "Or remove the other copy: $HOME/.opencode/bin/opencode"
}

@test "update_main: no PATH warning when PATH reaches the same binary via another spelling" {
    _update external 'export PATH="$HOME/.opencode/bin/:$PATH"; update_main'
    assert_success
    refute_output --partial "on PATH is"
}

@test "update_main: no PATH warning when ~/.opencode/bin wins" {
    _update external 'update_main'
    assert_success
    refute_output --partial "on PATH is"
}

@test "main update dispatches to update_main without the environment menu" {
    _update external 'main update'
    assert_success
    refute_output --partial "Available Environments"
    assert_output --partial "OpenCode CLI Update"
}

# --- remove_stale_npm_opencode: global and ~/.local prefixes (#2419) -----------

# npm stub: `root -g [--prefix p]` prints <p or $HOME/g>/lib/node_modules.
_npm_root_stub='npm() {
    printf "%s\n" "$*" >> "$HOME/calls"
    case "$1" in
        root) [ "$3" = --prefix ] && echo "$4/lib/node_modules" || echo "$HOME/g/lib/node_modules" ;;
        uninstall) [ -z "${NPM_UNINSTALL_FAIL-}" ] ;;
    esac
}'

@test "remove_stale_npm_opencode: checks and removes both global and ~/.local prefixes" {
    mkdir -p "$HOME/g/lib/node_modules/opencode-ai" "$HOME/.local/lib/node_modules/opencode-ai"
    run_opencode_tool "$_npm_root_stub; remove_stale_npm_opencode"
    assert_success
    run cat "$HOME/calls"
    assert_line "root -g"
    assert_line "uninstall -g opencode-ai"
    assert_line "root -g --prefix $HOME/.local"
    assert_line "uninstall -g --prefix $HOME/.local opencode-ai"
}

@test "remove_stale_npm_opencode: skips prefixes without opencode-ai" {
    mkdir -p "$HOME/.local/lib/node_modules/opencode-ai"
    run_opencode_tool "$_npm_root_stub; remove_stale_npm_opencode"
    assert_success
    run cat "$HOME/calls"
    refute_line "uninstall -g opencode-ai"
    assert_line "uninstall -g --prefix $HOME/.local opencode-ai"
}

@test "remove_stale_npm_opencode: uninstall failure only warns and continues" {
    mkdir -p "$HOME/g/lib/node_modules/opencode-ai" "$HOME/.local/lib/node_modules/opencode-ai"
    run_opencode_tool "
        export NPM_UNINSTALL_FAIL=1
        $_npm_root_stub
        remove_stale_npm_opencode
    "
    assert_success
    assert_output --partial "Could not remove npm opencode-ai"
    run grep -c '^uninstall' "$HOME/calls"
    assert_output "2"
}

# --- integrations/opencode.sh: uninstall + alias (#2419) -----------------------

_opencode_integration() {
    local shell="$1" body="$2"
    run "$shell" -c "
        export HOME='$HOME' TERM=dumb DOTFILES_FORCE_INIT=1
        export DOTFILES_ROOT='$DOTFILES_ROOT' SHELL_COMMON='$DOTFILES_ROOT/shell-common'
        . '$DOTFILES_ROOT/shell-common/tools/ux_lib/ux_lib.sh'
        . '$DOTFILES_ROOT/shell-common/tools/integrations/opencode.sh'
        $body
    "
}

_npm_stub_on_path() {
    mkdir -p "$HOME/stub"
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/calls"\n[ "$1" = root ] && echo "%s/stubroot"\nexit 0\n' "$HOME" "$HOME" > "$HOME/stub/npm"
    mkdir -p "$HOME/stubroot/opencode-ai"
    chmod +x "$HOME/stub/npm"
}

@test "uninstall_opencode: removes ~/.opencode and npm leftovers in both prefixes" {
    _npm_stub_on_path
    mkdir -p "$HOME/.opencode/bin"
    _opencode_integration bash "export PATH='$HOME/stub':\"\$PATH\"; printf 'y\n' | uninstall_opencode"
    assert_success
    [ ! -d "$HOME/.opencode" ]
    run cat "$HOME/calls"
    assert_line "uninstall -g opencode-ai"
    assert_line "uninstall -g --prefix $HOME/.local opencode-ai"
}

@test "uninstall_opencode: continues without npm" {
    mkdir -p "$HOME/.opencode/bin" "$HOME/nonpm"
    ln -s "$(command -v dirname)" "$HOME/nonpm/dirname"
    ln -s "$(command -v readlink)" "$HOME/nonpm/readlink"
    ln -s "$(command -v rm)" "$HOME/nonpm/rm"
    _opencode_integration bash "export PATH='$HOME/nonpm'; printf 'y\n' | uninstall_opencode"
    assert_success
    assert_output --partial "npm not found"
    assert_output --partial "OpenCode Uninstallation Complete"
    [ ! -d "$HOME/.opencode" ]
}

@test "update-opencode alias loads and runs update mode in bash and zsh" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
    for sh in bash zsh; do
        _opencode_integration "$sh" "
            alias update-opencode
            bash() { printf 'bash-args:%s\n' \"\$*\"; }
            update_opencode
        "
        assert_success
        assert_output --partial "update-opencode="
        assert_output --partial "tools/custom/install_opencode.sh update"
    done
}
