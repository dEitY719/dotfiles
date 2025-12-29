#!/bin/bash

# ==============================================================================
# Bash Script Analyzer: alias 및 function 정의를 파싱하여 매뉴얼 생성
# (LC_ALL=C 추가 및 파서 재수정)
# ==============================================================================

# 일관된 정규식 및 정렬 동작을 위해 로케일을 C로 설정
export LC_ALL=C

# 전역 변수 초기화
declare -A ALL_ALIASES
declare -A ALL_FUNCTIONS
TOTAL_ALIAS_COUNT=0
TOTAL_FUNCTION_COUNT=0

# ==============================================================================
# 함수 정의
# ==============================================================================

usage() {
    echo "사용법: $0 <bash_files_directory>"
    echo "예시: $0 ~/my_bash_config"
    exit 1
}

# alias 정의를 파싱하고 전역 변수에 업데이트하는 함수
parse_aliases() {
    local file_path="$1"
    local alias_names
    # grep의 정규식을 수정하여 '..', '~' 같은 다양한 alias 이름을 올바르게 처리
    mapfile -t alias_names < <(grep -E '^\s*alias\s+.*=' "$file_path" | grep -v '^\s*#' | sed -E 's/^\s*alias\s+([^=]+)=.*/\1/')

    for alias_name in "${alias_names[@]}"; do
        if [[ -n "$alias_name" && ! -v ALL_ALIASES["$alias_name"] ]]; then
            ALL_ALIASES["$alias_name"]=1
            ((TOTAL_ALIAS_COUNT++))
        fi
    done
}

# function 정의를 파싱하고 전역 변수에 업데이트하는 함수
parse_functions() {
    local file_path="$1"
    local func_names
    # Handles 'name()' and 'function name()'
    mapfile -t func_names < <(grep -E '^\s*(function\s+)?[a-zA-Z0-9._-]+\s*\(\)' "$file_path" | grep -v '^\s*#' | sed -E 's/^\s*(function\s+)?//; s/\s*\(\).*//')

    for func_name in "${func_names[@]}"; do
        if [[ -n "$func_name" && ! -v ALL_FUNCTIONS["$func_name"] ]]; then
            ALL_FUNCTIONS["$func_name"]=1
            ((TOTAL_FUNCTION_COUNT++))
        fi
    done
}

# 결과 출력 함수
print_results() {
    echo "---"
    echo "## Bash 매뉴얼 요약"
    echo "---"
    echo ""
    echo "총 alias 개수: **$TOTAL_ALIAS_COUNT**"
    echo "총 function 개수: **$TOTAL_FUNCTION_COUNT**"
    echo ""

    echo "### Alias 목록"
    if [[ ${#ALL_ALIASES[@]} -eq 0 ]]; then
        echo "  (발견된 alias 없음)"
    else
        printf "  - %s\n" "${!ALL_ALIASES[@]}" | sort
    fi
    echo ""

    echo "### Function 목록"
    if [[ ${#ALL_FUNCTIONS[@]} -eq 0 ]]; then
        echo "  (발견된 function 없음)"
    else
        printf "  - %s\n" "${!ALL_FUNCTIONS[@]}" | sort
    fi
    echo ""
    echo "---"
}

# ==============================================================================
# 메인 로직
# ==============================================================================

if [[ -z "$1" ]]; then
    usage
fi

TARGET_DIR="$1"

if [[ ! -d "$TARGET_DIR" ]]; then
    echo "오류: '$TARGET_DIR' 디렉토리를 찾을 수 없습니다."
    usage
fi

mapfile -t sh_files < <(find "$TARGET_DIR" -type f -name "*.sh")

for sh_file in "${sh_files[@]}"; do
    parse_aliases "$sh_file"
    parse_functions "$sh_file"
done

print_results

exit 0
