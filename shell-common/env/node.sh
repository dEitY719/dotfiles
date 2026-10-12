#!/bin/sh
# shell-common/env/node.sh
# Node.js trusts the OS CA store, so TLS-intercepting proxies work (#2093).
# Older Node versions ignore the variable; a pre-set value is kept.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

export NODE_USE_SYSTEM_CA="${NODE_USE_SYSTEM_CA:-1}"
