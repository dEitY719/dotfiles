#!/bin/sh
# shellcheck shell=bash
# shellcheck disable=SC2034  # SETUP_* are read by setup.sh's main and hint fn
# shell-common/lib/setup/bootstrap.sh — the gate steps of root ./setup.sh (#2343)
#
# Claude Code install, prerequisite table, auth/key check, skills clone and
# plugin restore. bash only (arrays), explicit source only, defines functions
# and prints nothing at source time. Relies on setup.sh's $DOTFILES_DIR and on
# ux_lib. Steps run with their output captured, so nothing here may prompt or
# call sudo: what needs a human is collected in SETUP_FIXES and printed by
# setup.sh's hint function.
#
# Gate level: public PCs stop on a missing item (critical); internal/external
# PCs get a notice and carry on, because the install routes on those networks
# are unconfirmed and a working PC must not start failing (#2343 open question).

SETUP_MODE=""
SETUP_GATE_LEVEL=notice
SETUP_CLAUDE_STATE=present
SETUP_FIXES=()

# Prerequisite SSOT: name|kind|installer|manual command
#   pkg     system package (needs sudo): printed, never run; column 3 = package
#   locale  system locale (needs sudo): printed, never run
#   auto    no sudo: installer function runs on public PCs; column 4 is the
#           command printed when it fails or is not run
_setup_prereq_table() {
    cat <<'TABLE'
zsh|pkg|zsh|
en_US.UTF-8|locale||
jq|pkg|jq|
gh|pkg|gh|
socat|pkg|socat|
mise|auto|_setup_install_mise|curl https://mise.run | sh
uv|auto|_setup_install_uv|./shell-common/tools/custom/install_uv.sh --yes
sops|auto|_setup_install_sops_age|./shell-common/tools/custom/install_sops_age.sh
age|auto|_setup_install_sops_age|./shell-common/tools/custom/install_sops_age.sh
TABLE
}

_setup_resolve_gate() {
    case "${SETUP_CHOICE:-}" in
    1) SETUP_MODE=public ;;
    2) SETUP_MODE=internal ;;
    3) SETUP_MODE=external ;;
    *) SETUP_MODE=$(_dotfiles_setup_mode) || SETUP_MODE="" ;; # verbose path: the menu saved it
    esac
    SETUP_GATE_LEVEL=notice
    if [ "$SETUP_MODE" = public ]; then SETUP_GATE_LEVEL=critical; fi
}

# ~/.local/bin and the mise shims stay on PATH for this run only: a tool mise
# installed must not read as missing just because no shell rc activated it yet.
_setup_extend_path() {
    local dir shims="${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}/shims"
    for dir in "$HOME/.local/bin" "$shims"; do
        case ":$PATH:" in *":$dir:"*) continue ;; esac
        if [ -d "$dir" ]; then PATH="$PATH:$dir"; fi
    done
    export PATH
}

# Print the tool's path, or fail. `mise which` runs from $HOME: inside the repo
# an untrusted mise.toml could prompt.
_setup_find_tool() {
    local found
    _setup_extend_path
    if type -P "$1"; then return 0; fi
    type -P mise >/dev/null || return 1
    found=$(cd "$HOME" && mise which "$1" </dev/null 2>/dev/null) || return 1
    [ -n "$found" ] || return 1
    PATH="$PATH:${found%/*}"
    export PATH
    printf '%s\n' "$found"
}

_setup_has_locale() {
    locale -a 2>/dev/null | grep -Eqi "^${1%%.*}\.utf-?8$"
}

# Print the install command of a system package for this PC's package manager.
_setup_pkg_cmd() {
    if type -P apt-get >/dev/null; then
        printf 'sudo apt install -y %s\n' "$1"
    elif type -P dnf >/dev/null; then
        printf 'sudo dnf install -y %s\n' "$1"
    elif type -P yum >/dev/null; then
        printf 'sudo yum install -y %s\n' "$1"
    elif type -P pacman >/dev/null; then
        printf 'sudo pacman -S --noconfirm %s\n' "$1"
    elif type -P brew >/dev/null; then
        printf 'brew install %s\n' "$1"
    else
        printf 'sudo apt install -y %s\n' "$1"
    fi
}

_setup_locale_cmd() {
    printf 'sudo apt install -y locales && sudo locale-gen %s\n' "$1"
}

_setup_install_mise() {
    # shellcheck source=shell-common/tools/custom/lib/install_helpers.sh
    . "${DOTFILES_DIR}/shell-common/tools/custom/lib/install_helpers.sh" &&
        run_remote_installer https://mise.run
}

_setup_install_uv() {
    "${DOTFILES_DIR}/shell-common/tools/custom/install_uv.sh" --yes
}

_setup_install_sops_age() {
    "${DOTFILES_DIR}/shell-common/tools/custom/install_sops_age.sh"
}

# Prints every missing item at once (F-5): SETUP_FIXES holds one
# "<name>: <command>" per item, whatever was not fixed by an auto install.
_setup_prereq_check() {
    local name kind arg manual
    SETUP_FIXES=()
    while IFS='|' read -r name kind arg manual; do
        case "$kind" in
        locale)
            if ! _setup_has_locale "$name"; then
                SETUP_FIXES+=("$name: $(_setup_locale_cmd "$name")")
            fi
            ;;
        pkg)
            if ! _setup_find_tool "$name" >/dev/null; then
                SETUP_FIXES+=("$name: $(_setup_pkg_cmd "$arg")")
            fi
            ;;
        auto)
            if _setup_find_tool "$name" >/dev/null; then continue; fi
            if [ "$SETUP_GATE_LEVEL" = critical ]; then
                ux_info "$name 자동 설치"
                "$arg" </dev/null || true
                if _setup_find_tool "$name" >/dev/null; then continue; fi
            fi
            SETUP_FIXES+=("$name: $manual")
            ;;
        esac
    done < <(_setup_prereq_table)
    [ ${#SETUP_FIXES[@]} -eq 0 ]
}

# Never prints the token. `gh auth status` is the fallback for a gh without
# `auth token`; no version gate on purpose (#2343 open question).
_setup_gh_logged_in() {
    gh auth token >/dev/null 2>&1 </dev/null || gh auth status >/dev/null 2>&1 </dev/null
}

_setup_age_key_file() {
    printf '%s\n' "${SOPS_AGE_KEY_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/sops/age/keys.txt}"
}

_setup_auth_check() {
    local key
    key=$(_setup_age_key_file)
    SETUP_FIXES=()
    if ! _setup_find_tool gh >/dev/null || ! _setup_gh_logged_in; then
        SETUP_FIXES+=("gh 로그인: gh auth login")
    fi
    if [ ! -s "$key" ]; then
        SETUP_FIXES+=("age 키: 기존 PC 의 keys.txt 를 scp 나 USB 로 $key 에 복사한 뒤 chmod 600 $key")
        SETUP_FIXES+=("age 키 절차: sops-help setup")
    fi
    [ ${#SETUP_FIXES[@]} -eq 0 ]
}

# proxy.sh / security.sh load what the shell-common step just configured.
# Subshell: later steps keep the environment they always ran with.
_setup_run_claude_installer() {
    (
        # shellcheck disable=SC2030  # subshell-local on purpose (see above)
        export SHELL_COMMON="${DOTFILES_DIR}/shell-common" DOTFILES_FORCE_INIT=1
        # shellcheck source=shell-common/env/proxy.sh
        . "${SHELL_COMMON}/env/proxy.sh" || true
        # shellcheck source=shell-common/env/security.sh
        . "${SHELL_COMMON}/env/security.sh" || true
        "${DOTFILES_DIR}/shell-common/tools/custom/install_claude.sh" --yes
    ) </dev/null
}

# internal PCs never fetch the claude.ai installer (#2343 open question): the
# manual route is printed instead.
_setup_ensure_claude() {
    SETUP_CLAUDE_STATE=present
    if _setup_find_tool claude >/dev/null; then return 0; fi
    if [ "$SETUP_MODE" = internal ]; then
        SETUP_CLAUDE_STATE=manual
        return 1
    fi
    if _setup_run_claude_installer && _setup_find_tool claude >/dev/null; then
        SETUP_CLAUDE_STATE=installed
        return 0
    fi
    SETUP_CLAUDE_STATE=failed
    return 1
}

_setup_hint_claude() {
    if [ "$SETUP_CLAUDE_STATE" = manual ]; then
        ux_bullet_sub "internal PC 는 claude.ai 설치 프로그램을 자동으로 실행하지 않습니다"
        ux_bullet_sub "사내 절차로 Claude Code 를 설치한 뒤 ./setup.sh 를 다시 실행하세요"
        ux_bullet_sub "프록시, CA 안내: proxy-help, ssl-help"
        return 0
    fi
    ux_bullet_sub "네트워크 확인: curl -I https://claude.ai (curl 이 없으면 $(_setup_pkg_cmd curl))"
    ux_bullet_sub "프록시 확인: echo \$https_proxy, proxy-help"
    ux_bullet_sub "CA 확인: echo \$SSL_CERT_FILE, ssl-help"
}

_setup_claude_next_steps() {
    if [ "$SETUP_CLAUDE_STATE" != installed ]; then return 0; fi
    ux_info "Claude Code 설치 완료: 다른 터미널에서 claude 로 대화하며 나머지 단계를 진행할 수 있습니다"
    ux_info "다중 계정 PC 는 ./setup.sh 가 끝난 뒤 로그인하면 계정 폴더가 준비된 상태에서 시작합니다"
}

_setup_has_vscode() {
    type -P code >/dev/null || [ -d "$HOME/.config/Code/User" ] ||
        [ -d "$HOME/Library/Application Support/Code/User" ]
}

# GIT_TERMINAL_PROMPT / BatchMode: a credential or host-key prompt would wait
# unseen in summary mode.
_setup_clone_skills() {
    GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes}" \
        "${DOTFILES_DIR}/claude/plugin/git-clone-skills.sh" </dev/null
}

# Print the tracked manifest's plugins the target config dir lacks, minus local
# tombstones. Same target dir as restore.sh's default.
_setup_plugins_missing() {
    local plugin_dir="${DOTFILES_DIR}/claude/plugin" cfg="$HOME/.claude-${CLAUDE_DEFAULT_ACCOUNT:-personal}"
    local want have gone
    if [ "$SETUP_MODE" = internal ]; then cfg="$HOME/.claude"; fi
    # shellcheck source=shell-common/lib/claude_plugin_manifest.sh
    . "${DOTFILES_DIR}/shell-common/lib/claude_plugin_manifest.sh" || return 1
    want=$(_claude_plugin_read_json_or "$plugin_dir/plugins.json" '{}')
    have=$(_claude_plugin_read_json_or "$cfg/plugins/installed_plugins.json" '{}')
    gone=$(_claude_plugin_read_json_or "$plugin_dir/removed.local.json" '{}')
    jq -rn --argjson want "$want" --argjson have "$have" --argjson gone "$gone" '
        (($want.plugins // []) - ($gone.plugins // []) - (($have.plugins // {}) | keys))
        | map(select((split("@") | last) as $m | ($gone.marketplaces // []) | index($m) | not))
        | .[]'
}

# restore.sh re-adds every entry and rewrites the plugin store even with nothing
# to do, and exits 0 on per-item failures, so it runs only on a gap and the gap
# is checked again afterwards. No gap: no claude call, no file change.
_setup_restore_plugins() {
    local missing
    SETUP_FIXES=("플러그인 복원: ./claude/plugin/restore.sh")
    _setup_find_tool claude >/dev/null || return 1
    _setup_find_tool jq >/dev/null || return 1
    missing=$(_setup_plugins_missing) || return 1
    if [ -z "$missing" ]; then return 0; fi
    SHELL_COMMON="${DOTFILES_DIR}/shell-common" "${DOTFILES_DIR}/claude/plugin/restore.sh" </dev/null || return 1
    missing=$(_setup_plugins_missing) || return 1
    [ -z "$missing" ]
}
