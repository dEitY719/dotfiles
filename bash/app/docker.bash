#!/bin/bash

# bash/app/docker.bash

# -------------------------------
# Docker / Docker Compose Aliases
# -------------------------------
# 참고: Docker Compose V2('docker compose') 기준입니다.
# 구버전(V1: docker-compose) 사용 시 아래의 'docker compose'를 'docker-compose'로 변경하세요.

# 🔹 Compose 기본 단축키 (요청하신 핵심 6개)
alias dc='docker compose'         # 기본 compose 명령
alias dcu='docker compose up'     # foreground 실행 (옵션 추가 가능: dcu -d 등)
alias dcud='docker compose up -d' # detached 모드 고정 실행
alias dcd='docker compose down'   # 서비스 종료 + 네트워크 정리
# dcl: 개선된 함수 (compose 서비스 또는 컨테이너 이름으로 로그 조회, 아래에 정의)
alias dce='docker compose exec' # 서비스 내 명령 실행 (dce app bash 등)

# 🔹 Compose 추가 alias
alias dcps='docker compose ps'       # compose 서비스 상태
alias dcb='docker compose build'     # 서비스 이미지 빌드
alias dcdv='docker compose down -v'  # 볼륨까지 삭제 (데이터 초기화)
alias dcstop='docker compose stop'   # 컨테이너만 정지
alias dcstart='docker compose start' # 정지된 컨테이너 시작

# 개선된 dcl 함수: compose 서비스 또는 컨테이너 이름으로 로그 조회
# 사용법: dcl <service_name_or_container>
# 먼저 docker compose logs 시도 → 실패하면 docker logs로 자동 폴백
# Now uses central UX library for consistent styling
unalias dcl 2>/dev/null # 기존 alias 제거 (함수 정의 전)
unalias dcr 2>/dev/null # 기존 alias 제거 (함수 정의 전)
dcl() {
    # UX library is already loaded globally in main.bash
    if [ -z "$1" ]; then
        ux_header "Docker Compose Logs (dcl)"

        ux_section "Usage"
        echo "  ${UX_SUCCESS}dcl${UX_RESET} ${UX_MUTED}<service_name_or_container> [options]${UX_RESET}"
        echo ""

        ux_section "Examples"
        echo "  ${UX_MUTED}#${UX_RESET} View logs for a service or container"
        echo "  ${UX_INFO}dcl slea-backend${UX_RESET}"
        echo ""
        echo "  ${UX_MUTED}#${UX_RESET} Follow last 50 lines"
        echo "  ${UX_INFO}dcl slea-backend --tail 50${UX_RESET}"
        echo ""
        echo "  ${UX_MUTED}#${UX_RESET} Follow logs in real-time with timestamps"
        echo "  ${UX_INFO}dcl slea-backend -f --timestamps${UX_RESET}"
        echo ""

        ux_section "Currently Running Containers"
        if docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null | tail -n +2 | head -20; then
            echo ""
        else
            ux_warning "No running containers found"
            echo ""
        fi

        ux_info "Run ${UX_BOLD}dockerhelp${UX_RESET} for more Docker commands"
        echo ""
        return 0
    fi

    local service="$1"
    shift # 첫 번째 인자 제거 (나머지 옵션들을 위해)

    # 1. Try to identify as a Docker Compose service
    # We check 'docker compose config --services' to verify existence without running logs yet.
    # This prevents 'docker compose logs' from swallowing stderr (app logs) via the old 2>/dev/null method.
    if docker compose config --services 2>/dev/null | grep -qFx "$service"; then
        docker compose logs -f "$service" "$@"
        return 0
    fi

    # 2. Fallback: Check if it's a valid container name/ID
    if docker container inspect "$service" >/dev/null 2>&1; then
        docker logs -f "$service" "$@"
        return 0
    fi

    ux_error "Service or container '${service}' not found"
    echo ""
    ux_info "Run ${UX_BOLD}dcl${UX_RESET} without arguments to see available containers"
    return 1
}

# Compose restart with auto-discovery
# Usage: dcr <service_name> [docker compose args...]
# - Tries current dir compose file first
# - Falls back to LITELLM_PROJECT_PATH or ~/para/project/litellm-stack
# - If no compose file found, falls back to docker restart on the container
dcr() {
    if [ -z "$1" ]; then
        ux_usage "dcr" "<service_name> [options]" "Restart service (compose-aware, auto path detect)"
        ux_bullet "Search order: ./compose.yml → \$LITELLM_PROJECT_PATH → ~/para/project/litellm-stack"
        ux_bullet "Fallback: docker restart <container>"
        return 1
    fi

    local service="$1"; shift

    # Build candidate directories
    local -a candidate_dirs=()
    local cwd_dir
    cwd_dir="$(pwd)"
    candidate_dirs+=("$cwd_dir")

    if [[ -n "$LITELLM_PROJECT_PATH" ]]; then
        candidate_dirs+=("$LITELLM_PROJECT_PATH")
    fi
    if [[ -d "$HOME/para/project/litellm-stack" ]]; then
        candidate_dirs+=("$HOME/para/project/litellm-stack")
    fi

    # Deduplicate directories
    local -a unique_dirs=()
    local seen
    for dir in "${candidate_dirs[@]}"; do
        seen=false
        for udir in "${unique_dirs[@]}"; do
            if [[ "$dir" == "$udir" ]]; then
                seen=true
                break
            fi
        done
        [[ "$seen" == false ]] && unique_dirs+=("$dir")
    done

    local compose_file=""
    local compose_dir=""
    local fname
    for dir in "${unique_dirs[@]}"; do
        for fname in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
            if [[ -f "$dir/$fname" ]]; then
                compose_file="$dir/$fname"
                compose_dir="$dir"
                break 2
            fi
        done
    done

    if [[ -n "$compose_file" ]]; then
        ux_info "Using compose file: $compose_file"

        # Use absolute compose path, no directory change
        local -a compose_args=("-f" "$compose_file")

        # Capture current start time (if container exists) to detect no-op restarts
        local container_id=""
        local old_started=""
        container_id=$(docker compose "${compose_args[@]}" ps -q "$service" 2>/dev/null | head -1)
        if [[ -n "$container_id" ]]; then
            old_started=$(docker inspect -f '{{.State.StartedAt}}' "$container_id" 2>/dev/null || echo "")
        fi

        # First try a standard restart
        if docker compose "${compose_args[@]}" restart "$service" "$@"; then
            # Check if start time changed; if not, force recreate
            local new_started=""
            if [[ -n "$container_id" ]]; then
                new_started=$(docker inspect -f '{{.State.StartedAt}}' "$container_id" 2>/dev/null || echo "")
            fi

            if [[ -n "$old_started" && -n "$new_started" && "$old_started" == "$new_started" ]]; then
                ux_warning "Restart did not change start time; forcing recreate (up -d --force-recreate --no-deps)."
                docker compose "${compose_args[@]}" up -d --force-recreate --no-deps "$service"
                container_id=$(docker compose "${compose_args[@]}" ps -q "$service" 2>/dev/null | head -1)
                if [[ -n "$container_id" ]]; then
                    new_started=$(docker inspect -f '{{.State.StartedAt}}' "$container_id" 2>/dev/null || echo "")
                fi
            fi

            if [[ -n "$container_id" ]]; then
                local status_line
                status_line=$(docker ps --filter "id=$container_id" --format "{{.Names}} {{.Status}}")
                [[ -n "$status_line" ]] && ux_info "Status: $status_line"
            fi
            return 0
        else
            ux_warning "docker compose restart failed; attempting compose up -d."
            if docker compose "${compose_args[@]}" up -d --no-deps "$service"; then
                container_id=$(docker compose "${compose_args[@]}" ps -q "$service" 2>/dev/null | head -1)
                if [[ -n "$container_id" ]]; then
                    local status_line
                    status_line=$(docker ps --filter "id=$container_id" --format "{{.Names}} {{.Status}}")
                    [[ -n "$status_line" ]] && ux_info "Status: $status_line"
                fi
                return 0
            fi
            ux_error "Compose restart/up failed for service '$service'."
            return 1
        fi
    fi

    # Fallback: restart container directly
    if docker container inspect "$service" >/dev/null 2>&1; then
        ux_warning "Compose file not found (searched: ${unique_dirs[*]}). Falling back to docker restart."
        docker restart "$service" "$@"
        return $?
    fi

    ux_error "No compose file found (searched: ${unique_dirs[*]}) and container '$service' not found."
    return 1
}

# Filter dcl logs for errors
# Usage: dcl_errors <service_name_or_container>
dcl_errors() {
    local service="$1"
    if [ -z "$service" ]; then
        ux_usage "dcl_errors" "<service_name_or_container>" "Filter dcl logs for ERROR/WARN/INFO"
        return 1
    fi
    ux_info "Filtering logs for '$service' to show ERROR/WARN/INFO..."
    dcl "$service" | ux_filter_logs
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
# Now uses central UX library for consistent styling
dbash() {
    # UX library is already loaded globally in main.bash
    if [ -z "$1" ]; then
        ux_usage "dbash" "<container_name_or_id>" "Access container shell (tries bash, falls back to sh)"
        echo ""
        ux_section "Running Containers"
        docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null || ux_error "Docker is not running"
        echo ""
        return 1
    fi

    local container="$1"

    # Try bash first, fallback to sh
    if docker exec -it "$container" /bin/bash 2>/dev/null; then
        return 0
    elif docker exec -it "$container" /bin/sh 2>/dev/null; then
        return 0
    else
        ux_error "Cannot access shell for container '${container}'"
        ux_info "Make sure the container is running: ${UX_BOLD}docker ps${UX_RESET}"
        return 1
    fi
}

# 실행 중인 모든 컨테이너 정지
dstopall() {
    local ids
    ids=$(docker ps -q)
    if [ -z "$ids" ]; then
        ux_warning "실행 중인 컨테이너가 없습니다."
        return 0
    fi
    echo "${UX_BOLD}${UX_PRIMARY}[Docker]${UX_RESET} 모든 실행 중 컨테이너 정지:"
    echo "${UX_SUCCESS}$ids${UX_RESET}"
    docker stop "$ids"
}

# 중지된 컨테이너 일괄 삭제
drmall() {
    local ids
    ids=$(docker ps -aq)
    if [ -z "$ids" ]; then
        ux_warning "삭제할 컨테이너가 없습니다."
        return 0
    fi
    echo "${UX_BOLD}${UX_ERROR}[Docker]${UX_RESET} 모든 컨테이너 삭제:"
    echo "${UX_SUCCESS}$ids${UX_RESET}"
    docker rm "$ids"
}

# dangling(태그 없는) 이미지 삭제
drm_dangling() {
    local ids
    ids=$(docker images -f "dangling=true" -q)
    if [ -z "$ids" ]; then
        ux_warning "삭제할 dangling 이미지가 없습니다."
        return 0
    fi
    echo "${UX_BOLD}${UX_PRIMARY}[Docker]${UX_RESET} dangling 이미지 삭제:"
    echo "${UX_SUCCESS}$ids${UX_RESET}"
    docker rmi "$ids"
}

# Docker 시스템 기본 청소 (사용되지 않는 컨테이너/네트워크/이미지 등)
dprune() {
    ux_with_progress "Pruning Docker system" docker system prune -f
}

# Docker 강력 청소 (사용하지 않는 이미지/볼륨까지 전부 삭제) - 매우 주의!
dprune_full() {
    ux_header "Docker Full System Prune"
    ux_warning "주의: Docker 전체 강력 청소를 수행합니다."
    echo ""
    ux_section "삭제 대상"
    ux_bullet "중지된 컨테이너"
    ux_bullet "사용되지 않는 이미지(모든 태그)"
    ux_bullet "사용되지 않는 네트워크"
    ux_bullet "사용되지 않는 볼륨"
    echo ""
    ux_section "실행 명령어"
    ux_info "docker system prune -a --volumes -f"
    echo ""

    if ux_confirm "정말 실행하시겠습니까?" "n"; then
        echo "${UX_BOLD}${UX_PRIMARY}[Docker]${UX_RESET} docker system prune -a --volumes -f 실행..."
        docker system prune -a --volumes -f
        ux_success "Docker 강력 청소 완료"
    else
        ux_info "작업이 취소되었습니다."
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
        ux_warning "삭제할 dangling 볼륨이 없습니다."
        return 0
    fi
    echo "${UX_BOLD}${UX_PRIMARY}[Docker]${UX_RESET} dangling 볼륨 삭제:"
    echo "${UX_SUCCESS}$ids${UX_RESET}"
    docker volume rm "$ids"
    ux_success "dangling 볼륨 삭제 완료"
}

# 컨테이너 환경변수 확인 (정렬)
# 사용법: denv <container_name_or_id> (interactive if no args)
denv() {
    local container_name="$1"

    if [ -z "$container_name" ]; then
        # Show menu of running containers
        local containers
        mapfile -t containers < <(docker ps --format '{{.Names}}' 2>/dev/null)

        if [ ${#containers[@]} -eq 0 ]; then
            ux_warning "No running containers found."
            return 1
        fi

        local selection_idx
        selection_idx=$(ux_menu "Select container to inspect:" "${containers[@]}")

        if [ -z "$selection_idx" ]; then
            ux_info "Operation cancelled."
            return 0
        fi

        container_name="${containers[$selection_idx]}"
    fi

    if [ -z "$container_name" ]; then
        ux_error "No container selected."
        return 1
    fi

    ux_header "Environment Variables: $container_name"
    if docker exec "$container_name" env | sort; then
        ux_success "Successfully listed environment variables for $container_name."
    else
        ux_error "Failed to retrieve environment variables for $container_name."
        return 1
    fi
}

# docker inspect에서 Env 섹션 확인
# 사용법: dinspect_env <container_name_or_id>
dinspect_env() {
    if [ -z "$1" ]; then
        ux_usage "dinspect_env" "<container_name_or_id>" "docker inspect에서 Env 섹션 확인"
        return 1
    fi
    docker inspect "$1" | grep -A 50 '"Env":'
}

# 사용되지 않는 네트워크 정리
dnetwork_prune() {
    echo "${UX_BOLD}${UX_SUCCESS}🧹 Docker network prune -f 실행 중...${UX_RESET}"
    docker network prune -f
}

# 빌드 캐시 정리
dbuild_prune() {
    echo "${UX_BOLD}${UX_SUCCESS}🧹 Docker builder prune -f 실행 중...${UX_RESET}"
    docker builder prune -f
}

# 최근 N줄 로그만 보기 (기본 200줄)
# 사용법: dlog_last <container_name> [줄수]
dlog_last() {
    if [ -z "$1" ]; then
        ux_usage "dlog_last" "<container_name> [줄수]" "컨테이너 최근 N줄 로그 조회"
        return 1
    fi
    local container="$1"
    local lines="${2:-200}"
    echo "${UX_BOLD}${UX_WARNING}[Docker]${UX_RESET} $container (최근 $lines줄):"
    docker logs --tail "$lines" "$container"
}

# 모든 컨테이너를 tar 파일로 백업
dexport() {
    local backup_dir="$HOME/dotfiles/backup"
    local containers

    echo "${UX_BOLD}${UX_PRIMARY}[Docker]${UX_RESET} 백업 디렉토리 확인: ${UX_WARNING}$backup_dir${UX_RESET}"
    mkdir -p "$backup_dir"

    # 모든 컨테이너 이름 가져오기
    containers=$(docker ps -a --format "{{.Names}}")

    if [ -z "$containers" ]; then
        ux_warning "백업할 컨테이너가 없습니다."
        return 0
    fi

    echo "${UX_BOLD}${UX_PRIMARY}[Docker]${UX_RESET} 다음 컨테이너를 백업합니다:"
    echo "${UX_SUCCESS}$containers${UX_RESET}"
    echo "----------------------------------------"

    # 각 컨테이너 export
    for name in $containers; do
        echo "📦 Exporting ${UX_BOLD}$name${UX_RESET}..."
        if docker export "$name" >"$backup_dir/${name}.tar"; then
            echo "${UX_BOLD}${UX_SUCCESS}✅ $name → $backup_dir/${name}.tar 완료${UX_RESET}"
        else
            echo "${UX_BOLD}${UX_WARNING}❌ $name 백업 실패${UX_RESET}"
        fi
    done

    echo "----------------------------------------"
    echo "${UX_BOLD}${UX_SUCCESS}🎉 모든 백업 작업이 완료되었습니다.${UX_RESET}"
    ls -lh "$backup_dir"
}

# WSL Docker 설치 (대화형 스크립트)
dinstall() {
    bash "$HOME/dotfiles/mytool/install-docker.sh"
}

# WSL Docker 제거 (대화형 스크립트)
duninstall() {
    bash "$HOME/dotfiles/mytool/uninstall-docker.sh"
}

# Docker 서비스 자동 시작 설정 (대화형 스크립트)
denable() {
    bash "$HOME/dotfiles/mytool/enable-docker.sh"
}

# Docker 회사 프록시 설정 (대화형 스크립트)
dproxy_setup() {
    bash "$HOME/dotfiles/mytool/docker-configure-proxy.sh"
}

# Docker 회사 프록시 설정 도움말
dproxyhelp() {
    ux_header "Docker Corporate Proxy Setup Guide"

    ux_section "1. Config File Location"
    ux_info "/etc/systemd/system/docker.service.d/http-proxy.conf"
    echo ""

    ux_section "2. Check Current Config"
    ux_info "systemctl show --property=Environment docker"
    echo "  Output example:"
    echo "    Environment=HTTP_PROXY=http://... HTTPS_PROXY=http://... NO_PROXY=..."
    echo ""

    ux_section "3. View Config File"
    ux_info "cat /etc/systemd/system/docker.service.d/http-proxy.conf"
    echo ""

    ux_section "4. Edit Config"
    ux_info "sudo nano /etc/systemd/system/docker.service.d/http-proxy.conf"
    echo "  After edit:"
    echo "    ${UX_SUCCESS}sudo systemctl daemon-reload${UX_RESET}"
    echo "    ${UX_SUCCESS}sudo systemctl restart docker${UX_RESET}"
    echo ""

    ux_section "5. Remove Config"
    ux_info "sudo rm -f /etc/systemd/system/docker.service.d/http-proxy.conf"
    echo "  After remove:"
    echo "    ${UX_SUCCESS}sudo systemctl daemon-reload${UX_RESET}"
    echo "    ${UX_SUCCESS}sudo systemctl restart docker${UX_RESET}"
    echo ""

    ux_section "6. Test Connection"
    ux_info "docker pull alpine:latest"
    echo ""

    ux_section "7. Reset All (Danger)"
    ux_warning "sudo rm -rf /etc/systemd/system/docker.service.d/"
    echo "  ⚠️  This deletes all drop-in configs!"
    echo ""

    ux_divider
    echo ""
    ux_info "Quick Commands:"
    ux_bullet "${UX_SUCCESS}dproxy_setup${UX_RESET} : Interactive setup script"
    ux_bullet "${UX_SUCCESS}dproxyhelp${UX_RESET}   : Show this help"
    ux_bullet "${UX_SUCCESS}dproxy_show${UX_RESET}  : Show current proxy config"
    echo ""
}

# Docker Proxy 설정 확인
dproxy_show() {
    local proxy_conf="/etc/systemd/system/docker.service.d/http-proxy.conf"

    ux_header "Docker Proxy Configuration"

    if [ -f "$proxy_conf" ]; then
        ux_success "Proxy Config File Exists"
        echo ""
        ux_section "File Location"
        echo "  ${UX_WARNING}${proxy_conf}${UX_RESET}"
        echo ""
        ux_section "Content"
        sed 's/^/  /' <"$proxy_conf"
        echo ""
        ux_section "Current Docker Environment"
        systemctl show --property=Environment docker | sed 's/^/  /'
    else
        ux_warning "No Proxy Config File Found"
        echo ""
        ux_info "To set up proxy, run: ${UX_SUCCESS}dproxy_setup${UX_RESET}"
    fi
}

# -------------------------------
# Docker Helper
# -------------------------------
dockerhelp() {
    ux_header "Docker / Docker Compose Quick Commands"

    ux_section "Docker Compose Basics"
    ux_table_row "dc" "docker compose" "Base command"
    ux_table_row "dcu" "docker compose up" "Foreground start"
    ux_table_row "dcud" "docker compose up -d" "Detached start"
    ux_table_row "dcd" "docker compose down" "Stop & remove"
    ux_table_row "dcl" "logs <svc>" "Smart logs (service/container)"
    ux_table_row "dce" "exec <svc> <cmd>" "Execute command"
    echo ""

    ux_section "Docker Compose Extra"
    ux_table_row "dcps" "docker compose ps" "Status"
    ux_table_row "dcb" "docker compose build" "Build services"
    ux_table_row "dcr" "docker compose restart" "Restart services"
    ux_table_row "dcdv" "down -v" "Stop & remove volumes"
    ux_table_row "dcstop" "stop" "Stop containers"
    ux_table_row "dcstart" "start" "Start containers"
    echo ""

    ux_section "Docker Basics"
    ux_table_row "dps" "docker ps" "Running containers"
    ux_table_row "dpsa" "docker ps -a" "All containers"
    ux_table_row "di/dim" "docker images" "List images"
    ux_table_row "dstats" "docker stats" "Resource usage"
    ux_table_row "dstop" "docker stop" "Stop container"
    ux_table_row "drm" "docker rm" "Remove container"
    ux_table_row "drmi" "docker rmi" "Remove image"
    ux_table_row "dlogs" "docker logs -f" "Follow logs"
    ux_table_row "dinspect" "docker inspect" "Inspect object"
    echo ""

    ux_section "Resource Management"
    ux_table_row "ddf" "system df" "Disk usage"
    ux_table_row "dprune" "system prune -f" "Basic cleanup"
    ux_table_row "dprune_full" "full prune" "Deep cleanup (interactive)"
    ux_table_row "dvols" "volume ls -f dangling" "Dangling volumes"
    ux_table_row "dvol_rm" "volume rm" "Remove volume"
    ux_table_row "dnetwork_prune" "network prune" "Cleanup networks"
    ux_table_row "dbuild_prune" "builder prune" "Cleanup build cache"
    echo ""

    ux_section "Utilities"
    ux_table_row "dbash" "dbash <name>" "Shell access (bash/sh)"
    ux_table_row "denv" "denv <name>" "Show env vars"
    ux_table_row "dinspect_env" "inspect env" "Inspect env section"
    ux_table_row "dstopall" "Stop all" "Stop all running"
    ux_table_row "drmall" "Remove all" "Remove all containers"
    ux_table_row "dexport" "Export all" "Backup to tar files"
    ux_table_row "dinstall" "Install script" "Install Docker on WSL"
    ux_table_row "dproxy_setup" "Proxy setup" "Corporate proxy config"
    echo ""

    ux_info "Note: 'docker compose' (V2) is used by default."
    echo ""
}
