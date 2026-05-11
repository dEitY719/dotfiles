#!/bin/bash
# shell-common/tools/custom/analyze_bash_scripts.sh
# Scan a directory of bash files and emit a Markdown summary of all
# aliases and functions defined within.

# zsh-compat: this script uses bash arrays + mapfile + ((...)); when sourced
# from zsh, drop into strict POSIX-sh emulation to keep the syntax legal.
[ -n "${ZSH_VERSION-}" ] && emulate -L sh

# 일관된 정규식 및 정렬 동작을 위해 로케일을 C로 설정
export LC_ALL=C

usage() {
    cat <<'EOF'
Analyze a directory of bash files and print a Markdown summary of every
alias and function defined within.

Usage:
  analyze_bash_scripts.sh [-h|--help|help] <directory>

Arguments:
  <directory>    Directory to scan recursively (skips */lib/* paths).

Examples:
  analyze_bash_scripts.sh ~/dotfiles/shell-common
  analyze_bash_scripts.sh ./bash
EOF
}

# Initialize common tools environment (ux_lib + have_command)
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/init.sh" || exit 1

# 전역 변수 초기화
declare -A ALL_ALIASES
declare -A ALL_FUNCTIONS
TOTAL_ALIAS_COUNT=0
TOTAL_FUNCTION_COUNT=0

# alias 정의를 파싱하고 전역 변수에 업데이트하는 함수
parse_aliases() {
    local file_path="$1"
    local alias_names
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
    ux_header "Bash Script Inventory"
    ux_bullet "Total aliases: $TOTAL_ALIAS_COUNT"
    ux_bullet "Total functions: $TOTAL_FUNCTION_COUNT"

    ux_section "Alias 목록"
    if [[ ${#ALL_ALIASES[@]} -eq 0 ]]; then
        ux_info "(발견된 alias 없음)"
    else
        printf "  - %s\n" "${!ALL_ALIASES[@]}" | sort
    fi

    ux_section "Function 목록"
    if [[ ${#ALL_FUNCTIONS[@]} -eq 0 ]]; then
        ux_info "(발견된 function 없음)"
    else
        printf "  - %s\n" "${!ALL_FUNCTIONS[@]}" | sort
    fi
}

main() {
    case "${1:-}" in
        -h|--help|help) usage; exit 0 ;;
        "") ux_error "Missing argument: <directory>"; usage >&2; exit 2 ;;
    esac

    local TARGET_DIR="$1"

    if [[ ! -d "$TARGET_DIR" ]]; then
        ux_error "Directory not found: $TARGET_DIR"
        exit 1
    fi

    local sh_files
    mapfile -t sh_files < <(find "$TARGET_DIR" -type f -name "*.sh" -not -path '*/lib/*')

    local files_scanned=${#sh_files[@]}
    if [ "$files_scanned" -eq 0 ]; then
        ux_warning "No .sh files found under: $TARGET_DIR"
        exit 0
    fi

    for sh_file in "${sh_files[@]}"; do
        parse_aliases "$sh_file"
        parse_functions "$sh_file"
    done

    print_results
    ux_section "Summary"
    ux_bullet "state: ok"
    ux_bullet "files_scanned: $files_scanned"
    ux_bullet "aliases: $TOTAL_ALIAS_COUNT"
    ux_bullet "functions: $TOTAL_FUNCTION_COUNT"
    ux_info "Next: pipe this output into a manual or diff against the previous run"
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
