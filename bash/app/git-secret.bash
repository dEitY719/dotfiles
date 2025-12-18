#!/bin/bash

: <<'GIT_SECRET_DOC'
==========================================================
git-secret Quickstart (GPG 기반)
==========================================================

1) 설치
--------
apt-get install git-secret

2) 초기화 및 키 등록
-------------------
git secret init
git secret tell user@example.com  # 팀원 GPG 공개키 등록

3) 비밀 파일 추가/암호화
-----------------------
git secret add .env
git secret hide                  # .env.secret 생성

4) 복호화 (pull 이후)
---------------------
git secret reveal

==========================================================
GIT_SECRET_DOC

# --- Alias & Helpers ---
alias gscrt='git secret'
alias gsi='git secret init'
alias gst='git secret tell'
alias gsa='git secret add'
alias gsh='git secret hide'
alias gsr='git secret reveal'
alias gsl='git secret list'
alias gshelp='gs_help'
alias gs-help='gs_help'
alias gsinstall='git_secret_install'

# git-secret 설치 스크립트 실행
git_secret_install() {
    bash "$HOME/dotfiles/mytool/install-git-secret.sh"
}

# git-secret 빠른 도움말
gs_help() {
    ux_header "git-secret (GPG 기반 비밀 관리)"

    ux_section "설치"
    ux_table_row "gsinstall" "설치 스크립트" "apt-get 기반 설치"
    ux_table_row "패키지" "git-secret" "apt-get install git-secret"
    ux_bullet "필수: git, gpg, 팀원 공개키"
    echo ""

    ux_section "기본 워크플로"
    ux_table_row "초기화" "git secret init" "리포지토리 설정"
    ux_table_row "키 등록" "git secret tell user@example.com" "공개키 추가 (팀원별)"
    ux_table_row "파일 추가" "git secret add .env" ".env을 암호화 대상으로 등록"
    ux_table_row "암호화" "git secret hide" ".env.secret 생성 후 commit/push"
    ux_table_row "복호화" "git secret reveal" "pull 후 .env 복구"
    echo ""

    ux_section "Alias"
    ux_table_row "gscrt" "git secret" "기본 명령"
    ux_table_row "gsi" "git secret init" "초기화"
    ux_table_row "gst" "git secret tell" "GPG 키 등록"
    ux_table_row "gsa" "git secret add" "비밀 파일 추가"
    ux_table_row "gsh" "git secret hide" "암호화 (.secret 생성)"
    ux_table_row "gsr" "git secret reveal" "복호화"
    ux_table_row "gsl" "git secret list" "추가된 비밀 목록"
    echo ""

    ux_section "Tips"
    ux_bullet ".env는 .gitignore 유지, commit에는 .env.secret만 포함"
    ux_bullet "GPG 공개키는 팀원별로 tell 실행"
    ux_bullet "재암호화 시 gsh (hide) 실행 후 commit"
    ux_bullet "키 회전/삭제 시 git secret killperson <email> 참고"
    echo ""
}
