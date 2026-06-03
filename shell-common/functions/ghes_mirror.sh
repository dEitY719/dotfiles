#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/ghes_mirror.sh
# Interactive wizard: clone a public GitHub repo and mirror it to an internal GHES instance.
# Sets up upstream (public) + origin (GHES) remotes and pushes all content.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

ghes_mirror() {
    if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        ghes_mirror_help
        return 0
    fi

    ux_header "GHES Mirror Wizard"
    ux_info "Mirrors a public GitHub repo into your internal GHES instance."
    ux_info "Press Enter to accept [ default ] values."
    echo ""

    # --- Collect inputs ---
    local _default_upstream="https://github.com/dEitY719/claude-plugin-visuals"
    printf "%s1. Upstream URL%s [%s]: " "${UX_PRIMARY}" "${UX_RESET}" "${_default_upstream}"
    read -r _upstream
    _upstream="${_upstream:-${_default_upstream}}"

    # Derive GHES URL default — query GHES for authenticated owner namespace
    local _default_ghes_host="github.samsungds.net"
    local _upstream_path="${_upstream#https://github.com/}"
    local _upstream_owner="${_upstream_path%%/*}"
    local _upstream_repo="${_upstream_path##*/}"
    _upstream_repo="${_upstream_repo%.git}"
    local _default_ghes_user
    _default_ghes_user=$(gh api --hostname "${_default_ghes_host}" user --jq '.login' 2>/dev/null \
        || echo "${_upstream_owner}")
    local _default_ghes_url="https://${_default_ghes_host}/${_default_ghes_user}/${_upstream_repo}"
    printf "%s2. GHES repo URL%s [%s]: " "${UX_PRIMARY}" "${UX_RESET}" "${_default_ghes_url}"
    read -r _ghes_full_url
    _ghes_full_url="${_ghes_full_url:-${_default_ghes_url}}"

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
    ux_step 2 "Creating GHES repository (--internal)..."
    # Use --private instead of --internal if your GHES plan does not support internal repos.
    # GH_HOST env var is required; gh repo create does not support --hostname flag.
    if ! GH_HOST="${_ghes_host}" gh repo create "${_ghes_owner}/${_repo_name}" --internal --source=.; then
        ux_error "GHES repo creation failed. Check: GH_HOST=${_ghes_host} gh auth status"
        cd "${_orig_dir}" || return 1
        return 1
    fi

    # --- Step 3: Configure remotes ---
    ux_step 3 "Configuring remotes..."
    git remote rename origin upstream

    # Owner is parsed directly from the GHES URL — no gh api query needed.
    local _origin_url="https://${_ghes_host}/${_ghes_owner}/${_repo_name}"
    git remote add origin "${_origin_url}"
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
    ux_info "Working directory is now: $(pwd)"
    echo ""
    git remote -v
}

alias ghes-mirror='ghes_mirror'
