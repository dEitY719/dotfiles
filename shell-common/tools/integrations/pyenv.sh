#!/bin/sh
# shell-common/tools/external/pyenv.sh
# Auto-generated from bash/app/pyenv.bash


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

# Python 설치 (대화형 스크립트)
py_install() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_python.sh" "$@"
}
alias install-pyenv='py_install'

# 특정 Python 버전 제거
py_uninstall() {
    local version="$1"

    if [ -z "$version" ]; then
        ux_error "Usage: uninstall-pyenv <python_version>"
        return 1
    fi

    if ! command -v pyenv >/dev/null; then
        ux_error "pyenv is not installed or not on PATH."
        return 1
    fi

    if ! pyenv versions --bare | grep -Fxq "$version"; then
        ux_warning "Python ${version} is not installed via pyenv."
        return 0
    fi

    if ! ux_confirm "Uninstall Python ${version} via pyenv?" "n"; then
        ux_info "Uninstall cancelled."
        return 0
    fi

    if pyenv uninstall -f "$version"; then
        ux_success "Python ${version} removed."
    else
        ux_error "Failed to uninstall Python ${version}."
        return 1
    fi
}

alias uninstall-pyenv='py_uninstall'
