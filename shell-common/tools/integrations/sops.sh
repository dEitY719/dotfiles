#!/bin/sh
# shell-common/tools/integrations/sops.sh
# sops + age status diagnostics (issue #1833)
#
# SOPS_AGE_KEY_FILE is deliberately NOT exported: sops already defaults to
# ~/.config/sops/age/keys.txt. The private key must never reach stdout, so the
# key file is only stat'ed and fed to `age-keygen -y`, whose output is filtered.
#
# Install: install-sops-age
# Details: sops-help

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

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
        pub=$(age-keygen -y "$key" 2>/dev/null | grep '^age1' | grep -v 'AGE-SECRET-KEY')
        if [ -n "$pub" ]; then
            ux_success "public key: ${pub}"
        else
            ux_warning "could not derive public key (age-keygen -y failed)"
        fi
    fi
}

alias sops-status='sops_age_status'
