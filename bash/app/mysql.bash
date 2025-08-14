#!/usr/bin/env bash
# file: ~/dotfiles/bash/app/mysql.bash

: <<'MYSQL_DOC'
==========================================================
MySQL Dotfiles Helper - Getting Started Guide
==========================================================

1) 설치 (Ubuntu / WSL)
------------------------
sudo apt update
sudo apt install -y mysql-server mysql-client

2) MySQL 서비스 관리
------------------------
# 서비스 시작
sudo service mysql start
# 서비스 상태 확인
sudo service mysql status   # active (running) 확인

3) root 계정 비밀번호 설정 및 유저/DB 생성
-----------------------------------
# root 패스워드 변경 (MySQL 8.x 기준)
sudo mysql -u root <<'SQL'
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'change_me_root_pw';
FLUSH PRIVILEGES;
SQL

# 앱 전용 유저/DB 생성 (개발 / 테스트)
mysql -u root -pchange_me_root_pw <<'SQL'
CREATE USER 'dmc_user'@'localhost' IDENTIFIED BY 'change_me_strong_pw';
CREATE DATABASE dmc_playground_dev;
CREATE DATABASE dmc_playground_test;
GRANT ALL PRIVILEGES ON dmc_playground_dev.* TO 'dmc_user'@'localhost';
GRANT ALL PRIVILEGES ON dmc_playground_test.* TO 'dmc_user'@'localhost';
FLUSH PRIVILEGES;
SQL

4) 접속 테스트
---------------
mysql -u dmc_user -pchange_me_strong_pw -D dmc_playground_test -e "SHOW DATABASES;"

5) Dotfiles MySQL Helper Functions
----------------------------------------
# 서비스 기반 mysql 접속
mysql_<service>   # 예: mysql_dmc_dev, mysql_dmc_test

# 등록된 서비스와 URI 확인
mysql_list [true] 
#   true 옵션: 서비스 목록만 간결하게 출력
#   false/없음: full URI 정보와 alias 포함

# mysql 명령어 직접 실행
mysql_cmd <service> <command>
# 예: mysql_cmd dmc_dev "SHOW TABLES;"
#      mysql_cmd dmc_test "DESCRIBE mytable;"

# MySQL 서버 제어
mysql_server <start|stop|restart|reload|status>
# 예: mysql_server start
#      mysql_server status

==========================================================
MYSQL_DOC

# -------------------------------
# Service list (format: service db user pass)
# -------------------------------
services=(
    "dmc_dev dmc_playground_dev dmc_user change_me_strong_pw"
    "dmc_test dmc_playground_test dmc_user change_me_strong_pw"
)

MYSQL_CNF_FILE="$HOME/.my.cnf"

# -------------------------------
# 0) 기존 파일 삭제 후 새로 생성
# -------------------------------
rm -f "$MYSQL_CNF_FILE"
touch "$MYSQL_CNF_FILE"
chmod 600 "$MYSQL_CNF_FILE"

# -------------------------------
# 1) 기존 mysql_* alias 삭제
# -------------------------------
for a in $(alias | grep -oP "^mysql_\w+" 2>/dev/null); do
    unalias "$a" 2>/dev/null
done

# -------------------------------
# 2) 서비스 배열 기반으로 파일/alias 업데이트
# -------------------------------
for entry in "${services[@]}"; do
    service_name=$(echo "$entry" | awk '{print $1}')
    db_name=$(echo "$entry" | awk '{print $2}')
    db_user=$(echo "$entry" | awk '{print $3}')
    db_pass=$(echo "$entry" | awk '{print $4}')

    cat >>"$MYSQL_CNF_FILE" <<EOF

[client_$service_name]
user=$db_user
password=$db_pass
host=localhost
database=$db_name
EOF

    alias_name="mysql_$service_name"
    alias "$alias_name"="mysql --defaults-group-suffix=_$service_name"
done

# -------------------------------
# 3) MySQL alias list
# -------------------------------
mysql_list() {
    local service_only="$1"
    if [[ "$service_only" == "true" ]]; then
        printf "%-15s  %-20s\n" "Service Name" "Alias"
        printf "%-15s  %-20s\n" "------------" "--------------------"
        for entry in "${services[@]}"; do
            service_name=$(echo "$entry" | awk '{print $1}')
            alias_name="mysql_${service_name}"
            printf "%-15s  %-20s\n" "$service_name" "$alias_name"
        done
    else
        printf "%-15s  %-20s  %s\n" "Service Name" "Alias" "Connection Info"
        printf "%-15s  %-20s  %s\n" "------------" "--------------------" "----------------------------------------------"
        for entry in "${services[@]}"; do
            service_name=$(echo "$entry" | awk '{print $1}')
            db_name=$(echo "$entry" | awk '{print $2}')
            db_user=$(echo "$entry" | awk '{print $3}')
            db_pass=$(echo "$entry" | awk '{print $4}')
            alias_name="mysql_${service_name}"
            printf "%-15s  %-20s  mysql://%s:%s@localhost:3306/%s\n" \
                "$service_name" "$alias_name" "$db_user" "$db_pass" "$db_name"
        done
    fi
}

# -------------------------------
# 4) MySQL command helper
# -------------------------------
mysql_cmd() {
    local service="$1"
    shift
    local user_input_cmd="$1"
    shift || true
    local rest_args="$*"

    declare -A cmd_templates=(
        ["databases"]="SHOW DATABASES;"
        ["tables"]="SHOW TABLES;"
        ["version"]="SELECT VERSION();"
        ["describe"]="DESCRIBE {arg};"
        ["status"]="SHOW GLOBAL STATUS LIKE 'Threads_connected';"
        ["uptime"]="SHOW GLOBAL STATUS LIKE 'Uptime';"
        ["processlist"]="SHOW FULL PROCESSLIST;"
        ["engines"]="SHOW ENGINES;"
        ["variables"]="SHOW VARIABLES LIKE '{arg}%';"
    )

    if [[ -z "$service" || -z "$user_input_cmd" ]]; then
        echo "Usage: mysql_cmd <service> '<command>'"
        echo "Example commands:"
        for k in "${!cmd_templates[@]}"; do
            if [[ "${cmd_templates[$k]}" == *"{arg}"* ]]; then
                printf "  %-12s -> %s (requires argument)\n" "$k" "${cmd_templates[$k]}"
            else
                printf "  %-12s -> %s\n" "$k" "${cmd_templates[$k]}"
            fi
        done
        echo
        echo "Available services:"
        mysql_list true
        return 1
    fi

    local found=false
    for entry in "${services[@]}"; do
        s=$(echo "$entry" | awk '{print $1}')
        if [[ "$s" == "$service" ]]; then
            found=true
            break
        fi
    done
    if [[ "$found" == "false" ]]; then
        echo "[Error] Unknown service: $service"
        mysql_list true
        return 1
    fi

    local sql=""
    if [[ -n "${cmd_templates[$user_input_cmd]+_}" ]]; then
        local template="${cmd_templates[$user_input_cmd]}"
        if [[ "$template" == *"{arg}"* ]]; then
            if [[ -z "$rest_args" ]]; then
                echo "[Error] '$user_input_cmd' requires an argument."
                echo "Usage: mysql_cmd $service $user_input_cmd <arg>"
                return 1
            fi
            sql="${template//\{arg\}/$rest_args}"
        else
            sql="$template"
        fi
    else
        sql="$user_input_cmd"
        [[ -n "$rest_args" ]] && sql+=" $rest_args"
        [[ "$sql" != *";" ]] && sql+=";"
    fi

    if [[ "$user_input_cmd" == "describe" ]]; then
        local output
        output=$(mysql --defaults-group-suffix="_$service" -N -s -e "$sql")
        if [[ -z "$output" ]]; then
            echo "[Notice] Table '$rest_args' does not exist or has no columns."
            return 1
        fi
        echo "$output"
    else
        mysql --defaults-group-suffix="_$service" -e "$sql"
    fi
}

# --------------------------------------
# MySQL server 관리 함수
# --------------------------------------
mysql_server() {
    declare -A cmd_list=(
        ["start"]="start the MySQL service"
        ["stop"]="stop the MySQL service"
        ["restart"]="restart the MySQL service"
        ["status"]="show MySQL service status"
        ["reload"]="reload MySQL configuration"
    )

    local usage_str
    usage_str=$(
        IFS='|'
        echo "${!cmd_list[*]}"
    )

    local action="$1"

    if [[ -z "$action" ]]; then
        echo "Usage: mysql_server <${usage_str}>"
        echo "Commands:"
        for cmd in "${!cmd_list[@]}"; do
            printf "  %-7s -> %s\n" "$cmd" "${cmd_list[$cmd]}"
        done
        return 1
    fi

    if [[ -n "${cmd_list[$action]}" ]]; then
        echo "[Info] Running: sudo service mysql $action"
        sudo service mysql "$action"
    else
        echo "[Error] Unknown action: $action"
        echo "Usage: mysql_server <${usage_str}>"
        return 1
    fi
}
