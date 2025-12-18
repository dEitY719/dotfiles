#!/bin/bash
# shellcheck disable=SC2148

# bash/app/git-secret.bash
# Git-secret integration and helper functions

# Ensure ux_lib is sourced
if [ -z "$(type -t ux_info)" ]; then
    # Assume ux_lib.bash is in the same directory structure relative to main.bash
    # This script is sourced by main.bash, so it should be fine.
    # If this script is run standalone, it will need to source ux_lib.bash
    # For now, rely on main.bash sourcing it.
    true
fi

# ==============================================================================
# Git Secret Helper Functions
# ==============================================================================

# Git Secret Help
gs-help() {
  ux_header "Git Secret Usage"
  ux_info "Git Secret is a tool to store your private data inside a Git repo."
  ux_bullet "It uses GPG encryption for security."
  echo ""

  ux_section "Workflow (GPG based)"
  ux_numbered 1 "Installation: Install git-secret (e.g., \
${UX_PRIMARY}install-git-secret.sh${UX_RESET}
)"
  ux_numbered 2 "Generate a GPG key: \
${UX_PRIMARY}gpg --full-generate-key${UX_RESET}
"
  ux_numbered 3 "Initialize a git repo for git-secret: \
${UX_PRIMARY}git secret init${UX_RESET}
"
  ux_numbered 4 "Add team members' GPG public keys: \
${UX_PRIMARY}git secret tell user@example.com${UX_RESET}
"
  ux_numbered 5 "Add files to hide (e.g., .env): \
${UX_PRIMARY}git secret add .env${UX_RESET}
"
  ux_numbered 6 "Encrypt (hide) added files: \
${UX_PRIMARY}git secret hide${UX_RESET}
 (creates .env.secret)"
  ux_numbered 7 "Decrypt (reveal) files after git pull: \
${UX_PRIMARY}git secret reveal${UX_RESET}
"
  echo ""

  ux_section "Available Commands"
  ux_bullet "${UX_PRIMARY}gs_init${UX_RESET}   : \
`git secret init`${UX_RESET}" - Initializes git-secret in a repo."
  ux_bullet "${UX_PRIMARY}gs_tell${UX_RESET}   : \
`git secret tell <emails>`${UX_RESET}" - Adds GPG keys to git-secret."
  ux_bullet "${UX_PRIMARY}gs_add${UX_RESET}    : \
`git secret add <files>`${UX_RESET}" - Adds files to be encrypted."
  ux_bullet "${UX_PRIMARY}gs_hide${UX_RESET}   : \
`git secret hide`${UX_RESET}" - Encrypts added files."
  ux_bullet "${UX_PRIMARY}gs_reveal${UX_RESET} : \
`git secret reveal`${UX_RESET}" - Decrypts files."
  ux_bullet "${UX_PRIMARY}gs_list${UX_RESET}   : \
`git secret list`${UX_RESET}" - Lists encrypted files."
  ux_bullet "${UX_PRIMARY}gs_whoknows${UX_RESET} : \
`git secret whoknows`${UX_RESET}" - Lists GPG keys authorized to decrypt."
  echo ""
}

# ==============================================================================
# Git Secret Aliases/Functions
# ==============================================================================

# Initialize git-secret
gs_init() {
  ux_info "Initializing git-secret in current repository..."
  git secret init "$@"
  if [ $? -eq 0 ]; then
    ux_success "git-secret initialized."
    ux_info "Remember to run \
`${UX_PRIMARY}git secret tell <your_gpg_email>${UX_RESET}`
"
  else
    ux_error "Failed to initialize git-secret."
  fi
}

# Add GPG keys to git-secret
gs_tell() {
  if [ -z "$1" ]; then
    ux_error "Usage: gs_tell <GPG_EMAIL1> [GPG_EMAIL2...]"
    return 1
  fi
  ux_info "Adding GPG key(s) to git-secret..."
  git secret tell "$@"
  if [ $? -eq 0 ]; then
    ux_success "GPG key(s) added."
  else
    ux_error "Failed to add GPG key(s)."
  fi
}

# Add files to be encrypted
gs_add() {
  if [ -z "$1" ]; then
    ux_error "Usage: gs_add <file1> [file2...]"
    return 1
  fi
  ux_info "Adding file(s) to git-secret for encryption..."
  git secret add "$@"
  if [ $? -eq 0 ]; then
    ux_success "File(s) added to git-secret. Now run \
`${UX_PRIMARY}gs_hide${UX_RESET}`
 to encrypt."
  else
    ux_error "Failed to add file(s) to git-secret."
  fi
}

# Encrypt (hide) files
gs_hide() {
  ux_info "Encrypting git-secret files..."
  git secret hide "$@"
  if [ $? -eq 0 ]; then
    ux_success "Files encrypted (hidden)."
    ux_info "Don't forget to \
`${UX_PRIMARY}git add .gitsecret/${UX_RESET}`
 and \
`${UX_PRIMARY}git add <your_secret_file>.secret${UX_RESET}`
"
  else
    ux_error "Failed to encrypt (hide) files."
  fi
}

# Decrypt (reveal) files
gs_reveal() {
  ux_info "Decrypting git-secret files..."
  git secret reveal "$@"
  if [ $? -eq 0 ]; then
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


# Register with myhelp
myhelp_register "gs-help" "git-secret" "Manage GPG-encrypted secrets in Git"

# Ensure git-secret is available
if ! command -v git-secret &>/dev/null; then
    # ux_warning "git-secret is not installed. Run 'install-git-secret.sh' to install it."
    # Commented out to avoid spamming the terminal on every shell startup if git-secret is not installed
    true
fi