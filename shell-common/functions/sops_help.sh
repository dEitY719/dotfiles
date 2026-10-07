#!/bin/sh
# shell-common/functions/sops_help.sh
# sops + age 비밀값 암호화 워크플로 도움말 (issue #1833)
#
# 예시는 sops 3.13.3 / age 1.3.2 에서 임시 키로 실측한 형태만 싣는다.
# 실측 결과: `.env.enc` 는 확장자로 dotenv 가 추론되지 않아 `sops -d .env.enc`
# 와 `sops exec-env .env.enc` 가 "Could not unmarshal input data" 로 실패한다.
# exec-env 에는 --input-type 플래그가 없으므로 senv run 이 복호화 후 export 한다.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_sops_help_summary() {
    ux_info "Usage: sops-help [section|--list|--all]   (alias: age-help)"
    ux_bullet "quick start (senv, 현재 디렉터리 기준)"
    ux_bullet_sub "키가 있는 PC: senv init -> senv enc -> git commit -> senv key export"
    ux_bullet_sub "새 PC: git pull -> senv key import -> senv dec  (또는 senv run make run)"
    ux_bullet_sub "점검: senv check"
    ux_bullet "sections"
    ux_bullet_sub "overview: 공개키=자물쇠 | 개인키=열쇠 | .env -> .env.enc 커밋"
    ux_bullet_sub "setup: install-sops-age | age-keygen | sops-status"
    ux_bullet_sub "newproject: senv init | senv enc | 커밋"
    ux_bullet_sub "usage: senv init|enc|dec|edit|run|check|key + senv 가 실행하는 sops 명령"
    ux_bullet_sub "newpc: senv key export -> senv key import -> senv check"
    ux_bullet_sub "risks: 분실=복구 불가 | 유출=원본 비밀값 교체"
    ux_bullet_sub "trouble: unmarshal 오류 | no master key | 권한"
    ux_bullet_sub "more: 공식 문서 | 관련 명령"
    ux_bullet_sub "details: sops-help <section>  (example: sops-help usage)"
}

_sops_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "overview"
    ux_bullet_sub "setup"
    ux_bullet_sub "newproject"
    ux_bullet_sub "usage"
    ux_bullet_sub "newpc"
    ux_bullet_sub "risks"
    ux_bullet_sub "trouble"
    ux_bullet_sub "more"
}

_sops_help_rows_overview() {
    ux_bullet "age: 키 쌍 생성/암호화 도구. 공개키(age1...)=자물쇠, 개인키(AGE-SECRET-KEY-1...)=열쇠"
    ux_bullet "sops: 파일의 값만 암호화 (키 이름은 평문) -> git diff 로 변경 항목 확인 가능"
    ux_bullet "흐름: .sops.yaml 에 공개키 기재 -> .env 를 .env.enc 로 암호화해 커밋"
    ux_bullet "복호화: 각 PC 의 개인키 ~/.config/sops/age/keys.txt 로 해제 (sops 기본 경로)"
    ux_bullet "개인키는 외울 수 없는 약 74자 문자열 -> PC 마다 파일로 배치해야 한다 (sops-help newpc)"
}

_sops_help_rows_setup() {
    ux_table_row "install-sops-age" "sops + age 설치" "mise 우선, 없으면 ~/.local/bin"
    ux_table_row "sops-status" "설치/키/권한 진단" "개인키 값은 출력하지 않음"
    ux_bullet "개인키 생성은 직접 실행 (AI 에게 시키지 말 것: 키가 대화 기록에 남는다)"
    ux_bullet_sub "mkdir -p ~/.config/sops/age"
    ux_bullet_sub "age-keygen -o ~/.config/sops/age/keys.txt"
    ux_bullet_sub "chmod 600 ~/.config/sops/age/keys.txt"
    ux_bullet_sub "age-keygen -y ~/.config/sops/age/keys.txt   # 공개키(age1...) 출력"
    ux_bullet "Claude Code 에서는 '! age-keygen -o ...' 처럼 ! 접두사로 사용자가 직접 실행"
}

_sops_help_rows_newproject() {
    ux_bullet "프로젝트 루트에서 (개인키가 먼저 있어야 한다: sops-help setup)"
    ux_bullet_sub "senv init   # .sops.yaml(공개키) 생성 + .gitignore 에 .env 추가"
    ux_bullet_sub "senv enc    # .env -> .env.enc"
    ux_bullet_sub "git add .sops.yaml .gitignore .env.enc && git commit"
    ux_bullet "개인키 내보내기: senv key export  (~/senv-key.age, sops-help newpc)"
    ux_bullet "새 PC: git pull -> senv key import -> senv dec (파일 생성) 또는 senv run make run (파일 없음)"
    ux_bullet "senv init 이 만드는 .sops.yaml (공개키만 들어가므로 커밋 OK)"
    ux_bullet_sub "creation_rules:"
    ux_bullet_sub "  - path_regex: '(^|/)\\.env(\\.enc)?\$'"
    ux_bullet_sub "    age: age1xxxxxxxx...   # 여러 키면 콤마로 구분"
    ux_bullet "체크: git status 에 .env 가 안 보이는지, .env.enc 값이 ENC[AES256_GCM,...] 인지"
}

_sops_help_rows_usage() {
    ux_table_row "senv init" ".sops.yaml + .gitignore" "기존 .sops.yaml 은 덮어쓰지 않음"
    ux_table_row "senv enc [file]" ".env -> .env.enc" "실패 시 기존 .env.enc 유지"
    ux_table_row "senv dec [-f] [file]" ".env.enc 또는 .enc.env -> .env (600)" "기존 .env 는 -f 없이 안 덮어씀"
    ux_table_row "senv edit [file]" "\$EDITOR 로 편집" "저장 시 재암호화"
    ux_table_row "senv run <cmd...>" "환경변수로 주입해 실행" "디스크에 평문 없음, eval 안 함"
    ux_table_row "senv check" "키/권한 600/공개키 일치/복호화 점검" "평문 미출력, 실패마다 다음 행동"
    ux_table_row "senv key show" "공개키 + .sops.yaml 일치 여부" "비밀 출력 없음"
    ux_table_row "senv key export [-o f] [-f]" "개인키를 비밀번호로 잠금 (~/senv-key.age)" "git 작업트리 안 거절, 되풀어 검증"
    ux_table_row "senv key import [f] [-f]" "잠금 파일 -> keys.txt (600)" "기존 keys.txt 는 -f 없이 안 덮어씀"
    ux_bullet "암호문 파일: 인자 [file] 우선, 없으면 .env.enc, 그것도 없으면 .enc.env"
    ux_bullet "senv 가 실행하는 sops 명령 (.env.enc 는 확장자 추론 불가 -> 타입 플래그 필수)"
    ux_bullet_sub "sops -e --input-type dotenv --output-type dotenv .env > .env.enc"
    ux_bullet_sub "sops -d --input-type dotenv --output-type dotenv .env.enc > .env"
    ux_bullet_sub "sops edit --input-type dotenv --output-type dotenv .env.enc"
    ux_bullet "sops exec-env 는 타입 플래그 미지원 -> .env.enc 불가 (senv run 이 대체)"
    ux_bullet_sub "직접 쓰려면 이름이 .env 로 끝나야 함: sops exec-env .enc.env 'npm start'"
    ux_bullet "주의: 'sops -d .env.enc' (플래그 없음) 는 unmarshal 오류로 실패한다 (실측)"
}

_sops_help_rows_newpc() {
    ux_bullet "권장: senv 로 옮긴다 (age 가 터미널에서 비밀번호를 직접 묻는다)"
    ux_bullet_sub "키가 있는 PC: senv key export   # ~/senv-key.age (git 작업트리 밖에만 쓴다)"
    ux_bullet_sub "새 PC: senv key import ~/senv-key.age -> senv dec -> senv check"
    ux_bullet "수동 방법 A: 기존 PC 의 keys.txt 를 안전한 경로(scp, USB)로 복사"
    ux_bullet_sub "복사 위치: ~/.config/sops/age/keys.txt  ->  chmod 600 ~/.config/sops/age/keys.txt"
    ux_bullet "수동 방법 B: 비밀번호로 잠근 키 파일을 개인 저장소에 두고 새 PC 에서 1회 해제"
    ux_bullet_sub "잠금 (기존 PC): age -p -o keys.txt.age ~/.config/sops/age/keys.txt"
    ux_bullet_sub "해제 (새 PC):   age -d keys.txt.age > ~/.config/sops/age/keys.txt"
    ux_bullet_sub "해제 후 반드시: chmod 600 ~/.config/sops/age/keys.txt  (기본 644 로 생성됨)"
    ux_bullet "age -p / age -d 는 터미널에서 비밀번호를 묻는다 (파이프/스크립트로 넘기지 말 것)"
    ux_bullet "마무리: install-sops-age && sops-status"
}

_sops_help_rows_risks() {
    ux_table_row "개인키 분실" "복구 불가" "keys.txt 백업 필수 (잠금 파일/오프라인 보관)"
    ux_table_row "개인키 유출" "재암호화만으로 부족" "원본 비밀값(DB 암호, API 키) 자체를 교체"
    ux_bullet "유출 대응: 새 키 생성 -> .sops.yaml 공개키 교체 -> 비밀값 교체 -> 재암호화"
    ux_bullet_sub "sops updatekeys 는 수신자만 바꾼다. 옛 키로 git 이력의 .env.enc 는 여전히 열린다"
    ux_bullet "평문 .env 커밋 사고: .gitignore 확인, 이미 push 했다면 비밀값 교체"
    ux_bullet "keys.txt 권한은 600 유지 (sops-status 로 점검)"
}

_sops_help_rows_trouble() {
    ux_table_row "Could not unmarshal input data" "형식 추론 실패" "--input-type dotenv --output-type dotenv 추가"
    ux_table_row "no master key was able to decrypt" "개인키 없음/불일치" "keys.txt 위치 확인 (sops-status)"
    ux_table_row "no matching creation rules found" ".sops.yaml path_regex 불일치" "파일명이 규칙과 맞는지 확인"
    ux_table_row "File has not changed, exiting." "편집 내용 없음 (종료 코드 200)" "정상 동작"
    ux_table_row "권한 경고" "keys.txt 가 600 아님" "chmod 600 ~/.config/sops/age/keys.txt"
    ux_bullet "키 경로를 바꿨다면 SOPS_AGE_KEY_FILE=/path/to/keys.txt 로 지정 (dotfiles 는 export 안 함)"
}

_sops_help_rows_more() {
    ux_bullet "sops: https://github.com/getsops/sops"
    ux_bullet "age:  https://github.com/FiloSottile/age"
    ux_bullet "설치 스크립트: shell-common/tools/custom/install_sops_age.sh"
    ux_bullet "진단/워크플로 함수: sops-status, senv (shell-common/tools/integrations/sops.sh)"
}

_sops_help_render_section() {
    ux_section "$1"
    "$2"
}

_sops_help_section_rows() {
    case "$1" in
        overview | about) _sops_help_rows_overview ;;
        setup | install) _sops_help_rows_setup ;;
        newproject | project | init) _sops_help_rows_newproject ;;
        usage | examples | cmds) _sops_help_rows_usage ;;
        newpc | pc) _sops_help_rows_newpc ;;
        risks | risk) _sops_help_rows_risks ;;
        trouble | troubleshooting) _sops_help_rows_trouble ;;
        more | docs | references) _sops_help_rows_more ;;
        *)
            ux_error "Unknown sops-help section: $1"
            ux_info "Try: sops-help --list"
            return 1
            ;;
    esac
}

_sops_help_full() {
    ux_header "sops + age Secret Encryption"
    _sops_help_render_section "개요" _sops_help_rows_overview
    _sops_help_render_section "설치 + 개인키 생성" _sops_help_rows_setup
    _sops_help_render_section "신규 프로젝트" _sops_help_rows_newproject
    _sops_help_render_section "사용 예시" _sops_help_rows_usage
    _sops_help_render_section "새 PC" _sops_help_rows_newpc
    _sops_help_render_section "위험 요소" _sops_help_rows_risks
    _sops_help_render_section "문제 해결" _sops_help_rows_trouble
    _sops_help_render_section "더 알아보기" _sops_help_rows_more
}

sops_help() {
    case "${1:-}" in
        "" | -h | --help | help) _sops_help_summary ;;
        --list | list | section | sections) _sops_help_list_sections ;;
        --all | all) _sops_help_full ;;
        *) _sops_help_section_rows "$1" ;;
    esac
}

alias sops-help='sops_help'
alias age-help='sops_help'
