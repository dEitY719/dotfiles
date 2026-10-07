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
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
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
# The default ciphertext is `.enc.env` (#2062): sops infers dotenv from the
# extension and the global pre-commit hook blocks `.env.enc`. `.env.enc` is
# still read as a fallback. It is not auto-detected as dotenv, so every sops
# call passes --input-type/--output-type dotenv. `sops exec-env` takes no type
# flags, so
# `senv run` decrypts to a shell variable and exports line by line instead.
# The decrypted text is never eval'ed and never written to disk.
#
# `senv key export|import` move the private key between PCs as an age
# passphrase file. age asks for the passphrase on the tty itself; senv never
# reads, pipes or passes it.
# ---------------------------------------------------------------------------

_senv_usage() {
    ux_info "Usage: senv <command> [args]   (acts on the current directory)"
    ux_bullet "workflow"
    ux_bullet_sub "키가 있는 PC: senv init -> senv enc -> git commit -> senv key export"
    ux_bullet_sub "새 PC: git pull -> senv key import -> senv dec"
    ux_bullet_sub "점검: senv check"
    ux_bullet "init              write .sops.yaml (your age public key) + ignore .env"
    ux_bullet "enc [file]        encrypt .env -> .enc.env ([file] -> [file].enc)"
    ux_bullet "dec [-f] [file]   decrypt .enc.env (or legacy .env.enc) -> .env (-f overwrites)"
    ux_bullet "edit [file]       edit the encrypted file in \$EDITOR, re-encrypt on save"
    ux_bullet "run <cmd...>      run cmd with the encrypted values as env vars (no file)"
    ux_bullet "check             key present / mode 600 / matches .sops.yaml / decrypts"
    ux_bullet "key show          your public key + whether .sops.yaml lists it"
    ux_bullet "key export [-o file] [-f]   lock the private key with a passphrase (~/senv-key.age)"
    ux_bullet "key import [file] [-f]      unlock it into the sops key file (mode 600)"
    ux_info "Details: sops-help usage"
}

_senv_need_sops() {
    command -v sops >/dev/null 2>&1 && return 0
    ux_error "sops is not installed"
    ux_info "Install: install-sops-age"
    return 1
}

_senv_key_file() {
    printf '%s' "${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
}

# Encrypted file to act on: the argument, else .enc.env, else legacy .env.enc.
# Falls back to .enc.env so "not found" messages name the standard file.
_senv_enc_file() {
    if [ -n "${1-}" ]; then
        printf '%s' "$1"
    elif [ ! -f .enc.env ] && [ -f .env.enc ]; then
        printf '.env.enc'
    else
        printf '.enc.env'
    fi
}

# Public key(s) of a key file, one per line. Only age1... lines survive, so
# the private key can never be printed.
_senv_pubkeys() {
    age-keygen -y "$1" 2>/dev/null | grep '^age1' | grep -v 'AGE-SECRET-KEY'
}

# 0: a public key of $1 is a recipient in ./.sops.yaml, 1: none is,
# 2: no .sops.yaml here.
_senv_key_matches() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local p
    [ -f .sops.yaml ] || return 2
    for p in $(_senv_pubkeys "$1"); do
        grep -qF "$p" .sops.yaml && return 0
    done
    return 1
}

# age prompts on the terminal; a pipe or cron has none to prompt on.
_senv_has_tty() {
    [ -t 0 ] && (: </dev/tty) 2>/dev/null
}

_senv_need_tty() {
    _senv_has_tty && return 0
    ux_error "no terminal: age must ask for the passphrase itself"
    ux_info "Run this directly in a terminal: senv key $1"
    return 1
}

_senv_init() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local key pub
    key=$(_senv_key_file)
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
    pub=$(_senv_pubkeys "$key" | paste -sd ',' -)
    if [ -z "$pub" ]; then
        ux_error "could not derive a public key from ${key}"
        return 1
    fi

    if [ -e .sops.yaml ]; then
        ux_warning ".sops.yaml already exists, left unchanged"
    else
        printf "creation_rules:\n  - path_regex: '(^|/)\\.(enc\\.)?env(\\.enc)?\$'\n    age: %s\n" "$pub" >.sops.yaml
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

    ux_info "Next: senv enc && git add .sops.yaml .gitignore .enc.env"
}

_senv_enc() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local in="${1:-.env}" out tmp
    if [ -n "${1-}" ]; then out="${in}.enc"; else out=".enc.env"; fi
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
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local force="" in="" out tmp
    while [ $# -gt 0 ]; do
        case "$1" in
            -f | --force) force=1 ;;
            *) in="$1" ;;
        esac
        shift
    done
    in=$(_senv_enc_file "$in")
    case "$in" in
        *.enc.env) out="${in%.enc.env}.env" ;;
        *.enc) out="${in%.enc}" ;;
        *)
            ux_error "expected a *.enc or *.enc.env file: ${in}"
            return 1
            ;;
    esac
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
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local in rc
    in=$(_senv_enc_file "${1-}")
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
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local _senv_plain _senv_in
    if [ $# -eq 0 ]; then
        ux_error "senv run needs a command"
        ux_info "Example: senv run make run"
        return 2
    fi
    _senv_in=$(_senv_enc_file)
    if [ ! -f "$_senv_in" ]; then
        ux_error ".enc.env (or legacy .env.enc) not found in $(pwd)"
        return 1
    fi
    if ! _senv_plain=$(sops -d --input-type dotenv --output-type dotenv "$_senv_in"); then
        ux_error "sops failed to decrypt ${_senv_in}; command not run"
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

# Report-only health check. Prints success/failure per item and one next
# step per failure; never prints plaintext or any line of the decrypted file.
_senv_check() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local key mode in fail=0
    key=$(_senv_key_file)
    if [ ! -f "$key" ]; then
        ux_error "key file not found: ${key}"
        ux_info "Next: senv key import  (or create one: sops-help setup)"
        return 1
    fi
    ux_success "key file: ${key}"

    mode=$(_sops_file_mode "$key")
    if [ "$mode" = "600" ]; then
        ux_success "key mode 600"
    else
        ux_error "key mode ${mode:-unknown}, expected 600"
        ux_info "Next: chmod 600 ${key}"
        fail=1
    fi

    _senv_key_matches "$key"
    case $? in
        0) ux_success "public key is a recipient in .sops.yaml" ;;
        1)
            ux_error "public key is not a recipient in .sops.yaml"
            ux_info "Next: import the key this project was encrypted for (senv key show)"
            fail=1
            ;;
        *) ux_warning "no .sops.yaml in $(pwd); recipient not checked" ;;
    esac

    in=$(_senv_enc_file)
    if [ ! -f "$in" ]; then
        ux_warning "no .enc.env (or legacy .env.enc) in $(pwd); decryption not checked"
    elif sops -d --input-type dotenv --output-type dotenv "$in" >/dev/null 2>&1; then
        ux_success "decrypts: ${in}"
    else
        ux_error "cannot decrypt: ${in}"
        ux_info "Next: senv key import  (the key does not open this file)"
        fail=1
    fi
    return "$fail"
}

_senv_key_show() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local key pub
    key=$(_senv_key_file)
    if [ ! -f "$key" ]; then
        ux_error "key file not found: ${key}"
        ux_info "Next: senv key import"
        return 1
    fi
    pub=$(_senv_pubkeys "$key" | paste -sd ' ' -)
    if [ -z "$pub" ]; then
        ux_error "could not derive a public key from ${key}"
        return 1
    fi
    ux_info "public key: ${pub}"
    _senv_key_matches "$key"
    case $? in
        0) ux_success "matches .sops.yaml" ;;
        1)
            ux_warning "not a recipient in .sops.yaml"
            return 1
            ;;
        *) ux_info "no .sops.yaml in $(pwd)" ;;
    esac
}

_senv_key_export() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local key out="$HOME/senv-key.age" force="" dir tmp
    while [ $# -gt 0 ]; do
        case "$1" in
            -f | --force) force=1 ;;
            -o)
                out="${2-}"
                shift
                ;;
            *)
                ux_error "unknown option: $1"
                ux_info "Usage: senv key export [-o file] [-f]"
                return 2
                ;;
        esac
        [ $# -gt 0 ] && shift
    done
    key=$(_senv_key_file)
    if [ ! -f "$key" ]; then
        ux_error "key file not found: ${key}"
        return 1
    fi
    if [ -z "$out" ]; then
        ux_error "-o needs a file path"
        return 2
    fi
    dir=$(dirname "$out")
    if [ ! -d "$dir" ]; then
        ux_error "directory not found: ${dir}"
        return 1
    fi
    if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        ux_error "refusing to write the locked key inside a git work tree: ${dir}"
        ux_info "Pick a path outside any repository (default: ~/senv-key.age)"
        return 1
    fi
    if [ -e "$out" ] && [ -z "$force" ]; then
        ux_error "${out} already exists"
        ux_info "Overwrite: senv key export -o ${out} -f"
        return 1
    fi
    _senv_need_tty export || return 1

    tmp=$(mktemp "${out}.XXXXXX") || return 1
    ux_info "age asks for a new passphrase (twice)"
    if ! age -p -o "$tmp" "$key"; then
        rm -f "$tmp"
        ux_error "age failed to lock the key"
        return 1
    fi
    # Round-trip: the locked file must unlock to the exact key bytes.
    ux_info "verify: enter the same passphrase once more"
    if ! age -d "$tmp" | cmp -s - "$key"; then
        rm -f "$tmp"
        ux_error "verification failed; nothing written"
        return 1
    fi
    chmod 600 "$tmp" && mv -f "$tmp" "$out" || return 1
    ux_success "locked key written: ${out}"
    ux_info "Move it to the new PC, then: senv key import ${out}"
}

_senv_key_import() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local in="" force="" key dir tmp
    while [ $# -gt 0 ]; do
        case "$1" in
            -f | --force) force=1 ;;
            *) in="$1" ;;
        esac
        shift
    done
    in="${in:-$HOME/senv-key.age}"
    key=$(_senv_key_file)
    if [ ! -f "$in" ]; then
        ux_error "locked key not found: ${in}"
        ux_info "Create it on the PC that has the key: senv key export"
        return 1
    fi
    if [ -e "$key" ] && [ -z "$force" ]; then
        ux_error "${key} already exists"
        ux_info "Overwrite: senv key import ${in} -f"
        return 1
    fi
    _senv_need_tty import || return 1

    dir=$(dirname "$key")
    mkdir -p "$dir" || return 1
    tmp=$(mktemp "${key}.XXXXXX") || return 1
    chmod 600 "$tmp"
    if ! age -d -o "$tmp" "$in"; then
        rm -f "$tmp"
        ux_error "age failed to unlock ${in}"
        return 1
    fi
    if [ -z "$(_senv_pubkeys "$tmp")" ]; then
        rm -f "$tmp"
        ux_error "${in} did not contain an age private key"
        return 1
    fi
    chmod 600 "$tmp" && mv -f "$tmp" "$key" || return 1
    ux_success "key installed: ${key} (mode 600)"

    _senv_key_matches "$key"
    case $? in
        0) ux_success "public key matches .sops.yaml" ;;
        1) ux_warning "public key is not a recipient in .sops.yaml (wrong key?)" ;;
        *) ux_info "Next: cd <project> && senv check" ;;
    esac
    return 0
}

_senv_key() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local sub="${1:-}"
    case "$sub" in
        show | export | import) ;;
        *)
            ux_error "usage: senv key show|export|import"
            return 2
            ;;
    esac
    shift
    if ! command -v age >/dev/null 2>&1 || ! command -v age-keygen >/dev/null 2>&1; then
        ux_error "age is not installed"
        ux_info "Install: install-sops-age"
        return 1
    fi
    "_senv_key_${sub}" "$@"
}

senv() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local cmd="${1:-}"
    case "$cmd" in
        "" | -h | --help | help)
            _senv_usage
            return 0
            ;;
        init | enc | dec | edit | run | check | key) ;;
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
