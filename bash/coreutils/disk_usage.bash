#!/bin/bash

# 현재 디렉토리 전체 크기 요약
alias dus='du -sh .'

# 하위 디렉토리별 크기 정렬
alias dud='du -sh * | sort -h'

# SQL dump 파일 크기 정렬
alias dsql='du -h src/database/data/*.sql | sort -h'

# 현재 디렉토리에서 상위 10개 큰 디렉토리/파일 찾기
alias dubig='du -ah . | sort -rh | head -n 10'

duhelp() {
    # Color definitions
    local bold=$(tput bold 2>/dev/null || echo "")
    local blue=$(tput setaf 4 2>/dev/null || echo "")
    local green=$(tput setaf 2 2>/dev/null || echo "")
    local yellow=$(tput setaf 3 2>/dev/null || echo "")
    local reset=$(tput sgr0 2>/dev/null || echo "")

    cat <<EOF

${bold}${blue}Disk Usage Helper (du aliases)${reset}

  ${green}dus${reset}    : 현재 디렉토리 전체 크기 요약 (du -sh .)
  ${green}dud${reset}    : 하위 디렉토리 크기 정렬 (du -sh * | sort -h)
  ${green}dsql${reset}   : SQL dump 파일 크기 정렬 (du -h src/database/data/*.sql | sort -h)
  ${green}dubig${reset}  : 상위 10개 큰 파일/디렉토리 (du -ah . | sort -rh | head -n 10)

${yellow}Tip: -h 옵션은 사람이 읽기 좋은 단위(K, M, G)를 의미합니다.${reset}

EOF
}
