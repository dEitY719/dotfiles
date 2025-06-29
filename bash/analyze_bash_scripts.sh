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
    # alias 정의 패턴: 'alias 이름=...' 또는 'alias 이름 ...'
    # 앞뒤 공백 무시, 주석 무시
    # grep으로 라인 필터링 후, while read 파이프를 통해 처리 (서브쉘 문제 회피를 위해 mapfile/readarray 사용)
    local lines
    # alias는 `=`가 있을 수도 있고 없을 수도 있습니다.
    IFS=$'\n' read -r -d '' -a lines < <(grep -E '^\s*alias\s+([a-zA-Z0-9_-]+)\b.*$' "$file_path")

    for line in "${lines[@]}"; do
        # sed로 alias 이름만 추출 (alias 다음에 바로 이름이 오고, 공백이나 = 등으로 끝나는 것을 처리)
        local alias_name=$(echo "$line" | sed -E 's/^\s*alias\s+([a-zA-Z0-9_-]+).*$/\1/')
        if [[ -n "$alias_name" && ! -v ALL_ALIASES["$alias_name"] ]]; then
            ALL_ALIASES["$alias_name"]=1
            TOTAL_ALIAS_COUNT=$((TOTAL_ALIAS_COUNT + 1))
        fi
    done
}

# function 정의를 파싱하고 전역 변수에 업데이트하는 함수 (수정된 부분)
parse_functions() {
    local file_path="$1"
    local lines
    # function 정의 패턴: 'function 이름 { ... }' 또는 '이름() { ... }'
    # '{'가 다음 줄에 올 수도 있는 경우를 고려
    # 'b'는 단어 경계(word boundary)를 나타내어 'functionname' 같은 경우를 방지
    IFS=$'\n' read -r -d '' -a lines < <(grep -E '^\s*(function\s+([a-zA-Z0-9_-]+)\b|([a-zA-Z0-9_-]+)\s*\(\))\s*(\{)?' "$file_path")

    for line in "${lines[@]}"; do
        local func_name=""
        # 'function name' 형태 (function 키워드 사용)
        if [[ "$line" =~ ^\s*function\s+([a-zA-Z0-9_-]+)\b.* ]]; then
            func_name="${BASH_REMATCH[1]}"
        # 'name()' 형태 (괄호 사용)
        elif [[ "$line" =~ ^\s*([a-zA-Z0-9_-]+)\s*\(\).* ]]; then
            func_name="${BASH_REMATCH[1]}"
        fi

        if [[ -n "$func_name" && ! -v ALL_FUNCTIONS["$func_name"] ]]; then
            ALL_FUNCTIONS["$func_name"]=1
            TOTAL_FUNCTION_COUNT=$((TOTAL_FUNCTION_COUNT + 1))
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