#!/bin/sh
# shell-common/functions/gh_project_pat.sh
# gh-project-pat: PROJECT_BOARD_PAT 생성 안내 + 다중 저장소 Actions secret
# 등록/존재 확인 (issue #2064). Help: gh_project_pat_help.sh (guide 문구 SSOT).
#
# Thin dispatcher: host resolution + ux_lib rendering. Target listing, the
# hidden PAT prompt and `gh secret set` (PAT on stdin only) live in the
# stdlib helper shell-common/tools/custom/lib/gh_project_pat.py, which prints
# tab-separated records (never the PAT) that _gh_project_pat_render shows.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_gh_project_pat_render() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local tab kind a b c
    tab=$(printf '\t')
    while IFS="$tab" read -r kind a b c; do
        case "$kind" in
            host) ux_info "host: $a" ;;
            owner) ux_info "owner: $a" ;;
            secret) ux_info "secret: $a" ;;
            mode) ux_info "mode: $a" ;;
            target) ux_bullet "$a" ;;
            count) ux_info "대상 저장소: $a 개" ;;
            result)
                if [ "$b" = ok ]; then
                    ux_success "OK   $a"
                else
                    ux_error "FAIL $a: $c"
                fi
                ;;
            set_summary) ux_info "합계: 성공 $a, 실패 $b" ;;
            status)
                case "$b" in
                    present) ux_success "present  $a" ;;
                    missing) ux_warning "missing  $a" ;;
                    *) ux_error "error    $a: $c" ;;
                esac
                ;;
            status_summary) ux_info "합계: present $a, missing $b, error $c" ;;
            error) ux_error "$a" ;;
        esac
    done <<EOF
$1
EOF
}

# Succeed when "$@" already carries --host (else the caller resolves one).
_gh_project_pat_has_host() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --host) return 0 ;;
            --host=*) return 0 ;;
        esac
        shift
    done
    return 1
}

# Print field 2 of every record of kind $1 in helper output $2.
_gh_project_pat_field() {
    printf '%s\n' "$2" | awk -F '\t' -v k="$1" '$1 == k { print $2 }'
}

_gh_project_pat_guide() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local host=""
    local host_set=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --host)
                [ $# -ge 2 ] || { ux_error "--host 값이 필요합니다"; return 2; }
                host="$2"
                host_set=1
                shift 2
                ;;
            --host=*)
                host="${1#--host=}"
                host_set=1
                shift
                ;;
            *)
                ux_error "Unknown guide option: $1"
                return 2
                ;;
        esac
    done
    if [ "$host_set" = 1 ] && [ -z "$host" ]; then
        ux_error "--host 값이 비어 있습니다"
        return 2
    fi
    [ -n "$host" ] || host=$(_gh_resolve_host)
    ux_header "PROJECT_BOARD_PAT 생성 (classic PAT, $host)"
    _gh_project_pat_help_rows_guide "$host"
}

gh_project_pat() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local sub="${1-}"
    local helper
    helper=${SHELL_COMMON}/tools/custom/lib/gh_project_pat.py
    local arg out rc host targets t mode
    case "$sub" in
        "" | -h | --help | help)
            gh_project_pat_help
            return 0
            ;;
        guide | set | status) shift ;;
        *)
            ux_error "Unknown subcommand: $sub"
            ux_info "Try: gh-project-pat-help"
            return 2
            ;;
    esac
    for arg in "$@"; do
        case "$arg" in
            -h | --help)
                gh_project_pat_help "$sub"
                return 0
                ;;
        esac
    done
    [ "$sub" = guide ] && {
        _gh_project_pat_guide "$@"
        return $?
    }

    command -v python3 >/dev/null 2>&1 || {
        ux_error "python3 not found"
        return 1
    }
    _gh_project_pat_has_host "$@" || set -- --host "$(_gh_resolve_host)" "$@"
    out=$(python3 "$helper" "$sub" "$@")
    rc=$?
    _gh_project_pat_render "$out"
    [ "$rc" = 0 ] || return "$rc"
    mode=$(_gh_project_pat_field mode "$out")
    if [ "$mode" != apply ]; then
        [ "$sub" = set ] && ux_info "dry-run: 쓰기 없음. 등록하려면 --apply 를 추가"
        return 0
    fi

    host=$(_gh_project_pat_field host "$out")
    targets=$(_gh_project_pat_field target "$out")
    set -- --host "$host"
    while IFS= read -r t; do
        set -- "$@" --repo "$t"
    done <<EOF
$targets
EOF
    out=$(python3 "$helper" apply "$@")
    rc=$?
    _gh_project_pat_render "$out"
    return "$rc"
}

alias gh-project-pat='gh_project_pat'
