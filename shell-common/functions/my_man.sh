#!/bin/sh
# shell-common/functions/my_man.sh
# Project-level "manual" — pages through aliases/functions discovered by
# analyze_bash_scripts.sh.
#
# NOTE: shebang is POSIX /bin/sh per the shell-common policy, but the body
# below intentionally uses bash/zsh features (`[[ ]]`, heredocs with `<<EOF`).
# That's safe because shell-common files are sourced by bash/zsh — never
# executed under pure dash.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# zsh-compat: this function uses [[ ]] and `local`. Drop into POSIX-sh
# emulation when running under zsh so the bash-style syntax stays legal.
_myman_help() {
    if type ux_header >/dev/null 2>&1; then
        ux_header "my-man"
        ux_usage "my-man" "[alias | function]" "Show defined aliases or functions"
        ux_bullet "alias     Show every alias discovered under \$SHELL_COMMON"
        ux_bullet "function  Show every function discovered under \$SHELL_COMMON"
        ux_bullet "          (data sourced from tools/custom/analyze_bash_scripts.sh)"
        ux_info "Next: my-man alias | my-man function"
    else
        echo "Usage: my-man [alias | function]"
        echo "  alias     Show every alias discovered under \$SHELL_COMMON"
        echo "  function  Show every function discovered under \$SHELL_COMMON"
    fi
}

# myman 함수 정의
# 이 함수는 analyze_bash_scripts.sh 스크립트가 생성한 정보를 활용합니다.
myman() {
    [ -n "$ZSH_VERSION" ] && emulate -L sh

    local type_to_show="${1:-}"

    case "$type_to_show" in
        -h|--help|help) _myman_help; return 0 ;;
    esac

    local temp_output_file
    temp_output_file=$(mktemp) # 안전한 임시 파일 생성

    # 함수 종료 시 임시 파일 삭제 보장 (zsh 호환성: trap EXIT 사용)
    trap "rm -f '$temp_output_file'" EXIT

    if [[ -z "$type_to_show" ]]; then
        _myman_help
        return 1
    fi

    local analyzer_script="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/analyze_bash_scripts.sh"
    local sh_config_dir="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"

    if [[ ! -f "$analyzer_script" ]]; then
        ux_error "스크립트를 찾을 수 없습니다: '$analyzer_script'"
        ux_info "스크립트 경로를 확인하거나, 스크립트가 실행 가능한지 확인하십시오."
        return 1
    fi

    # 스크립트를 실행하여 임시 파일에 결과를 저장 (에러 출력은 숨김)
    "$analyzer_script" "$sh_config_dir" >"$temp_output_file" 2>/dev/null

    if [[ "$type_to_show" == "alias" ]]; then
        (
            ux_header "Alias 목록"
            # sed로 alias 목록만 추출하고 빈 줄 제거 후 less로 출력
            sed -n '/### Alias 목록/,/### Function 목록/p' "$temp_output_file" |
                grep -v '### Alias 목록' |
                grep -v '### Function 목록' |
                sed '/^$/d'
        ) | less
    elif [[ "$type_to_show" == "function" ]]; then
        (
            ux_header "Function 목록"
            # sed로 function 목록 추출 후 less로 출력
            sed -n '/### Function 목록/,$p' "$temp_output_file" |
                grep -v '### Function 목록'
        ) | less
    else
        ux_error "유효하지 않은 옵션: '$type_to_show'"
        _myman_help
        return 1
    fi
}

alias my-man='myman'
