#!/bin/sh
# shell-common/functions/gc_help.sh

gc_help() {
    ux_header "git-crypt (Transparent Git encryption)"

    ux_section "설치"
    ux_table_row "gcinstall" "설치 스크립트" "apt-get 기반 설치"
    ux_bullet "필수: git, gpg, GPG 키"

    ux_section "Alias"
    ux_table_row "gci" "git-crypt init" "초기화"
    ux_table_row "gcadduser" "git-crypt add-gpg-user" "GPG 키 추가"
    ux_table_row "gcstatus" "git-crypt status" "암호화 상태 확인"
    ux_table_row "gclock" "git-crypt lock" "수동 암호화 (잠금)"
    ux_table_row "gcunlock" "git-crypt unlock" "수동 복호화 (해제)"
    ux_table_row "gcls" "git-crypt status -f" "암호화된 파일 목록"

    ux_section "Helper Functions"
    ux_table_row "gcpush" "gc_push_env" ".env 암호화 & Push 🚀 (올인원)"
    ux_table_row "gcsetup" "gc_setup" "대화형 초기 설정 도우미"
    ux_table_row "gcaddme" "gc_addme" "내 GPG 키 자동 찾기 & 추가"
    ux_table_row "gc_encrypt_env" "암호화 .env" ".env 파일 암호화 퀵 스타트"
    ux_table_row "gcsetup-cache" "gc_setup_cache" "GPG agent 캐싱 설정 (24시간)"
    ux_table_row "gcpurge" "gc_purge_cache" "GPG 캐시 초기화 (즉시 만료)"
    ux_table_row "gc_cache_status" "캐싱 상태" "GPG agent 캐싱 상태 확인"
    ux_table_row "gcbackup" "gc_backup_key" "GPG 개인키 백업 (다른 PC 이동용)"
    ux_table_row "gcrestore" "gc_restore_key" "GPG 개인키 복원 (다른 PC에서)"
    ux_table_row "gcnewpc" "gc_setup_new_pc" "다른 PC 올인원 설정"

    ux_section "Tips"
    ux_bullet ".env는 .gitignore에 추가하되, .gitattributes로 암호화"
    ux_bullet "GPG 키는 gpg --list-keys 로 확인"
    ux_bullet "팀원 추가 시 각자의 GPG 공개키로 add-gpg-user 실행"
    ux_bullet "암호화 상태 확인: gcstatus 또는 gcls"
    ux_bullet "GPG passphrase 캐싱: gcsetup-cache (24시간 동안 재입력 불필요)"
}
