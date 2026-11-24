#!/bin/bash

# gh/setup.sh: GitHub CLI configuration setup
#
# PURPOSE: Set up gh CLI configuration symlinks
# WHEN TO RUN: Via ./setup.sh (do NOT run manually)
#
# SPECIAL FEATURES:
#   1. Creates ~/.config/gh/config.yml symlink to gh/config.yml
#   2. gh aliases (e.g. `gh postponed`) are version-controlled via this file
#   3. internal mode: guides `gh auth login --insecure-storage` per host
#      lacking a plaintext token in hosts.yml (never symlinked, #2428)

DOTFILES_GH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GH_CONFIG_SOURCE="${DOTFILES_GH_DIR}/config.yml"
GH_CONFIG_DIR="${HOME}/.config/gh"
GH_CONFIG_TARGET="${GH_CONFIG_DIR}/config.yml"

UX_LIB_SCRIPT="${DOTFILES_GH_DIR}/../shell-common/tools/ux_lib/ux_lib.sh"

if [[ -f "${UX_LIB_SCRIPT}" ]]; then
    source "${UX_LIB_SCRIPT}"
else
    echo "CRITICAL ERROR: UX library script not found at ${UX_LIB_SCRIPT}. Exiting." >&2
    exit 1
fi

SHELL_COMMON="$(cd "${DOTFILES_GH_DIR}/.." && pwd)/shell-common"
# shellcheck source=../shell-common/lib/setup/link.sh
. "${SHELL_COMMON}/lib/setup/link.sh" || exit 1

ux_header "GitHub CLI (gh) dotfiles setup 시작"

# Same link -> no-op; real file -> backed up to config.yml.original (#806, #2138).
dotfiles_ensure_link "$GH_CONFIG_SOURCE" "$GH_CONFIG_TARGET" || exit 1
if [ -L "$GH_CONFIG_TARGET" ]; then ux_success "심볼릭 링크: $GH_CONFIG_TARGET -> $GH_CONFIG_SOURCE"; fi

# _gh_hosts_has_token <host> — true when hosts.yml stores a non-empty
# plaintext oauth_token gh uses for <host>: the host-level one, or the one
# under users.<active user> (any user's when no `user:` line names one), so
# an inactive account's token never hides a keyring-backed active account.
# Quoted-empty, null and ~ values count as empty. Never prints the token.
_gh_hosts_has_token() {
    [ -f "${GH_CONFIG_DIR}/hosts.yml" ] || return 1
    awk -v h="$1:" '
        function filled(v) { return v != "" && v != "\"\"" && v != "'"''"'" && v != "null" && v != "~" && v !~ /^#/ }
        /^[^[:space:]#]/ { in_host = ($1 == h); hind = 0; next }
        !in_host || /^[[:space:]]*(#|$)/ { next }
        {
            ind = match($0, /[^ ]/) - 1
            if (!hind) hind = ind
            if (ind == hind) {
                in_users = ($1 == "users:")
                if ($1 == "oauth_token:" && filled($2)) top = 1
                if ($1 == "user:") active = $2
            } else if (in_users) {
                if ($1 == "oauth_token:") { if (filled($2)) tok[name] = 1 }
                else if ($2 == "") name = substr($1, 1, length($1) - 1)
            }
        }
        END {
            if (top) exit 0
            if (active != "") exit !(active in tok)
            for (n in tok) exit 0
            exit 1
        }
    ' "${GH_CONFIG_DIR}/hosts.yml"
}

# Internal PC (#2428): gh stores tokens in GNOME Keyring when it is installed,
# and WSL never unlocks the keyring at login, so the first gh call after a
# reboot (e.g. the issue-watcher cron) pops up "Unlock Keyring". hosts.yml
# holds per-PC tokens, so it is never symlinked into this repo: only guide
# the one-time plaintext login per host. Guidance never changes the exit code.
# One ux_warning line per host: ./setup.sh summary mode surfaces only warning
# lines from $STEP_LOG, so the command itself must be on that line.
# shellcheck source=../shell-common/lib/gh_host.sh
. "${SHELL_COMMON}/lib/gh_host.sh"
if [ "$(_dotfiles_setup_mode)" = internal ] && command -v gh >/dev/null 2>&1; then
    for _gh_host in "$(_gh_ghes_host)" github.com; do
        # GHES name comes from the gitignored internal.local.sh (#1965).
        [ -n "$_gh_host" ] || _gh_host="<GHES host>"
        _gh_hosts_has_token "$_gh_host" && continue
        ux_warning "${_gh_host} 토큰이 hosts.yml 에 없음 (keyring 은 재부팅 후 Unlock Keyring 팝업) — 1회 실행: gh auth login -h ${_gh_host} --insecure-storage (토큰은 ${GH_CONFIG_DIR}/hosts.yml 에 0600 평문 저장)"
    done
    unset _gh_host
fi

ux_success "GitHub CLI (gh) dotfiles setup 완료"
exit 0
