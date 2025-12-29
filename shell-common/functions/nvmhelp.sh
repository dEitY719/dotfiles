#!/bin/sh
# shell-common/functions/nvmhelp.sh
# nvmHelp - shared between bash and zsh

nvmhelp() {
    ux_header "NVM (Node Version Manager)"

    ux_section "Commands"
    ux_table_row "nvm-install" "Install Script" "Install NVM & Node LTS"
    echo ""

    ux_section "NVM Usage"
    ux_bullet "nvm install --lts  : Install latest LTS Node"
    ux_bullet "nvm use --lts      : Use latest LTS Node"
    ux_bullet "nvm ls             : List installed versions"
    echo ""
}
