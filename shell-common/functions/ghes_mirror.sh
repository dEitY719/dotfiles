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

    local _default_host="github.samsungds.net"
    printf "%s2. GHES host%s [%s]: " "${UX_PRIMARY}" "${UX_RESET}" "${_default_host}"
    read -r _ghes_host
    _ghes_host="${_ghes_host:-${_default_host}}"

    local _suggested_name="${_upstream##*/}"
    _suggested_name="${_suggested_name%.git}"
    printf "%s3. GHES repository name%s [%s]: " "${UX_PRIMARY}" "${UX_RESET}" "${_suggested_name}"
    read -r _repo_name
    _repo_name="${_repo_name:-${_suggested_name}}"

    echo ""
    ux_info "Upstream : ${_upstream}"
    ux_info "GHES host: ${_ghes_host}"
    ux_info "Repo name: ${_repo_name}"
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
    cd "${_repo_name}" || {
        ux_error "Cannot enter directory: ${_repo_name}"
        return 1
    }

    # --- Step 2: Create GHES repo ---
    ux_step 2 "Creating GHES repository (--internal)..."
    # Use --private instead of --internal if your GHES plan does not support internal repos.
    if ! gh repo create "${_repo_name}" --internal --source=. --hostname="${_ghes_host}"; then
        ux_error "GHES repo creation failed. Check: gh auth status --hostname ${_ghes_host}"
        return 1
    fi

    # --- Step 3: Configure remotes ---
    ux_step 3 "Configuring remotes..."
    git remote rename origin upstream

    local _ghes_user
    _ghes_user=$(gh api user --hostname="${_ghes_host}" --jq '.login' 2>/dev/null)
    if [ -z "${_ghes_user}" ]; then
        ux_warning "Could not detect GHES username automatically."
        printf "%sGHES username%s: " "${UX_PRIMARY}" "${UX_RESET}"
        read -r _ghes_user
    fi

    local _origin_url="https://${_ghes_host}/${_ghes_user}/${_repo_name}"
    git remote add origin "${_origin_url}"
    ux_info "upstream -> ${_upstream}"
    ux_info "origin   -> ${_origin_url}"

    # --- Step 4: Push ---
    ux_step 4 "Pushing to GHES..."
    local _branch
    _branch=$(git branch --show-current)
    if ! git push -u origin "${_branch}"; then
        ux_error "Push failed. Verify GHES authentication and repo permissions."
        return 1
    fi

    echo ""
    ux_success "Mirror complete."
    ux_info "Working directory is now: $(pwd)"
    echo ""
    git remote -v
}

alias ghes-mirror='ghes_mirror'
