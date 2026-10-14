#!/bin/sh
# shell-common/setup.d/local_files.sh — *.local.sh lifecycle (cleanup /
# install / security toggle) and the per-mode _pre_<mode> hooks (#2140).
#
# Sourced by shell-common/setup.sh only (never auto-sourced, no interactive
# guard): relies on its SHELL_COMMON_DIR / DOTFILES_ROOT / ux_* / constants.

# Print the double-quoted value of the first `^NAME="..."` line in a file
# (empty when the file or line is missing). Usage: _local_value NAME FILE
_local_value() {
    [ -f "$2" ] || return 0
    grep -m1 -E "^(export )?$1=" "$2" | cut -d'"' -f2
}

# Warn when a *.local.sh still carries template placeholders (#1969): the
# tracked templates hold fake values only, real ones must be typed in once.
_warn_if_placeholder() {
    if grep -Eq "$LOCAL_PLACEHOLDER_ERE" "$1" 2>/dev/null; then
        # Names only, never values (#2021).
        _wip_vars="$(grep -E "$LOCAL_PLACEHOLDER_ERE" "$1" \
            | sed -n 's/^[[:space:]]*\(export[[:space:]]\{1,\}\)\{0,1\}\([A-Za-z_][A-Za-z0-9_]*\)=.*/\2/p' \
            | paste -sd, - | sed 's/,/, /g')"
        ux_warning "${1#"$SHELL_COMMON_DIR"/} still has placeholder values${_wip_vars:+ ($_wip_vars)} — fill in the real ones (see the template comments)"
    fi
}

# Backup name of a generated local file: foo.local.sh -> foo.backup.local.sh
# (still matched by the `*.local.sh` gitignore rule).
_local_backup_path() {
    printf '%s\n' "${1%.local.sh}.backup.local.sh"
}

cleanup_local_files() {
    ux_header "Cleaning up environment-specific files"

    # Move (never delete) every live .local.sh aside (#1969): since the
    # tracked templates only carry placeholders, a deleted file's real values
    # could not be regenerated. copy_local_files restores these backups.
    find "$SHELL_COMMON_DIR" -name "*.local.sh" ! -name "*.backup.local.sh" -type f | while IFS= read -r local_file; do
        mv -f "$local_file" "$(_local_backup_path "$local_file")"
        ux_success "Moved aside: ${local_file#"$SHELL_COMMON_DIR"/} (restored on internal/external setup)"
    done
}

# Install one generated local file without ever clobbering real values:
# keep an existing file, else restore its backup, else copy the template.
_install_local_file() {
    _ilf_example="$1"
    _ilf_local="$2"
    _ilf_backup="$(_local_backup_path "$_ilf_local")"
    if [ -f "$_ilf_local" ]; then
        ux_info "Kept existing: ${_ilf_local#"$SHELL_COMMON_DIR"/}"
    elif [ -f "$_ilf_backup" ]; then
        mv "$_ilf_backup" "$_ilf_local"
        ux_success "Restored: ${_ilf_local#"$SHELL_COMMON_DIR"/}"
    else
        cp "$_ilf_example" "$_ilf_local"
        ux_success "Created: ${_ilf_local#"$SHELL_COMMON_DIR"/}"
    fi
    _warn_if_placeholder "$_ilf_local"
}

copy_local_files() {
    environment="$1"

    ux_header "Copying template files for: $environment"

    # External-PC account list. SSOT is shell-common/env/claude.sh's
    # external-mode default (CLAUDE_ENABLED_ACCOUNTS="personal work work1");
    # kept as a literal here (not sourced from claude.sh) because that file
    # has an interactive guard and sources claude.local.sh itself — the very
    # file this function is generating. Update both places if the list
    # changes. Assigned once here, before the `find | while` pipe below,
    # so it survives into the post-pipe block further down (that pipe forks
    # a subshell — anything assigned inside it is lost once `done` returns).
    _ext_accounts="personal work work1"

    # Decided before the pipe for the same reason: the email prompt below
    # runs only when claude.local.sh is about to be created from the template
    # (a kept / restored file already has its email lines, #1969).
    _claude_local_file="${SHELL_COMMON_DIR}/env/claude.local.sh"
    _claude_fresh=1
    if [ -f "$_claude_local_file" ] || [ -f "$(_local_backup_path "$_claude_local_file")" ]; then
        _claude_fresh=0
    fi

    # Install .local.example files as .local.sh (sh-compatible approach) to .local.sh (sh-compatible approach)
    find "$SHELL_COMMON_DIR" -name "*.local.example" -type f | while IFS= read -r example_file; do
        dir="$(dirname "$example_file")"
        filename="$(basename "$example_file" .example)"
        local_file="${dir}/${filename%.*}.local.sh"
        basename_file="$(basename "$example_file")"

        # Environment-specific handling
        case "$environment" in
            internal)
                # Internal company PC: install ALL .local.example files.
                # claude.local.sh 에 사내 게이트웨이 ANTHROPIC_BASE_URL/AUTH_TOKEN/
                # MODEL 을 inject 하지 않는다 (#683 F-1).
                # CLAUDE_ENABLED_ACCOUNTS 도 shell-common/env/claude.sh 가 setup-mode
                # 기준으로 "work" (single-account) 를 SSOT 로 export 하므로 여기서
                # 덮어쓰지 않는다.
                _install_local_file "$example_file" "$local_file"
                ;;
            external)
                # External company PC (VPN): skip proxy.local.example
                # Reason: proxy.local.sh is only valid for internal environment
                # (a backup moved aside by cleanup_local_files stays put).
                if [ "$basename_file" = "proxy.local.example" ]; then
                    ux_info "Skipped (not needed for VPN): ${basename_file}"
                else
                    _ilf_fresh=0
                    [ -f "$local_file" ] || [ -f "$(_local_backup_path "$local_file")" ] || _ilf_fresh=1
                    _install_local_file "$example_file" "$local_file"

                    # External-specific: Auto-enable work1 for multi-account
                    # setup — only on a fresh template copy, so a kept or
                    # restored file never gets the block appended twice.
                    if [ "$basename_file" = "claude.local.example" ] && [ "$_ilf_fresh" = 1 ]; then
                        cat >> "$local_file" <<EOF

# ─── External PC: Multi-account setup ────────────────────────────────────
export CLAUDE_ENABLED_ACCOUNTS="$_ext_accounts"
EOF
                        ux_info "  + Configured: work1 account for multi-account setup"
                    fi
                fi
                ;;
        esac
    done

    # External-specific: interactive per-account email prompt (issue #1173),
    # run *after* the find|while pipe above (not inside it) so the prompt's
    # own `[ -t 0 ]` check sees the real terminal — inside the pipe, fd 0 is
    # rebound to find's output and would always read as non-tty. Populates
    # CLAUDE_ACCOUNT_EMAIL_<name> so the account/email mismatch guard in
    # tools/integrations/claude.sh works without hand-editing the file on
    # every new PC. Guarded on the file actually having been created above
    # (skipped e.g. if claude.local.example is ever removed from the repo).
    if [ "$environment" = "external" ] && [ "$_claude_fresh" = 1 ] && [ -f "$_claude_local_file" ]; then
        _prompt_claude_account_emails "$_ext_accounts" "$_claude_local_file"
    fi
}

setup_security_config() {
    environment="$1"
    security_local="${SHELL_COMMON_DIR}/env/security.local.sh"

    # The sed toggles below key on the option path prefixes kept by
    # env/security.local.example (/usr/local/share/..., /etc/ssl/certs/...,
    # /usr/share/ca-certificates/...); the file names themselves live only in
    # each PC's security.local.sh (#1969).
    case "$environment" in
        internal)
            ux_info "Configuring security for internal company PC (System CA)"
            # CA_CERT: comment out Option 1, uncomment Option 2.
            # SSL_CERT_FILE: Option 2 (proxy inspection CA) — reverted here too
            # in case a restored file was last toggled for external.
            if [ -f "$security_local" ]; then
                sed -i 's/^CA_CERT="\/usr\/local\/share/#CA_CERT="\/usr\/local\/share/' "$security_local"
                sed -i 's/^#CA_CERT="\/etc\/ssl\/certs/CA_CERT="\/etc\/ssl\/certs/' "$security_local"
                sed -i 's/^SSL_CERT_FILE="\/usr\/local\/share/#SSL_CERT_FILE="\/usr\/local\/share/' "$security_local"
                sed -i 's/^#SSL_CERT_FILE="\/usr\/share\/ca-certificates/SSL_CERT_FILE="\/usr\/share\/ca-certificates/' "$security_local"
            fi
            ;;
        external)
            ux_info "Configuring security for external company PC (Custom Certificate)"
            if [ -f "$security_local" ]; then
                sed -i 's/^#CA_CERT="\/usr\/local\/share/CA_CERT="\/usr\/local\/share/' "$security_local"
                sed -i 's/^CA_CERT="\/etc\/ssl\/certs/#CA_CERT="\/etc\/ssl\/certs/' "$security_local"
                # SSL_CERT_FILE: comment out Option 2, uncomment Option 1
                sed -i 's/^SSL_CERT_FILE="\/usr\/share\/ca-certificates/#SSL_CERT_FILE="\/usr\/share\/ca-certificates/' "$security_local"
                sed -i 's/^#SSL_CERT_FILE="\/usr\/local\/share/SSL_CERT_FILE="\/usr\/local\/share/' "$security_local"
            fi
            ;;
        *)
            ux_error "Unknown environment: $environment"
            return 1
            ;;
    esac
    ux_success "CA Certificate: $(_local_value CA_CERT "$security_local")"
    ux_success "SSL Certificate: $(_local_value SSL_CERT_FILE "$security_local")"
    if [ "$environment" = external ]; then
        ux_info "Next: Run 'setup_crt.sh' to install the certificate"
    fi
}

verify_config() {
    environment="$1"

    ux_header "Verifying configuration for: $environment"

    # Verify CA cert is accessible if configured (SSOT: security.local.sh)
    ca_cert="$(_local_value CA_CERT "${SHELL_COMMON_DIR}/env/security.local.sh")"
    if [ -n "$ca_cert" ] && [ -f "$ca_cert" ]; then
        ux_success "CA Certificate accessible: $ca_cert"
    elif [ -n "$ca_cert" ]; then
        ux_info "CA Certificate not found yet: $ca_cert (will be installed by setup_crt.sh)"
    fi
}

setup_local_files() {
    environment="$1"

    ux_header "Setting up environment-specific files for: $environment"

    # Stage 1: Copy template files
    copy_local_files "$environment"

    # Stage 2: Configure each setting type
    setup_security_config "$environment"

    # Stage 3: Verify configuration
    verify_config "$environment"
}

# ============================================================================
# Per-mode pre-steps (before the registry loop)
# ============================================================================

_pre_public() {
    cleanup_local_files
}

_pre_internal() {
    cleanup_local_files
    setup_local_files internal
    # Seed gitignored *.internal.local real-value siblings before the
    # links are made (#1968). Never overwrites; skips placeholders.
    bash "${DOTFILES_ROOT}/scripts/internal-config-migrate.sh" --apply \
        || ux_warning "internal-config-migrate.sh failed; links fall back to tracked *.internal"
    # ~/.ssh/config.internal.local + ~/.gitconfig.internal.local (#2006)
    bash "${DOTFILES_ROOT}/scripts/internal-ssh-git-migrate.sh" --apply \
        || ux_warning "internal-ssh-git-migrate.sh failed; internal SSH/GHES hosts may be unresolved"
}

_pre_external() {
    cleanup_local_files
    setup_local_files external
}
