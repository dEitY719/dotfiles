#!/bin/bash

# bash/app/uv.bash

alias uv_install='uv sync'
alias uv_update='uv sync --upgrade'
alias uv_upgrade='uv sync --upgrade'
alias uv_clean='uv sync --clean'
alias uv_check='uv check'
alias uv_lock='uv lock'
alias uv_unlock='uv unlock'
alias uv_freeze="uv pip compile pyproject.toml > requirements.txt"
alias uv_add_req='grep -vE "^\s*#|^\s*$" requirements.txt | cut -d= -f1 | sort -u | xargs -n1 uv add'

uv_sync() {
    log_dim "Installing [project & development] dependencies..."
    uv sync
    uv sync --dev --extra dev
    log_info "[project & development] dependencies installed"
}

uv_dev() {
    log_dim "Installing [development] dependencies..."
    uv sync --dev --extra dev
    log_info "[development] dependencies installed"
}

uv_prod() {
    log_dim "Installing [production] dependencies..."
    uv sync
    log_info "[production] dependencies installed"
}

install_uv() {
    log_dim "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    log_info "uv installed"
}

# Defines the uv_help function to display common uv pip sync commands for this project.
uv_help() {
    cat <<-'EOF'

Usage: source this file and then run 'uv_help'

This will display the common 'uv pip sync' commands for this project.

--------------------------------------------------------------------------------

[ uv pip sync Commands ]

1. Full Installation (frontend, backend, and dev):
   Installs all project dependencies.
   
   uv pip sync --all-extras

2. Backend Only Installation:
   Installs base, backend, and development dependencies.
   
   uv pip sync --extra backend --extra dev

3. Frontend Only Installation:
   Installs base, frontend, and development dependencies.
   
   uv pip sync --extra frontend --extra dev

--------------------------------------------------------------------------------

[ Lock File Update ]

If you modify 'pyproject.toml', update the lockfile before syncing:

   uv lock

EOF
}
