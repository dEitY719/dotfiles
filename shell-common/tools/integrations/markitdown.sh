#!/bin/sh
# shell-common/tools/integrations/markitdown.sh
# markitdown wrapper - 인자 없이 TTY 에서 실행하면 stdin 대기로 멈추므로 --help 를 보여준다.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

markitdown() {
    if [ "$#" -eq 0 ] && [ -t 0 ]; then
        command markitdown --help
        return
    fi
    command markitdown "$@"
}
