#!/bin/bash
# shellcheck disable=SC2148

# bash/app/git-secret.bash
# Git-secret integration and helper functions

# ==============================================================================
# Git Secret Helper Functions
# ==============================================================================

# Git Secret Help
# Register with myhelp
# shellcheck disable=SC2034  # consumed by myhelp for help listings
HELP_DESCRIPTIONS["gs-help"]="Manage GPG-encrypted secrets in Git"
gs-help() {
    ux_header "Git Secret Usage"
    ux_info "Git Secret is a tool to store your private data inside a Git repo."
    ux_bullet "It uses GPG encryption for security."
    echo ""

    ux_section "Workflow (GPG based)"
    ux_numbered 1 "Installation: Install git-secret (e.g., '${UX_PRIMARY}install-git-secret.sh${UX_RESET}')"
    ux_numbered 2 "Generate a GPG key: '${UX_PRIMARY}gpg --full-generate-key${UX_RESET}'"
    ux_numbered 3 "Initialize a git repo for git-secret: '${UX_PRIMARY}git secret init${UX_RESET}'"
    ux_numbered 4 "Add team members' GPG public keys: '${UX_PRIMARY}git secret tell user@example.com${UX_RESET}'"
    ux_numbered 5 "Add files to hide (e.g., .env): '${UX_PRIMARY}git secret add .env${UX_RESET}'"
    ux_numbered 6 "Encrypt (hide) added files: '${UX_PRIMARY}git secret hide${UX_RESET}' (creates .env.secret)"
    ux_numbered 7 "Decrypt (reveal) files after git pull: '${UX_PRIMARY}git secret reveal${UX_RESET}'"
    echo ""

    ux_section "Available Commands"
    ux_table_header "Command" "Description"
    ux_table_row "gs_init" "Initializes git-secret in a repo."
    ux_table_row "gs_tell <emails>" "Adds GPG keys to git-secret."
    ux_table_row "gs_add <files>" "Adds files to be encrypted."
    ux_table_row "gs_hide" "Encrypts all added files."
    ux_table_row "gs_reveal" "Decrypts all files."
    ux_table_row "gs_list" "Lists encrypted files."
    ux_table_row "gs_whoknows" "Lists GPG keys authorized to decrypt."
    echo ""
}

# ==============================================================================
# Git Secret Aliases/Functions
# ==============================================================================

# Initialize git-secret
gs_init() {
    ux_info "Initializing git-secret in current repository..."
    if git secret init "$@"; then
        ux_success "git-secret initialized."
        ux_info "Remember to run '${UX_PRIMARY}git secret tell <your_gpg_email>${UX_RESET}'"
    else
        ux_error "Failed to initialize git-secret."
    fi
}

# Add GPG keys to git-secret
gs_tell() {
    if [ $# -eq 0 ]; then
        ux_error "Usage: gs_tell <GPG_EMAIL1> [GPG_EMAIL2...]"
        return 1
    fi
    ux_info "Adding GPG key(s) to git-secret..."
    if git secret tell "$@"; then
        ux_success "GPG key(s) added."
    else
        ux_error "Failed to add GPG key(s)."
    fi
}

# Add files to be encrypted
gs_add() {
    if [ $# -eq 0 ]; then
        ux_error "Usage: gs_add <file1> [file2...]"
        return 1
    fi
    ux_info "Adding file(s) to git-secret for encryption..."
    if git secret add "$@"; then
        ux_success "File(s) added to git-secret. Now run '${UX_PRIMARY}gs_hide${UX_RESET}' to encrypt."
    else
        ux_error "Failed to add file(s) to git-secret."
    fi
}

# Encrypt (hide) files
gs_hide() {
    ux_info "Encrypting git-secret files..."
    if git secret hide "$@"; then
        ux_success "Files encrypted (hidden)."
        ux_info "Don't forget to '${UX_PRIMARY}git add .gitsecret/${UX_RESET}' and '${UX_PRIMARY}git add <your_secret_file>.secret${UX_RESET}'"
    else
        ux_error "Failed to encrypt (hide) files."
    fi
}

# Decrypt (reveal) files
gs_reveal() {
    ux_info "Decrypting git-secret files..."
    if git secret reveal "$@"; then
        ux_success "Files decrypted (revealed)."
    else
        ux_error "Failed to decrypt (reveal) files. Ensure your GPG key is set up."
    fi
}

# List encrypted files
gs_list() {
    ux_info "Listing git-secret files:"
    git secret list "$@"
}

# List GPG keys authorized to decrypt
gs_whoknows() {
    ux_info "Listing GPG keys authorized to decrypt git-secret:"
    git secret whoknows "$@"
}

# Ensure git-secret is available
if ! command -v git-secret &>/dev/null; then
    # ux_warning "git-secret is not installed. Run 'install-git-secret.sh' to install it."
    # Commented out to avoid spamming the terminal on every shell startup if git-secret is not installed
    true
fi
