#!/bin/sh
# shell-common/setup.sh
# Environment-specific configuration setup for shell-common

set -e

# Get the directory where this script is located (sh-compatible)
SHELL_COMMON_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_ROOT="$(cd "$SHELL_COMMON_DIR/.." && pwd)"

# Source UX library for consistent output styling (sh-compatible: use . instead of source)
if [ -f "${SHELL_COMMON_DIR}/tools/ux_lib/ux_lib.sh" ]; then
    . "${SHELL_COMMON_DIR}/tools/ux_lib/ux_lib.sh"
else
    # Fallback: define basic functions if ux_lib is not available
    ux_header() { echo "=== $1 ==="; }
    ux_section() { echo ""; echo "$1"; }
    ux_success() { echo "✓ $1"; }
    ux_info() { echo "ℹ $1"; }
    ux_error() { echo "✗ $1" >&2; }
fi

# Latest-only backup policy (issue #806). SSOT for the fixed suffixes;
# fallback defaults guard against a missing helper (an empty suffix would
# overwrite the live target).
if [ -f "${SHELL_COMMON_DIR}/functions/dotfiles_backup.sh" ]; then
    . "${SHELL_COMMON_DIR}/functions/dotfiles_backup.sh"
fi
: "${DOTFILES_BACKUP_SUFFIX:=.backup}"
: "${DOTFILES_ORIGINAL_SUFFIX:=.original}"

# ============================================================================
# Configuration Values (SSOT - Single Source of Truth)
# ============================================================================
# These are extracted settings values for maintainability
# If values change, update only here (not in sed patterns)
# Note: Using sh-compatible variable naming (no associative arrays)

# Security configuration: the CA / SSL certificate paths are NOT kept here.
# Their SSOT is env/security.local.sh (gitignored; template
# env/security.local.example carries placeholders only, #1969) — read back
# via _local_value below, the same way tools/custom/setup_crt.sh does.

# Placeholder marker of the tracked *.local.example templates (#1944/#1969):
# fake hosts end in `.example.invalid`, fake cert files are `example-*.crt`;
# non-domain fakes (SSH key name, usage id, CA fingerprint, AWS account id,
# review model id) are listed one by one — keep in sync with the templates (#2021).
LOCAL_PLACEHOLDER_ERE='example\.invalid|/example-[a-z-]*\.crt|id_rsa_example|"EMP00000"|"000000000000"|EXAMPLEPROXYCAFINGERPRINT|example-corp/example-model'

# Fake gateway URL of opencode/opencode.json.internal, replaced at setup time
# with DOTFILES_OPENCODE_BASE_URL from env/internal.local.sh (#1967).
OPENCODE_URL_PLACEHOLDER='http://llm-gateway.example.invalid/v1'

# Account-ID placeholder of opencode/opencode.json.internal (#1982). The second
# alternative is the legacy token, read-only fallback: configs deployed before
# the rename may still carry it unsubstituted.
OPENCODE_ACCOUNT_ID_ERE='your-(account|knox)-id'

# Tool-specific configurations are managed via tracked files at project root
# and symlinked to their respective locations:
#   npm/   → ~/.npmrc
#   bun/   → ~/.bunfig.toml
#   pip/   → ~/.config/pip/pip.conf
#   uv/    → ~/.config/uv/uv.toml

# ============================================================================
# Helper Functions
# ============================================================================

# Prepare a config target path for symlink creation.
# Removes existing symlinks, backs up regular files and directories.
# Usage: _prepare_config_target "/path/to/config"
_prepare_config_target() {
    _target="$1"
    if [ -L "$_target" ]; then
        rm -f "$_target"
        ux_info "Removed existing symlink: $_target"
    elif [ -d "$_target" ]; then
        _backup="${_target}${DOTFILES_BACKUP_SUFFIX}"
        rm -rf "$_backup"
        mv "$_target" "$_backup"
        ux_warning "Backed up existing directory: $_backup"
    elif [ -f "$_target" ]; then
        _backup="${_target}${DOTFILES_BACKUP_SUFFIX}"
        rm -f "$_backup"
        mv "$_target" "$_backup"
        ux_info "Backed up existing file: $_backup"
    fi
}

# Resolve the deploy source for a tracked internal-mode config (#1968).
# Prefers the gitignored real-value sibling "<file>.local" when present and
# falls back to the tracked file, so behavior is unchanged without one.
# Seed the siblings with scripts/internal-config-migrate.sh. The tracked files
# hold placeholders only (#1986), so falling back to one warns on stderr
# (stdout is the captured path).
# Usage: _internal_src npm/npmrc.internal
_internal_src() {
    if [ -f "${DOTFILES_ROOT}/$1.local" ]; then
        printf '%s\n' "${DOTFILES_ROOT}/$1.local"
    else
        if grep -Eq "$LOCAL_PLACEHOLDER_ERE" "${DOTFILES_ROOT}/$1" 2>/dev/null; then
            ux_warning "$1 holds placeholder values and $1.local is missing — create $1.local with the real values and re-run setup" >&2
        fi
        printf '%s\n' "${DOTFILES_ROOT}/$1"
    fi
}

# Restore a config target from the latest backup after removing a dotfiles symlink.
# Usage: _restore_config_from_backup "/path/to/config"
_restore_config_from_backup() {
    _target="$1"
    if [ -L "$_target" ]; then
        rm -f "$_target"
        # Prefer the new fixed-suffix backup (issue #806); fall back to the
        # newest legacy timestamped backup so existing machines still migrate.
        if [ -e "${_target}${DOTFILES_BACKUP_SUFFIX}" ]; then
            _latest="${_target}${DOTFILES_BACKUP_SUFFIX}"
        else
            # Backup names are generated by this script (fixed `.backup.<ts>`
            # suffix), so `ls -t` mtime ordering is safe here (SC2012).
            # shellcheck disable=SC2012
            _latest="$(ls -t "${_target}".backup.* 2>/dev/null | head -1)"
        fi
        if [ -n "$_latest" ]; then
            mv "$_latest" "$_target"
            ux_success "Restored: $(basename "$_latest") → $_target"
        else
            ux_info "Removed dotfiles symlink (no backup to restore, using defaults)"
        fi
    else
        ux_info "No dotfiles config to remove: $_target"
    fi
}

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
                # Bedrock 으로 통일된 #677 이후, claude.local.sh 에 사내 게이트웨이
                # ANTHROPIC_BASE_URL/AUTH_TOKEN/MODEL 을 inject 하지 않는다 (#683 F-1).
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

# Escape + append one CLAUDE_ACCOUNT_EMAIL_<acct> export line to file $3
# (issue #1173 review, PR #1176). Pure — no prompt, no tty check — so it is
# directly unit-testable without a pty harness, unlike the interactive loop
# below. Empty $2 is a silent no-op (mirrors the caller's skip-on-Enter rule).
_pcae_write_email_export() {
    _pcae_acct="$1"
    _pcae_email="$2"
    _pcae_file="$3"

    [ -n "$_pcae_email" ] || return 0

    # Escape backslash/quote/backtick/dollar before embedding in a
    # double-quoted export — this file gets `.`-sourced on every shell
    # startup (shell-common/env/claude.sh), so an unescaped `"`, `` ` ``,
    # or `$(...)` in the typed value would execute as shell syntax. `[$]`
    # (not `\$`) matches a literal dollar portably across sed
    # implementations (gemini-code-assist review on PR #1176). The sed scripts
    # stay single-quoted on purpose — `$` must reach sed literally (SC2016).
    # shellcheck disable=SC2016
    _pcae_email_esc="$(printf '%s' "$_pcae_email" \
        | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
              -e 's/`/\\`/g' -e 's/[$]/\\$/g')"
    printf 'export CLAUDE_ACCOUNT_EMAIL_%s="%s"\n' \
        "$_pcae_acct" "$_pcae_email_esc" >> "$_pcae_file"
}

# Interactively populate CLAUDE_ACCOUNT_EMAIL_<account> for each account in
# $1 (space-separated), appending export lines to file $2 (issue #1173).
# Mirrors _resolve_account_id's tty-guard pattern: skip silently when stdin is
# not a tty (CI / test harness / `bash -c`) so non-interactive setup falls
# back to the current behavior (F-4). Caller must invoke this outside any
# pipe (see copy_local_files) so `[ -t 0 ]` reflects the real terminal.
_prompt_claude_account_emails() {
    _pcae_accounts="$1"
    _pcae_file="$2"

    [ -t 0 ] || return 0

    for _pcae_acct in $_pcae_accounts; do
        # Backticks are literal prompt text, so the format string stays
        # single-quoted (SC2016).
        # shellcheck disable=SC2016
        printf '`%s` 계정 이메일 (Enter로 건너뛰기): ' "$_pcae_acct" >&2
        read -r _pcae_email || _pcae_email=""
        _pcae_write_email_export "$_pcae_acct" "$_pcae_email" "$_pcae_file"
    done
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
}

setup_npm_symlink() {
    environment="$1"
    npmrc_target="$HOME/.npmrc"

    ux_header "Setting up npm configuration for: $environment"

    _prepare_config_target "$npmrc_target"

    # Create symlink based on environment
    case "$environment" in
        internal)
            ln -s "$(_internal_src npm/npmrc.internal)" "$npmrc_target"
            ux_success "Created symlink: ~/.npmrc → npm/npmrc.internal"
            ux_info "Using: internal Nexus repository + proxy"
            ;;
        external)
            ln -s "${DOTFILES_ROOT}/npm/npmrc.external" "$npmrc_target"
            ux_success "Created symlink: ~/.npmrc → npm/npmrc.external"
            ux_info "Using: Public npmjs registry (no proxy)"
            ;;
        public)
            # Public PC: pin npm prefix to a user-owned dir so `claude`
            # auto-update does not fail against the root-owned /usr default.
            ln -s "${DOTFILES_ROOT}/npm/npmrc.public" "$npmrc_target"
            ux_success "Created symlink: ~/.npmrc → npm/npmrc.public"
            ux_info "Using: Public npmjs registry (prefix pinned to ~/.npm-global)"
            ;;
    esac
}

setup_bun_config() {
    environment="$1"
    bunfig_target="$HOME/.bunfig.toml"

    ux_header "Setting up Bun configuration for: $environment"

    # Create symlink based on environment
    case "$environment" in
        internal)
            _prepare_config_target "$bunfig_target"
            ln -s "$(_internal_src bun/bunfig.toml.internal)" "$bunfig_target"
            ux_success "Created symlink: ~/.bunfig.toml → bun/bunfig.toml.internal"
            ux_info "Using: internal Nexus registry for npm packages"
            ;;
        external)
            _prepare_config_target "$bunfig_target"
            ln -s "${DOTFILES_ROOT}/bun/bunfig.toml.external" "$bunfig_target"
            ux_success "Created symlink: ~/.bunfig.toml → bun/bunfig.toml.external"
            ux_info "Using: Public npmjs registry (no proxy)"
            ;;
        public)
            _restore_config_from_backup "$bunfig_target"
            ;;
    esac
}

# Escape sed replacement metacharacters (\ / | &) so unusual values cannot
# corrupt a substitution. Usage: sed "s|x|$(_sed_escape "$val")|"
_sed_escape() {
    printf '%s' "$1" | sed -e 's/[\\/|&]/\\&/g'
}

# Resolve the internal account ID for OpenCode's internal-mode config (#1121, #1982).
# Lookup order (first non-empty wins):
#   1. $DOTFILES_ACCOUNT_ID env var (legacy env name as read-only fallback)
#      — reuse the shell-sourced SSOT (see env/development.local.example).
#   2. ~/.dotfiles-account-id file — persistent file SSOT, mirrors the
#      ~/.dotfiles-setup-mode convention (legacy file copied over by
#      _migrate_account_id_file).
#   3. one-time interactive prompt (tty only) — the entered value is saved to
#      ~/.dotfiles-account-id so later runs are non-interactive and idempotent.
# Prints the resolved ID on stdout; returns 1 (no output) when nothing is
# available and stdin is not a tty — keeping non-interactive setup / CI safe.
_resolve_account_id() {
    _acct_file="$HOME/.dotfiles-account-id"
    # Legacy env name, read-only fallback.
    _acct_val="${DOTFILES_ACCOUNT_ID:-${DOTFILES_KNOX_ID:-}}"

    # 1. Environment variable SSOT.
    if [ -n "$_acct_val" ]; then
        printf '%s\n' "$_acct_val"
        return 0
    fi

    # 2. File SSOT.
    _migrate_account_id_file
    if [ -f "$_acct_file" ]; then
        _acct_val="$(head -n 1 "$_acct_file" | tr -d '[:space:]')"
        if [ -n "$_acct_val" ]; then
            printf '%s\n' "$_acct_val"
            return 0
        fi
    fi

    # 3. One-time prompt (interactive shells only). Persist to the file SSOT so
    #    subsequent runs resolve via step 2 without prompting again.
    if [ -t 0 ]; then
        printf 'Enter your internal account ID (saved to %s): ' "$_acct_file" >&2
        read -r _acct_val || _acct_val=""
        _acct_val="$(printf '%s' "$_acct_val" | tr -d '[:space:]')"
        if [ -n "$_acct_val" ]; then
            printf '%s\n' "$_acct_val" >"$_acct_file"
            chmod 600 "$_acct_file" 2>/dev/null || true
            printf '%s\n' "$_acct_val"
            return 0
        fi
    fi

    return 1
}

# Copy the legacy account-ID file to ~/.dotfiles-account-id (#1982). Keeps the
# old file (older checkouts may still read it) and never overwrites an existing
# new file, so re-runs are no-ops.
_migrate_account_id_file() {
    # Legacy file name, read-only fallback.
    _acct_legacy="$HOME/.dotfiles-knox-id"
    [ -f "$_acct_legacy" ] || return 0
    [ -e "$HOME/.dotfiles-account-id" ] && return 0
    cp "$_acct_legacy" "$HOME/.dotfiles-account-id" \
        && chmod 600 "$HOME/.dotfiles-account-id" 2>/dev/null
    return 0
}

setup_opencode_config() {
    environment="$1"
    opencode_target="$HOME/.config/opencode/opencode.json"

    ux_header "Setting up OpenCode configuration for: $environment"

    case "$environment" in
        internal)
            mkdir -p "$(dirname "$opencode_target")"
            # The tracked template holds a fake gateway URL (#1967); the real
            # one comes from DOTFILES_OPENCODE_BASE_URL in the gitignored
            # env/internal.local.sh (empty while it is still the placeholder).
            _oc_url="$(_local_value DOTFILES_OPENCODE_BASE_URL "${SHELL_COMMON_DIR}/env/internal.local.sh")"
            if printf '%s' "$_oc_url" | grep -Eq "$LOCAL_PLACEHOLDER_ERE"; then
                _oc_url=""
            fi
            _oc_render=1
            if [ ! -L "$opencode_target" ] && [ -f "$opencode_target" ]; then
                # Preserve a fully customised config: never overwrite + never
                # back up (issue #792).
                if ! grep -Eq "$OPENCODE_ACCOUNT_ID_ERE" "$opencode_target" \
                    && ! grep -Eq "$LOCAL_PLACEHOLDER_ERE" "$opencode_target"; then
                    ux_info "Preserved customised OpenCode config: $opencode_target"
                    return 0
                fi
                # Without the real URL a re-render would replace a deployed
                # config's real values with placeholders: keep it (#1967).
                if [ -z "$_oc_url" ]; then
                    _oc_render=0
                    ux_warning "Kept existing $opencode_target (DOTFILES_OPENCODE_BASE_URL not set in shell-common/env/internal.local.sh)"
                fi
            fi
            if [ "$_oc_render" -eq 1 ]; then
                _prepare_config_target "$opencode_target"
                if [ -n "$_oc_url" ]; then
                    sed "s|${OPENCODE_URL_PLACEHOLDER}|$(_sed_escape "$_oc_url")|g" \
                        "${DOTFILES_ROOT}/opencode/opencode.json.internal" >"$opencode_target"
                    ux_success "Rendered opencode/opencode.json.internal → ~/.config/opencode/opencode.json"
                else
                    cp "${DOTFILES_ROOT}/opencode/opencode.json.internal" "$opencode_target"
                    ux_success "Copied template: opencode/opencode.json.internal → ~/.config/opencode/opencode.json"
                    ux_warning "Gateway URL is a placeholder: set DOTFILES_OPENCODE_BASE_URL in shell-common/env/internal.local.sh and re-run setup"
                fi
                chmod 600 "$opencode_target"
                ux_info "Using: internal LLM gateway"
            fi
            # Fill in the account ID from the SSOT (env → ~/.dotfiles-account-id →
            # one-time prompt) so the placeholder warning no longer recurs on
            # every setup (issue #1121). Falls back to the manual-edit warning
            # only when nothing is available and setup is non-interactive.
            _migrate_account_id_file
            if ! grep -Eq "$OPENCODE_ACCOUNT_ID_ERE" "$opencode_target"; then
                return 0
            fi
            _acct_id="$(_resolve_account_id)" || _acct_id=""
            if [ -n "$_acct_id" ]; then
                # Portable temp-file rewrite instead of `sed -i` — GNU and BSD
                # (macOS) disagree on the -i argument syntax (PR #1123 review).
                # `mv` drops the 600 perms, so re-apply chmod afterwards.
                sed -E "s/${OPENCODE_ACCOUNT_ID_ERE}/$(_sed_escape "$_acct_id")/g" "$opencode_target" >"${opencode_target}.tmp"
                mv "${opencode_target}.tmp" "$opencode_target"
                chmod 600 "$opencode_target"
                ux_success "Applied account ID to OpenCode config (SSOT: \$DOTFILES_ACCOUNT_ID or ~/.dotfiles-account-id)"
            else
                ux_warning "Edit $opencode_target and replace 'your-account-id' with your internal account ID"
                ux_info "Tip: save it once to ~/.dotfiles-account-id (or export DOTFILES_ACCOUNT_ID) to auto-fill next time"
            fi
            ;;
        external)
            mkdir -p "$(dirname "$opencode_target")"
            _prepare_config_target "$opencode_target"
            ln -s "${DOTFILES_ROOT}/opencode/opencode.json.external" "$opencode_target"
            ux_success "Created symlink: ~/.config/opencode/opencode.json → opencode/opencode.json.external"
            ux_info "Using: Local LiteLLM proxy (localhost:4444)"
            ;;
        public)
            if [ -L "$opencode_target" ]; then
                _restore_config_from_backup "$opencode_target"
            elif [ -f "$opencode_target" ]; then
                rm -f "$opencode_target"
                if [ -e "${opencode_target}${DOTFILES_BACKUP_SUFFIX}" ]; then
                    _latest="${opencode_target}${DOTFILES_BACKUP_SUFFIX}"
                else
                    # Backup names are generated by this script, so `ls -t`
                    # mtime ordering is safe here (SC2012).
                    # shellcheck disable=SC2012
                    _latest="$(ls -t "${opencode_target}.backup."* 2>/dev/null | head -1)"
                fi
                if [ -n "$_latest" ]; then
                    mv "$_latest" "$opencode_target"
                    ux_success "Restored: $(basename "$_latest") → $opencode_target"
                else
                    ux_info "Removed dotfiles-managed config (using OpenCode defaults)"
                fi
            fi
            ;;
    esac
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

setup_uv_config() {
    environment="$1"
    uv_config_dir="${HOME}/.config/uv"
    uv_conf="${uv_config_dir}/uv.toml"

    # Ensure ~/.config/uv directory exists
    mkdir -p "$uv_config_dir"

    ux_header "Setting up uv configuration for: $environment"

    _prepare_config_target "$uv_conf"

    # Create symlink based on environment
    case "$environment" in
        internal)
            ln -s "$(_internal_src uv/uv.toml.internal)" "$uv_conf"
            ux_success "Created symlink: ~/.config/uv/uv.toml → uv/uv.toml.internal"
            ux_info "Using: internal repositories + proxy"
            ;;
        external|public)
            # External/Public: no uv.toml needed (defaults to public PyPI)
            ux_info "No uv.toml needed (using default public PyPI)"
            ;;
    esac
}

setup_pip_config() {
    environment="$1"
    pip_config_dir="${HOME}/.config/pip"
    pip_conf="${pip_config_dir}/pip.conf"

    # Ensure ~/.config/pip directory exists
    mkdir -p "$pip_config_dir"

    ux_header "Setting up pip configuration for: $environment"

    _prepare_config_target "$pip_conf"

    # Create symlink based on environment
    case "$environment" in
        internal)
            ln -s "$(_internal_src pip/pip.conf.internal)" "$pip_conf"
            ux_success "Created symlink: ~/.config/pip/pip.conf → pip/pip.conf.internal"
            ux_info "Using: internal repositories"
            ;;
        external|public)
            ln -s "${DOTFILES_ROOT}/pip/pip.conf.external" "$pip_conf"
            ux_success "Created symlink: ~/.config/pip/pip.conf → pip/pip.conf.external"
            ux_info "Using: Public PyPI"
            ;;
    esac
}

setup_cargo_config() {
    environment="$1"
    cargo_config_dir="${HOME}/.cargo"
    cargo_conf="${cargo_config_dir}/config.toml"

    # Ensure ~/.cargo directory exists
    mkdir -p "$cargo_config_dir"

    ux_header "Setting up Cargo configuration for: $environment"

    case "$environment" in
        internal)
            _prepare_config_target "$cargo_conf"
            ln -s "$(_internal_src cargo/config.toml.internal)" "$cargo_conf"
            ux_success "Created symlink: ~/.cargo/config.toml → cargo/config.toml.internal"
            ux_info "Using: internal Nexus proxy for crates.io"
            ;;
        external|public)
            _restore_config_from_backup "$cargo_conf"
            ;;
    esac
}

setup_nuget_config() {
    environment="$1"
    # NuGet config can be read from two paths depending on tooling
    nuget_primary="${HOME}/.nuget/NuGet/NuGet.Config"
    nuget_secondary="${HOME}/.config/NuGet/NuGet.Config"

    ux_header "Setting up NuGet configuration for: $environment"

    case "$environment" in
        internal)
            for _nuget_conf in "$nuget_primary" "$nuget_secondary"; do
                mkdir -p "$(dirname "$_nuget_conf")"
                _prepare_config_target "$_nuget_conf"
                ln -s "$(_internal_src nuget/NuGet.Config.internal)" "$_nuget_conf"
            done
            ux_success "Created symlinks: NuGet.Config → nuget/NuGet.Config.internal"
            ux_info "  ~/.nuget/NuGet/ (dotnet CLI) + ~/.config/NuGet/ (mono)"
            ux_info "Using: internal Nexus proxy for NuGet"
            ;;
        external|public)
            for _nuget_conf in "$nuget_primary" "$nuget_secondary"; do
                _restore_config_from_backup "$_nuget_conf"
            done
            ux_info "NuGet config restored to defaults"
            ;;
    esac
}

setup_rpm_repo() {
    environment="$1"
    repo_target="/etc/yum.repos.d/ds.repo"
    marker="MANAGED_BY_DOTFILES"

    ux_header "Setting up RPM repository configuration for: $environment"

    # Gate 1: Only proceed if yum or dnf is available
    if ! command -v yum >/dev/null 2>&1 && ! command -v dnf >/dev/null 2>&1; then
        ux_info "Skipped: yum/dnf not found (not a RHEL/CentOS system)"
        return 0
    fi

    # Gate 2: Verify RHEL 8 — do not deploy RHEL 8.6 repos to Fedora/Rocky/RHEL 9
    if [ -f /etc/os-release ]; then
        _rpm_os_id="$(. /etc/os-release && echo "${ID:-}")"
        _rpm_os_version="$(. /etc/os-release && echo "${VERSION_ID:-}")"
        case "$_rpm_os_id" in
            rhel|centos)
                case "$_rpm_os_version" in
                    8|8.*) ;; # RHEL 8.x — proceed
                    *)
                        ux_info "Skipped: RHEL ${_rpm_os_version} detected (repo is RHEL 8.6 only)"
                        return 0
                        ;;
                esac
                ;;
            *)
                ux_info "Skipped: ${_rpm_os_id} detected (repo is RHEL 8 only)"
                return 0
                ;;
        esac
    fi

    # Gate 3: Verify privilege — use sudo if needed, skip if unavailable
    _rpm_run_privileged=""
    if [ "$(id -u)" = "0" ]; then
        _rpm_run_privileged=""  # already root, no sudo needed
    elif command -v sudo >/dev/null 2>&1; then
        _rpm_run_privileged="sudo"
        ux_info "Root privileges required for /etc/yum.repos.d/ — sudo will prompt for password"
    else
        ux_warning "Skipped: sudo not available and not running as root"
        return 0
    fi

    case "$environment" in
        internal)
            _rpm_src="$(_internal_src rpm/ds.repo.internal)"
            # A placeholder repo in /etc would break dnf/yum: keep the
            # existing system file instead (_internal_src already warned).
            if grep -Eq "$LOCAL_PLACEHOLDER_ERE" "$_rpm_src" 2>/dev/null; then
                ux_info "Skipped: $repo_target left untouched (placeholder source)"
                return 0
            fi

            # Ensure target directory exists
            if [ ! -d "/etc/yum.repos.d" ]; then
                $_rpm_run_privileged mkdir -p "/etc/yum.repos.d"
                ux_info "Created directory: /etc/yum.repos.d"
            fi

            # Backup existing repo file if present
            if [ -f "$repo_target" ]; then
                backup="${repo_target}.backup.$(date +%Y%m%d%H%M%S)"
                $_rpm_run_privileged mv "$repo_target" "$backup"
                ux_info "Backed up existing file: $backup"
            fi

            # Copy (not symlink) since this is a system-level config in /etc/
            $_rpm_run_privileged cp "$_rpm_src" "$repo_target"
            ux_success "Copied: rpm/ds.repo.internal → $repo_target"
            ux_info "Using: internal repositories (RHEL 8.6)"
            ;;
        external|public)
            # Only remove if the file was deployed by dotfiles (has marker)
            if [ -f "$repo_target" ] && grep -q "$marker" "$repo_target" 2>/dev/null; then
                backup="${repo_target}.backup.$(date +%Y%m%d%H%M%S)"
                $_rpm_run_privileged mv "$repo_target" "$backup"
                ux_info "Backed up and removed dotfiles-managed repo: $backup"
            elif [ -f "$repo_target" ]; then
                ux_info "Existing $repo_target is not managed by dotfiles — leaving untouched"
            fi
            ;;
    esac
}

setup_apt_sources() {
    environment="$1"
    sources_target="/etc/apt/sources.list"
    marker="MANAGED_BY_DOTFILES"

    ux_header "Setting up APT sources configuration for: $environment"

    # Gate 1: Only proceed if apt is available
    if ! command -v apt >/dev/null 2>&1; then
        ux_info "Skipped: apt not found (not a Debian/Ubuntu system)"
        return 0
    fi

    # Gate 2: Verify privilege — use sudo if needed, skip if unavailable
    _apt_run_privileged=""
    if [ "$(id -u)" = "0" ]; then
        _apt_run_privileged=""
    elif command -v sudo >/dev/null 2>&1; then
        _apt_run_privileged="sudo"
        ux_info "Root privileges required for /etc/apt/sources.list — sudo will prompt for password"
    else
        ux_warning "Skipped: sudo not available and not running as root"
        return 0
    fi

    # Read OS identity (used by both deploy and restore paths)
    _apt_os_id=""
    _apt_codename=""
    if [ -f /etc/os-release ]; then
        _apt_os_id="$(. /etc/os-release && echo "${ID:-}")"
        _apt_codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
    fi

    case "$environment" in
        internal)
            # Deploy gate: verify Ubuntu + matching config file exists
            if [ "$_apt_os_id" != "ubuntu" ]; then
                ux_info "Skipped: ${_apt_os_id:-unknown} detected (only Ubuntu is supported)"
                return 0
            fi
            _apt_source="${DOTFILES_ROOT}/apt/sources.list.${_apt_codename}"
            if [ -z "$_apt_codename" ] || [ ! -f "$_apt_source" ]; then
                # Listing repo-tracked `apt/sources.list.*` names — all
                # alphanumeric, so `ls` is fine here (SC2012).
                # shellcheck disable=SC2012
                ux_info "Skipped: no apt config for '${_apt_codename:-unknown}' (available: $(ls "${DOTFILES_ROOT}"/apt/sources.list.* 2>/dev/null | sed 's/.*sources\.list\.//' | grep -v '\.internal' | tr '\n' ' ' || echo 'none'))"
                return 0
            fi

            # Backup existing sources.list if present and not already managed
            if [ -f "$sources_target" ]; then
                if ! grep -q "$marker" "$sources_target" 2>/dev/null; then
                    backup="${sources_target}.backup.$(date +%Y%m%d%H%M%S)"
                    $_apt_run_privileged cp "$sources_target" "$backup"
                    ux_info "Backed up original: $backup"
                fi
            fi

            $_apt_run_privileged cp "$_apt_source" "$sources_target"
            ux_success "Copied: apt/sources.list.${_apt_codename} → $sources_target"
            ux_info "Using: official Ubuntu mirrors (Ubuntu ${_apt_codename})"
            ux_info "Run 'sudo apt update' to refresh package lists"
            ;;
        external|public)
            # Restore path: no codename/OS gate — must always reach here
            # to handle post-upgrade scenarios (e.g., jammy → noble)
            if [ -f "$sources_target" ] && grep -q "$marker" "$sources_target" 2>/dev/null; then
                # Backup names are generated by this script, so `ls -t` mtime
                # ordering is safe here (SC2012).
                # shellcheck disable=SC2012
                _apt_latest_backup="$(ls -t "${sources_target}".backup.* 2>/dev/null | head -1)"
                if [ -n "$_apt_latest_backup" ]; then
                    $_apt_run_privileged cp "$_apt_latest_backup" "$sources_target"
                    ux_success "Restored original: $_apt_latest_backup → $sources_target"
                else
                    $_apt_run_privileged rm -f "$sources_target"
                    ux_warning "Removed dotfiles-managed sources.list (no backup found to restore)"
                fi
            elif [ -f "$sources_target" ]; then
                ux_info "Existing $sources_target is not managed by dotfiles — leaving untouched"
            fi
            ;;
    esac
}

# ============================================================================
# Main Menu
# ============================================================================

main() {
    echo ""
    ux_header "Shell-Common Environment Setup"
    echo ""
    echo "Select your environment:"
    echo ""
    echo "1) Public PC (home environment)"
    echo "2) Internal company PC (direct connection)"
    echo "3) External company PC (VPN)"
    echo ""

    printf "Enter your choice (1-3): "
    read -r choice
    echo ""

    # Persist the symbolic mode (not the numeric choice) right after the
    # selection, before any step can fail under `set -e`: a mid-run failure
    # used to leave the OLD mode on disk, so the next shell and setup run
    # defaulted to the wrong environment. Every step below re-runs on the next
    # ./setup.sh, so writing first keeps setup idempotent. Readers canonicalise
    # legacy "1|2|3" files (util/setup_mode_read.sh).

    case "$choice" in
        1) setup_mode="public" ;;
        2) setup_mode="internal" ;;
        3) setup_mode="external" ;;
        *)
            ux_error "Invalid choice. Please run again and select 1, 2, or 3."
            exit 1
            ;;
    esac
    echo "$setup_mode" >"$HOME/.dotfiles-setup-mode"

    case "$choice" in
        1)
            ux_info "Selected: Public PC"
            cleanup_local_files
            setup_npm_symlink "public"
            setup_bun_config "public"
            setup_opencode_config "public"
            setup_pip_config "public"
            setup_uv_config "public"
            setup_cargo_config "public"
            setup_nuget_config "public"
            setup_rpm_repo "public"
            setup_apt_sources "public"
            echo ""
            ux_success "Setup complete for public PC (home environment)"
            ux_info "All environment-specific configuration removed"
            ux_info "  - NPM: ~/.npmrc → npm/npmrc.public (prefix pinned to ~/.npm-global)"
            ux_info "Setup mode saved to: ~/.dotfiles-setup-mode"
            echo ""
            ;;
        2)
            ux_info "Selected: Internal company PC (direct connection)"
            cleanup_local_files
            setup_local_files "internal"
            # Seed gitignored *.internal.local real-value siblings before the
            # links are made (#1968). Never overwrites; skips placeholders.
            bash "${DOTFILES_ROOT}/scripts/internal-config-migrate.sh" --apply \
                || ux_warning "internal-config-migrate.sh failed; links fall back to tracked *.internal"
            # ~/.ssh/config.internal.local + ~/.gitconfig.internal.local (#2006)
            bash "${DOTFILES_ROOT}/scripts/internal-ssh-git-migrate.sh" --apply \
                || ux_warning "internal-ssh-git-migrate.sh failed; internal SSH/GHES hosts may be unresolved"
            setup_npm_symlink "internal"
            setup_bun_config "internal"
            setup_opencode_config "internal"
            setup_pip_config "internal"
            setup_uv_config "internal"
            setup_cargo_config "internal"
            setup_nuget_config "internal"
            setup_rpm_repo "internal"
            setup_apt_sources "internal"
            echo ""
            ux_success "Setup complete for internal company PC"
            ux_info "Changes made:"
            ux_info "  - Installed all .local.example files as .local.sh (existing files kept)"
            ux_info "  - Security: System CA Bundle (Option 2) activated"
            ux_info "  - SSL Certificate: proxy inspection CA (path from env/security.local.sh)"
            ux_info "  - Proxy: company proxy from env/proxy.local.sh"
            ux_info "  - NPM: ~/.npmrc → npm/npmrc.internal (Nexus + proxy)"
            ux_info "  - Bun: ~/.bunfig.toml → bun/bunfig.toml.internal (Nexus registry)"
            ux_info "  - OpenCode: opencode/opencode.json.internal rendered with DOTFILES_OPENCODE_BASE_URL (env/internal.local.sh) + account ID from SSOT (\$DOTFILES_ACCOUNT_ID / ~/.dotfiles-account-id, else 1-time prompt)"
            ux_info "  - Pip: internal repository configured"
            ux_info "  - uv: internal repository + proxy configured"
            ux_info "  - Cargo: ~/.cargo/config.toml (Nexus proxy for crates.io)"
            ux_info "  - NuGet: ~/.nuget/NuGet/NuGet.Config (Nexus proxy for nuget.org)"
            ux_info "  - RPM: /etc/yum.repos.d/ds.repo (if yum/dnf available)"
            ux_info "  - APT: /etc/apt/sources.list (if Ubuntu jammy)"
            ux_info "Setup mode saved to: ~/.dotfiles-setup-mode"
            echo ""
            ux_section "⚠️  IMPORTANT: Reload your shell to apply changes"
            ux_bullet "Option 1 (Current shell): source ~/.bashrc"
            ux_bullet "Option 2 (New shell): exec bash  or  exec zsh"
            ux_bullet "Verify: ssl-help  (or: echo \$SSL_CERT_FILE)"
            echo ""
            ;;
        3)
            ux_info "Selected: External company PC (VPN)"
            cleanup_local_files
            setup_local_files "external"
            setup_npm_symlink "external"
            setup_bun_config "external"
            setup_opencode_config "external"
            setup_pip_config "external"
            setup_uv_config "external"
            setup_cargo_config "external"
            setup_nuget_config "external"
            setup_rpm_repo "external"
            setup_apt_sources "external"
            echo ""
            ux_success "Setup complete for external company PC"
            ux_info "Changes made:"
            ux_info "  - Installed .local.example files as .local.sh (except proxy; existing files kept)"
            ux_info "  - Security: Custom Certificate (Option 1) activated"
            ux_info "  - SSL Certificate: custom CA (path from env/security.local.sh)"
            ux_info "  - Proxy: Skipped (not needed for VPN - direct connection)"
            ux_info "  - NPM: ~/.npmrc → npm/npmrc.external (npmjs + no proxy)"
            ux_info "  - Bun: ~/.bunfig.toml → bun/bunfig.toml.external (public registry)"
            ux_info "  - OpenCode: ~/.config/opencode/opencode.json → opencode/opencode.json.external"
            ux_info "  - Pip: Public PyPI configured"
            ux_info "  - Next: Run 'setup_crt.sh' to install the certificate"
            ux_info "Setup mode saved to: ~/.dotfiles-setup-mode"
            echo ""
            ux_section "⚠️  IMPORTANT: Reload your shell to apply changes"
            ux_bullet "Option 1 (Current shell): source ~/.bashrc"
            ux_bullet "Option 2 (New shell): exec bash  or  exec zsh"
            ux_bullet "Verify: ssl-help  (or: echo \$SSL_CERT_FILE)"
            echo ""
            ;;
    esac
}

# Direct-exec guard: only invoke main() when executed directly. When this
# script is sourced (e.g. by bats tests), `$0` reflects the parent shell
# instead of `setup.sh`, so the pattern below won't match and main() is
# skipped — letting tests call individual setup_* functions in isolation.
case "$0" in
    *setup.sh) main "$@" ;;
esac
