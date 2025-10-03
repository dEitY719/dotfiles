#!/bin/bash

# ==============================================================================
# Bash Script Analyzer: alias 및 function 정의를 파싱하여 매뉴얼 생성
# (gawk 비의존적으로 수정된 버전)
# ==============================================================================

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
    # sed를 사용하여 alias 이름 추출 (주석 처리된 라인 제외)
    mapfile -t alias_names < <(grep '^	*alias' "$file_path" | grep -v '^	*#' | sed -n 's/^	*alias		\+\([a-zA-Z0-9_-]\+\)=.*\/\1/p')

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
    # sed를 사용하여 두 가지 형태의 함수 정의('function name' 및 'name()')를 모두 파싱
    mapfile -t func_names < <(grep -v '^	*#' "$file_path" | sed -n -E 's/^	*function		\+\([a-zA-Z0-9_-]\+\).*/\1/p; s/^	*\([a-zA-Z0-9_-]\+\)		*\(\).*/\1/p')

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

# echo "Analyzing bash files in: $TARGET_DIR" # This message is now hidden in myman

mapfile -t bash_files < <(find "$TARGET_DIR" -type f -name "*.bash")

for bash_file in "${bash_files[@]}"; do
    parse_aliases "$bash_file"
    parse_functions "$bash_file"
done

print_results

exit 0