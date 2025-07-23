#!/bin/bash

# Python Virtual Environment
alias cv='python -m venv .venv'
alias av='source .venv/bin/activate'
alias ev='echo $VIRTUAL_ENV'
alias dv='deactivate' # deactivate는 source 없이도 작동합니다.

# Python Package Management
alias pp_install='pip install'                                 # 일반 패키지 설치
alias pp_install_up='pip install --upgrade pip && pip install' # pip 업그레이드 후 설치
alias pp_freeze='pip freeze > requirements.txt'
alias pp_reqs='pip install -r requirements.txt'
alias pp_list='pip list --outdated --format=columns'
alias pp_check='pip check'
alias pp_uninstall='pip uninstall -y'

# Python Code Quality & Formatting
alias code_format='black . && isort . && flake8 .'
alias code_lint='pylint .'
alias code_type='mypy .'

# Python Testing
alias test_pytest='pytest --maxfail=1 --disable-warnings -q' # pytest 전용
alias test_unittest='python -m unittest discover'            # unittest 전용

# Python Documentation
alias docs_gen='sphinx-apidoc -o docs/source . && sphinx-build -b html docs/source docs/build'
