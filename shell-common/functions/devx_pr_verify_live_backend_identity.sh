#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/devx_pr_verify_live_backend_identity.sh
# Shell function wrapper for container-backend identity verification.
#
# ═══════════════════════════════════════════════════════════════════════════════
# DEVELOPER NOTES - NAMING CONVENTION (See AGENTS.md:174-178)
# ═══════════════════════════════════════════════════════════════════════════════
# User-facing command: devx-pr-verify-live-backend-identity (dash-form)
# Internal function: devx_pr_verify_live_backend_identity() (snake_case)
# ═══════════════════════════════════════════════════════════════════════════════

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# Source UX library
_UX_LIB_PATH="${SHELL_COMMON:-${HOME}/.local/dotfiles/shell-common}/tools/ux_lib/ux_lib.sh"
if [ -f "$_UX_LIB_PATH" ]; then
    # shellcheck disable=SC1090
    source "$_UX_LIB_PATH"
else
    ux_error() { echo "✗ $1" >&2; }
    ux_info() { echo "ℹ $1"; }
    ux_header() { echo "=== $1 ==="; }
fi
unset _UX_LIB_PATH

devx_pr_verify_live_backend_identity() {
    local repo_root=""
    local target_repo=""
    local target_sha=""
    local base_url=""
    local backend_ports=""
    local container_name=""

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --repo-root)
                repo_root="$2"
                shift 2
                ;;
            --repo-root=*)
                repo_root="${1#--repo-root=}"
                shift
                ;;
            --target-repo)
                target_repo="$2"
                shift 2
                ;;
            --target-repo=*)
                target_repo="${1#--target-repo=}"
                shift
                ;;
            --target-sha)
                target_sha="$2"
                shift 2
                ;;
            --target-sha=*)
                target_sha="${1#--target-sha=}"
                shift
                ;;
            --base-url)
                base_url="$2"
                shift 2
                ;;
            --base-url=*)
                base_url="${1#--base-url=}"
                shift
                ;;
            --backend-ports)
                backend_ports="$2"
                shift 2
                ;;
            --backend-ports=*)
                backend_ports="${1#--backend-ports=}"
                shift
                ;;
            --container-name)
                container_name="$2"
                shift 2
                ;;
            --container-name=*)
                container_name="${1#--container-name=}"
                shift
                ;;
            -h|--help|help)
                show_devx_pr_verify_live_backend_identity_help
                return 0
                ;;
            *)
                ux_error "Unknown argument: $1"
                return 2
                ;;
        esac
    done

    # Validation
    if [ -z "$repo_root" ] || [ -z "$target_repo" ] || [ -z "$target_sha" ] || [ -z "$base_url" ]; then
        ux_error "Usage: devx-pr-verify-live-backend-identity --repo-root <path> --target-repo <repo> --target-sha <sha> --base-url <url> [--backend-ports <ports>] [--container-name <name>]"
        return 2
    fi

    # Locate Python script
    local python_script
    local python_script_base
    python_script_base="devx""_pr_verify_live_backend_identity.py"
    python_script="${SHELL_COMMON:-${HOME}/dotfiles/shell-common}/functions/${python_script_base}"

    if [ ! -f "$python_script" ]; then
        # Fallback if python helper is missing
        # Output unverified JSON per schema
        printf '{"result": "unverified", "layer": "backend", "evidence": [], "logs": ["helper script missing"], "reason": "helper_script_missing"}\n'
        return 0
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        # Fallback if python3 is missing
        printf '{"result": "unverified", "layer": "backend", "evidence": [], "logs": ["python3 missing"], "reason": "python3_missing"}\n'
        return 0
    fi

    # Build options
    local opts="--repo-root $repo_root --target-repo $target_repo --target-sha $target_sha --base-url $base_url"
    if [ -n "$backend_ports" ]; then
        opts="$opts --backend-ports $backend_ports"
    fi
    if [ -n "$container_name" ]; then
        opts="$opts --container-name $container_name"
    fi

    # Run helper
    # shellcheck disable=SC2086
    python3 "$python_script" $opts
}

show_devx_pr_verify_live_backend_identity_help() {
    ux_header "devx-pr-verify-live-backend-identity Help"
    echo ""
    ux_info "Usage: devx-pr-verify-live-backend-identity --repo-root <path> --target-repo <repo> --target-sha <sha> --base-url <url> [--backend-ports <ports>] [--container-name <name>]"
    echo ""
    ux_info "Options:"
    echo "  --repo-root <path>      Host repository root directory"
    echo "  --target-repo <repo>    GitHub repository owner/repo"
    echo "  --target-sha <sha>      Target commit OID to check ancestry"
    echo "  --base-url <url>        Frontend serving URL"
    echo "  --backend-ports <ports> Comma-separated candidate backend ports"
    echo "  --container-name <name> Explicit backend docker container name"
    echo ""
}

alias devx-pr-verify-live-backend-identity='devx_pr_verify_live_backend_identity'
if [ -n "$BASH_VERSION" ]; then
    export -f devx_pr_verify_live_backend_identity show_devx_pr_verify_live_backend_identity_help
fi
