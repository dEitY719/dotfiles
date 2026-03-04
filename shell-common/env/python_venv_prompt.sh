#!/bin/sh
# shell-common/env/python_venv_prompt.sh
# Keep shell prompt styling consistent by preventing venv scripts from rewriting PS1.

# Standard venv/virtualenv prompt mutation disable flag.
export VIRTUAL_ENV_DISABLE_PROMPT=1

# pyenv-virtualenv prompt mutation disable flag.
export PYENV_VIRTUAL_ENV_DISABLE_PROMPT=1
