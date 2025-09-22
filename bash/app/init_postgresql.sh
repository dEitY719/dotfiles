#!/usr/bin/env bash
# file: ~/dotfiles/bash/app/init_postgresql.sh
# Purpose: WSL/Ubuntu 환경에서 PostgreSQL 설치 및 초기 DB/유저 설정 (1회 실행)

set -e

echo "[Info] Installing PostgreSQL..."
sudo apt update
sudo apt install -y postgresql postgresql-contrib

echo "[Info] Starting PostgreSQL service..."
sudo service postgresql start
sudo service postgresql status

# locale warning 방지
echo "[Info] Setting locale..."
sudo locale-gen en_US.UTF-8
sudo update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

echo "[Info] Creating default DB and user..."
sudo -u postgres psql <<'SQL'
CREATE ROLE dmc_user WITH LOGIN PASSWORD 'change_me_strong_pw';
CREATE DATABASE dmc_playground_dev OWNER dmc_user;
CREATE DATABASE dmc_playground_test OWNER dmc_user;
GRANT ALL PRIVILEGES ON DATABASE dmc_playground_dev TO dmc_user;
GRANT ALL PRIVILEGES ON DATABASE dmc_playground_test TO dmc_user;
SQL

echo "[Info] Initialization complete."
echo "You can now use the dotfiles helper script: postgresql.bash"
