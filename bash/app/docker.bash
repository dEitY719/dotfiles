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
alias dcl='docker compose logs -f' # 서비스 로그 follow
alias dce='docker compose exec'    # 서비스 내 명령 실행 (dce app bash 등)

# 🔹 Compose 추가 alias
alias dcps='docker compose ps'       # compose 서비스 상태
alias dcb='docker compose build'     # 서비스 이미지 빌드
alias dcr='docker compose restart'   # 서비스 재시작
alias dcdv='docker compose down -v'  # 볼륨까지 삭제 (데이터 초기화)
alias dcstop='docker compose stop'   # 컨테이너만 정지
alias dcstart='docker compose start' # 정지된 컨테이너 시작

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

# -------------------------------
# Docker Helper
# -------------------------------
dockerhelp() {
    cat <<-'EOF'

[Docker / Docker Compose Quick Commands]

  🔹 Docker Compose 기본 (핵심 6개)
    dc           : docker compose
    dcu          : docker compose up
                   예) dcu             (포어그라운드 실행)
                       dcu -d          (옵션으로 detached 실행)
    dcud         : docker compose up -d (항상 detached 실행)
    dcd          : docker compose down
    dcl          : docker compose logs -f
    dce          : docker compose exec <svc> <cmd>

  🔹 Docker Compose 추가
    dcps         : docker compose ps
    dcb          : docker compose build
    dcr          : docker compose restart
    dcdv         : docker compose down -v   (볼륨까지 삭제)
    dcstop       : docker compose stop      (컨테이너만 정지)
    dcstart      : docker compose start     (정지된 컨테이너 재시작)

  🔹 Docker 기본
    dps          : docker ps                (실행 중 컨테이너)
    dpsa         : docker ps -a             (모든 컨테이너)
    di / dim     : docker images            (이미지 목록)
    dstats       : docker stats             (리소스 모니터링)
    dstop        : docker stop <name/id>    (컨테이너 정지)
    drm          : docker rm <name/id>      (컨테이너 삭제)
    drmi         : docker rmi <image>       (이미지 삭제)
    dlogs        : docker logs -f <name>    (컨테이너 로그 follow)
    dinspect     : docker inspect <name>    (상세 정보)

  🔹 유틸리티 함수
    dbash <name>         : 컨테이너 쉘 접속 (bash 없으면 sh로 자동 시도)
    dstopall             : 모든 실행 중 컨테이너 정지
    drmall               : 중지 포함 모든 컨테이너 삭제
    drm_dangling         : dangling 이미지 삭제
    dprune               : docker system prune -f (기본 청소)
    dprune_full          : docker system prune -a --volumes -f (강력 청소, YES 확인 필요)
    dlog_last <name> [N] : 컨테이너 최근 N줄 로그 조회 (기본 200줄)

  🔹 참고
    - Compose V2 기준: 'docker compose' 사용
    - V1 환경이라면 alias 정의에서 'docker compose' → 'docker-compose'로 치환하세요.
    - 셸 시작 시:
        source /path/to/docker.bash
      를 .bashrc 또는 .zshrc에 추가하면 항상 자동 로드됩니다.

EOF
}
