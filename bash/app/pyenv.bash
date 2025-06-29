#!/bin/bash

# pyenv의 루트 경로를 설정합니다.
export PYENV_ROOT="$HOME/.pyenv"

# pyenv 바이너리가 PATH에 추가되도록 설정합니다.
export PATH="$PYENV_ROOT/bin:$PATH"

# pyenv 초기화를 위한 설정입니다.
# 이 줄은 pyenv 명령어가 작동하도록 핵심적인 역할을 합니다.
eval "$(pyenv init --path)"

# pyenv-virtualenv를 사용한다면 이 줄도 포함합니다.
# 가상 환경을 활성화/비활성화할 때 셸 프롬프트에 가상 환경 이름이 표시됩니다.
eval "$(pyenv virtualenv-init -)"

# --- pyenv 설정 끝 ---
