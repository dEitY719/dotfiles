#!/bin/bash

# Python Package Management
# alias pp_freeze: pyproject.toml에서 프로젝트 이름을 읽어와 pip freeze 목록에서 제외하고, -e .을 추가하여 requirements.txt를 생성하는 명령어입니다.
# 1. PROJECT_NAME=$(...): pyproject.toml에서 'name = "프로젝트명"' 부분을 찾아 프로젝트 이름만 추출하여 PROJECT_NAME 변수에 저장합니다.
# 2. pip freeze | grep -v "$PROJECT_NAME": 설치된 패키지 목록(pip freeze)에서 현재 프로젝트 이름($PROJECT_NAME)을 제외합니다.
# 3. > requirements.txt: 필터링된 패키지 목록을 requirements.txt 파일에 새로 작성합니다.
# 4. && echo "-e ." >> requirements.txt: 앞의 명령어가 성공적으로 실행되면, '-e .'를 requirements.txt 파일의 마지막 줄에 추가합니다.
alias pp_freeze='PROJECT_NAME=$(grep "name =" pyproject.toml | cut -d "\"" -f 2) && pip freeze | grep -v "$PROJECT_NAME" > requirements.txt && echo "-e ." >> requirements.txt'

alias pp_install='pip install'                                 # 일반 패키지 설치
alias pp_install_up='pip install --upgrade pip && pip install' # pip 업그레이드 후 설치
alias pp_reqs='pip install -r requirements.txt'
alias pp_list='pip list --outdated --format=columns'
alias pp_check='pip check'
alias pp_uninstall='pip uninstall -y'

# Python Code Quality & Formatting
alias code_check='ruff format . --check && ruff check .' # 포맷팅 및 린트 위반 사항 확인 (CI용)
alias code_fix='ruff format . && ruff check . --fix'     # 코드 자동 포맷팅 및 수정
alias code_type='mypy .'                                 # 타입 검사

# Python Testing
alias test_pytest='pytest --maxfail=1 --disable-warnings -q' # pytest 전용
alias test_unittest='python -m unittest discover'            # unittest 전용

# Python Documentation
alias docs_gen='sphinx-apidoc -o docs/source . && sphinx-build -b html docs/source docs/build'

# -------------------------------
# Python aliases 도움말
# -------------------------------
