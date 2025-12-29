#!/bin/bash

# myman 함수 정의
# 이 함수는 analyze_bash_scripts.sh 스크립트가 생성한 정보를 활용합니다.
myman() {
    local type_to_show="$1"
    local temp_output_file
    temp_output_file=$(mktemp) # 안전한 임시 파일 생성

    # 함수 종료 시 임시 파일 삭제 보장 (zsh 호환성: trap EXIT 사용)
    trap "rm -f '$temp_output_file'" EXIT

    if [[ -z "$type_to_show" ]]; then
        ux_header "myman"
        ux_usage "myman" "[alias | function]" "Show defined aliases or functions"
        ux_bullet "alias: 정의된 모든 alias 목록을 보여줍니다."
        ux_bullet "function: 정의된 모든 function 목록을 보여줍니다."
        echo ""
        return 1
    fi

    local analyzer_script="$HOME/dotfiles/shell-common/tools/custom/analyze_bash_scripts.sh"
    local sh_config_dir="$HOME/dotfiles/shell-common"

    if [[ ! -f "$analyzer_script" ]]; then
        ux_error "스크립트를 찾을 수 없습니다: '$analyzer_script'"
        ux_info "스크립트 경로를 확인하거나, 스크립트가 실행 가능한지 확인하십시오."
        return 1
    fi

    # 스크립트를 실행하여 임시 파일에 결과를 저장 (에러 출력은 숨김)
    "$analyzer_script" "$sh_config_dir" >"$temp_output_file" 2>/dev/null

    if [[ "$type_to_show" == "alias" ]]; then
        (
            echo "### Alias 목록"
            echo
            # sed로 alias 목록만 추출하고 빈 줄 제거 후 less로 출력
            sed -n '/### Alias 목록/,/### Function 목록/p' "$temp_output_file" |
                grep -v '### Alias 목록' |
                grep -v '### Function 목록' |
                sed '/^$/d'
        ) | less
    elif [[ "$type_to_show" == "function" ]]; then
        (
            echo "### Function 목록"
            echo
            # sed로 function 목록 추출 후 less로 출력
            sed -n '/### Function 목록/,$p' "$temp_output_file" |
                grep -v '### Function 목록'
        ) | less
    else
        ux_error "유효하지 않은 옵션: '$type_to_show'"
        ux_usage "myman" "[alias | function]" "Show defined aliases or functions"
        return 1
    fi
}
