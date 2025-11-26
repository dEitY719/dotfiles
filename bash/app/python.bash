#!/bin/bash

# bash/app/python.bash

# Add user-installed Python scripts to the PATH (for pip packages like gemini-cli)
export PATH="$HOME/.local/bin:$PATH"

# Python Virtual Environment
alias create_venv='python -m venv .venv'
alias act_venv='source .venv/bin/activate'
alias echo_venv='echo "$VIRTUAL_ENV"'
alias rm_venv='rm -rf .venv'
alias deact_venv='deactivate'

alias cv='python -m venv .venv'
alias av='source .venv/bin/activate'
alias ev='echo $VIRTUAL_ENV'
alias rv='rm -rf .venv'
alias dv='source deactivate'
# deactivate는 source 없이도 작동합니다.
# pyenv-virtualenv: deactivate must be sourced. Run 'source deactivate' instead of 'deactivate'

# -------------------------------
# Python venv 도움말
# -------------------------------
pyhelp() {
    # Color definitions
    local bold blue green reset
    bold=$(tput bold 2>/dev/null || echo "")
    blue=$(tput setaf 4 2>/dev/null || echo "")
    green=$(tput setaf 2 2>/dev/null || echo "")
    reset=$(tput sgr0 2>/dev/null || echo "")

    cat <<EOF

${bold}${blue}[Python Virtual Environment Commands]${reset}

  ${bold}${blue}Full Commands:${reset}
    ${green}create_venv${reset}  : python -m venv .venv (가상환경 생성)
    ${green}act_venv${reset}     : source .venv/bin/activate (가상환경 활성화)
    ${green}echo_venv${reset}    : echo "\$VIRTUAL_ENV" (현재 가상환경 경로 출력)
    ${green}rm_venv${reset}      : rm -rf .venv (가상환경 삭제)
    ${green}deact_venv${reset}   : deactivate (가상환경 비활성화)

  ${bold}${blue}Short Commands:${reset}
    ${green}cv${reset}           : create venv
    ${green}av${reset}           : activate venv
    ${green}ev${reset}           : echo venv path
    ${green}rv${reset}           : remove venv
    ${green}dv${reset}           : deactivate venv

  ${bold}${blue}[Quick Workflow]${reset}
    1. ${green}cv${reset}           # 가상환경 생성
    2. ${green}av${reset}           # 가상환경 활성화
    3. ${green}pip install${reset}  # 패키지 설치
    4. ${green}dv${reset}           # 작업 완료 후 비활성화

EOF
}
