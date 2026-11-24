#!/bin/bash
# Shared management entry point for Claude Code, OpenCode and Hermes Agent.
# Run only as a direct-exec script, never when sourced.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
set -e
source "$(dirname "$0")/init.sh" || exit 1
. "$(dirname "$0")/lib/install_helpers.sh" || exit 1

if [ "$#" = 1 ]; then
    case "$1" in
        -h|--help|help)
            ux_info "Usage: ai_cli_manage.sh <claude|opencode|hermes> <status|install|update|uninstall> [options]"
            exit 0 ;;
    esac
fi
if [ "$#" -lt 2 ]; then
    ux_error "Usage: ai_cli_manage.sh <claude|opencode|hermes> <status|install|update|uninstall> [options]"
    exit 2
fi
tool=$1
action=$2
shift 2
case "$tool" in
    claude)
        label="Claude Code"; bin="$HOME/.local/bin/claude"
        root="$HOME/.local/share/claude"; url="${CLAUDE_INSTALL_URL:-https://claude.ai/install.sh}" ;;
    opencode)
        label="OpenCode"; bin="$HOME/.opencode/bin/opencode"
        root="$HOME/.opencode/bin"; url="${OPENCODE_INSTALL_URL:-https://opencode.ai/install}" ;;
    hermes)
        label="Hermes Agent"; bin="$HOME/.local/bin/hermes"
        root="${HERMES_HOME:-$HOME/.hermes}/hermes-agent"; url="${HERMES_INSTALL_URL:-https://hermes-agent.nousresearch.com/install.sh}" ;;
    *) ux_error "Unknown tool: $tool"; exit 2 ;;
esac

usage() {
    ux_info "Usage: $tool-$action [--help] [--dry-run] [-y|--yes]"
    ux_bullet "status reports the active executable and installation method."
    ux_bullet "install/update use the official installer; uninstall preserves user data."
    ux_bullet "--dry-run previews changes without network access. -y skips confirmation."
    ux_bullet "Override installer URL with CLAUDE_INSTALL_URL, OPENCODE_INSTALL_URL or HERMES_INSTALL_URL; use trusted sources only."
    [ "$tool:$action" != opencode:uninstall ] || ux_bullet "--purge-config also removes the OpenCode config directory."
}
dry=0
yes=0
purge_config=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help|help) usage; exit 0 ;;
        --dry-run) dry=1 ;;
        -y|--yes) yes=1 ;;
        --purge-config)
            if [ "$tool" != opencode ] || [ "$action" != uninstall ]; then
                ux_error "--purge-config is only supported by opencode-uninstall."
                exit 2
            fi
            purge_config=1 ;;
        *) ux_error "Unknown argument: $1"; usage; exit 2 ;;
    esac
    shift
done

canonical_path() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"
    else
        readlink -f "$1" 2>/dev/null || readlink "$1" 2>/dev/null || printf '%s\n' "$1"
    fi
}

classify() {
    local path="$1" resolved
    if [ "$tool" = hermes ] && [ "$path" = "$bin" ] && [ ! -L "$path" ] &&
        [ -f "$path" ] && [ -x "$root/.hermes/bin/hermes" ] &&
        [ "$(wc -l < "$path")" -eq 2 ] &&
        [ "$(head -n 1 "$path")" = '#!/bin/sh' ] &&
        [ "$(tail -n 1 "$path")" = "exec $root/.hermes/bin/hermes \"\$@\"" ]; then
        printf 'official-source\n'
        return
    fi
    resolved=$(canonical_path "$path")
    case "$resolved" in
        */node_modules/@anthropic-ai/claude-code/*) [ "$tool" = claude ] && printf 'npm\n' || printf 'unknown\n' ;;
        */node_modules/opencode-ai/*|*/node_modules/@opencode/cli/*) [ "$tool" = opencode ] && printf 'npm\n' || printf 'unknown\n' ;;
        "$HOME/.local/share/claude/versions/"*) [ "$tool" = claude ] && printf 'standalone\n' || printf 'unknown\n' ;;
        "$HOME/.opencode/bin/opencode") [ "$tool" = opencode ] && printf 'standalone\n' || printf 'unknown\n' ;;
        "$root/"*) [ "$tool" = hermes ] && printf 'official-source\n' || printf 'unknown\n' ;;
        *) printf 'unknown\n' ;;
    esac
}

status() {
    local active candidate method version found=0 seen=""
    active=$(type -P "$tool" || true)
    ux_header "$label Status"
    if [ -n "$active" ]; then
        method=$(classify "$active")
        if version=$("$active" --version 2>/dev/null); then
            ux_success "$label installed"
            ux_table_row "Version" "$version" ""
        else
            ux_warning "$label executable is not runnable"
        fi
        ux_table_row "Location" "$active" ""
        ux_table_row "Install method" "$method" ""
        found=1
    else
        ux_warning "$label not found on PATH"
    fi
    ux_table_row "Managed path" "$root" ""
    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        case ":$seen:" in *":$candidate:"*) continue ;; esac
        seen="${seen:+$seen:}$candidate"
        if [ "$candidate" != "$active" ]; then
            ux_warning "Additional PATH installation: $candidate ($(classify "$candidate"))"
        fi
    done < <(type -aP "$tool" 2>/dev/null || true)
    if [ -e "$bin" ] || [ -L "$bin" ]; then
        if [ ! -x "$bin" ]; then
            ux_warning "Managed executable is missing or not executable: $bin"
        fi
        candidate=$(classify "$bin")
        if [ "$bin" != "$active" ]; then
            ux_warning "Additional installation: $bin ($candidate)"
        fi
        found=1
    fi
    [ "$found" = 1 ]
}

confirm() {
    [ "$yes" = 1 ] && return 0
    if [ ! -t 0 ]; then
        ux_error "Confirmation requires a terminal; use -y to accept the displayed action."
        return 1
    fi
    ux_confirm "$1" "n"
}

case "$action" in
    status) status ;;
    install|update)
        ux_header "$label ${action}"
        ux_info "Official installer: $url"
        ux_info "Expected executable: $bin"
        if [ "$dry" = 1 ]; then
            active=$(type -P "$tool" || true)
            if [ -n "$active" ]; then
                method=$(classify "$active")
                ux_info "[dry-run] Active executable: $active ($method)"
                if [ "$method" = npm ]; then
                    ux_info "[dry-run] After confirmation, install and verify before removing the matching npm package."
                elif [ "$method" = unknown ]; then
                    ux_warning "[dry-run] Unknown ownership must be resolved before installation."
                fi
            fi
            ux_info "[dry-run] Download and run installer, then verify $bin --version."
            exit 0
        fi
        active=$(type -P "$tool" || true)
        npm_package=""
        if [ -n "$active" ]; then
            case "$(classify "$active")" in
                npm)
                    case "$tool" in
                        claude) npm_package='@anthropic-ai/claude-code' ;;
                        opencode)
                            case "$(canonical_path "$active")" in
                                */node_modules/@opencode/cli/*) npm_package='@opencode/cli' ;;
                                *) npm_package='opencode-ai' ;;
                            esac ;;
                        *) ux_error "Unsupported npm installation: $active"; exit 1 ;;
                    esac
                    if [ "$active" = "$bin" ]; then
                        ux_error "The npm executable occupies $bin; migrate manually to avoid overwriting it."
                        exit 1
                    fi
                    npm_prefix=$(npm prefix -g 2>/dev/null) || { ux_error "Cannot locate npm global prefix."; exit 1; }
                    if [ "$npm_prefix/bin/$tool" = "$bin" ]; then
                        ux_error "The npm prefix owns $bin; migrate manually to avoid overwriting it."
                        exit 1
                    fi
                    npm_root=$(npm root -g 2>/dev/null) || { ux_error "Cannot locate npm global root."; exit 1; }
                    active_resolved=$(canonical_path "$active")
                    [ -d "$npm_root/$npm_package" ] || { ux_error "npm package directory is missing."; exit 1; }
                    package_root=$(canonical_path "$npm_root/$npm_package")
                    case "$active_resolved" in
                        "$package_root"/*) [ -n "$package_root" ] || exit 1 ;;
                        *) ux_error "The active npm installation is not in the default global root; migrate it manually."; exit 1 ;;
                    esac
                    ux_info "After a successful installation, remove npm package: $npm_package"
                    ;;
                standalone|official-source) ;;
                *) ux_error "Existing installation has unknown ownership: $active. Use its package manager."; exit 1 ;;
            esac
        fi
        if [ -e "$bin" ] || [ -L "$bin" ]; then
            case "$(classify "$bin")" in
                standalone|official-source) ;;
                *) ux_error "Cannot establish ownership of $bin; use its package manager."; exit 1 ;;
            esac
        fi
        confirm "Run the official $label installer?" || exit 1
        if [ "$tool" = opencode ]; then
            PATH="$HOME/.opencode/bin:$HOME/.local/bin:$PATH" run_remote_installer "$url" --no-modify-path || { ux_error "Installer failed; check the network, proxy or approved mirror."; exit 1; }
        elif [ "$tool" = hermes ] && [ "$yes" = 1 ]; then
            PATH="$HOME/.local/bin:$PATH" run_remote_installer "$url" --non-interactive || { ux_error "Installer failed; check the network, proxy or approved mirror."; exit 1; }
        else
            PATH="$HOME/.local/bin:$PATH" run_remote_installer "$url" || { ux_error "Installer failed; check the network, proxy or approved mirror."; exit 1; }
        fi
        version=$(verify_installed_binary "$bin" 2>&1) || { ux_error "Installed executable is not runnable: $bin"; exit 1; }
        if [ -n "$npm_package" ]; then
            npm uninstall -g "$npm_package" || { ux_error "Standalone installed but npm cleanup failed."; exit 1; }
        fi
        if [ "$tool" = hermes ]; then
            # The pinned Python can be replaced by an update; restore the
            # existing corporate TLS workaround without re-running full setup.
            ca_configured="${SSL_CERT_FILE:-${HERMES_CORP_CA_CERT:-}}"
            security_local="$SHELL_COMMON/env/security.local.sh"
            if [ -z "$ca_configured" ] && [ -z "${DOTFILES_SKIP_LOCAL_ENV-}" ] && [ -f "$security_local" ]; then
                ca_configured=$(DOTFILES_FORCE_INIT=1 sh -c '. "$1" >/dev/null 2>&1; printf "%s" "${CA_CERT:-}"' _ "$security_local")
            fi
            if [ -n "$ca_configured" ]; then
                for lib_dir in "${HERMES_HOME:-$HOME/.hermes}"/tools/python-*/lib/python3.*; do
                    [ -d "$lib_dir" ] || continue
                    cp "$DOTFILES_ROOT/hermes/sitecustomize.py" "$lib_dir/sitecustomize.py" || {
                        ux_error "Could not restore Hermes TLS workaround: $lib_dir"
                        exit 1
                    }
                done
            fi
        fi
        ux_success "$label installed: $version"
        ;;
    uninstall)
        ux_header "$label Uninstaller"
        if [ "$purge_config" = 0 ]; then
            ux_info "User configuration, authentication, sessions and skills are preserved."
        else
            ux_info "Authentication, sessions and skills are preserved; OpenCode configuration will be removed."
        fi
        have_bin=0
        if [ -e "$bin" ] || [ -L "$bin" ]; then
            have_bin=1
            method=$(classify "$bin")
            case "$method" in standalone|official-source) ;; *) ux_error "Ownership unknown for $bin; use its package manager."; exit 1 ;; esac
        else
            ux_info "No managed executable at $bin."
        fi
        if [ "$have_bin" = 0 ] && [ "$purge_config" = 0 ]; then
            active=$(type -P "$tool" || true)
            if [ -n "$active" ]; then
                ux_warning "Another installation remains: $active ($(classify "$active")); use its package manager."
                exit 1
            fi
            exit 0
        fi
        if [ "$tool" = claude ] && [ -L "$root" ]; then
            ux_error "Refusing to remove versions through a symlinked installation directory: $root"
            exit 1
        fi
        [ "$have_bin" = 0 ] || ux_info "Remove executable: $bin"
        config_dir="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
        config_file="${OPENCODE_CONFIG_FILE:-$config_dir/opencode.json}"
        config_target="$config_dir"
        [ ! -L "$config_file" ] || config_target="$config_file"
        if [ "$purge_config" = 1 ]; then
            if [ -L "$(dirname "$config_target")" ]; then
                ux_error "Refusing to remove configuration through a symlinked directory."
                exit 1
            fi
            ux_warning "Remove OpenCode configuration: $config_target"
        fi
        case "$tool" in
            claude) ux_info "Remove versioned binaries: $root/versions" ;;
            opencode) [ "$have_bin" = 0 ] || ux_info "Remove installation directory if empty: $root" ;;
            hermes)
                case "$root" in "$HOME/"*) ;; *) ux_error "Hermes installation is outside the home directory: $root"; exit 1 ;; esac
                if [ -L "${HERMES_HOME:-$HOME/.hermes}" ] || [ -L "$root" ] || [ -L "$root/.git" ] || [ ! -d "$root/.git" ]; then
                    ux_error "Cannot verify ownership of Hermes source directory: $root"
                    exit 1
                fi
                remote=$(GIT_DIR="$root/.git" GIT_WORK_TREE="$root" GIT_OPTIONAL_LOCKS=0 git -C "$root" remote get-url origin 2>/dev/null | tr '[:upper:]' '[:lower:]') || {
                    ux_error "Cannot verify Hermes source remote."
                    exit 1
                }
                case "$remote" in
                    https://github.com/nousresearch/hermes-agent|https://github.com/nousresearch/hermes-agent.git|git@github.com:nousresearch/hermes-agent|git@github.com:nousresearch/hermes-agent.git) ;;
                    *) ux_error "Unrecognized Hermes source remote; remove it manually."; exit 1 ;;
                esac
                changes=$(GIT_DIR="$root/.git" GIT_WORK_TREE="$root" GIT_OPTIONAL_LOCKS=0 git -C "$root" status --porcelain --untracked-files=normal 2>/dev/null) || {
                    ux_error "Cannot inspect Hermes source changes."
                    exit 1
                }
                if [ -n "$changes" ]; then
                    ux_error "Hermes source has local changes; preserve or remove them manually."
                    exit 1
                fi
                ux_info "Remove verified Hermes source and runtime: $root"
                ;;
        esac
        [ "$dry" = 1 ] && exit 0
        confirm "Remove the displayed $label installation?" || exit 1
        [ "$have_bin" = 0 ] || rm -f -- "$bin"
        if [ "$tool" = opencode ] && [ "$have_bin" = 1 ] && [ ! -L "$root" ]; then
            # Only remove an empty installer directory; unknown files stay.
            rmdir -- "$root" 2>/dev/null || :
        fi
        if [ "$tool" = hermes ]; then
            rm -rf -- "$root"
        fi
        if [ "$purge_config" = 1 ] && { [ -e "$config_target" ] || [ -L "$config_target" ]; }; then
            rm -rf -- "$config_target"
        fi
        if [ "$tool" = claude ] && [ -d "$root/versions" ] && [ ! -L "$root/versions" ]; then
            rm -rf -- "$root/versions"
        fi
        ux_success "$label executable removed."
        ;;
    *) ux_error "Unknown action: $action"; exit 2 ;;
esac

fi
