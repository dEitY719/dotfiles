#!/bin/sh
# shell-common/env/mise.sh
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# Put the mise shims dir on PATH so mise-installed tools (sops, age, uv, ...)
# resolve in every shell (#2342). Shims, not `mise activate`: no eval and no
# per-prompt hook at shell start, and bash and zsh share this one POSIX file.
# The installer's `mise activate` line must not go into ~/.bashrc, which is a
# symlink to the tracked bash/main.bash.
#
# Silent no-op on a PC without mise. Also sourced by functions/secret_run.sh,
# because its non-interactive callers (hermes/mcporter setup, secret-run) never
# run this loader and may inherit a PATH from a shell that predates mise.

# Same resolution as mise itself: MISE_DATA_DIR, then XDG_DATA_HOME, then ~/.local/share.
_mise_shims="${MISE_DATA_DIR:-${XDG_DATA_HOME:-${HOME}/.local/share}/mise}/shims"
if [ -d "$_mise_shims" ]; then
    case ":${PATH}:" in
    *":${_mise_shims}:"*) ;;
    *) export PATH="${_mise_shims}:${PATH}" ;;
    esac
fi
unset _mise_shims
