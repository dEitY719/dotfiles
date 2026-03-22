#!/bin/sh
# shell-common/functions/nvm_help.sh

nvm_help() {
    ux_header "NVM (Node Version Manager)"

    ux_section "Commands"
    ux_table_row "nvm-install" "Install Script" "Install NVM & Node LTS"

    ux_section "NVM Usage"
    ux_bullet "nvm install --lts  : Install latest LTS Node"
    ux_bullet "nvm use --lts      : Use latest LTS Node"
    ux_bullet "nvm ls             : List installed versions"
}

alias nvm-help='nvm_help'
