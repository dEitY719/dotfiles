#!/bin/bash



# setup.sh: Entry point to set up all dotfiles components



# Exit immediately if a command exits with a non-zero status

set -e



# Run setup scripts for git and bash

./bash/setup.sh

./git/setup.sh



# Run setup scripts for vim and tmux

# ./vim/setup.sh

# ./tmux/setup.sh