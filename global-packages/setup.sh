#!/bin/bash

# global-packages/setup.sh: sync global uv tools from uv-tools.txt
#
# PURPOSE: Install every uv tool listed in uv-tools.txt that is missing
# WHEN TO RUN: Via ./setup.sh (idempotent; safe to re-run)
#
# Never fails the parent setup: every problem is a ux_warning + exit 0.
# Never uninstalls: unlisted installed tools are only reported.
# GLOBAL_PACKAGES_LIST overrides the list file (tests).

# --- Constants ---

_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
DOTFILES_ROOT="$(cd "$(dirname "$_SCRIPT_PATH")/.." && pwd)"
LIST_FILE="${GLOBAL_PACKAGES_LIST:-${DOTFILES_ROOT}/global-packages/uv-tools.txt}"

UX_LIB="${DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh"
if [ -f "$UX_LIB" ]; then
    # shellcheck source=/dev/null
    source "$UX_LIB"
else
    echo "Error: UX library not found at $UX_LIB"
    exit 1
fi

# --- Functions ---

# Package name from a spec: drop [extras], version specifiers, markers;
# normalize like uv does (lowercase, _ and . -> -).
spec_name() {
    printf '%s\n' "$1" | sed 's/[][<>=!~;@ ].*//' | tr 'A-Z_.' 'a-z--'
}

# uv missing -> install the mise-pinned version (mise.toml) and use it.
ensure_uv() {
    command -v uv >/dev/null 2>&1 && return 0
    command -v mise >/dev/null 2>&1 || return 1
    ux_info "uv 없음 — mise install uv 시도"
    local uv_bin
    (cd "$DOTFILES_ROOT" && mise install uv) >/dev/null 2>&1 || return 1
    uv_bin="$(cd "$DOTFILES_ROOT" && mise which uv 2>/dev/null)" || return 1
    [ -x "$uv_bin" ] || return 1
    PATH="$(dirname "$uv_bin"):$PATH"
}

main() {
    if [ ! -f "$LIST_FILE" ]; then
        ux_warning "목록 파일 없음: $LIST_FILE"
        return 0
    fi
    if ! ensure_uv; then
        ux_warning "uv/mise 를 찾을 수 없어 global uv tools 동기화를 건너뜀"
        return 0
    fi

    # Tool header lines look like "name vX.Y.Z"; "- entrypoint" lines skipped.
    local installed spec name listed="" extra
    installed="$(uv tool list 2>/dev/null | awk '!/^-/ && $2 ~ /^v/ {print $1}')"

    while IFS= read -r spec || [ -n "$spec" ]; do
        spec="${spec%%#*}"
        spec="$(printf '%s' "$spec" | tr -d '[:space:]')"
        [ -z "$spec" ] && continue
        name="$(spec_name "$spec")"
        listed="$listed $name "
        if printf '%s\n' "$installed" | grep -qx -- "$name"; then
            ux_info "이미 설치됨, 건너뜀: $name"
        elif uv tool install --native-tls "$spec"; then
            ux_success "설치 완료: $spec"
        else
            ux_warning "설치 실패 (계속 진행): $spec"
        fi
    done <"$LIST_FILE"

    extra=""
    for name in $installed; do
        case "$listed" in *" $name "*) ;; *) extra="$extra $name" ;; esac
    done
    if [ -n "$extra" ]; then
        ux_warning "uv-tools.txt 에 없는 설치된 도구 (삭제하지 않음):$extra"
    fi
    return 0
}

main "$@"
