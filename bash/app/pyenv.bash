#!/bin/bash

# pyenv의 루트 경로
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"

# 인터랙티브 셸에서 pyenv hook 활성화
# (pyenv shell, pyenv activate 같은 기능이 정상 동작하려면 필요)
if command -v pyenv >/dev/null; then
    eval "$(pyenv init -)"
    eval "$(pyenv virtualenv-init -)" # pyenv-virtualenv 사용 시
fi

# pyenv PATH 초기화 (로그인 셸용)
if command -v pyenv >/dev/null; then
    eval "$(pyenv init --path)"
fi
