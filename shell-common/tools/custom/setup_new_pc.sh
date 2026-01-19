#!/bin/bash

# mytool/setup_new_pc.sh
# 다른 PC에서 한 번에 git-crypt 환경 설정 (인터랙티브)

set -e

# Source UX library for consistent styling (unified library)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UX_LIB_PATH="${SCRIPT_DIR}/../ux_lib/ux_lib.sh"
if [[ -f "$UX_LIB_PATH" ]]; then
    source "$UX_LIB_PATH"
else
    echo "Error: UX library not found at $UX_LIB_PATH"
    exit 1
fi

# Helper functions using UX library
info() {
    ux_info "$*"
}

success() {
    ux_success "$*"
}

warning() {
    ux_warning "$*"
}

error() {
    ux_error "$*"
}

confirm() {
    ux_confirm "$1" "${2:-y}"
}

main() {
    clear
    ux_header "다른 PC에서 git-crypt 환경 설정 (올인원)"
    echo ""
    ux_info "이 스크립트는 새로운 PC에서 git-crypt를 사용하기 위한"
    ux_info "모든 설정을 자동으로 진행합니다."
    echo ""
    ux_section "진행 단계"
    ux_numbered 1 "git-crypt 설치 확인/설치"
    ux_numbered 2 "GPG 개인키 복원"
    ux_numbered 3 "GPG 캐싱 설정 (선택)"
    ux_numbered 4 "git-crypt 복호화"
    ux_numbered 5 ".env 파일 확인"
    echo ""
    ux_warning "주의: 이 스크립트는 dotfiles 리포지토리 내에서 실행해야 합니다."
    echo ""

    if ! confirm "계속 진행하시겠습니까?"; then
        warning "설정이 취소되었습니다."
        exit 0
    fi

    # ========================================
    # Step 0: Check if in dotfiles repo
    # ========================================
    info "Step 0/5: dotfiles 리포지토리 확인 중..."

    if [[ ! -d .git ]] || [[ ! -f bash/app/git-crypt.bash ]]; then
        error "dotfiles 리포지토리가 아닙니다."
        warning "다음 명령어를 먼저 실행하세요:"
        echo "  git clone <your-dotfiles-repo>"
        echo "  cd dotfiles"
        echo "  bash mytool/setup_new_pc.sh"
        exit 1
    fi
    success "dotfiles 리포지토리 확인됨"
    echo ""

    # ========================================
    # Step 1: Install git-crypt
    # ========================================
    info "Step 1/5: git-crypt 설치 확인 중..."

    if command -v git-crypt &>/dev/null; then
        success "git-crypt 이미 설치됨: $(git-crypt --version 2>/dev/null || echo 'unknown')"
    else
        warning "git-crypt이 설치되어 있지 않습니다."
        if confirm "지금 설치하시겠습니까?"; then
            if confirm "sudo apt-get install -y git-crypt 를 실행할까요?"; then
                sudo apt-get update
                sudo apt-get install -y git-crypt
                success "git-crypt 설치 완료"
            else
                error "git-crypt 설치가 필요합니다."
                exit 1
            fi
        else
            error "git-crypt 설치가 필요합니다."
            exit 1
        fi
    fi
    echo ""

    # ========================================
    # Step 2: Restore GPG key
    # ========================================
    info "Step 2/5: GPG 개인키 복원 중..."

    # Check if gpg is installed
    if ! command -v gpg &>/dev/null; then
        error "gpg가 설치되어 있지 않습니다."
        if confirm "sudo apt-get install -y gnupg 를 실행할까요?"; then
            sudo apt-get install -y gnupg
        else
            exit 1
        fi
    fi

    # Find encrypted backup files
    local encrypted_files
    encrypted_files=$(find .secrets -name "gpg-backup-*.asc.gpg" 2>/dev/null)

    if [[ -z "$encrypted_files" ]]; then
        error ".secrets/ 디렉토리에 암호화된 GPG 백업 파일이 없습니다."
        warning "다음 중 하나를 확인하세요:"
        echo "  1. git pull 로 최신 상태 확인"
        echo "  2. 원래 PC에서 gcbackup 실행 후 git push 했는지 확인"
        exit 1
    fi

    # Show found files
    echo ""
    echo "${bold}발견된 GPG 백업 파일:${reset}"
    local file_count=0
    local file_array=()
    while IFS= read -r file; do
        ((file_count++))
        file_array+=("$file")
        echo "  [$file_count] $file"
    done <<< "$encrypted_files"
    echo ""

    # Select file
    local backup_file
    if [[ $file_count -eq 1 ]]; then
        backup_file="${file_array[0]}"
        info "백업 파일 자동 선택: $backup_file"
    else
        echo -n "  복원할 파일 번호 [1-$file_count] (Enter = 1): "
        read -r selection
        selection=${selection:-1}

        if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ $selection -lt 1 ]] || [[ $selection -gt $file_count ]]; then
            error "잘못된 선택입니다."
            exit 1
        fi

        backup_file="${file_array[$((selection-1))]}"
        info "선택된 파일: $backup_file"
    fi

    echo ""
    info "GPG 백업 파일 복호화 중..."
    warning "대칭키 Passphrase를 입력하세요 (gcbackup 시 설정한 것)"
    echo ""

    # Decrypt backup file
    local decrypted_file="/tmp/gpg-backup-temp.asc"
    if ! gpg --decrypt --output "$decrypted_file" "$backup_file" 2>/dev/null; then
        error "복호화 실패 (Passphrase 확인)"
        exit 1
    fi
    success "복호화 완료!"

    # Import GPG key
    echo ""
    info "GPG 개인키 import 중..."
    if gpg --import "$decrypted_file" 2>/dev/null; then
        success "GPG 개인키 import 완료!"
        rm -f "$decrypted_file"
    else
        error "GPG 키 import 실패"
        rm -f "$decrypted_file"
        exit 1
    fi

    # Show imported key
    local imported_key
    imported_key=$(gpg --list-secret-keys --keyid-format=long 2>/dev/null | grep "^sec" | tail -n 1 | awk '{print $2}' | cut -d'/' -f2)
    if [[ -n "$imported_key" ]]; then
        info "Import된 키 ID: $imported_key"
    fi
    echo ""

    # ========================================
    # Step 3: GPG caching setup (optional)
    # ========================================
    info "Step 3/5: GPG 캐싱 설정 (선택)..."

    if confirm "GPG Passphrase를 24시간 동안 캐싱하시겠습니까? (권장)"; then
        # Create .gnupg directory
        mkdir -p ~/.gnupg
        chmod 700 ~/.gnupg

        # Configure gpg-agent.conf
        local gpg_agent_conf="$HOME/.gnupg/gpg-agent.conf"
        local cache_ttl=86400

        # Remove old settings
        if [[ -f "$gpg_agent_conf" ]]; then
            sed -i '/default-cache-ttl/d' "$gpg_agent_conf" 2>/dev/null || true
            sed -i '/max-cache-ttl/d' "$gpg_agent_conf" 2>/dev/null || true
        fi

        # Add new settings
        echo "default-cache-ttl $cache_ttl" >> "$gpg_agent_conf"
        echo "max-cache-ttl $cache_ttl" >> "$gpg_agent_conf"

        # Reload gpg-agent
        gpg-connect-agent reloadagent /bye &>/dev/null || true

        success "GPG 캐싱 설정 완료 (24시간)"
    else
        info "GPG 캐싱 스킵됨 (나중에 gcsetup-cache 실행 가능)"
    fi
    echo ""

    # ========================================
    # Step 4: git-crypt unlock
    # ========================================
    info "Step 4/5: git-crypt 복호화 중..."

    if ! git-crypt status &>/dev/null; then
        error "git-crypt이 초기화되지 않은 리포지토리입니다."
        exit 1
    fi

    echo ""
    warning "GPG 개인키 Passphrase를 입력하세요 (gpg --full-generate-key 시 설정한 것)"
    echo ""

    if git-crypt unlock 2>/dev/null; then
        success "git-crypt 복호화 완료!"
    else
        error "git-crypt unlock 실패"
        warning "다음을 확인하세요:"
        echo "  1. Passphrase가 올바른지"
        echo "  2. GPG 키가 리포지토리에 추가되었는지"
        exit 1
    fi
    echo ""

    # ========================================
    # Step 5: Verify .env file
    # ========================================
    info "Step 5/5: .env 파일 확인 중..."

    if [[ ! -f .env ]]; then
        warning ".env 파일이 없습니다."
        warning "리포지토리에 .env가 없거나 다른 위치에 있을 수 있습니다."
    else
        # Check if decrypted (not binary)
        if file .env | grep -q "text"; then
            success ".env 파일 복호화 확인됨!"
            echo ""
            ux_section ".env 파일 미리보기 (첫 5줄)"
            head -n 5 .env | while read -r line; do
                ux_bullet "$line"
            done
            ux_bullet "..."
        else
            error ".env 파일이 여전히 암호화되어 있습니다."
            exit 1
        fi
    fi
    echo ""

    # ========================================
    # Completion
    # ========================================
    echo ""
    ux_success "설정이 완료되었습니다!"
    echo ""
    ux_section "다음 단계 (선택)"
    ux_bullet "dotfiles 적용: bash bash/setup.sh"
    ux_bullet "셸 새로고침: source ~/.bashrc"
    ux_bullet "git-crypt 도움말: gchelp"
    echo ""
    ux_section "설정된 내용"
    ux_success "git-crypt 설치됨"
    ux_success "GPG 개인키 복원됨"
    ux_success "GPG 캐싱 설정됨 (선택)"
    ux_success ".env 파일 복호화됨"
    echo ""
    ux_info "이제 암호화된 파일들을 자유롭게 사용할 수 있습니다!"
    echo ""
}

main "$@"
