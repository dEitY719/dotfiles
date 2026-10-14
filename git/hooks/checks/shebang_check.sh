#!/usr/bin/env bash

get_expected_shebang() {
    local repo_root="$1"
    local abs_path="$2"

    # Only tools/custom *entry points* get the bash shebang; the source-only
    # helpers in its subdirectories fall through to the generic shell-common
    # #!/bin/sh rule below rather than restating it here. custom_tool_class
    # (shared.sh) owns that distinction.
    if [[ "$(custom_tool_class "${abs_path#"$repo_root"/}")" == "entrypoint" ]]; then
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

# --- pre-commit registry adapter (contract: git/doc/CHECK_REGISTRY.md, #2143) ---
CHECK_NAME=shebang
CHECK_SCOPE=per-file
CHECK_SEVERITY=blocking
CHECK_TITLE="Shebang violations"
check_run() {
    local repo_root="$1" file="$3" out="$4" abs_path
    case "$file" in shell-common/*.sh | bash/*.sh | zsh/*.sh) ;; *) return 0 ;; esac
    abs_path="$repo_root/$file"
    [ -f "$abs_path" ] || return 0
    check_shebang_violation "$repo_root" "$abs_path" && return 0
    echo "$file:1: Expected: $(get_expected_shebang "$repo_root" "$abs_path") Got: $(head -n1 "$abs_path")" >>"$out"
    return 1
}
