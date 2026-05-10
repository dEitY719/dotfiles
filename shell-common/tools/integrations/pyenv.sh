#!/bin/sh
# shell-common/tools/integrations/pyenv.sh


# pyenv의 루트 경로

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"

# pyenv 초기화 (인터랙티브 셸 hook + PATH)
# --no-rehash: shell 시작마다 rehash 하지 않음.
#   - pyenv init - / --path 는 기본적으로 `command pyenv rehash 2>/dev/null` 를 emit
#   - pyenv-rehash 는 "cannot rehash: ... .pyenv-shim exists" 를 stdout 으로 쏘므로
#     2>/dev/null 로 막히지 않고, VSCode 가 동시에 여러 터미널을 열면 lock race 가 나
#     Powerlevel10k instant-prompt warning 을 유발한다.
#   - rehash 는 `pyenv install` / 새 entry-point 설치 후에만 수동으로 돌리면 충분.
# init --path 는 .zprofile 전용 PATH 세팅용이라 init - 가 이미 PATH 를 깐 뒤에는 중복.
if command -v pyenv >/dev/null; then
    eval "$(pyenv init - --no-rehash)"
    eval "$(pyenv virtualenv-init -)" # pyenv-virtualenv 사용 시
fi

# Python 설치 (대화형 스크립트)
py_install() {
    bash "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_python.sh" "$@"
}
alias install-py='py_install'

# 특정 Python 버전 제거
py_uninstall() {
    local version="$1"

    if [ -z "$version" ]; then
        ux_error "Usage: uninstall-py <python_version>"
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

alias uninstall-py='py_uninstall'
