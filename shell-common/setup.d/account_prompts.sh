#!/bin/sh
# shell-common/setup.d/account_prompts.sh — account e-mail / account-ID
# prompts, tty only (#2140).
#
# Sourced by shell-common/setup.sh only (never auto-sourced, no interactive
# guard): relies on its SHELL_COMMON_DIR / DOTFILES_ROOT / ux_* / constants.

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
# Mirrors _resolve_account_id's tty-guard pattern: skip (with one warning) when stdin is
# not a tty (CI / test harness / `bash -c`) so non-interactive setup falls
# back to the current behavior (F-4). Caller must invoke this outside any
# pipe (see copy_local_files) so `[ -t 0 ]` reflects the real terminal.
_prompt_claude_account_emails() {
    _pcae_accounts="$1"
    _pcae_file="$2"

    # Non-interactive (summary-mode ./setup.sh, CI): skip, but say so (#2140).
    if [ ! -t 0 ]; then
        ux_warning "Claude account e-mails not set — run ./setup.sh -v, or add CLAUDE_ACCOUNT_EMAIL_<account> to ${_pcae_file#"$SHELL_COMMON_DIR"/}"
        return 0
    fi

    for _pcae_acct in $_pcae_accounts; do
        # Backticks are literal prompt text, so the format string stays
        # single-quoted (SC2016).
        # shellcheck disable=SC2016
        printf '`%s` 계정 이메일 (Enter로 건너뛰기): ' "$_pcae_acct" >&2
        read -r _pcae_email || _pcae_email=""
        _pcae_write_email_export "$_pcae_acct" "$_pcae_email" "$_pcae_file"
    done
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
