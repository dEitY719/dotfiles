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
#
# `senv vault-push` copies .enc.env (+ .sops.yaml) into the private vault repo
# and commits/pushes only those paths; plaintext .env never leaves $PWD.
# ---------------------------------------------------------------------------

_senv_usage() {
    ux_info "Usage: senv <command> [args]   (acts on the current directory)"
    ux_bullet "workflow"
    ux_bullet_sub "키가 있는 PC: senv init -> senv enc -> git commit (vault 보관: senv vault-push)"
    ux_bullet_sub "시크릿 저장·추출 (dotfiles .enc.env): senv set KEY -> 자동 commit+push, senv get KEY / senv keys"
    ux_bullet_sub "키 백업: senv key export -> cp ~/senv-key.age ~/para/project/vault/secrets/ -> vault 에서 git commit && git push"
    ux_bullet_sub "새 PC: cd ~/para/project/vault && git pull -> senv key import ~/para/project/vault/secrets/senv-key.age -> senv dec -f (기존 .env 덮어씀) -> senv check"
    ux_bullet "init              write .sops.yaml (your age public key) + ignore .env"
    ux_bullet "enc [file]        encrypt .env -> .enc.env ([file] -> [file].enc)"
    ux_bullet "dec [-f] [file]   decrypt .enc.env (or legacy .env.enc) -> .env (-f overwrites)"
    ux_bullet "edit [file]       edit the encrypted file in \$EDITOR, re-encrypt on save"
    ux_bullet "run <cmd...>      run cmd with the encrypted values as env vars (no file)"
    ux_bullet "check             key present / mode 600 / matches .sops.yaml / decrypts"
    ux_bullet "set KEY [--stdin]  dotfiles .enc.env 에 키 저장: enc -> commit -> push (값은 숨김 입력)"
    ux_bullet "get KEY|keys|push  dotfiles 에서 pull+복호화해 값/키 이름만 출력, push 는 수동 편집 반영"
    ux_bullet "create-pr         enc -> branch -> commit -> push -> PR (default branch only, .enc.env only)"
    ux_bullet "vault-push [opts]  .enc.env + .sops.yaml -> vault secrets/<dir name>/ -> commit -> push (sops-help usage)"
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
        _senv_export_lines "$_senv_plain"
        unset _senv_plain
        exec "$@"
    )
}

# Export each KEY=VALUE line of decrypted dotenv text $1 into the current
# shell. Optional $2 is a space-separated allow-list of key names; other keys
# are skipped. Shared by `senv run` and dotfiles_secret_run (#2096).
# Split on newlines with parameter expansion (no `read`, no heredoc temp file,
# same behaviour in bash and zsh). Each line is exported verbatim; nothing is
# eval'ed. Callers run this in a subshell so the values never outlive the
# command they are for.
_senv_export_lines() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local _senv_nl _senv_rest _senv_line _senv_only="${2-}"
    _senv_nl='
'
    _senv_rest="$1"
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
        if [ -n "$_senv_only" ]; then
            case " $_senv_only " in
                *" ${_senv_line%%=*} "*) ;;
                *) continue ;;
            esac
        fi
        # shellcheck disable=SC2163  # exports the KEY=VALUE string itself
        export "$_senv_line"
    done
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

# Re-encrypt .env, then branch -> commit -> push -> PR in one go (#2228).
# Runs from the default branch only, so a PR never mixes in other work; only
# .enc.env is ever added, never .env. The PR is not merged.
_senv_create_pr() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local base cur branch url rc staged host ahead
    if [ $# -gt 0 ]; then
        ux_error "create-pr takes no arguments (it always re-encrypts .env -> .enc.env)"
        return 1
    fi
    local title="chore(secrets): .enc.env 를 현재 .env 로 다시 암호화한다"
    local body="\`senv create-pr\` 로 \`.env\` 를 다시 암호화했다. 변경은 \`.enc.env\` 한 파일뿐이다."
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        ux_error "not inside a git work tree: $(pwd)"
        return 1
    fi
    if ! command -v gh >/dev/null 2>&1; then
        ux_error "gh is not installed"
        return 1
    fi
    base=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
    base="${base#origin/}"
    if [ -z "$base" ]; then
        ux_error "cannot determine the default branch (origin/HEAD unset)"
        ux_info "Next: git remote set-head origin -a"
        return 1
    fi
    cur=$(git symbolic-ref -q --short HEAD 2>/dev/null)
    if [ "$cur" != "$base" ]; then
        ux_error "run from the default branch (${base}), not '${cur:-detached HEAD}'"
        ux_info "Next: git switch ${base}"
        return 1
    fi
    if [ -n "$(git rev-parse --show-prefix)" ]; then
        ux_error "run from the repository root (.enc.env is resolved relative to it)"
        ux_info "Next: cd \"\$(git rev-parse --show-toplevel)\""
        return 1
    fi
    git fetch -q origin "$base" 2>/dev/null || ux_warning "could not fetch origin/${base}; using the cached ref"
    ahead=$(git rev-list --count "origin/${base}..HEAD" 2>/dev/null) || {
        ux_error "cannot compare ${base} with origin/${base}"
        return 1
    }
    if [ "$ahead" -gt 0 ]; then
        ux_error "${base} has ${ahead} unpushed commit(s) that would be mixed into the PR"
        ux_info "Next: git push origin ${base}  (or move them to a branch)"
        return 1
    fi
    if [ "$(git rev-list --count "HEAD..origin/${base}")" -gt 0 ]; then
        ux_error "${base} is behind origin/${base}"
        ux_info "Next: git pull --ff-only"
        return 1
    fi
    staged=$(git diff --cached --name-only --relative | grep -vx '\.enc\.env' || true)
    if [ -n "$staged" ]; then
        ux_error "other staged changes would be mixed into the PR:"
        printf '%s\n' "$staged" | while IFS= read -r f; do ux_bullet_sub "$f"; done
        ux_info "Next: git restore --staged <file>  (or commit them first)"
        return 1
    fi

    # sops output is non-deterministic (fresh nonce/mac each run), so compare the
    # plaintext: an unchanged .env must not produce an empty-meaning PR.
    if [ -f .enc.env ] && [ -z "$(git status --porcelain -- .enc.env)" ] &&
        sops -d --input-type dotenv --output-type dotenv .enc.env 2>/dev/null | cmp -s - .env; then
        ux_info "no change: .enc.env already matches .env; nothing to do"
        return 0
    fi

    branch="chore/reencrypt-env-$(date +%Y%m%d-%H%M%S)"
    if git show-ref --verify --quiet "refs/heads/${branch}"; then
        ux_error "branch already exists: ${branch}"
        return 1
    fi
    _senv_enc "$@" || return 1 # "$@" is empty: args were rejected above
    if [ -z "$(git status --porcelain -- .enc.env)" ]; then
        ux_info "no change in .enc.env; nothing to do"
        return 0
    fi

    if ! git switch -c "$branch" >/dev/null 2>&1; then
        git restore -- .enc.env 2>/dev/null
        ux_error "cannot create branch ${branch}; .enc.env restored"
        return 1
    fi
    git add -- .enc.env
    if ! git commit -m "$title" -- .enc.env >/dev/null; then
        ux_error "commit failed (now on ${branch}; .enc.env is modified)"
        return 1
    fi
    ux_success "committed on ${branch}"
    git push -u origin HEAD || {
        ux_error "push failed (branch ${branch} is committed locally)"
        return 1
    }
    host=$(_senv_gh_host)
    url=$([ -z "$host" ] || export GH_HOST="$host"
        gh pr create --base "$base" --head "$branch" --title "$title" --body "$body")
    rc=$?
    if [ "$rc" -ne 0 ]; then
        ux_error "gh pr create failed (branch ${branch} is pushed)"
        return "$rc"
    fi
    ux_success "PR: ${url}"
}

# ---------------------------------------------------------------------------
# senv set/get/push/keys: the dotfiles .enc.env store cycle (#2096 저장소).
#
# The commands above act on the CWD project; these four act on the dotfiles
# root — the parent of $SHELL_COMMON — where the personal .enc.env lives:
#   set KEY   hidden prompt -> .env 갱신 -> enc -> commit(.enc.env 만) -> push
#   get KEY   git pull -> 복호화 -> 해당 값만 stdout (파이프/클립보드용)
#   push      수동 .env 편집 후 enc -> commit -> push (변경 시만)
#   keys      복호화 -> 키 이름만 한 줄씩 (값 없음)
# The value lives only in a shell variable: never echoed, logged or passed as
# an argument. `--stdin` reads it from stdin instead of the hidden terminal
# prompt (printf '%s' "$V" | senv set KEY --stdin) — the value still never
# touches argv or the environment. main 에 직접 commit+push 한다 (사용자 결정).
# ---------------------------------------------------------------------------

# The dotfiles root the store subcommands act on: the parent of $SHELL_COMMON.
# CWD-independent, and tests point SHELL_COMMON at an isolated tree, so both
# sides resolve the same way.
_senv_dotfiles_root() {
    dirname "${SHELL_COMMON:-$HOME/dotfiles/shell-common}"
}

# Git preflight shared by `senv set` / `senv push` ($1 = dotfiles root): a
# work tree, on the default branch, nothing staged except .enc.env — the same
# invariants create-pr enforces. This path pushes main directly (no PR), so
# the guard runs before the secret is even read. $2 (optional) is the ERE of
# root-relative staged paths that are allowed (default: only .enc.env).
_senv_git_guard() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local root="$1" allow="${2:-\.enc\.env}" base cur staged
    if ! git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        ux_error "not a git work tree: ${root}"
        return 1
    fi
    base=$(git -C "$root" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
    base="${base#origin/}"
    if [ -z "$base" ]; then
        ux_error "cannot determine the default branch (origin/HEAD unset)"
        ux_info "Next: git -C ${root} remote set-head origin -a"
        return 1
    fi
    cur=$(git -C "$root" symbolic-ref -q --short HEAD 2>/dev/null)
    if [ "$cur" != "$base" ]; then
        ux_error "run from the default branch (${base}), not '${cur:-detached HEAD}'"
        ux_info "Next: git -C ${root} switch ${base}"
        return 1
    fi
    staged=$(git -C "$root" diff --cached --name-only | grep -Evx "$allow" || true)
    if [ -n "$staged" ]; then
        ux_error "other staged changes would be mixed into the commit:"
        printf '%s\n' "$staged" | while IFS= read -r f; do ux_bullet_sub "$f"; done
        ux_info "Next: git -C ${root} restore --staged <file>  (or commit them first)"
        return 1
    fi
}

# Commit .enc.env (pathspec 고정 — 평문 .env 는 절대 staging/commit 되지
# 않는다) and push the default branch to origin. Shared tail of `senv set` /
# `senv push`. $1 = dotfiles root, $2 = commit message. The commit is the
# user's own terminal action, so it deliberately carries no Co-Authored-By
# trailer.
_senv_commit_push() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local root="$1" msg="$2" branch
    git -C "$root" add -- .enc.env || {
        ux_error "git add failed: ${root}/.enc.env"
        return 1
    }
    if ! git -C "$root" commit -m "$msg" -- .enc.env >/dev/null; then
        ux_error "commit failed (.enc.env stays staged)"
        return 1
    fi
    ux_success "committed: ${msg}"
    branch=$(git -C "$root" symbolic-ref -q --short HEAD 2>/dev/null)
    if ! git -C "$root" push origin HEAD; then
        ux_error "push failed (the commit stays local on ${branch:-HEAD})"
        ux_info "Next: git -C ${root} pull --rebase && git -C ${root} push origin HEAD"
        return 1
    fi
    ux_success "pushed ${branch:-HEAD} to origin"
}

_senv_set() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local key="" use_stdin=0 root value msg tmp
    while [ $# -gt 0 ]; do
        case "$1" in
            --stdin) use_stdin=1 ;;
            *)
                if [ -n "$key" ]; then
                    ux_error "usage: senv set KEY [--stdin]"
                    return 2
                fi
                key="$1"
                ;;
        esac
        shift
    done
    if [ -z "$key" ]; then
        ux_error "senv set needs a KEY name"
        ux_info "Usage: senv set KEY [--stdin]"
        return 2
    fi
    case "$key" in
        [!A-Za-z_]* | *[!A-Za-z0-9_]*)
            ux_error "invalid KEY name: ${key} (regex ^[A-Za-z_][A-Za-z0-9_]*$)"
            return 2
            ;;
    esac
    root=$(_senv_dotfiles_root)
    if [ ! -f "$root/.sops.yaml" ]; then
        ux_error ".sops.yaml not found in ${root}"
        ux_info "Next: cd ${root} && senv init"
        return 1
    fi
    if [ ! -f "$root/.env" ] && [ ! -f "$root/.enc.env" ]; then
        ux_error "neither .env nor .enc.env found in ${root}"
        ux_info "Next: git -C ${root} pull && cd ${root} && senv dec -f"
        return 1
    fi
    # The git guard runs before the secret is read: a refused set must not
    # make the user type the value for nothing.
    _senv_git_guard "$root" || return 1
    if [ "$use_stdin" -eq 0 ] && ! _senv_has_tty; then
        ux_error "no terminal for the hidden prompt"
        ux_info "Pipe the value instead: senv set ${key} --stdin"
        return 1
    fi
    [ "$use_stdin" -eq 1 ] || printf 'value for %s (hidden): ' "$key" >&2
    # read -rs: bash and zsh both hide the echo (-s); the value stays in this
    # local and never reaches argv, the environment or a log. read returns 1
    # on EOF without a trailing newline (`printf '%s' "$V" | ...`), so the
    # emptiness of $value — not the exit status — is what rejects "no input".
    value=""
    # shellcheck disable=SC3045  # read -s (hidden echo) is a bash/zsh extension, same as _senv_need_tty's tty
    read -rs value || true
    if [ -z "$value" ]; then
        ux_error "empty input; nothing written"
        return 1
    fi
    msg="chore(secrets): .enc.env 에 ${key} 추가"
    (
        cd "$root" || exit 1
        if [ ! -f .env ]; then
            ux_info "no .env here; decrypting .enc.env first (senv dec -f)"
            _senv_dec -f || exit 1
        fi
        tmp=$(mktemp .env.XXXXXX) || exit 1
        cur=""
        if grep -q "^${key}=" .env; then
            msg="chore(secrets): .enc.env 에 ${key} 갱신"
            cur=$(grep "^${key}=" .env)
        fi
        # Drop the old KEY line (if any), keep the rest, append the new line
        # verbatim (dotenv 원문 그대로 — no quoting or escaping).
        grep -v "^${key}=" .env >"$tmp" || true
        printf '%s=%s\n' "$key" "$value" >>"$tmp"
        # Defensive no-change: the store already holds this KEY at this value
        # and the rest of .env still matches the store. Moving the KEY line to
        # the end must not look like a change, and a manual edit of another
        # key must not be swallowed by a no-op — hence the two-part check.
        if [ -f .enc.env ] &&
            [ "$cur" = "$key=$value" ] &&
            [ "$(sops -d --input-type dotenv --output-type dotenv .enc.env 2>/dev/null | grep -v "^${key}=")" = "$(grep -v "^${key}=" .env)" ]; then
            rm -f "$tmp"
            ux_info "no change: ${key} 값이 이미 .enc.env 와 같다; nothing to do"
            exit 0
        fi
        mv -f "$tmp" .env
        _senv_enc || exit 1
        _senv_commit_push "$root" "$msg" || exit 1
    )
}

# Locate and decrypt the dotfiles store's ciphertext, printing the plaintext
# dotenv to stdout for the caller to capture. Diagnoses missing config/file
# and decrypt failures itself. Shared by `senv get` / `senv keys`.
_senv_store_plain() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local root in plain
    root=$(_senv_dotfiles_root)
    # Diagnostics must go to stderr: callers capture stdout ($(...)), and a
    # hint swallowed into the capture is a hint never shown.
    if [ ! -f "$root/.sops.yaml" ]; then
        ux_error ".sops.yaml not found in ${root}"
        ux_info "Next: cd ${root} && senv init" >&2
        return 1
    fi
    if [ -f "$root/.enc.env" ]; then
        in="$root/.enc.env"
    elif [ -f "$root/.env.enc" ]; then
        in="$root/.env.enc"
    else
        ux_error ".enc.env not found in ${root}"
        ux_info "Next: git -C ${root} pull" >&2
        return 1
    fi
    if ! plain=$(sops -d --input-type dotenv --output-type dotenv "$in" 2>/dev/null); then
        ux_error "sops failed to decrypt: ${in}"
        ux_info "Next: senv check  (개인키가 이 파일을 여는지)" >&2
        return 1
    fi
    printf '%s' "$plain"
}

_senv_get() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local key="${1-}" root plain nl rest line val found=""
    if [ $# -ne 1 ]; then
        ux_error "usage: senv get KEY"
        return 2
    fi
    root=$(_senv_dotfiles_root)
    # Fresh store first; offline or a diverged branch must not block
    # extraction, so a failed pull only warns (stdout stays pure: stderr).
    if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "$root" pull --ff-only >/dev/null 2>&1 ||
            ux_warning "git pull failed (offline?); using the local .enc.env" >&2
    fi
    if ! plain=$(_senv_store_plain); then
        return 1
    fi
    # Walk the decrypted dotenv without eval; print only the named KEY's
    # value on stdout — other keys and metadata never reach the output.
    nl='
'
    rest="$plain"
    while [ -n "$rest" ]; do
        line="${rest%%"$nl"*}"
        case "$rest" in
            *"$nl"*) rest="${rest#*"$nl"}" ;;
            *) rest="" ;;
        esac
        case "$line" in
            "" | "#"*) continue ;;
            [A-Za-z_]*=*) ;;
            *) continue ;;
        esac
        [ "${line%%=*}" = "$key" ] || continue
        val="${line#*=}"
        found=1
        break
    done
    if [ -z "$found" ]; then
        ux_error "${key} not found in the dotfiles .enc.env"
        ux_info "Next: senv keys   # 키 목록"
        return 1
    fi
    printf '%s\n' "$val"
}

_senv_keys() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local plain nl rest line
    if [ $# -gt 0 ]; then
        ux_error "senv keys takes no arguments"
        return 2
    fi
    if ! plain=$(_senv_store_plain); then
        return 1
    fi
    nl='
'
    rest="$plain"
    while [ -n "$rest" ]; do
        line="${rest%%"$nl"*}"
        case "$rest" in
            *"$nl"*) rest="${rest#*"$nl"}" ;;
            *) rest="" ;;
        esac
        case "$line" in
            "" | "#"*) continue ;;
            [A-Za-z_]*=*) ;;
            *) continue ;;
        esac
        case "${line%%=*}" in
            *[!A-Za-z0-9_]*) continue ;;
        esac
        printf '%s\n' "${line%%=*}"
    done
}

_senv_push() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local root
    if [ $# -gt 0 ]; then
        ux_error "senv push takes no arguments (수동 .env 편집 후 실행)"
        return 2
    fi
    root=$(_senv_dotfiles_root)
    if [ ! -f "$root/.sops.yaml" ]; then
        ux_error ".sops.yaml not found in ${root}"
        ux_info "Next: cd ${root} && senv init"
        return 1
    fi
    if [ ! -f "$root/.env" ]; then
        ux_error ".env not found in ${root}"
        ux_info "Next: cd ${root} && senv dec -f   (기존 .env 를 덮어쓴다)"
        return 1
    fi
    _senv_git_guard "$root" || return 1
    (
        cd "$root" || exit 1
        # sops output is non-deterministic (fresh nonce/mac each run), so
        # compare the plaintext: an unchanged .env must not produce an
        # empty-meaning commit (create-pr pattern).
        if [ -f .enc.env ] && [ -z "$(git status --porcelain -- .enc.env)" ] &&
            sops -d --input-type dotenv --output-type dotenv .enc.env 2>/dev/null | cmp -s - .env; then
            ux_info "no change: .enc.env already matches .env; nothing to do"
            exit 0
        fi
        _senv_enc || exit 1
        _senv_commit_push "$root" "chore(secrets): .enc.env 를 현재 .env 로 다시 암호화한다" ||
            exit 1
    )
}

# ---------------------------------------------------------------------------
# senv vault-push: copy the CWD project's .enc.env (+ .sops.yaml) into the
# private vault repo (${SENV_VAULT_DIR:-~/para/project/vault}) under
# secrets/<NAME>/, then commit only those paths and push the default branch.
# Plaintext .env is never copied; if it differs from .enc.env it is
# re-encrypted first. The commit carries no Co-Authored-By trailer.
# ---------------------------------------------------------------------------

_senv_vault_usage() {
    ux_info "Usage: senv vault-push [-n NAME] [-d SUBDIR] [-v VAULT] [-m MSG] [--no-push] [--no-sops]"
}

# A vault-relative path must be non-empty, relative and free of `..`.
_senv_vault_safe_path() {
    case "$1" in
        "" | /* | *..*) return 1 ;;
    esac
}

_senv_vault_push() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local name dest="" dest_set=0 vault="${SENV_VAULT_DIR:-$HOME/para/project/vault}"
    local msg="" do_push=1 do_sops=1 esc branch
    name=$(basename "$(pwd)")
    while [ $# -gt 0 ]; do
        case "$1" in
            -n | --name | -d | --dest | -v | --vault | -m | --message)
                if [ $# -lt 2 ]; then
                    ux_error "$1 needs a value"
                    _senv_vault_usage
                    return 2
                fi
                case "$1" in
                    -n | --name) name="$2" ;;
                    -d | --dest) dest="$2" dest_set=1 ;;
                    -v | --vault) vault="$2" ;;
                    *) msg="$2" ;;
                esac
                shift
                ;;
            --no-push) do_push=0 ;;
            --no-sops) do_sops=0 ;;
            *)
                ux_error "unknown option: $1"
                _senv_vault_usage
                return 2
                ;;
        esac
        shift
    done
    [ "$dest_set" -eq 1 ] || dest="secrets/${name}"
    dest="${dest%/}"
    if ! _senv_vault_safe_path "$name" || ! _senv_vault_safe_path "$dest"; then
        ux_error "unsafe name/dest (empty, absolute or contains ..): name='${name}' dest='${dest}'"
        return 2
    fi
    if [ ! -f .enc.env ]; then
        ux_error ".enc.env not found in $(pwd)"
        ux_info "Next: senv enc"
        return 1
    fi
    if [ ! -d "$vault" ]; then
        ux_error "vault not found: ${vault}"
        ux_info "Next: git clone git@github.com:dEitY719/vault.git ${vault}"
        return 1
    fi
    esc=$(printf '%s' "$dest" | sed 's/[][\.*^$+?(){}|]/\\&/g')
    _senv_git_guard "$vault" "${esc}/(\.enc\.env|\.sops\.yaml)" || return 1

    # sops output is non-deterministic, so compare plaintext. sops drops blank
    # lines in dotenv, so ignore them on both sides (else .env with blank lines
    # always looks changed and every run re-encrypts).
    if [ -f .env ] && [ "$(sops -d --input-type dotenv --output-type dotenv .enc.env 2>/dev/null | grep -v '^[[:space:]]*$')" != "$(grep -v '^[[:space:]]*$' .env)" ]; then
        ux_info ".env differs from .enc.env; re-encrypting first"
        _senv_enc || return 1
    fi
    if [ "$do_sops" -eq 1 ] && [ ! -f .sops.yaml ]; then
        ux_warning ".sops.yaml not found in $(pwd); copying .enc.env only"
        do_sops=0
    fi
    if [ -z "$msg" ]; then
        if [ -n "$(git -C "$vault" ls-files -- "$dest")" ]; then
            msg="chore: update ${name} .enc.env"
        else
            msg="chore: add ${name} .enc.env"
        fi
    fi

    set -- "$dest/.enc.env"
    [ "$do_sops" -eq 1 ] && set -- "$@" "$dest/.sops.yaml"
    if ! { mkdir -p "$vault/$dest" && command cp -f .enc.env "$vault/$dest/.enc.env"; }; then
        ux_error "copy failed: ${vault}/${dest}/.enc.env"
        return 1
    fi
    if [ "$do_sops" -eq 1 ] && ! command cp -f .sops.yaml "$vault/$dest/.sops.yaml"; then
        ux_error "copy failed: ${vault}/${dest}/.sops.yaml"
        return 1
    fi
    git -C "$vault" add -- "$@" || {
        ux_error "git add failed in ${vault}"
        return 1
    }
    if git -C "$vault" diff --cached --quiet -- "$@"; then
        ux_info "no change: ${vault}/${dest} already holds this .enc.env; nothing to do"
        return 0
    fi
    if ! git -C "$vault" commit -m "$msg" -- "$@" >/dev/null; then
        ux_error "commit failed (files stay staged in ${vault})"
        return 1
    fi
    ux_success "committed: ${msg}"
    if [ "$do_push" -eq 0 ]; then
        ux_info "not pushed (--no-push). Next: git -C ${vault} push origin HEAD"
        return 0
    fi
    branch=$(git -C "$vault" symbolic-ref -q --short HEAD 2>/dev/null)
    if ! git -C "$vault" push origin HEAD; then
        ux_error "push failed (the commit stays local on ${branch:-HEAD})"
        ux_info "Next: git -C ${vault} pull --rebase && git -C ${vault} push origin HEAD"
        return 1
    fi
    ux_success "pushed ${branch:-HEAD} to origin"
}

# GH_HOST for gh: shared resolver (internal vs external PC), else empty so gh
# falls back to its own default host. lib/ is never auto-sourced (#2154, #2225).
_senv_gh_host() {
    command -v _gh_resolve_host >/dev/null 2>&1 ||
        . "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/lib/gh_host.sh" 2>/dev/null
    if command -v _gh_resolve_host >/dev/null 2>&1; then
        _gh_resolve_host 2>/dev/null
    fi
}

senv() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local cmd="${1:-}"
    case "$cmd" in
        "" | -h | --help | help)
            _senv_usage
            return 0
            ;;
        init | enc | dec | edit | run | check | key | create-pr | set | get | push | keys | vault-push) ;;
        *)
            ux_error "unknown senv command: ${cmd}"
            _senv_usage
            return 2
            ;;
    esac
    shift
    _senv_need_sops || return 1
    [ "$cmd" = "create-pr" ] && cmd="create_pr"
    [ "$cmd" = "vault-push" ] && cmd="vault_push"
    "_senv_${cmd}" "$@"
}

# Help registry (#2135, #2392): senv is a function, so my-help search finds it
# only through this row. Skipped when sourced without util/help_registry.sh.
# Keep this block last: the `return 0` skips anything appended below it.
command -v _register_func >/dev/null 2>&1 || return 0
_register_func senv "Encrypt/decrypt/run the current directory .env with sops + age (sops-help)"
