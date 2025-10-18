#!/usr/bin/env bash
# PostgreSQL service bootstrap & helpers
# file: ~/dotfiles/bash/app/postgresql.bash

# -------------------------------------------------
# Strict mode: 실행(run)일 때만 -euo 적용, source일 땐 pipefail만
# -------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -euo pipefail
else
    set -o pipefail
fi

: <<'POSTGRES_DOC'
==========================================================
PostgreSQL Dotfiles Helper - Getting Started Guide
==========================================================

1) 설치 (Ubuntu / WSL)
------------------------
sudo apt update
sudo apt install -y postgresql postgresql-contrib

1-추가) PostgreSQL 16 설치 (공식 APT 저장소 사용)
------------------------------------------------
※ Ubuntu 기본 저장소에는 PostgreSQL 16이 없을 수 있습니다.  
  PostgreSQL 공식 APT 저장소를 추가한 뒤 설치하세요.

# 1. PostgreSQL 공식 저장소 추가
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'

# 2. 최신 방식으로 GPG 키 추가
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg

# 3. 권한 설정
sudo chmod 644 /etc/apt/trusted.gpg.d/postgresql.gpg

# 4. 업데이트 (경고 없이 실행되어야 함)
sudo apt update

# 5. PostgreSQL 16 설치
sudo apt install postgresql-16

# 6. 설치 확인
pg_lsclusters

2) PostgreSQL 서비스 관리
------------------------
# 서비스 시작
sudo service postgresql start
# 서비스 상태 확인
sudo service postgresql status   # active (running) 확인

3) postgres 슈퍼유저로 DB/유저 생성
-----------------------------------
sudo -u postgres psql <<'SQL'
-- 앱 전용 유저/DB 생성 (개발 / 테스트)
CREATE ROLE dmc_user WITH LOGIN PASSWORD 'change_me_strong_pw';
CREATE DATABASE dmc_playground_dev OWNER dmc_user;
CREATE DATABASE dmc_playground_test OWNER dmc_user;
CREATE DATABASE dmc_playground_prod OWNER dmc_user;

-- 권한 부여
GRANT ALL PRIVILEGES ON DATABASE dmc_playground_dev TO dmc_user;
GRANT ALL PRIVILEGES ON DATABASE dmc_playground_test TO dmc_user;
GRANT ALL PRIVILEGES ON DATABASE dmc_playground_prod TO dmc_user;
SQL

4) 접속 테스트
---------------
psql "host=localhost dbname=dmc_playground user=dmc_user password=change_me_strong_pw" -c "\l"
psql "host=localhost dbname=dmc_playground_test user=dmc_user password=change_me_strong_pw" -c "\l"
psql "host=localhost dbname=dmc_playground_prod user=dmc_user password=change_me_strong_pw" -c "\l"

5) Dotfiles PostgreSQL Helper Functions
----------------------------------------
# 서비스 기반 psql 접속
psql_<service>   # 예: psql_dmc_dev, psql_dmc_test, psql_dmc_prod

# 등록된 서비스와 URI 확인
psql_list [true] 
#   true 옵션: 서비스 목록만 간결하게 출력
#   false/없음: full URI 정보와 alias 포함

# psql 명령어 직접 실행
psql_cmd <service> <command>
# 예: psql_cmd dmc_dev \du
#      psql_cmd dmc_test "\dt"

# PostgreSQL 서버 제어
psql_server <start|stop|restart|reload|status>
# 예: psql_server start
#      psql_server status

==========================================================
POSTGRES_DOC

# -------------------------------
# 0) Locale 설정 (WSL/Ubuntu Perl warning 제거용)
# -------------------------------
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# -------------------------------
# 1) 서비스 정의: "서비스명 DB명 사용자 비밀번호"
# -------------------------------
services=(
    "dmc_dev  dmc_playground_dev  dmc_user  change_me_strong_pw"
    "dmc_test dmc_playground_test dmc_user  change_me_strong_pw"
    "dmc_prod dmc_playground_prod dmc_user  change_me_strong_pw"
)

PGSERVICE_FILE="$HOME/.pg_service.conf"

DEFAULT_HOST="localhost"
DEFAULT_PORT="5432"

# -------------------------------
# 2) 기존 파일 초기화
# -------------------------------
rm -f "$PGSERVICE_FILE"
touch "$PGSERVICE_FILE"
chmod 600 "$PGSERVICE_FILE"

# -------------------------------
# 3) 기존 psql_* function 삭제
# -------------------------------
while IFS= read -r name; do
    if [[ -n "${name}" ]]; then
        unset -f "${name}" 2>/dev/null
    fi
done < <(declare -F | awk '{print $3}' | grep '^psql_')

# -------------------------------
# 4) 서비스 배열 기반 설정/alias 생성
# -------------------------------
for entry in "${services[@]}"; do
    # shellcheck disable=SC2086
    read -r service_name db_name db_user db_pass <<<"$entry"

    # ~/.pg_service.conf 에 서비스 섹션 작성
    {
        echo "[$service_name]"
        echo "host=$DEFAULT_HOST"
        echo "port=$DEFAULT_PORT"
        echo "dbname=$db_name"
        echo "user=$db_user"
        echo "password=$db_pass"
        echo
    } >>"$PGSERVICE_FILE"

    # alias 등록
    # _create_psql_service_function "$service_name"
    # alias "psql_${service_name}=PGSERVICE=\"$service_name\" psql"
done

# Helper function to create dynamic psql service functions
_create_psql_service_function() {
    local service_name="$1"
    local func_name="psql_${service_name}"
    # Define the function dynamically using 'function' keyword for better compatibility
    eval "function ${func_name} { PGSERVICE=\"${service_name}\" psql \"\$@\"; }"
}

# -------------------------------
# 4) 서비스 배열 기반 설정/alias 생성
# -------------------------------
for entry in "${services[@]}"; do
    # shellcheck disable=SC2086
    read -r service_name db_name db_user db_pass <<<"$entry"

    # ~/.pg_service.conf 에 서비스 섹션 작성
    {
        echo "[$service_name]"
        echo "host=$DEFAULT_HOST"
        echo "port=$DEFAULT_PORT"
        echo "dbname=$db_name"
        echo "user=$db_user"
        echo "password=$db_pass"
        echo
    } >>"$PGSERVICE_FILE"

    # Create function instead of alias
    _create_psql_service_function "$service_name"
done

# -------------------------------
# 5) PostgreSQL alias list
# -------------------------------
psql_list() {
    local service_only="${1:-false}"
    if [[ "$service_only" == "true" ]]; then
        for entry in "${services[@]}"; do
            read -r service_name _ <<<"$entry"
            echo "psql_${service_name}=PGSERVICE=${service_name} psql"
        done
    else
        echo "Registered PostgreSQL aliases (current shell):"
        for entry in "${services[@]}"; do
            read -r service_name db_name db_user db_pass <<<"$entry"
            echo "psql_${service_name}=psql \"$service_name\" | URI: postgresql://$db_user:$db_pass@$DEFAULT_HOST:$DEFAULT_PORT/$db_name"
        done
    fi
}

# -------------------------------
# 6) PostgreSQL command helper
# -------------------------------
# 가독성 향상 버전: psqlhelp
psqlhelp() {
    # ---------- 색/스타일 ----------
    local _nocolor=false
    if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
        if [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
            BOLD=$(tput bold)
            DIM=$(tput dim)
            RESET=$(tput sgr0)
            FG_CYAN=$(tput setaf 6)
            FG_GREEN=$(tput setaf 2)
            FG_YELLOW=$(tput setaf 3)
            FG_BLUE=$(tput setaf 4)
            FG_MAGENTA=$(tput setaf 5)
            FG_RED=$(tput setaf 1)
        else _nocolor=true; fi
    else _nocolor=true; fi
    if $_nocolor; then
        BOLD=""
        DIM=""
        RESET=""
        FG_CYAN=""
        FG_GREEN=""
        FG_YELLOW=""
        # shellcheck disable=SC2034
        FG_BLUE=""
        # shellcheck disable=SC2034
        FG_MAGENTA=""
        # shellcheck disable=SC2034
        FG_RED=""
    fi

    # ---------- 인자/축약어 사전 ----------
    local service="${1:-}"
    shift || true
    local cmd="${*:-}"

    # 축약어 사전 (우측은 실제 \명령)
    declare -A cmd_map=(
        ["du"]="du" # list roles
        ["l"]="l"   # list databases
        ["dt"]="dt" # list tables
        ["d"]="d"   # describe table
        ["q"]="q"   # quit
        ["x"]="x"   # toggle expanded output
    )
    # 축약어 설명(출력용)
    declare -A cmd_desc=(
        ["du"]="list roles"
        ["l"]="list databases"
        ["dt"]="list tables"
        ["d"]="describe table"
        ["q"]="quit"
        ["x"]="toggle expanded output"
    )

    # ---------- 도움말/리스트 출력 유틸 ----------
    _print_header() {
        local title="$1"
        printf "%s%s%s\n" "$BOLD$FG_CYAN" "$title" "$RESET"
    }
    _print_usage() {
        _print_header "Usage"
        cat <<USAGE
  ${BOLD}psqlhelp${RESET} ${FG_YELLOW}<service>${RESET} ${FG_GREEN}<command>${RESET}

${BOLD}Examples${RESET}
  psqlhelp dmc_dev ${FG_GREEN}\l${RESET}
  psqlhelp dmc_prod ${FG_GREEN}\l${RESET}
  psqlhelp dmc_test ${FG_GREEN}dt${RESET}      ${DIM}(shortcut → \\dt)${RESET}
USAGE
        echo
    }
    _print_shortcuts() {
        _print_header "Shortcuts"
        # 이름 정렬 폭
        local k
        for k in du l dt d x q; do
            printf "  %-3s %s→%s \\%-2s %s\n" \
                "$BOLD$k$RESET" "$DIM" "$RESET" "${cmd_map[$k]}" "${cmd_desc[$k]}"
        done
        echo
    }
    _print_services_table() {
        _print_header "Available services (current shell)"
        # 표 헤더
        printf "%s\n" "${DIM}┌──────────────────────┬──────────────────────────────┬─────────────────────┬──────────────┐${RESET}"
        printf "%s %-20s %s %-28s %s %-19s %s %-12s %s\n" \
            "│" "SERVICE" "│" "ALIAS" "│" "DB" "│" "USER" "│"
        printf "%s\n" "${DIM}├──────────────────────┼──────────────────────────────┼─────────────────────┼──────────────┤${RESET}"

        # services 배열 필요 (형식: "service db user pass")
        local entry svc db user alias_name
        for entry in "${services[@]}"; do
            # shellcheck disable=SC2086
            read -r svc db user _ <<<"$entry"
            alias_name="psql_${svc}"
            printf "│ %-20s │ %-28s │ %-19s │ %-12s │\n" \
                "$svc" "$alias_name" "$db" "$user"
        done
        printf "%s\n" "${DIM}└──────────────────────┴──────────────────────────────┴─────────────────────┴──────────────┘${RESET}"
        echo
        printf "Run with:  %spsql_${DIM}<service>%s%s\n" "$BOLD" "$RESET" "  or  psqlhelp <service> <command>"
        echo
    }

    # ---------- 인자 없을 때: 도움말 모드 ----------
    if [[ -z "$service" || -z "$cmd" ]]; then
        _print_usage
        _print_shortcuts
        _print_services_table
        return 1
    fi

    # ---------- 축약어 자동 매핑 ----------
    if [[ -n "${cmd_map[$cmd]:-}" && "${cmd:0:1}" != "\\" ]]; then
        cmd="\\${cmd_map[$cmd]}"
    fi

    # ---------- 실행 표시 ----------
    printf "%s→%s Using service %s%s%s, executing %s%s%s\n" \
        "$DIM" "$RESET" "$BOLD$FG_MAGENTA" "$service" "$RESET" "$BOLD$FG_GREEN" "$cmd" "$RESET"

    # ---------- 실제 실행 ----------
    PGSERVICE="$service" psql <<EOF
$cmd
EOF
}

# -------------------------------
# 7) PostgreSQL server 관리 함수
# -------------------------------
psql_server() {
    declare -A cmd_list=(
        ["start"]="start the PostgreSQL service"
        ["stop"]="stop the PostgreSQL service"
        ["restart"]="restart the PostgreSQL service"
        ["status"]="show PostgreSQL service status"
        ["reload"]="reload PostgreSQL configuration"
    )

    local action="${1:-}"
    if [[ -z "$action" ]]; then
        echo "Usage: psql_server <${!cmd_list[*]}>"
        return 1
    fi

    if [[ -n "${cmd_list[$action]:-}" ]]; then
        if command -v systemctl >/dev/null 2>&1; then
            echo "[Info] sudo systemctl $action postgresql"
            sudo systemctl "$action" postgresql
        else
            echo "[Info] sudo service postgresql $action"
            sudo service postgresql "$action"
        fi
    else
        echo "[Error] Unknown action: $action"
        return 1
    fi
}

# -------------------------------
# 8) WSL2 안내
# -------------------------------
# if grep -qEi "(Microsoft|WSL)" /proc/version &>/dev/null; then
#     echo ""
#     echo " [Info] WSL detected. Use 'sudo service postgresql start' instead of systemctl if needed."
# fi


# -------------------------------
# 9) Create DB quickly from services[] (psql_create <DB_NAME>)
# Example)
# 9.1) dmc_playground_prod 생성/하드닝 (services에 이미 정의돼 있으므로 비번 프롬프트 없이 진행)
#   psql_create dmc_playground_prod
# 9.2) services에 없는 DB를 만들 때 (비번 입력 프롬프트가 뜸)
#   psql_create my_new_db
# -------------------------------
psql_create() {
    local DB_NAME="${1:-}"
    if [[ -z "$DB_NAME" ]]; then
        echo "Usage: psql_create <DB_NAME>"
        return 1
    fi

    # 9-1) services 배열에서 DB_NAME 매칭하여 app_user/app_pass 추출
    local APP_USER="" APP_PASS="" SERVICE_HIT=""
    for entry in "${services[@]}"; do
        # shellcheck disable=SC2086
        read -r svc db user pass <<<"$entry"
        if [[ "$db" == "$DB_NAME" ]]; then
            APP_USER="$user"
            APP_PASS="$pass"
            SERVICE_HIT="$svc"
            break
        fi
    done
    # 매칭 실패 시 기본값/프롬프트
    if [[ -z "$APP_USER" ]]; then
        APP_USER="dmc_user"
        read -r -s -p "Enter password for role '$APP_USER': " APP_PASS; echo
    fi

    # 9-2) admin psql 커맨드 선택 (sudo 우선, 실패 시 로컬 postgres 계정)
    local ADMIN_PSQL=("sudo" "-u" "postgres" "psql" "-v" "ON_ERROR_STOP=1" "-X" "-q")
    if ! printf "\\q\\n" | "${ADMIN_PSQL[@]}" >/dev/null 2>&1; then
        ADMIN_PSQL=("psql" "-h" "${DEFAULT_HOST:-localhost}" "-p" "${DEFAULT_PORT:-5432}" "-U" "postgres" "-v" "ON_ERROR_STOP=1" "-X" "-q")
        if ! printf "\\q\\n" | "${ADMIN_PSQL[@]}" >/dev/null 2>&1; then
            echo "[Error] Can't connect as postgres (sudo or local). Set up access and retry."
            return 1
        fi
    fi

    # 9-3) 도우미: admin 쿼리 실행
    _admin_sql() { "${ADMIN_PSQL[@]}" -d "${2:-postgres}" -c "$1"; }

    # 9-4) 역할 생성/비번 설정 (존재하면 비번만 보정)
    local ROLE_EXISTS
    ROLE_EXISTS=$("${ADMIN_PSQL[@]}" -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='${APP_USER}'" || true)
    if [[ "$ROLE_EXISTS" != "1" ]]; then
        echo "==> Creating role '${APP_USER}'..."
        _admin_sql "CREATE ROLE ${APP_USER} LOGIN PASSWORD \$\$${APP_PASS}\$\$;"
    else
        echo "==> Role '${APP_USER}' exists. Ensuring password..."
        _admin_sql "ALTER ROLE ${APP_USER} WITH LOGIN PASSWORD \$\$${APP_PASS}\$\$;"
    fi

    # 9-5) DB 생성 (없으면)
    local DB_EXISTS
    DB_EXISTS=$("${ADMIN_PSQL[@]}" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" || true)
    if [[ "$DB_EXISTS" != "1" ]]; then
        echo "==> Creating database '${DB_NAME}' owned by '${APP_USER}'..."
        _admin_sql "CREATE DATABASE ${DB_NAME} OWNER ${APP_USER} TEMPLATE template0 ENCODING 'UTF8';"
    else
        echo "==> Database '${DB_NAME}' already exists. Skipping create."
    fi

    # 9-6) 최소 하드닝 & 권한
    echo "==> Hardening connect privileges..."
    _admin_sql "REVOKE CONNECT ON DATABASE ${DB_NAME} FROM PUBLIC;"
    _admin_sql "GRANT  CONNECT ON DATABASE ${DB_NAME} TO ${APP_USER};"

    echo "==> Schema ownership & privileges..."
    _admin_sql "ALTER SCHEMA public OWNER TO ${APP_USER};" "${DB_NAME}"
    _admin_sql "REVOKE CREATE ON SCHEMA public FROM PUBLIC;" "${DB_NAME}"
    _admin_sql "GRANT USAGE, CREATE ON SCHEMA public TO ${APP_USER};" "${DB_NAME}"

    # 9-7) 요약/연동 안내
    echo "==> Done. Created/validated '${DB_NAME}' for user '${APP_USER}'."
    if [[ -n "$SERVICE_HIT" ]]; then
        echo "    Tip: psqlhelp ${SERVICE_HIT} \\l"
        echo "         psql_${SERVICE_HIT} -c '\\dt'"
    else
        echo "    (No service matched this DB in services[]. Consider adding one for convenience.)"
    fi
}
