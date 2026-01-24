#!/usr/bin/env bash

get_expected_shebang() {
    local repo_root="$1"
    local abs_path="$2"

    if [[ "$abs_path" == "$repo_root/shell-common/tools/custom/"* ]]; then
        echo "${DOTFILES_HOOKS_SHEBANG_SHELL_COMMON_CUSTOM:-#!/bin/bash}"
    elif [[ "$abs_path" == "$repo_root/shell-common"* ]]; then
        echo "${DOTFILES_HOOKS_SHEBANG_SHELL_COMMON:-#!/bin/sh}"
    elif [[ "$abs_path" == "$repo_root/bash"* ]]; then
        echo "${DOTFILES_HOOKS_SHEBANG_BASH:-#!/bin/bash}"
    elif [[ "$abs_path" == "$repo_root/zsh"* ]]; then
        echo "${DOTFILES_HOOKS_SHEBANG_ZSH:-#!/bin/zsh}"
    else
        echo ""
    fi
}

check_shebang_violation() {
    local repo_root="$1"
    local abs_path="$2"

    local expected
    expected=$(get_expected_shebang "$repo_root" "$abs_path")
    [ -z "$expected" ] && return 0

    local actual
    actual=$(head -n1 "$abs_path")
    [ "$actual" = "$expected" ] && return 0
    return 1
}
