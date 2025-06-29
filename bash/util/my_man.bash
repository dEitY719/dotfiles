#!/bin/bash

# myman 함수 정의
# 이 함수는 analyze_bash_scripts.sh 스크립트가 생성한 정보를 활용합니다.
myman() {
    local type_to_show="$1"
    local temp_output_file="/tmp/bash_man_output.txt" # 임시 파일 경로

    if [[ -z "$type_to_show" ]]; then
        echo "사용법: myman [alias | function]"
        echo "  - alias: 정의된 모든 alias 목록을 보여줍니다."
        echo "  - function: 정의된 모든 function 목록을 보여줍니다."
        return 1
    fi

    # analyze_bash_scripts.sh 스크립트의 경로를 정확히 지정하세요.
    # 예시: ~/dotfiles/bash/analyze_bash_scripts.sh
    local analyzer_script="$HOME/dotfiles/bash/analyze_bash_scripts.sh"
    local bash_config_dir="$HOME/dotfiles/bash"

    # analyzer 스크립트가 없을 경우 오류 처리
    if [[ ! -f "$analyzer_script" ]]; then
        echo "오류: '$analyzer_script' 스크립트를 찾을 수 없습니다." >&2
        echo "스크립트 경로를 확인하거나, 스크립트가 실행 가능한지 확인하십시오." >&2
        return 1
    fi

    # 스크립트를 실행하여 임시 파일에 결과를 저장
    # 여기서 스크립트의 출력 결과가 표준 출력으로 나오므로 파일로 리디렉션합니다.
    "$analyzer_script" "$bash_config_dir" >"$temp_output_file"

    if [[ "$type_to_show" == "alias" ]]; then
        echo "### Alias 목록"
        # alias 목록 시작부터 다음 헤딩 전까지의 내용만 추출
        sed -n '/### Alias 목록/,/### Function 목록/p' "$temp_output_file" |
            grep -v '### Alias 목록' |
            grep -v '### Function 목록' |
            sed '$d' # 마지막 줄 (공백 또는 다음 헤딩 라인) 제거
    elif [[ "$type_to_show" == "function" ]]; then
        echo "### Function 목록"
        # function 목록 시작부터 마지막까지의 내용만 추출
        sed -n '/### Function 목록/,$p' "$temp_output_file" |
            grep -v '### Function 목록'
    else
        echo "유효하지 않은 옵션: '$type_to_show'"
        echo "사용법: myman [alias | function]"
        return 1
    fi

    # 임시 파일 삭제 (선택 사항, 필요에 따라 유지할 수도 있습니다)
    rm -f "$temp_output_file"
}

# (선택 사항) 스크립트 로드 시 자동으로 myman 함수를 사용할 수 있도록 export
# export -f myman # 함수는 자동으로 export되지 않아도 됩니다.
