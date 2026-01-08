#!/bin/bash
# shell-common/tools/external/nvm.sh
# Auto-generated from bash/app/nvm.bash


export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"                   # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" # This loads nvm bash_completion

# NVM Help

# NVM Install Script
nvm-install() {
    bash "$HOME/dotfiles/shell-common/tools/custom/install_nvm.sh"
}
