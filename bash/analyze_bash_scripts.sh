#!/bin/bash

# ==============================================================================
# Bash Script Analyzer: alias 및 function 정의를 파싱하여 매뉴얼 생성
# (함수 이름 추출 정규식 강화 버전)
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
    # awk를 사용하여 alias 정의 라인에서 이름만 효율적으로 추출합니다.
    # grep과 sed를 반복 호출하는 대신, 단일 awk 프로세스로 처리하여 효율성을 높입니다.
    mapfile -t alias_names < <(awk '
        # 주석 처리된 라인은 건너뜁니다.
        /^\s*#/ { next }
        # "alias my_alias=..." 형태와 일치하는 라인에서 alias 이름만 추출합니다.
        match($0, /^\s*alias\s+([a-zA-Z0-9_-]+)/, m) {
            print m[1]
        }
    ' "$file_path")

    for alias_name in "${alias_names[@]}"; do
        if [[ -n "$alias_name" && ! -v ALL_ALIASES["$alias_name"] ]]; then
            ALL_ALIASES["$alias_name"]=1
            ((TOTAL_ALIAS_COUNT++))
        fi
    done
}

# function 정의를 파싱하고 전역 변수에 업데이트하는 함수 (수정된 부분)
parse_functions() {
    local file_path="$1"
    local func_names
    # awk를 사용하여 두 가지 형태의 함수 정의('function name' 및 'name()')를 모두 찾아
    # 함수 이름만 효율적으로 추출합니다.
    mapfile -t func_names < <(awk '
        # 주석 처리된 라인은 건너뜁니다.
        /^\s*#/ { next }
        # "function my_func" 형태를 먼저 확인합니다.
        if (match($0, /^\s*function\s+([a-zA-Z0-9_-]+)/, m)) {
            print m[1]
        # "my_func()" 형태를 확인합니다.
        } else if (match($0, /^\s*([a-zA-Z0-9_-]+)\s*\(\)/, m)) {
            print m[1]
        }
    ' "$file_path")

    for func_name in "${func_names[@]}"; do
        if [[ -n "$func_name" && ! -v ALL_FUNCTIONS["$func_name"] ]]; then
            ALL_FUNCTIONS["$func_name"]=1
            ((TOTAL_FUNCTION_COUNT++))
        fi
    done
}

# 결과 출력 함수 (이전과 동일)
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
# 메인 로직 (이전과 동일)
# ==============================================================================

if [[ -z "$1" ]]; then
    usage
fi

TARGET_DIR="$1"

if [[ ! -d "$TARGET_DIR" ]]; then
    echo "오류: '$TARGET_DIR' 디렉토리를 찾을 수 없습니다."
    usage
fi

echo "Analyzing bash files in: $TARGET_DIR"

mapfile -t bash_files < <(find "$TARGET_DIR" -type f -name "*.bash")

for bash_file in "${bash_files[@]}"; do
    # 디버그 메시지 제거 (정상 동작 확인 후)
    # echo "  Processing: $(basename "$bash_file")"
    parse_aliases "$bash_file"
    parse_functions "$bash_file"
done

print_results

exit 0
