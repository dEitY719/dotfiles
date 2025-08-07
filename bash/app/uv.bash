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
