#!/bin/sh
# shell-common/functions/wcp.sh
# cp that accepts Windows paths (WSL): "C:\Users\me\Videos" -> /mnt/c/Users/me/Videos.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_wcp_help() {
    ux_header "wcp - Windows 경로를 받는 cp (WSL)"
    ux_section "Usage"
    ux_bullet "wcp [cp 옵션] <원본>... <대상>"
    ux_bullet "wcp -h | --help"
    ux_info "Windows 경로(C:\\..., C:/..., \\\\wsl\$\\...)는 wslpath 로 변환하고, 나머지 인자와 옵션은 cp 에 그대로 넘깁니다."
    ux_section "Examples"
    ux_bullet 'wcp "C:\Users\me\Videos\a.mp4" .          # Windows -> 현재 폴더'
    ux_bullet 'wcp -r "C:\Users\me\Docs" ~/backup/        # 폴더 복사'
    ux_bullet 'wcp a.txt "D:\share\"                       # Linux -> Windows'
    ux_bullet 'wcp -v "C:\a.txt" "C:\b.txt" ~/tmp/         # 여러 파일 + cp 옵션'
    ux_info "Tip: 백슬래시가 셸에서 사라지지 않도록 경로를 따옴표로 감싸세요."
}

wcp() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    case ${1-} in -h | --help)
        _wcp_help
        return 0
        ;;
    esac
    local _n=$# _a
    while [ "$_n" -gt 0 ]; do
        _a=$1
        shift
        # Drive path (C:\..., C:/...) or UNC (\\wsl$\...). Flags/Linux paths pass through.
        case $_a in
        [A-Za-z]:[\\/]* | \\\\*)
            _a=$(wslpath -u "$_a") || {
                ux_error "wslpath failed: $_a"
                return 1
            }
            ;;
        esac
        set -- "$@" "$_a"
        _n=$((_n - 1))
    done
    command cp "$@"
}
