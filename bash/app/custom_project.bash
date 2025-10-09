#!/bin/bash
# /bash/app/custom_project.bash

#======================================
# dotfiles
#       ✨ https://github.com/dEitY719/dotfiles.git
#======================================
# myh
# cd_dot

#======================================
# FinRx
#       💰 https://github.com/dEitY719/FinRx.git
#======================================
alias run_fr_cli='python ./src/ticker_library/cli/cli.py'

#======================================
# dmc-playground
#       📚 https://github.com/dEitY719/dmc-playground.git
#======================================
alias run_bes="uv run uvicorn src.backend.main:app --reload --host 127.0.0.1 --port 8000"
alias run_tbes='PYTEST_CURRENT_TEST=1 uv run uvicorn src.backend.main:app --reload --host 127.0.0.1 --port 8001'
alias run_api_cli="python src/backend/api_cli.py"
alias run_db_cli="python src/database/db_cli.py"

clihelp() {
    cat <<-'EOF'

[Custom Project CLI Help]

# Repos
  • dotfiles      ✨ https://github.com/dEitY719/dotfiles.git
  • FinRx         💰 https://github.com/dEitY719/FinRx.git
  • dmc-playground📚 https://github.com/dEitY719/dmc-playground.git

# Aliases / Commands

  [FinRx]
    run_fr_cli     : python ./src/ticker_library/cli/cli.py

  [dmc-playground]
    run_bes        : uv run uvicorn src.backend.main:app --reload --host 127.0.0.1 --port 8000
    run_tbes       : PYTEST_CURRENT_TEST=1 uv run uvicorn src.backend.main:app --reload --host 127.0.0.1 --port 8001
    run_api_cli    : python src/backend/api_cli.py
    run_db_cli     : python src/database/db_cli.py

# Recipes

  # 백엔드 개발 서버 실행 (FastAPI + Uvicorn, hot reload)
  run_bes

  # API 유틸리티 CLI 사용
  run_api_cli --help

  # DB 유틸리티 CLI 사용
  run_db_cli --help

  # FinRx 티커 CLI 사용
  run_fr_cli --help


Tip)
  - 프로젝트 루트에서 실행하는 걸 가정합니다.
  - 가상환경은 uv/pyproject 기반을 권장합니다 (필요 시: uvs / uvd).

EOF
}
