#!/bin/sh
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac
# shell-common/tools/integrations/sops.sh
# sops + age status diagnostics (issue #1833)
#
# SOPS_AGE_KEY_FILE is deliberately NOT exported: sops already defaults to
# ~/.config/sops/age/keys.txt. The private key must never reach stdout, so the
# key file is only stat'ed and fed to `age-keygen -y`, whose output is filtered.
#
# Install: install-sops-age
# Details: sops-help

# Octal mode of a file: GNU stat, then BSD/macOS stat.
_sops_file_mode() {
    stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null
}

sops_age_status() {
    local tool ver missing="" key mode pub

    ux_header "sops + age status"

    ux_section "Tools"
    for tool in sops age age-keygen; do
        if command -v "$tool" >/dev/null 2>&1; then
            if [ "$tool" = "sops" ]; then
                ver=$(sops --version --disable-version-check 2>/dev/null | head -n 1)
            else
                ver=$("$tool" --version 2>/dev/null | head -n 1)
            fi
            ux_success "${tool}: ${ver:-installed}"
        else
            ux_warning "${tool}: not installed"
            missing="${missing} ${tool}"
        fi
    done
    [ -n "$missing" ] && ux_info "Install: install-sops-age"

    ux_section "Private key"
    key="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
    if [ ! -f "$key" ]; then
        ux_warning "key file not found: ${key}"
        ux_info "Place your key: sops-help newpc  (new key: sops-help setup)"
        return 0
    fi
    mode=$(_sops_file_mode "$key")
    if [ "$mode" = "600" ]; then
        ux_success "key file: ${key} (mode 600)"
    else
        ux_warning "key file: ${key} (mode ${mode:-unknown}, expected 600)"
        ux_info "Fix: chmod 600 ${key}"
    fi

    if command -v age-keygen >/dev/null 2>&1; then
        # grep drops anything that is not a public key, so even a misbehaving
        # age-keygen cannot echo AGE-SECRET-KEY-1... here.
        # paste joins a multi-identity key file's recipients onto one line.
        pub=$(age-keygen -y "$key" 2>/dev/null | grep '^age1' | grep -v 'AGE-SECRET-KEY' | paste -sd ' ' -)
        if [ -n "$pub" ]; then
            ux_success "public key: ${pub}"
        else
            ux_warning "could not derive public key (age-keygen -y failed)"
        fi
    fi
}

alias sops-status='sops_age_status'

# ---------------------------------------------------------------------------
# senv: encrypt/decrypt/run a project's .env with sops + age, in $PWD.
#
# `.env.enc` is not auto-detected as dotenv, so every sops call passes
# --input-type/--output-type dotenv. `sops exec-env` takes no type flags, so
# `senv run` decrypts to a shell variable and exports line by line instead.
# The decrypted text is never eval'ed and never written to disk.
# ---------------------------------------------------------------------------

_senv_usage() {
    ux_info "Usage: senv <command> [args]   (acts on the current directory)"
    ux_bullet "init              write .sops.yaml (your age public key) + ignore .env"
    ux_bullet "enc [file]        encrypt .env -> .env.enc"
    ux_bullet "dec [-f] [file]   decrypt .env.enc -> .env (-f overwrites)"
    ux_bullet "edit [file]       edit .env.enc in \$EDITOR, re-encrypt on save"
    ux_bullet "run <cmd...>      run cmd with .env.enc values as env vars (no file)"
    ux_info "Details: sops-help usage"
}

_senv_need_sops() {
    command -v sops >/dev/null 2>&1 && return 0
    ux_error "sops is not installed"
    ux_info "Install: install-sops-age"
    return 1
}

_senv_init() {
    local key pub
    key="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
    if [ ! -f "$key" ]; then
        ux_error "age key file not found: ${key}"
        ux_info "Create one first: sops-help setup"
        return 1
    fi
    if ! command -v age-keygen >/dev/null 2>&1; then
        ux_error "age-keygen is not installed"
        ux_info "Install: install-sops-age"
        return 1
    fi
    # Only age1... lines survive, so the private key can never reach the file.
    pub=$(age-keygen -y "$key" 2>/dev/null | grep '^age1' | paste -sd ',' -)
    if [ -z "$pub" ]; then
        ux_error "could not derive a public key from ${key}"
        return 1
    fi

    if [ -e .sops.yaml ]; then
        ux_warning ".sops.yaml already exists, left unchanged"
    else
        printf "creation_rules:\n  - path_regex: '(^|/)\\.env(\\.enc)?\$'\n    age: %s\n" "$pub" >.sops.yaml
        ux_success "wrote .sops.yaml"
    fi

    if [ -f .gitignore ] && grep -qxF '.env' .gitignore; then
        ux_info ".gitignore already ignores .env"
    else
        # Keep the appended line on its own line if the file lacks a final \n.
        if [ -s .gitignore ] && [ -n "$(tail -c 1 .gitignore)" ]; then
            printf '\n' >>.gitignore
        fi
        printf '.env\n' >>.gitignore
        ux_success "added .env to .gitignore"
    fi

    ux_info "Next: senv enc && git add .sops.yaml .gitignore .env.enc"
}

_senv_enc() {
    local in="${1:-.env}" out tmp
    out="${in}.enc"
    if [ ! -f "$in" ]; then
        ux_error "input not found: ${in}"
        return 1
    fi
    if [ ! -f .sops.yaml ]; then
        ux_error ".sops.yaml not found in $(pwd)"
        ux_info "Run: senv init"
        return 1
    fi
    tmp=$(mktemp "${out}.XXXXXX") || return 1
    if sops -e --input-type dotenv --output-type dotenv "$in" >"$tmp"; then
        mv -f "$tmp" "$out" && ux_success "encrypted ${in} -> ${out}"
    else
        rm -f "$tmp"
        ux_error "sops failed to encrypt ${in}"
        return 1
    fi
}

_senv_dec() {
    local force="" in="" out tmp
    while [ $# -gt 0 ]; do
        case "$1" in
            -f | --force) force=1 ;;
            *) in="$1" ;;
        esac
        shift
    done
    in="${in:-.env.enc}"
    out="${in%.enc}"
    if [ "$out" = "$in" ]; then
        ux_error "expected a *.enc file: ${in}"
        return 1
    fi
    if [ ! -f "$in" ]; then
        ux_error "input not found: ${in}"
        return 1
    fi
    if [ -e "$out" ] && [ -z "$force" ]; then
        ux_error "${out} already exists"
        ux_info "Overwrite: senv dec -f ${in}"
        return 1
    fi
    tmp=$(mktemp "${out}.XXXXXX") || return 1
    if sops -d --input-type dotenv --output-type dotenv "$in" >"$tmp"; then
        chmod 600 "$tmp" && mv -f "$tmp" "$out" && chmod 600 "$out" &&
            ux_success "decrypted ${in} -> ${out} (mode 600)"
    else
        rm -f "$tmp"
        ux_error "sops failed to decrypt ${in}"
        return 1
    fi
}

_senv_edit() {
    local in="${1:-.env.enc}" rc
    if [ ! -f "$in" ]; then
        ux_error "input not found: ${in}"
        return 1
    fi
    sops edit --input-type dotenv --output-type dotenv "$in"
    rc=$?
    # sops exits 200 when the file was saved unchanged; that is not an error.
    if [ "$rc" -eq 200 ]; then
        ux_info "no changes"
        return 0
    fi
    return "$rc"
}

_senv_run() {
    local _senv_plain
    if [ $# -eq 0 ]; then
        ux_error "senv run needs a command"
        ux_info "Example: senv run make run"
        return 2
    fi
    if [ ! -f .env.enc ]; then
        ux_error ".env.enc not found in $(pwd)"
        return 1
    fi
    if ! _senv_plain=$(sops -d --input-type dotenv --output-type dotenv .env.enc); then
        ux_error "sops failed to decrypt .env.enc; command not run"
        return 1
    fi
    (
        # Split on newlines with parameter expansion (no `read`, no heredoc
        # temp file, same behaviour in bash and zsh). Each KEY=VALUE line is
        # exported verbatim; nothing is eval'ed.
        _senv_nl='
'
        _senv_rest="$_senv_plain"
        unset _senv_plain
        while [ -n "$_senv_rest" ]; do
            _senv_line="${_senv_rest%%"$_senv_nl"*}"
            case "$_senv_rest" in
                *"$_senv_nl"*) _senv_rest="${_senv_rest#*"$_senv_nl"}" ;;
                *) _senv_rest="" ;;
            esac
            case "$_senv_line" in
                "" | "#"*) continue ;;
                [A-Za-z_]*=*) ;;
                *) continue ;;
            esac
            case "${_senv_line%%=*}" in
                *[!A-Za-z0-9_]*) continue ;;
            esac
            # shellcheck disable=SC2163  # exports the KEY=VALUE string itself
            export "$_senv_line"
        done
        unset _senv_nl _senv_rest _senv_line
        exec "$@"
    )
}

senv() {
    local cmd="${1:-}"
    case "$cmd" in
        "" | -h | --help | help)
            _senv_usage
            return 0
            ;;
        init | enc | dec | edit | run) ;;
        *)
            ux_error "unknown senv command: ${cmd}"
            _senv_usage
            return 2
            ;;
    esac
    shift
    _senv_need_sops || return 1
    "_senv_${cmd}" "$@"
}
