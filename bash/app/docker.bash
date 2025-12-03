#!/bin/bash

# bash/app/docker.bash

# -------------------------------
# Docker / Docker Compose Aliases
# -------------------------------
# 참고: Docker Compose V2('docker compose') 기준입니다.
# 구버전(V1: docker-compose) 사용 시 아래의 'docker compose'를 'docker-compose'로 변경하세요.

# 🔹 Compose 기본 단축키 (요청하신 핵심 6개)
alias dc='docker compose'          # 기본 compose 명령
alias dcu='docker compose up'      # foreground 실행 (옵션 추가 가능: dcu -d 등)
alias dcud='docker compose up -d'  # detached 모드 고정 실행
alias dcd='docker compose down'    # 서비스 종료 + 네트워크 정리
# dcl: 개선된 함수 (compose 서비스 또는 컨테이너 이름으로 로그 조회, 아래에 정의)
alias dce='docker compose exec'    # 서비스 내 명령 실행 (dce app bash 등)

# 🔹 Compose 추가 alias
alias dcps='docker compose ps'       # compose 서비스 상태
alias dcb='docker compose build'     # 서비스 이미지 빌드
alias dcr='docker compose restart'   # 서비스 재시작
alias dcdv='docker compose down -v'  # 볼륨까지 삭제 (데이터 초기화)
alias dcstop='docker compose stop'   # 컨테이너만 정지
alias dcstart='docker compose start' # 정지된 컨테이너 시작

# 개선된 dcl 함수: compose 서비스 또는 컨테이너 이름으로 로그 조회
# 사용법: dcl <service_name_or_container>
# 먼저 docker compose logs 시도 → 실패하면 docker logs로 자동 폴백
unalias dcl 2>/dev/null  # 기존 alias 제거 (함수 정의 전)
dcl() {
    if [ -z "$1" ]; then
        echo "사용법: dcl <service_name_or_container> [options]"
        echo ""
        echo "예시:"
        echo "  dcl slea-backend              # compose 서비스 또는 컨테이너 이름"
        echo "  dcl slea-backend --tail 50    # 최근 50줄"
        return 1
    fi

    local service="$1"
    shift  # 첫 번째 인자 제거 (나머지 옵션들을 위해)

    # 먼저 docker compose logs 시도, 실패하면 docker logs로 폴백
    docker compose logs -f "$service" "$@" 2>/dev/null || docker logs -f "$service" "$@"
}

# -------------------------------
# Docker Standard Aliases
# -------------------------------
alias dps='docker ps'       # 실행 중 컨테이너
alias dpsa='docker ps -a'   # 모든 컨테이너(정지 포함)
alias di='docker images'    # 이미지 목록
alias dim='docker images'   # di와 동일 (취향용)
alias dstats='docker stats' # 컨테이너 리소스(CPU/MEM) 모니터링

alias dstop='docker stop'       # 개별 컨테이너 정지
alias drm='docker rm'           # 개별 컨테이너 삭제
alias drmi='docker rmi'         # 개별 이미지 삭제
alias dlogs='docker logs -f'    # 개별 컨테이너 로그 follow
alias dinspect='docker inspect' # 컨테이너/이미지 상세 정보

# -------------------------------
# Utility Functions
# -------------------------------

# 컨테이너 쉘 접속 (bash 우선, 없으면 sh)
# 사용법: dbash <container_name_or_id>
dbash() {
    if [ -z "$1" ]; then
        echo "사용법: dbash <container_name_or_id>"
        return 1
    fi
    docker exec -it "$1" /bin/bash 2>/dev/null || docker exec -it "$1" /bin/sh
}

# 실행 중인 모든 컨테이너 정지
dstopall() {
    local ids
    ids=$(docker ps -q)
    if [ -z "$ids" ]; then
        echo "[Docker] 실행 중인 컨테이너가 없습니다."
        return 0
    fi
    echo "[Docker] 모든 실행 중 컨테이너 정지:"
    echo "$ids"
    docker stop "$ids"
}

# 중지된 컨테이너 일괄 삭제
drmall() {
    local ids
    ids=$(docker ps -aq)
    if [ -z "$ids" ]; then
        echo "[Docker] 삭제할 컨테이너가 없습니다."
        return 0
    fi
    echo "[Docker] 모든 컨테이너 삭제:"
    echo "$ids"
    docker rm "$ids"
}

# dangling(태그 없는) 이미지 삭제
drm_dangling() {
    local ids
    ids=$(docker images -f "dangling=true" -q)
    if [ -z "$ids" ]; then
        echo "[Docker] 삭제할 dangling 이미지가 없습니다."
        return 0
    fi
    echo "[Docker] dangling 이미지 삭제:"
    echo "$ids"
    docker rmi "$ids"
}

# Docker 시스템 기본 청소 (사용되지 않는 컨테이너/네트워크/이미지 등)
dprune() {
    echo "🧹 Docker system prune -f 실행 중..."
    docker system prune -f
}

# Docker 강력 청소 (사용하지 않는 이미지/볼륨까지 전부 삭제) - 매우 주의!
dprune_full() {
    cat <<-'EOF'
⚠️  주의: Docker 전체 강력 청소를 수행합니다.

삭제 대상:
  - 중지된 컨테이너
  - 사용되지 않는 이미지(모든 태그)
  - 사용되지 않는 네트워크
  - 사용되지 않는 볼륨

명령어:
  docker system prune -a --volumes -f

정말 실행하시겠습니까? (YES 입력 시 진행)
EOF

    read -r answer
    if [ "$answer" = "YES" ]; then
        echo "[Docker] docker system prune -a --volumes -f 실행..."
        docker system prune -a --volumes -f
        echo "✅ Docker 강력 청소 완료"
    else
        echo "⏹ 작업이 취소되었습니다."
    fi
}

# 디스크 사용량 확인
ddf() {
    docker system df
}

# 상세 디스크 사용량 확인
ddfv() {
    docker system df -v
}

# Dangling 볼륨 확인
dvols() {
    docker volume ls -f dangling=true
}

# 특정 볼륨 삭제
dvol_rm() {
    if [ -z "$1" ]; then
        echo "사용법: dvol_rm <volume_name>"
        return 1
    fi
    docker volume rm "$1"
}

# 모든 dangling 볼륨 일괄 삭제
dvol_rm_dangling() {
    local ids
    ids=$(docker volume ls -f dangling=true -q)
    if [ -z "$ids" ]; then
        echo "[Docker] 삭제할 dangling 볼륨이 없습니다."
        return 0
    fi
    echo "[Docker] dangling 볼륨 삭제:"
    echo "$ids"
    docker volume rm "$ids"
    echo "✅ dangling 볼륨 삭제 완료"
}

# 컨테이너 환경변수 확인 (정렬)
# 사용법: denv <container_name_or_id>
denv() {
    if [ -z "$1" ]; then
        echo "사용법: denv <container_name_or_id>"
        return 1
    fi
    docker exec "$1" env | sort
}

# docker inspect에서 Env 섹션 확인
# 사용법: dinspect_env <container_name_or_id>
dinspect_env() {
    if [ -z "$1" ]; then
        echo "사용법: dinspect_env <container_name_or_id>"
        return 1
    fi
    docker inspect "$1" | grep -A 50 '"Env":'
}

# 사용되지 않는 네트워크 정리
dnetwork_prune() {
    echo "🧹 Docker network prune -f 실행 중..."
    docker network prune -f
}

# 빌드 캐시 정리
dbuild_prune() {
    echo "🧹 Docker builder prune -f 실행 중..."
    docker builder prune -f
}

# 최근 N줄 로그만 보기 (기본 200줄)
# 사용법: dlog_last <container_name> [줄수]
dlog_last() {
    if [ -z "$1" ]; then
        echo "사용법: dlog_last <container_name> [줄수]"
        return 1
    fi
    local container="$1"
    local lines="${2:-200}"
    docker logs --tail "$lines" "$container"
}

# 모든 컨테이너를 tar 파일로 백업
dexport() {
    local backup_dir="/home/bwyoon/dotfiles/backup"
    local containers

    echo "[Docker] 백업 디렉토리 확인: $backup_dir"
    mkdir -p "$backup_dir"

    # 모든 컨테이너 이름 가져오기
    containers=$(docker ps -a --format "{{.Names}}")

    if [ -z "$containers" ]; then
        echo "[Docker] 백업할 컨테이너가 없습니다."
        return 0
    fi

    echo "[Docker] 다음 컨테이너를 백업합니다:"
    echo "$containers"
    echo "----------------------------------------"

    # 각 컨테이너 export
    for name in $containers; do
        echo "📦 Exporting $name..."
        if docker export "$name" >"$backup_dir/${name}.tar"; then
            echo "✅ $name -> $backup_dir/${name}.tar 완료"
        else
            echo "❌ $name 백업 실패"
        fi
    done

    echo "----------------------------------------"
    echo "🎉 모든 백업 작업이 완료되었습니다."
    ls -lh "$backup_dir"
}

# WSL Docker 설치 (대화형 스크립트)
dinstall() {
    bash /home/bwyoon/dotfiles/mytool/install-docker.sh
}

# WSL Docker 제거 (대화형 스크립트)
duninstall() {
    bash /home/bwyoon/dotfiles/mytool/uninstall-docker.sh
}

# Docker 서비스 자동 시작 설정 (대화형 스크립트)
denable() {
    bash /home/bwyoon/dotfiles/mytool/enable-docker.sh
}

# Docker 회사 프록시 설정 (대화형 스크립트)
dproxy_setup() {
    bash /home/bwyoon/dotfiles/mytool/docker-configure-proxy.sh
}

# Docker 회사 프록시 설정 도움말
dproxyhelp() {
    local bold blue green yellow red reset
    bold=$(tput bold 2>/dev/null || echo "")
    blue=$(tput setaf 4 2>/dev/null || echo "")
    green=$(tput setaf 2 2>/dev/null || echo "")
    yellow=$(tput setaf 3 2>/dev/null || echo "")
    red=$(tput setaf 1 2>/dev/null || echo "")
    reset=$(tput sgr0 2>/dev/null || echo "")

    cat <<EOF

${bold}${blue}════════════════════════════════════════════════════
  Docker 회사 프록시(Corporate Proxy) 설정 가이드
════════════════════════════════════════════════════${reset}

${bold}${blue}1️⃣  설정 파일 위치${reset}
  ${yellow}/etc/systemd/system/docker.service.d/http-proxy.conf${reset}

${bold}${blue}2️⃣  설정 확인${reset}
  ${green}systemctl show --property=Environment docker${reset}

  출력 예:
    Environment=HTTP_PROXY=http://12.26.204.100:8080/ \\
               HTTPS_PROXY=http://12.26.204.100:8080/ \\
               NO_PROXY=localhost,127.0.0.1,...

${bold}${blue}3️⃣  설정 파일 내용 확인${reset}
  ${green}cat /etc/systemd/system/docker.service.d/http-proxy.conf${reset}

${bold}${blue}4️⃣  설정 수정${reset}
  ${green}sudo nano /etc/systemd/system/docker.service.d/http-proxy.conf${reset}

  수정 후:
    ${green}sudo systemctl daemon-reload${reset}
    ${green}sudo systemctl restart docker${reset}

${bold}${blue}5️⃣  설정 제거${reset}
  ${green}sudo rm -f /etc/systemd/system/docker.service.d/http-proxy.conf${reset}

  제거 후:
    ${green}sudo systemctl daemon-reload${reset}
    ${green}sudo systemctl restart docker${reset}

${bold}${blue}6️⃣  Proxy 연결 테스트${reset}
  ${green}docker pull alpine:latest${reset}

  성공하면 이미지를 pull할 수 있습니다.

${bold}${blue}7️⃣  설정 초기화 (전체 drop-in 디렉토리 삭제)${reset}
  ${red}sudo rm -rf /etc/systemd/system/docker.service.d/${reset}

  ${red}⚠️  주의: 다른 설정도 함께 삭제됩니다!${reset}

${bold}${blue}═══════════════════════════════════════════════════${reset}

${bold}빠른 명령어:${reset}
  ${green}dproxy_setup${reset}   : Proxy 설정 대화형 스크립트
  ${green}dproxyhelp${reset}    : 이 도움말 표시
  ${green}dproxy_show${reset}    : 현재 Proxy 설정 확인

EOF
}

# Docker Proxy 설정 확인
dproxy_show() {
    local bold blue green yellow reset
    bold=$(tput bold 2>/dev/null || echo "")
    blue=$(tput setaf 4 2>/dev/null || echo "")
    green=$(tput setaf 2 2>/dev/null || echo "")
    yellow=$(tput setaf 3 2>/dev/null || echo "")
    reset=$(tput sgr0 2>/dev/null || echo "")

    local proxy_conf="/etc/systemd/system/docker.service.d/http-proxy.conf"

    echo "${bold}${blue}Docker Proxy Configuration${reset}"
    echo ""

    if [ -f "$proxy_conf" ]; then
        echo "${bold}${green}✓ Proxy 설정 파일 존재${reset}"
        echo ""
        echo "${bold}설정 파일 위치:${reset}"
        echo "  ${yellow}${proxy_conf}${reset}"
        echo ""
        echo "${bold}설정 내용:${reset}"
        sed 's/^/  /' <"$proxy_conf"
        echo ""
        echo "${bold}현재 Docker 환경변수:${reset}"
        systemctl show --property=Environment docker | sed 's/^/  /'
    else
        echo "${bold}${yellow}⚠  Proxy 설정 파일 없음${reset}"
        echo ""
        echo "Proxy를 설정하려면:"
        echo "  ${green}dproxy_setup${reset}"
    fi
}

# -------------------------------
# Docker Helper
# -------------------------------
dockerhelp() {
    # Color definitions
    local bold blue green yellow reset
    bold=$(tput bold 2>/dev/null || echo "")
    blue=$(tput setaf 4 2>/dev/null || echo "")
    green=$(tput setaf 2 2>/dev/null || echo "")
    yellow=$(tput setaf 3 2>/dev/null || echo "")
    reset=$(tput sgr0 2>/dev/null || echo "")

    cat <<EOF

${bold}${blue}[Docker / Docker Compose Quick Commands]${reset}

  ${bold}${blue}🔹 Docker Compose 기본 (핵심 6개)${reset}
    ${green}dc${reset}           : docker compose
    ${green}dcu${reset}          : docker compose up
                   예) dcu             (포어그라운드 실행)
                       dcu -d          (옵션으로 detached 실행)
    ${green}dcud${reset}         : docker compose up -d (항상 detached 실행)
    ${green}dcd${reset}          : docker compose down
    ${green}dcl${reset}          : 개선된 로그 조회 (compose 서비스 또는 컨테이너 이름 모두 지원)
                   예) dcl slea-backend          (포어그라운드)
                       dcl slea-backend --tail 50 (최근 50줄)
    ${green}dce${reset}          : docker compose exec <svc> <cmd>

  ${bold}${blue}🔹 Docker Compose 추가${reset}
    ${green}dcps${reset}         : docker compose ps
    ${green}dcb${reset}          : docker compose build
    ${green}dcr${reset}          : docker compose restart
    ${green}dcdv${reset}         : docker compose down -v   (볼륨까지 삭제)
    ${green}dcstop${reset}       : docker compose stop      (컨테이너만 정지)
    ${green}dcstart${reset}      : docker compose start     (정지된 컨테이너 재시작)

  ${bold}${blue}🔹 Docker 기본${reset}
    ${green}dps${reset}          : docker ps                (실행 중 컨테이너)
    ${green}dpsa${reset}         : docker ps -a             (모든 컨테이너)
    ${green}di / dim${reset}     : docker images            (이미지 목록)
    ${green}dstats${reset}       : docker stats             (리소스 모니터링)
    ${green}dstop${reset}        : docker stop <name/id>    (컨테이너 정지)
    ${green}drm${reset}          : docker rm <name/id>      (컨테이너 삭제)
    ${green}drmi${reset}         : docker rmi <image>       (이미지 삭제)
    ${green}dlogs${reset}        : docker logs -f <name>    (컨테이너 로그 follow)
    ${green}dinspect${reset}     : docker inspect <name>    (상세 정보)

  ${bold}${blue}🔹 Docker 리소스 관리${reset}
    ${green}ddf${reset}                  : docker system df              (디스크 사용량 확인)
    ${green}ddfv${reset}                 : docker system df -v           (상세 디스크 사용량)
    ${green}dvols${reset}                : docker volume ls -f dangling=true (dangling 볼륨 확인)
    ${green}dvol_rm <name>${reset}       : docker volume rm <name>       (특정 볼륨 삭제)
    ${green}dvol_rm_dangling${reset}     : dangling 볼륨 일괄 삭제
    ${green}dnetwork_prune${reset}       : 사용되지 않는 네트워크 정리
    ${green}dbuild_prune${reset}         : 빌드 캐시 정리
    ${green}dprune${reset}               : docker system prune -f         (기본 청소)
    ${green}dprune_full${reset}          : docker system prune -a --volumes -f (강력 청소)

  ${bold}${blue}🔹 유틸리티 함수${reset}
    ${green}dinstall${reset}             : WSL Docker 설치 (대화형 스크립트)
    ${green}duninstall${reset}           : WSL Docker 제거 (대화형 스크립트)
    ${green}denable${reset}              : Docker 자동 시작 설정 (systemd)
    ${green}dproxy_setup${reset}         : 회사 프록시 설정 (대화형 스크립트)
    ${green}dproxyhelp${reset}          : 회사 프록시 설정 가이드 및 명령어 안내
    ${green}dproxy_show${reset}          : 현재 회사 프록시 설정 확인
    ${green}dbash <name>${reset}         : 컨테이너 쉘 접속 (bash 없으면 sh로 자동 시도)
    ${green}denv <name>${reset}          : 컨테이너 환경변수 확인 (docker exec env | sort)
    ${green}dinspect_env <name>${reset}  : docker inspect에서 Env 섹션 확인 (-A 50줄)
    ${green}dstopall${reset}             : 모든 실행 중 컨테이너 정지
    ${green}drmall${reset}               : 중지 포함 모든 컨테이너 삭제
    ${green}drm_dangling${reset}         : dangling 이미지 삭제
    ${green}dprune${reset}               : docker system prune -f (기본 청소)
    ${green}dprune_full${reset}          : docker system prune -a --volumes -f (강력 청소, YES 확인 필요)
    ${green}dlog_last <name> [N]${reset} : 컨테이너 최근 N줄 로그 조회 (기본 200줄)
    ${green}dexport${reset}              : 모든 컨테이너를 tar 파일로 백업 (~/dotfiles/backup)

  ${bold}${blue}🔹 참고${reset}
    ${yellow}- Compose V2 기준: 'docker compose' 사용
    - V1 환경이라면 alias 정의에서 'docker compose' → 'docker-compose'로 치환하세요.
    - 셸 시작 시:
        source /path/to/docker.bash
      를 .bashrc 또는 .zshrc에 추가하면 항상 자동 로드됩니다.${reset}

EOF
}
