#!/bin/bash

# This script sets up the en_US.UTF-8 locale to resolve "manpath: can't set the locale" errors.

echo "Generating en_US.UTF-8 locale..."
sudo locale-gen en_US.UTF-8

echo "Updating default system locale to en_US.UTF-8..."
sudo update-locale LANG=en_US.UTF-8

echo "Locale setup complete. Please restart your terminal or run 'source ~/.bashrc' to apply changes."
