#!/bin/bash

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"                   # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" # This loads nvm bash_completion

# NVM Help
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

# NVM Install Script
nvm-install() {
    bash "$HOME/dotfiles/mytool/install-nvm.sh"
}
