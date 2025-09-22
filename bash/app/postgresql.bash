#!/usr/bin/env bash
# file: ~/dotfiles/bash/app/postgresql.bash

: <<'POSTGRES_DOC'
==========================================================
PostgreSQL Dotfiles Helper - Getting Started Guide
==========================================================

1) 설치 (Ubuntu / WSL)
------------------------
sudo apt update
sudo apt install -y postgresql postgresql-contrib

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

-- 권한 부여
GRANT ALL PRIVILEGES ON DATABASE dmc_playground_dev TO dmc_user;
GRANT ALL PRIVILEGES ON DATABASE dmc_playground_test TO dmc_user;
SQL

4) 접속 테스트
---------------
psql "host=localhost dbname=dmc_playground_test user=dmc_user password=change_me_strong_pw" -c "\l"

5) Dotfiles PostgreSQL Helper Functions
----------------------------------------
# 서비스 기반 psql 접속
psql_<service>   # 예: psql_dmc_dev, psql_dmc_test

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
# 1) 서비스 정의
# -------------------------------
services=(
    "dmc_dev dmc_playground_dev dmc_user change_me_strong_pw"
    "dmc_test dmc_playground_test dmc_user change_me_strong_pw"
)

PGSERVICE_FILE="$HOME/.pg_service.conf"
PGPASS_FILE="$HOME/.pgpass"

# -------------------------------
# 2) 기존 파일 삭제 후 새로 생성
# -------------------------------
rm -f "$PGSERVICE_FILE" "$PGPASS_FILE"
touch "$PGSERVICE_FILE" "$PGPASS_FILE"
chmod 600 "$PGSERVICE_FILE" "$PGPASS_FILE"

# -------------------------------
# 3) 기존 psql_* alias 삭제
# -------------------------------
for a in $(alias | grep -oP "^psql_\w+" 2>/dev/null); do
    unalias "$a" 2>/dev/null
done

# -------------------------------
# 4) 서비스 배열 기반으로 파일/alias 업데이트
# -------------------------------
for entry in "${services[@]}"; do
    service_name=$(echo "$entry" | awk '{print $1}')
    db_name=$(echo "$entry" | awk '{print $2}')
    db_user=$(echo "$entry" | awk '{print $3}')
    db_pass=$(echo "$entry" | awk '{print $4}')

    # ~/.pg_service.conf
    cat >>"$PGSERVICE_FILE" <<EOF

[$service_name]
host=localhost
port=5432
user=$db_user
dbname=$db_name
EOF

    # ~/.pgpass
    echo "localhost:5432:$db_name:$db_user:$db_pass" >>"$PGPASS_FILE"

    # alias 등록
    alias_name="psql_$service_name"
    alias "$alias_name"="psql \"\$service_name\""
done

# -------------------------------
# 5) PostgreSQL alias list
# -------------------------------
psql_list() {
    local service_only="$1"
    if [[ "$service_only" == "true" ]]; then
        for entry in "${services[@]}"; do
            service_name=$(echo "$entry" | awk '{print $1}')
            echo "psql_$service_name=psql \"$service_name\""
        done
    else
        echo "Registered PostgreSQL aliases with full command:"
        for entry in "${services[@]}"; do
            service_name=$(echo "$entry" | awk '{print $1}')
            db_name=$(echo "$entry" | awk '{print $2}')
            db_user=$(echo "$entry" | awk '{print $3}')
            db_pass=$(echo "$entry" | awk '{print $4}')
            echo "psql_$service_name=psql \"$service_name\" | URI: postgresql://$db_user:$db_pass@localhost:5432/$db_name"
        done
    fi
}

# -------------------------------
# 6) PostgreSQL command helper
# -------------------------------
psql_cmd() {
    local service="$1"
    shift
    local cmd="$*"

    declare -A cmd_list=(
        ["du"]="list roles"
        ["l"]="list databases"
        ["dt"]="list tables"
        ["d"]="describe table"
        ["q"]="quit"
        ["x"]="toggle expanded output"
    )

    if [[ -z "$service" || -z "$cmd" ]]; then
        echo "Usage: psql_cmd <service> '<command>'"
        echo "Example commands:"
        for key in "${!cmd_list[@]}"; do
            echo "  \\$key -> ${cmd_list[$key]}"
        done
        echo
        echo "Available services:"
        psql_list true
        return 1
    fi

    # 자동으로 \ 접두사 추가
    if [[ -n "${cmd_list[$cmd]}" ]]; then
        cmd="\\$cmd"
    fi

    # Here-doc 방식으로 안전하게 실행
    psql "service=$service" <<EOF
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

    local usage_str
    usage_str=$(IFS='|'; echo "${!cmd_list[*]}")
    local action="$1"

    if [[ -z "$action" ]]; then
        echo "Usage: psql_server <${usage_str}>"
        echo "Commands:"
        for cmd in "${!cmd_list[@]}"; do
            printf "  %-7s -> %s\n" "$cmd" "${cmd_list[$cmd]}"
        done
        return 1
    fi

    if [[ -n "${cmd_list[$action]}" ]]; then
        echo "[Info] Running: sudo service postgresql $action"
        sudo service postgresql "$action"
    else
        echo "[Error] Unknown action: $action"
        echo "Usage: psql_server <${usage_str}>"
        return 1
    fi
}

# -------------------------------
# 8) WSL2 / systemd 안내 (필요시)
# -------------------------------
if grep -qEi "(Microsoft|WSL)" /proc/version &>/dev/null; then
    echo "[Info] WSL detected. Use 'sudo service postgresql start' instead of systemctl if needed."
fi
