#!/bin/bash
# shell-common/tools/custom/ghes_mirror.sh
# Interactive wizard: clone a public GitHub repo and mirror it to an internal GHES instance.
# Sets up upstream (public) + origin (GHES) remotes and pushes all content.
#
# PATH executable since #2155 (~/.local/bin/ghes-mirror via config/symlinks.conf).
# The wizard ends inside the new clone; a child process cannot move its parent
# shell, so the `ghes_mirror` wrapper in functions/ghes_mirror.sh passes
# GHES_MIRROR_CD_FILE, this script writes the clone path there on success, and
# the wrapper cds into it (docs/.ssot/command-delivery-model.md §4).

# readlink -f: resolve the ~/.local/bin symlink to find init.sh next to the source.
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/init.sh" || exit 1

main() {
    case "${1-}" in
    -h | --help)
        # shellcheck source=/dev/null
        DOTFILES_FORCE_INIT=1 . "${SHELL_COMMON}/functions/ghes_mirror_help.sh"
        ghes_mirror_help
        return 0
        ;;
    esac

    ux_header "GHES Mirror Wizard"
    ux_info "Mirrors a public GitHub repo into your internal GHES instance."
    ux_info "Press Enter to accept [ default ] values."
    echo ""

    # --- Collect inputs ---
    local _default_upstream="https://github.com/dEitY719/visuals-skills"
    printf "%s1. Upstream URL%s [%s]: " "${UX_PRIMARY}" "${UX_RESET}" "${_default_upstream}"
    read -r _upstream
    _upstream="${_upstream:-${_default_upstream}}"

    # Derive GHES URL default — query GHES for authenticated owner namespace.
    # Host comes from DOTFILES_GHES_HOST (shell-common/env/internal.local.sh, #1944).
    local _default_ghes_host="${DOTFILES_GHES_HOST-}"
    local _upstream_path="${_upstream#https://github.com/}"
    local _upstream_owner="${_upstream_path%%/*}"
    local _upstream_repo="${_upstream_path##*/}"
    _upstream_repo="${_upstream_repo%.git}"
    local _default_ghes_url=""
    if [ -n "${_default_ghes_host}" ]; then
        local _default_ghes_user
        _default_ghes_user=$(gh api --hostname "${_default_ghes_host}" user --jq '.login' 2>/dev/null \
            || echo "${_upstream_owner}")
        _default_ghes_url="https://${_default_ghes_host}/${_default_ghes_user}/${_upstream_repo}"
    else
        ux_warning "DOTFILES_GHES_HOST not set (see shell-common/env/internal.local.example) — enter the full GHES URL"
    fi
    printf "%s2. GHES repo URL%s [%s]: " "${UX_PRIMARY}" "${UX_RESET}" "${_default_ghes_url}"
    read -r _ghes_full_url
    _ghes_full_url="${_ghes_full_url:-${_default_ghes_url}}"
    if [ -z "${_ghes_full_url}" ]; then
        ux_error "GHES repo URL is required."
        return 1
    fi

    # Parse host / owner / repo from GHES URL
    local _ghes_url_path="${_ghes_full_url#*://}"       # host/owner/repo (strip any protocol)
    local _ghes_host="${_ghes_url_path%%/*}"             # host
    _ghes_host="${_ghes_host%%:*}"                       # strip port if present
    local _ghes_owner_repo="${_ghes_url_path#*/}"        # owner/repo
    local _ghes_owner="${_ghes_owner_repo%%/*}"          # owner
    local _repo_name="${_ghes_owner_repo##*/}"           # repo
    _repo_name="${_repo_name%.git}"                      # strip .git suffix

    echo ""
    ux_info "Upstream : ${_upstream}"
    ux_info "GHES URL : ${_ghes_full_url}"
    echo ""
    printf "%sConfirm? [Y/n]%s " "${UX_WARNING}" "${UX_RESET}"
    read -r _confirm
    case "${_confirm:-Y}" in
    [Nn]*)
        ux_info "Aborted."
        return 0
        ;;
    esac
    echo ""

    # --- Step 1: Clone ---
    ux_step 1 "Cloning upstream..."
    if ! git clone "${_upstream}" "${_repo_name}"; then
        ux_error "Clone failed. Check upstream URL and network access."
        return 1
    fi
    local _orig_dir
    _orig_dir=$(pwd)
    cd "${_repo_name}" || {
        ux_error "Cannot enter directory: ${_repo_name}"
        return 1
    }

    # --- Step 2: Create GHES repo ---
    # upstream is always a public repo, so mirror as --public.
    # --internal is GHEC-only (not supported on GHES); account-type detection is unnecessary.
    local _visibility_flag="--public"
    ux_step 2 "Creating GHES repository (${_visibility_flag})..."
    # GH_HOST env var is required; gh repo create does not support --hostname flag.
    # --remote=_ghes_tmp avoids collision with clone's existing "origin" remote (#941).
    if ! GH_HOST="${_ghes_host}" gh repo create "${_ghes_owner}/${_repo_name}" "${_visibility_flag}" --source=. --remote=_ghes_tmp; then
        ux_error "GHES repo creation failed. Check: GH_HOST=${_ghes_host} gh auth status"
        cd "${_orig_dir}" || return 1
        return 1
    fi

    # --- Step 3: Configure remotes ---
    ux_step 3 "Configuring remotes..."
    if ! git remote rename origin upstream; then
        ux_error "Failed to rename origin to upstream."
        cd "${_orig_dir}" || return 1
        return 1
    fi
    if ! git remote rename _ghes_tmp origin; then
        ux_error "Failed to rename _ghes_tmp to origin."
        cd "${_orig_dir}" || return 1
        return 1
    fi

    # Owner is parsed directly from the GHES URL — no gh api query needed.
    local _origin_url="https://${_ghes_host}/${_ghes_owner}/${_repo_name}"
    # gh repo create may have registered an SSH URL (following gh's git_protocol
    # setting); force HTTPS so origin is always protocol-agnostic.
    if ! git remote set-url origin "${_origin_url}"; then
        ux_error "Failed to set origin URL to ${_origin_url}."
        cd "${_orig_dir}" || return 1
        return 1
    fi
    ux_info "upstream -> ${_upstream}"
    ux_info "origin   -> ${_origin_url}"

    # --- Step 4: Push ---
    ux_step 4 "Pushing to GHES..."
    local _branch
    _branch=$(git branch --show-current)
    if [ -z "${_branch}" ]; then
        ux_error "Could not detect current branch name (detached HEAD?)."
        cd "${_orig_dir}" || return 1
        return 1
    fi
    if ! git push -u origin "${_branch}"; then
        ux_error "Push failed. Verify GHES authentication and repo permissions."
        cd "${_orig_dir}" || return 1
        return 1
    fi

    echo ""
    ux_success "Mirror complete."
    if [ -n "${GHES_MIRROR_CD_FILE-}" ]; then
        pwd >"${GHES_MIRROR_CD_FILE}"
        ux_info "Working directory is now: $(pwd)"
    else
        ux_info "Mirror clone: $(pwd)"
    fi
    echo ""
    git remote -v
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
