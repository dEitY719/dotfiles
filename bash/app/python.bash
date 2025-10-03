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
    cat <<-'EOF'

[Python Virtual Environment Commands]

  Full Commands:
    create_venv  : python -m venv .venv (가상환경 생성)
    act_venv     : source .venv/bin/activate (가상환경 활성화)
    echo_venv    : echo "$VIRTUAL_ENV" (현재 가상환경 경로 출력)
    rm_venv      : rm -rf .venv (가상환경 삭제)
    deact_venv   : deactivate (가상환경 비활성화)

  Short Commands:
    cv           : create venv
    av           : activate venv
    ev           : echo venv path
    rv           : remove venv
    dv           : deactivate venv

[Quick Workflow]
  1. cv           # 가상환경 생성
  2. av           # 가상환경 활성화
  3. pip install  # 패키지 설치
  4. dv           # 작업 완료 후 비활성화

EOF
}
