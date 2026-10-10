#!/bin/sh
# shell-common/tools/integrations/markitdown.sh
# markitdown wrapper - 인자 없이 TTY 에서 실행하면 stdin 대기로 멈추므로 --help 를 보여준다.
# 소스(파일/URL)를 주고 stdout 이 터미널이면 결과를 <이름>.md 로 저장한다:
#   기본은 현재 디렉토리, --output-path DIR 이면 DIR (없으면 만든다).
# -o/--output 지정, stdin 입력, stdout 리다이렉트/파이프는 원본 동작 그대로.
# Details: markitdown-help

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# 소스 -> 저장 파일 이름(확장자 제외). URL 은 query/fragment 를 떼고 마지막
# 경로 조각, YouTube watch?v=ID 는 ID, 경로가 없으면 호스트 이름.
_markitdown_name() {
    _md_src=$1
    case $_md_src in
        *://*)
            case $_md_src in
                *[?\&]v=*)
                    _md_name=${_md_src#*[?&]v=}
                    _md_name=${_md_name%%[&#]*}
                    ;;
                *)
                    _md_name=${_md_src%%[?#]*}
                    _md_name=${_md_name%/}
                    _md_name=${_md_name##*/}
                    ;;
            esac
            ;;
        *)
            _md_name=${_md_src##*/}
            case $_md_name in ?*.*) _md_name=${_md_name%.*} ;; esac
            ;;
    esac
    printf '%s\n' "${_md_name:-markitdown}"
}

markitdown() {
    if [ "$#" -eq 0 ] && [ -t 0 ]; then
        command markitdown --help
        return
    fi

    _md_dir='' _md_src='' _md_pass=0 _md_n=$#
    # 인자를 한 바퀴 돌리며 --output-path 만 빼고 나머지는 순서대로 다시 쌓는다.
    while [ "$_md_n" -gt 0 ]; do
        _md_a=$1
        shift
        _md_n=$((_md_n - 1))
        case $_md_a in
            --output-path)
                if [ "$_md_n" -eq 0 ]; then
                    echo "markitdown: --output-path 에 디렉토리가 필요합니다" >&2
                    return 2
                fi
                _md_dir=$1
                shift
                _md_n=$((_md_n - 1))
                continue
                ;;
            --output-path=*)
                _md_dir=${_md_a#*=}
                continue
                ;;
            -o | --output)
                _md_pass=1
                ;;
            -o?* | --output=*)
                _md_pass=1
                ;;
            -h | --help | -v | --version | --list-plugins)
                _md_pass=1
                ;;
            -x | --extension | -m | --mime-type | -c | --charset | -e | --endpoint | --cu-endpoint | --cu-analyzer | --cu-file-types)
                # 값을 받는 옵션: 값은 소스로 오인하지 않도록 함께 넘긴다.
                if [ "$_md_n" -gt 0 ]; then
                    set -- "$@" "$_md_a" "$1"
                    shift
                    _md_n=$((_md_n - 1))
                    continue
                fi
                ;;
            -*) ;;
            *) _md_src=$_md_a ;;
        esac
        set -- "$@" "$_md_a"
    done

    if [ "$_md_pass" -eq 1 ] || { [ -z "$_md_dir" ] && ! [ -t 1 ]; }; then
        command markitdown "$@"
        return
    fi
    if [ -z "$_md_src" ]; then
        if [ -n "$_md_dir" ]; then
            echo "markitdown: stdin 입력은 이름을 정할 수 없습니다. -o 로 파일을 지정하세요" >&2
            return 2
        fi
        command markitdown "$@"
        return
    fi

    _md_dir=${_md_dir:-.}
    mkdir -p -- "$_md_dir" || return
    _md_out="${_md_dir%/}/$(_markitdown_name "$_md_src").md"
    if [ -e "$_md_out" ]; then
        echo "markitdown: 이미 있음, 덮어쓰지 않음: $_md_out (-o 로 직접 지정)" >&2
        return 1
    fi
    command markitdown "$@" -o "$_md_out" || return
    echo "저장: $_md_out" >&2
}
