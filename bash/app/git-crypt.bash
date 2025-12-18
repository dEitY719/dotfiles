#!/bin/bash

: <<'GIT_CRYPT_DOC'
==========================================================
git-crypt Quickstart (투명한 Git 암호화)
==========================================================

1) 설치
--------
apt-get install git-crypt
또는: bash mytool/install-git-crypt.sh

2) 초기화 및 GPG 키 추가
------------------------
git-crypt init
gpg --full-generate-key                    # GPG 키 없으면 생성
git-crypt add-gpg-user YOUR_GPG_KEY_ID    # 자신의 GPG 키 추가

3) 암호화할 파일 패턴 지정 (.gitattributes)
------------------------------------------
echo ".env filter=git-crypt diff=git-crypt" >> .gitattributes
echo "*.secret filter=git-crypt diff=git-crypt" >> .gitattributes

4) 자동 암호화/복호화
--------------------
git add .env .gitattributes
git commit -m "Add encrypted secrets"
git push                               # 자동으로 암호화되어 push됨

# 다른 컴퓨터에서 pull
git clone <repo>
git-crypt unlock                       # GPG 키로 자동 복호화

==========================================================
GIT_CRYPT_DOC

# --- Alias & Helpers ---
alias gci='git-crypt init'
alias gcadduser='git-crypt add-gpg-user'
alias gcstatus='git-crypt status'
alias gclock='git-crypt lock'
alias gcunlock='git-crypt unlock'
alias gcls='git-crypt status -f'
alias gchelp='gc_help'
alias gc-help='gc_help'
alias gcinstall='git_crypt_install'
alias gcsetup='gc_setup'
alias gcsetup-cache='gc_setup_cache'
alias gcpurge='gc_purge_cache'
alias gcaddme='gc_addme'

# git-crypt 설치 스크립트 실행
git_crypt_install() {
    bash "$HOME/dotfiles/mytool/install-git-crypt.sh"
}

# git-crypt 빠른 도움말
gc_help() {
    ux_header "git-crypt (투명한 Git 암호화)"

    ux_section "설치"
    ux_table_row "gcinstall" "설치 스크립트" "apt-get 기반 설치"
    ux_table_row "패키지" "git-crypt" "apt-get install git-crypt"
    ux_bullet "필수: git, gpg, GPG 키"
    echo ""

    ux_section "기본 워크플로 (자동 암호화/복호화)"
    ux_table_row "1. 초기화" "gci (git-crypt init)" "리포지토리 설정"
    ux_table_row "2. GPG 키 추가" "gcaddme (자동) ⭐" "내 GPG 키 자동 찾기 & 추가"
    ux_table_row "   또는" "gcadduser KEY_ID (수동)" "GPG Key ID로 직접 추가"
    ux_table_row "3. .gitattributes" "gc_encrypt_env (자동)" ".env 암호화 설정"
    ux_table_row "4. Commit & Push" "git add && git commit && git push" "자동 암호화됨"
    ux_table_row "5. Clone & Pull" "git clone && gcunlock" "자동 복호화됨"
    echo ""

    ux_section "Alias"
    ux_table_row "gci" "git-crypt init" "초기화"
    ux_table_row "gcadduser" "git-crypt add-gpg-user" "GPG 키 추가"
    ux_table_row "gcstatus" "git-crypt status" "암호화 상태 확인"
    ux_table_row "gclock" "git-crypt lock" "수동 암호화 (잠금)"
    ux_table_row "gcunlock" "git-crypt unlock" "수동 복호화 (해제)"
    ux_table_row "gcls" "git-crypt status -f" "암호화된 파일 목록"
    echo ""

    ux_section "Helper Functions"
    ux_table_row "gcsetup" "gc_setup" "대화형 초기 설정 도우미"
    ux_table_row "gcaddme" "gc_addme" "내 GPG 키 자동 찾기 & 추가 ⭐"
    ux_table_row "gc_encrypt_env" "암호화 .env" ".env 파일 암호화 퀵 스타트"
    ux_table_row "gcsetup-cache" "gc_setup_cache" "GPG agent 캐싱 설정 (24시간)"
    ux_table_row "gcpurge" "gc_purge_cache" "GPG 캐시 초기화 (즉시 만료)"
    ux_table_row "gc_cache_status" "캐싱 상태" "GPG agent 캐싱 상태 확인"
    echo ""

    ux_section "git-secret과의 비교"
    echo "  ${bold}git-crypt${reset}           ${bold}git-secret${reset}"
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  자동 암호화/복호화    수동 hide/reveal 필요"
    echo "  .gitattributes       .gitsecret/ 디렉토리"
    echo "  투명한 통합           명시적 명령어"
    echo "  git add 시 암호화    git secret hide 실행"
    echo "  git pull 시 복호화   git secret reveal 실행"
    echo ""

    ux_section "Tips"
    ux_bullet ".env는 .gitignore에 추가하되, .gitattributes로 암호화"
    ux_bullet "GPG 키는 gpg --list-keys 로 확인"
    ux_bullet "팀원 추가 시 각자의 GPG 공개키로 add-gpg-user 실행"
    ux_bullet "암호화 상태 확인: gcstatus 또는 gcls"
    ux_bullet "GPG passphrase 캐싱: gcsetup-cache (24시간 동안 재입력 불필요)"
    ux_bullet ".gitattributes 예시:"
    echo "    .env filter=git-crypt diff=git-crypt"
    echo "    *.secret filter=git-crypt diff=git-crypt"
    echo "    secrets/* filter=git-crypt diff=git-crypt"
    echo ""
}

# git-crypt 초기 설정 도우미 (대화형)
gc_setup() {
    ux_header "git-crypt 초기 설정 도우미"

    # 1. Check if in git repo
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        ux_error "Git 리포지토리가 아닙니다."
        return 1
    fi

    # 2. Check if git-crypt installed
    if ! command -v git-crypt &>/dev/null; then
        ux_error "git-crypt이 설치되어 있지 않습니다."
        ux_info "설치: gcinstall 또는 bash mytool/install-git-crypt.sh"
        return 1
    fi

    # 3. Initialize git-crypt
    ux_section "Step 1: git-crypt 초기화"
    if git-crypt status &>/dev/null; then
        ux_warning "이미 git-crypt이 초기화되어 있습니다."
    else
        ux_info "실행: git-crypt init"
        if git-crypt init; then
            ux_success "git-crypt 초기화 완료"
        else
            ux_error "git-crypt 초기화 실패"
            return 1
        fi
    fi
    echo ""

    # 4. GPG key check
    ux_section "Step 2: GPG 키 확인"
    if ! gpg --list-secret-keys | grep -q "sec"; then
        ux_warning "GPG 개인키가 없습니다."
        ux_info "GPG 키 생성: gpg --full-generate-key"
        ux_info "생성 후 다시 실행하세요: gc_setup"
        return 1
    fi

    ux_success "GPG 키 확인됨:"
    gpg --list-secret-keys --keyid-format=long | grep -A 1 "sec" | head -n 2
    echo ""

    # 5. Add GPG user
    ux_section "Step 3: GPG 키 추가"
    ux_info "현재 GPG 키 목록:"
    gpg --list-secret-keys --keyid-format=long
    echo ""

    ux_info "git-crypt add-gpg-user 명령어를 사용하여 GPG 키를 추가하세요."
    ux_info "예시: git-crypt add-gpg-user YOUR_GPG_KEY_ID"
    ux_info "또는: gcadduser YOUR_GPG_KEY_ID"
    echo ""

    # 6. .gitattributes setup
    ux_section "Step 4: .gitattributes 설정"
    if [[ -f .gitattributes ]]; then
        ux_info ".gitattributes 파일이 이미 존재합니다:"
        cat .gitattributes
    else
        ux_info ".gitattributes 파일이 없습니다. 예시:"
        echo "  .env filter=git-crypt diff=git-crypt"
        echo "  *.secret filter=git-crypt diff=git-crypt"
    fi
    echo ""

    ux_success "git-crypt 초기 설정 완료!"
    ux_info "다음: .gitattributes에 암호화할 파일 패턴을 추가하고 commit하세요."
}

# .env 파일 암호화 퀵 스타트
gc_encrypt_env() {
    ux_header ".env 파일 암호화 퀵 스타트"

    # Check if .env exists
    if [[ ! -f .env ]]; then
        ux_error ".env 파일이 없습니다."
        return 1
    fi

    ux_info ".env 파일을 git-crypt로 암호화합니다."
    echo ""

    # 1. Add to .gitattributes
    ux_section "Step 1: .gitattributes 설정"
    if ! grep -q "^\.env.*filter=git-crypt" .gitattributes 2>/dev/null; then
        echo ".env filter=git-crypt diff=git-crypt" >> .gitattributes
        ux_success ".gitattributes에 .env 패턴 추가됨"
    else
        ux_info ".env가 이미 .gitattributes에 있습니다."
    fi
    echo ""

    # 2. Handle .gitignore conflict
    ux_section "Step 2: .gitignore 확인 및 처리"
    local choice="1"

    if grep -q "^\.env$" .gitignore 2>/dev/null; then
        ux_warning ".env가 .gitignore에 있습니다."
        echo ""
        ux_info "git-crypt 사용 시 .env는 암호화되므로 저장소에 추가해도 안전합니다."
        ux_info "두 가지 선택지가 있습니다:"
        echo ""
        echo "  ${bold}[1] .gitignore에서 .env 제거 (권장)${reset}"
        echo "      → .env: 암호화되어 저장소에 커밋"
        echo "      → .env.local: .gitignore에 추가 (로컬 전용)"
        echo ""
        echo "  ${bold}[2] git add -f 사용 (강제 추가)${reset}"
        echo "      → .gitignore는 유지, 매번 -f 플래그 필요"
        echo ""

        echo -n "  선택 [1/2] (Enter = 1): "
        read -r choice
        choice=${choice:-1}

        if [[ "$choice" == "1" ]]; then
            # Remove .env from .gitignore
            if sed -i '/^\.env$/d' .gitignore; then
                ux_success ".gitignore에서 .env 제거됨"

                # Add .env.local instead
                if ! grep -q "^\.env\.local$" .gitignore 2>/dev/null; then
                    echo ".env.local" >> .gitignore
                    ux_success ".gitignore에 .env.local 추가됨 (로컬 전용)"
                fi
            else
                ux_error ".gitignore 수정 실패"
                return 1
            fi
        else
            ux_info "git add -f 플래그를 사용하세요."
        fi
    else
        ux_info ".env가 .gitignore에 없습니다."
        ux_bullet "로컬 전용 파일은 .env.local 사용을 권장합니다."
    fi
    echo ""

    # 3. Git add and commit
    ux_section "Step 3: Git add & commit"
    ux_info "실행할 명령어:"

    if [[ "$choice" == "2" ]]; then
        echo "  git add -f .env .gitattributes"
    else
        echo "  git add .env .gitattributes .gitignore"
    fi

    echo "  git commit -m \"Add encrypted .env with git-crypt\""
    echo "  git push"
    echo ""

    ux_success ".env 암호화 설정 완료!"
    ux_info "위 명령어를 실행하면 .env가 자동으로 암호화되어 push됩니다."
    echo ""

    ux_section "💡 Tip: .env.local 사용법"
    ux_bullet "공유할 환경 변수: .env (git-crypt로 암호화되어 커밋)"
    ux_bullet "로컬 전용 값: .env.local (git에 커밋 안 됨)"
    ux_bullet "애플리케이션에서 .env.local이 .env를 오버라이드하도록 설정 권장"
}

# GPG agent 캐싱 설정 (편의성 향상)
gc_setup_cache() {
    bash "$HOME/dotfiles/mytool/setup-gpg-cache.sh"
}

# GPG agent 캐시 수동 초기화 (passphrase 즉시 만료)
gc_purge_cache() {
    ux_header "GPG Agent 캐시 초기화"

    if ! command -v gpgconf &>/dev/null; then
        ux_error "gpgconf 명령어를 찾을 수 없습니다."
        return 1
    fi

    ux_info "GPG agent 캐시를 초기화합니다 (passphrase 재입력 필요)..."

    if gpgconf --kill gpg-agent; then
        ux_success "GPG agent 캐시 초기화 완료"
        ux_info "다음 GPG 사용 시 passphrase를 다시 입력해야 합니다."
    else
        ux_error "GPG agent 종료 실패"
        return 1
    fi
}

# GPG agent 캐싱 상태 확인
gc_cache_status() {
    ux_header "GPG Agent 캐싱 상태"

    local gpg_agent_conf="$HOME/.gnupg/gpg-agent.conf"

    # Check if config exists
    if [[ ! -f "$gpg_agent_conf" ]]; then
        ux_warning "gpg-agent.conf 파일이 없습니다."
        ux_info "캐싱 설정: gcsetup-cache"
        return 1
    fi

    # Show cache settings
    ux_section "현재 캐싱 설정"
    if grep -q "cache-ttl" "$gpg_agent_conf"; then
        grep -E "cache-ttl" "$gpg_agent_conf" | while read -r line; do
            ux_bullet "$line"
        done
    else
        ux_warning "캐싱 설정이 없습니다."
        ux_info "캐싱 설정: gcsetup-cache"
    fi
    echo ""

    # Check if gpg-agent is running
    ux_section "GPG Agent 실행 상태"
    if pgrep -x gpg-agent &>/dev/null; then
        ux_success "GPG agent 실행 중"
    else
        ux_warning "GPG agent가 실행되지 않았습니다."
    fi
}

# 내 GPG 키를 자동으로 찾아서 git-crypt에 추가
gc_addme() {
    ux_header "GPG 키 자동 추가 (git-crypt)"

    # Check if git-crypt is installed
    if ! command -v git-crypt &>/dev/null; then
        ux_error "git-crypt이 설치되어 있지 않습니다."
        ux_info "설치: gcinstall"
        return 1
    fi

    # Check if in git repo
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        ux_error "Git 리포지토리가 아닙니다."
        return 1
    fi

    # Check if git-crypt is initialized
    if ! git-crypt status &>/dev/null; then
        ux_error "git-crypt이 초기화되지 않았습니다."
        ux_info "초기화: gci (git-crypt init)"
        return 1
    fi

    # Get all GPG secret keys
    local gpg_keys
    gpg_keys=$(gpg --list-secret-keys --keyid-format=long 2>/dev/null | grep "^sec" | awk '{print $2}' | cut -d'/' -f2)

    if [[ -z "$gpg_keys" ]]; then
        ux_error "GPG 개인키가 없습니다."
        ux_info "GPG 키 생성: gpg --full-generate-key"
        return 1
    fi

    # Count keys
    local key_count
    key_count=$(echo "$gpg_keys" | wc -l)

    ux_section "GPG 키 목록 ($key_count개 발견)"
    echo ""

    # Show all keys with details
    local key_index=1
    local key_array=()
    while IFS= read -r key_id; do
        key_array+=("$key_id")
        local key_info
        key_info=$(gpg --list-secret-keys --keyid-format=long "$key_id" 2>/dev/null | grep "^uid" | sed 's/uid *\[.*\] //')
        echo "  [$key_index] $key_id"
        echo "      $key_info"
        echo ""
        ((key_index++))
    done <<< "$gpg_keys"

    # Select key
    local selected_key
    if [[ $key_count -eq 1 ]]; then
        selected_key="${key_array[0]}"
        ux_info "GPG 키 1개 발견, 자동 선택: $selected_key"
    else
        echo -n "  선택할 키 번호 [1-$key_count] (Enter = 1): "
        read -r selection
        selection=${selection:-1}

        if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ $selection -lt 1 ]] || [[ $selection -gt $key_count ]]; then
            ux_error "잘못된 선택입니다."
            return 1
        fi

        selected_key="${key_array[$((selection-1))]}"
        ux_info "선택된 키: $selected_key"
    fi

    echo ""
    ux_section "git-crypt에 GPG 키 추가 중..."

    # Add GPG user to git-crypt
    if git-crypt add-gpg-user "$selected_key"; then
        ux_success "GPG 키 추가 완료!"
        ux_info "이제 .gitattributes를 설정하고 파일을 추가하세요."
        echo ""
        ux_bullet "다음 단계: gc_encrypt_env 또는 수동으로 .gitattributes 설정"
    else
        ux_error "GPG 키 추가 실패"
        return 1
    fi
}
