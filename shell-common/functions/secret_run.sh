#!/bin/sh
# shell-common/functions/secret_run.sh
# Inject the dotfiles repo's .enc.env values into one command (issue #2096).
#
# `senv run` reads $PWD/.enc.env. This reads $DOTFILES_ROOT/.enc.env instead,
# so the caller's cwd never changes. The decrypted text lives only in a shell
# variable and is exported in a subshell right before exec (same loop as
# `senv run`: _senv_export_lines in tools/integrations/sops.sh). No plaintext
# file, no eval, no echo. Any failure warns and runs the command without the
# values, so a PC without the age key keeps working (NF-1).
#
# Keys are never loaded into the interactive shell itself: only the wrapped
# command and its children see them.
#
# Details: sops-help secrets

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# Repo-wide ciphertext. DOTFILES_ENC_ENV overrides it (tests, other repos).
_dotfiles_enc_env() {
    printf '%s' "${DOTFILES_ENC_ENV:-${DOTFILES_ROOT:-$HOME/dotfiles}/.enc.env}"
}

# Print the decrypted dotenv text on stdout, for capture into a variable only.
# Every failure prints a warning on stderr and returns 1.
_dotfiles_secret_decrypt() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local enc key mode
    enc=$(_dotfiles_enc_env)
    if ! command -v sops >/dev/null 2>&1; then
        ux_warning "sops not installed; .enc.env values not loaded (install-sops-age)" >&2
        return 1
    fi
    if [ ! -f "$enc" ]; then
        ux_warning ".enc.env not found: ${enc}" >&2
        return 1
    fi
    key=$(_senv_key_file)
    if [ ! -f "$key" ]; then
        ux_warning "age key not found: ${key}; .enc.env values not loaded" >&2
        ux_info "Next: senv key import" >&2
        return 1
    fi
    mode=$(_sops_file_mode "$key")
    if [ "$mode" != "600" ]; then
        ux_warning "age key mode ${mode:-unknown}, expected 600; .enc.env values not loaded" >&2
        ux_info "Fix: chmod 600 ${key}" >&2
        return 1
    fi
    if ! sops -d --input-type dotenv --output-type dotenv "$enc" 2>/dev/null; then
        ux_warning "sops could not decrypt ${enc}; values not loaded" >&2
        ux_info "Check: cd ${enc%/*} && senv check" >&2
        return 1
    fi
}

# dotfiles_secret_run [-k KEY]... <cmd...>
# -k limits the injected keys (repeatable); without it every key is injected.
dotfiles_secret_run() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local only="" plain
    while [ "${1-}" = "-k" ]; do
        if [ -z "${2-}" ]; then
            ux_error "-k needs a key name"
            return 2
        fi
        only="${only} $2"
        shift 2
    done
    if [ $# -eq 0 ]; then
        ux_error "secret-run needs a command"
        ux_info "Usage: secret-run [-k KEY]... <cmd...>   (example: secret-run -k EXA_API_KEY mcporter list)"
        return 2
    fi
    if plain=$(_dotfiles_secret_decrypt); then
        (
            _senv_export_lines "$plain" "$only"
            unset plain
            exec "$@"
        )
    else
        ux_warning "running $1 without .enc.env values" >&2
        (exec "$@")
    fi
}

alias secret-run='dotfiles_secret_run'

# Consumers. Each gets only the keys it needs, so an MCP server spawned by
# mcporter never sees the Twitter cookies.
# mcporter.json reads the key as ${EXA_API_KEY:-} (mcporter 0.14 expands it;
# see mcporter_exa_setup), so the key is never stored in plaintext.
# Defined only when the CLI is installed, so `command -v` keeps meaning
# "installed". Being shell functions, they are bypassed by anything that execs
# the binary directly (cron, xargs, timeout): use secret-run there.
if command -v mcporter >/dev/null 2>&1; then
    mcporter() { dotfiles_secret_run -k EXA_API_KEY mcporter "$@"; }
fi
# twitter-cli reads TWITTER_AUTH_TOKEN / TWITTER_CT0 from the environment.
if command -v twitter >/dev/null 2>&1; then
    twitter() { dotfiles_secret_run -k TWITTER_AUTH_TOKEN -k TWITTER_CT0 twitter "$@"; }
fi

# Point mcporter's exa server at ${EXA_API_KEY:-} instead of a literal key.
# Rewrites only mcpServers.exa's URL in ~/.mcporter/mcporter.json; other
# servers and fields are kept. The old URL (with the key) is never printed.
# Refuses unless .enc.env decrypts to a non-empty EXA_API_KEY: otherwise the
# plaintext key would be removed with no other copy, and exa would silently
# get an empty key.
mcporter_exa_setup() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    # Only $HOME is quoted: naming_check.sh reads a quoted mcporter path as help text.
    local cfg="$HOME"/.mcporter/mcporter.json tmp plain
    # Single quotes on purpose: mcporter expands the placeholder, not the shell.
    # shellcheck disable=SC2016
    local url='https://mcp.exa.ai/mcp?exaApiKey=${EXA_API_KEY:-}'
    if ! command -v jq >/dev/null 2>&1; then
        ux_error "jq is not installed"
        return 1
    fi
    if [ -L "$cfg" ]; then
        ux_error "${cfg} is a symlink; edit its target instead"
        return 1
    fi
    if ! plain=$(_dotfiles_secret_decrypt); then
        ux_error "EXA_API_KEY is not readable from .enc.env; ${cfg} left unchanged"
        return 1
    fi
    case "$plain" in
        EXA_API_KEY=?* | *"
EXA_API_KEY="?*) ;;
        *)
            ux_error ".enc.env has no EXA_API_KEY; ${cfg} left unchanged"
            ux_info "Add it first: sops-help secrets"
            return 1
            ;;
    esac
    unset plain
    mkdir -p "${cfg%/*}" || return 1
    [ -f "$cfg" ] || printf '{}\n' >"$cfg"
    tmp=$(mktemp "${cfg}.XXXXXX") || return 1
    if ! jq --arg u "$url" '.mcpServers.exa |= ((. // {}) | del(.url) | .baseUrl = $u)' "$cfg" >"$tmp" 2>/dev/null; then
        rm -f "$tmp"
        ux_error "could not update ${cfg} (invalid JSON?)"
        return 1
    fi
    chmod 600 "$tmp" && mv -f "$tmp" "$cfg" || return 1
    ux_success "exa reads EXA_API_KEY at run time: ${cfg}"
    ux_info "Run mcporter through the shell wrapper (it injects the key from .enc.env)"
    ux_info "Remove any plaintext EXA_API_KEY copy left in a .env file"
}

alias mcporter-exa-setup='mcporter_exa_setup'
