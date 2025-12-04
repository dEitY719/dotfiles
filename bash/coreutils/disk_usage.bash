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
    ux_header "Disk Usage Helper (du aliases)"

    ux_section "Aliases"
    ux_table_row "dus" "du -sh ." "Current dir summary"
    ux_table_row "dud" "du -sh *" "Subdir summary (sorted)"
    ux_table_row "dsql" "du .sql" "SQL dump sizes"
    ux_table_row "dubig" "du top 10" "Top 10 largest items"
    echo ""

    ux_info "Tip: -h option means 'human-readable' (K, M, G)"
    echo ""
}
