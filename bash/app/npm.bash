#!/bin/bash

#/home/bwyoon/dotfiles/bash/app/npm.bash

# Set up npm-global path
NPM_GLOBAL_PATH="$HOME/.npm-global"
if [ ! -d "$NPM_GLOBAL_PATH" ]; then
    mkdir -p "$NPM_GLOBAL_PATH"
fi
export PATH="$NPM_GLOBAL_PATH/bin:$PATH"