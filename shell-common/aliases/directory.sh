#!/bin/sh
# shell-common/aliases/directory.sh
# Shared directory navigation aliases for bash and zsh

# BASIC

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

alias cd-dot='cd "${DOTFILES_ROOT:-$HOME/dotfiles}"'
alias cd-down='cd ~/downloads'
alias cd-work='cd ~/workspace'

# Dotfiles navigation functions
dot() {
    cd "${DOTFILES_ROOT:-$HOME/dotfiles}" || return 1
}

dotfiles() {
    cd "${DOTFILES_ROOT:-$HOME/dotfiles}" || return 1
}

# Windows directory paths (WSL). The profile dir comes from _win_home
# (util/win_home.sh: $WIN_HOME, else %USERPROFILE% via wslpath). Resolved on
# first use and cached for this shell, so shell start never runs cmd.exe.
if ! command -v _win_home >/dev/null 2>&1; then
    # shellcheck disable=SC1091
    . "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/util/win_home.sh"
fi

_cd_win() {
    if [ -z "${WIN_HOME-}" ] && [ -z "${_DOTFILES_WIN_HOME-}" ]; then
        _DOTFILES_WIN_HOME=$(_win_home) || {
            _DOTFILES_WIN_HOME=""
            ux_error "Windows profile dir not found (WSL only). Set WIN_HOME to override."
            return 1
        }
    fi
    cd "${WIN_HOME:-$_DOTFILES_WIN_HOME}/$1" || return 1
}

alias cd-wdocu='_cd_win Documents'
alias cd-wobsidian='_cd_win Documents/.obsidian'
alias cd-wdown='_cd_win Downloads'
alias cd-wpicture='_cd_win Pictures'
alias cd-tilnote='_cd_win Documents/ObsidianVault-TilNote'
alias cd-obsidian='_cd_win Documents/ObsidianVault-TilNote'

# PARA structure
alias mk-para='mkdir -p para/{archive,area,project,resource}'
alias cd-para='cd ~/para'

# PARA directories
alias cd-proj='cd ~/para/project'
alias cd-project='cd ~/para/project'
alias cd-area='cd ~/para/area'
alias cd-resource='cd ~/para/resource'
alias cd-archive='cd ~/para/archive'

# PROJECT directories
alias cd-af='cd-at'
alias cd-at='cd ~/para/project/agent-toolbox'
alias cd-en='cd ~/para/project/equinest'
alias cd-jv='cd ~/para/project/jiravis'
alias cd-kk='cd ~/para/project/karakeep'
alias cd-lak='cd ~/para/project/llm-agent-kit'
alias cd-ll='cd ~/para/project/litellm'
alias cd-op='cd ~/para/project/obsidian-para'
alias cd-opc='cd ~/para/project/obsidian-para-company'
alias cd-qf='cd ~/para/project/quantfolio'
alias cd-sad='cd ~/para/project/slsi-agent-desktop'
alias cd-sk='cd ~/para/project/skills'
alias cd-ss='cd ~/para/project/stock-steward'
# Note: Project-specific CLI commands are defined in project-cli-aliases.sh

# AREA directories
alias cd-vault='cd ~/para/area/vault'

# ARCHIVE directories
alias cd-pb='cd ~/para/archive/playbook'
alias cd-til='cd ~/para/archive/til'

# Symlink management
alias symlink-manager='${SHELL_COMMON_ROOT:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/symlink-manager.sh'
alias symlink-init='symlink-manager init'
alias symlink-check='symlink-manager check'
alias symlink-config='symlink-manager config'
