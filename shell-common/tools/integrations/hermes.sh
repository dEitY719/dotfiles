#!/bin/sh
# shell-common/tools/integrations/hermes.sh
# Hermes Agent convenience aliases
#
# Deliberately minimal: the upstream installer puts a self-contained `hermes`
# binary on PATH itself, so there is nothing here to export or wrap. Config is
# owned by hermes/setup.sh (symlinks ~/.hermes/config.yaml into this repo).
#
# Setup:   ./hermes/setup.sh
# Details: hermes-help

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# ========================================
# Hermes Aliases
# ========================================
alias hermes-doctor='hermes doctor'
alias hermes-config='hermes config'
