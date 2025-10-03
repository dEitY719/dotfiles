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
    echo "Disk Usage Helper (du aliases)"
    echo
    echo "  dus    : 현재 디렉토리 전체 크기 요약 (du -sh .)"
    echo "  dud    : 하위 디렉토리 크기 정렬 (du -sh * | sort -h)"
    echo "  dsql   : SQL dump 파일 크기 정렬 (du -h src/database/data/*.sql | sort -h)"
    echo "  dubig  : 상위 10개 큰 파일/디렉토리 (du -ah . | sort -rh | head -n 10)"
    echo
    echo "Tip: -h 옵션은 사람이 읽기 좋은 단위(K, M, G)를 의미합니다."
}
