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
    service_name=$(echo_
