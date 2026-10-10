#!/bin/bash

# global-packages/setup.sh: sync global uv tools from uv-tools.txt
#
# PURPOSE: Install every uv tool listed in uv-tools.txt that is missing,
#          and reinstall (--force) one whose --python/--with drifted
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

# Receipt of installed tool $1 matches its options ($2...)? Only
# `--python V` and `--with X` (space-separated form) are checked.
receipt_matches() {
    local receipt
    receipt="$(uv tool dir 2>/dev/null)/$1/uv-receipt.toml"
    shift
    [ -f "$receipt" ] || return 1
    while [ $# -gt 0 ]; do
        case "$1" in
            --python) grep -qFx "python = \"$2\"" "$receipt" || return 1; shift ;;
            --with) grep -qF "name = \"$(spec_name "$2")\"" "$receipt" || return 1; shift ;;
        esac
        shift
    done
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
    local installed line spec name listed="" extra
    local -a toks opts force
    installed="$(uv tool list 2>/dev/null | awk '!/^-/ && $2 ~ /^v/ {print $1}')"

    while IFS= read -r line || [ -n "$line" ]; do
        read -r -a toks <<<"${line%%#*}"
        [ ${#toks[@]} -eq 0 ] && continue
        spec="${toks[0]}"
        opts=("${toks[@]:1}")
        name="$(spec_name "$spec")"
        listed="$listed $name "
        force=()
        if printf '%s\n' "$installed" | grep -qx -- "$name"; then
            if [ ${#opts[@]} -eq 0 ] || receipt_matches "$name" "${opts[@]}"; then
                ux_info "이미 설치됨, 건너뜀: $name"
                continue
            fi
            ux_info "설치 옵션 불일치 (${opts[*]}), --force 재설치: $name"
            force=(--force)
        fi
        if uv tool install --native-tls "${force[@]}" "${opts[@]}" "$spec" </dev/null; then
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
