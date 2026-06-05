#!/bin/sh
# shell-common/functions/zsh.sh
# Zsh shell management functions
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# Zsh Helper Functions
# ═══════════════════════════════════════════════════════════════

# Check if zsh is installed

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_zsh_check_installed() {
    if ! command -v zsh >/dev/null 2>&1; then
        ux_error "zsh is not installed."
        ux_info "Install with: ${UX_BOLD}install-zsh${UX_RESET}"
        return 1
    fi
    return 0
}

# Check if oh-my-zsh is installed
_zsh_check_omz() {
    if [ ! -d "${HOME}/.oh-my-zsh" ]; then
        ux_warning "oh-my-zsh is not installed."
        ux_info "Install with: ${UX_BOLD}install-zsh${UX_RESET}"
        return 1
    fi
    return 0
}

# Get current zsh version
zsh_version() {
    if _zsh_check_installed; then
        zsh --version
    fi
}

# List all available zsh themes
zsh_themes() {
    if ! _zsh_check_omz; then
        return 1
    fi

    ux_header "Available Zsh Themes"
    ux_info "Located in: ${UX_BOLD}~/.oh-my-zsh/themes/${UX_RESET}"


    local themes_dir="${HOME}/.oh-my-zsh/themes"
    if [ -d "$themes_dir" ]; then
        ux_header "Available themes:"
        find "$themes_dir" -maxdepth 1 -name "*.zsh-theme" -printf '%f\n' | sed 's/\.zsh-theme$//' | sort | nl
    else
        ux_error "Themes directory not found."
        return 1
    fi
}

# Change zsh theme
zsh_theme() {
    if ! _zsh_check_omz; then
        return 1
    fi

    if [ -z "$1" ]; then
        ux_usage "zsh-theme" "<theme-name>" "Change zsh theme"
        ux_bullet "Available themes: ${UX_BOLD}zsh-themes${UX_RESET}"
        ux_bullet "Example: ${UX_BOLD}zsh-theme powerlevel10k${UX_RESET}"
        return 1
    fi

    local theme_name="$1"
    local zshrc="${HOME}/.zshrc"

    if [ ! -f "$zshrc" ]; then
        ux_error "\$HOME/.zshrc not found."
        return 1
    fi

    # Use sed to update the ZSH_THEME line
    if sed -i.bak "s/^ZSH_THEME=.*/ZSH_THEME=\"$theme_name\"/" "$zshrc"; then
        ux_success "Theme changed to: ${UX_BOLD}$theme_name${UX_RESET}"
        ux_info "Run ${UX_BOLD}zsh-reload${UX_RESET} or restart zsh to apply changes."
    else
        ux_error "Failed to change theme."
        return 1
    fi
}

# Get current zsh theme
zsh_theme_current() {
    if [ ! -f "${HOME}/.zshrc" ]; then
        ux_error "\$HOME/.zshrc not found."
        return 1
    fi

    local current_theme
    current_theme=$(grep "^ZSH_THEME=" "${HOME}/.zshrc" | cut -d'"' -f2)
    if [ -z "$current_theme" ]; then
        ux_warning "No theme set."
    else
        ux_info "Current theme: ${UX_BOLD}$current_theme${UX_RESET}"
    fi
}

# List installed zsh plugins
zsh_plugins() {
    if ! _zsh_check_omz; then
        return 1
    fi

    ux_header "Installed Zsh Plugins"
    ux_info "Location: ${UX_BOLD}~/.oh-my-zsh/custom/plugins/${UX_RESET}"


    local plugins_dir="${HOME}/.oh-my-zsh/custom/plugins"
    if [ -d "$plugins_dir" ]; then
        ux_section "Custom Plugins"
        if [ -n "$(find "$plugins_dir" -maxdepth 1 -type d ! -name "." 2>/dev/null)" ]; then
            find "$plugins_dir" -maxdepth 1 -type d ! -name "." -printf '%f\n' | sort | nl
        else
            ux_warning "No custom plugins installed."
        fi
    fi


    ux_section "Built-in Plugins"
    ux_info "Location: ${UX_BOLD}~/.oh-my-zsh/plugins/${UX_RESET}"
    ux_header "Popular plugins:"
    ux_bullet "git - Git aliases and functions"
    ux_bullet "zsh-autosuggestions - Command auto-completion"
    ux_bullet "zsh-syntax-highlighting - Syntax highlighting"
    ux_bullet "extract - Extract various archive formats"
    ux_bullet "web-search - Quick web search from CLI"
    ux_bullet "timer - Simple timer functionality"
}

# Update oh-my-zsh to latest version
zsh_update() {
    if ! _zsh_check_omz; then
        return 1
    fi

    ux_header "Updating Oh-My-Zsh"
    local omz_dir="${HOME}/.oh-my-zsh"

    if [ -d "$omz_dir/.git" ]; then
        ux_info "Updating from Git repository..."
        cd "$omz_dir" || return 1
        git pull
        ux_success "Oh-My-Zsh updated successfully."
    else
        ux_error "Oh-My-Zsh was not installed via Git."
        return 1
    fi
}

# Reload zsh configuration (POSIX-compatible version)
zsh_reload() {
    if [ -f "${HOME}/.zshrc" ]; then
        ux_info "Reloading zsh configuration..."
        if [ -n "$ZSH_VERSION" ]; then
            # We're in zsh, source directly
            source "${HOME}/.zshrc"
            ux_success "Zsh configuration reloaded."
        else
            # We're in bash, notify user
            ux_warning "You are currently in bash. Switch to zsh first to reload configuration."
            ux_info "Run: ${UX_BOLD}zsh-switch${UX_RESET}"
        fi
    else
        ux_error "\$HOME/.zshrc not found."
        return 1
    fi
}

# Open zsh configuration in editor
zsh_edit() {
    local zshrc="${HOME}/.zshrc"
    if [ ! -f "$zshrc" ]; then
        ux_error "\$HOME/.zshrc not found."
        return 1
    fi

    ux_info "Opening \$HOME/.zshrc in editor..."
    if [ -n "$EDITOR" ]; then
        "$EDITOR" "$zshrc"
    elif command -v nano >/dev/null 2>&1; then
        nano "$zshrc"
    elif command -v vi >/dev/null 2>&1; then
        vi "$zshrc"
    else
        ux_error "No editor found."
        return 1
    fi
}

# Create/Edit zsh config snippet
zsh_snippet() {
    if [ -z "$1" ]; then
        ux_usage "zsh-snippet" "<snippet-name>" "Create or edit a config snippet"
        ux_bullet "Example: ${UX_BOLD}zsh-snippet aliases${UX_RESET}"
        return 1
    fi

    local snippet_name="$1"
    local snippets_dir="${HOME}/.zshrc.d"
    local snippet_file="${snippets_dir}/${snippet_name}.zsh"

    mkdir -p "$snippets_dir"

    if [ -f "$snippet_file" ]; then
        ux_info "Editing existing snippet: $snippet_name"
    else
        ux_info "Creating new snippet: $snippet_name"
        cat >"$snippet_file" <<'EOF'
# ~/.zshrc.d/SNIPPET_NAME.zsh
# Add your zsh configuration here

EOF
    fi

    if [ -n "$EDITOR" ]; then
        "$EDITOR" "$snippet_file"
    elif command -v nano >/dev/null 2>&1; then
        nano "$snippet_file"
    else
        ux_error "No editor found."
        return 1
    fi
}

# List zsh snippets
zsh_snippets() {
    local snippets_dir="${HOME}/.zshrc.d"

    if [ ! -d "$snippets_dir" ]; then
        ux_warning "No snippets directory found."
        ux_info "Create one with: ${UX_BOLD}mkdir -p ~/.zshrc.d${UX_RESET}"
        return 0
    fi

    ux_header "Zsh Configuration Snippets"
    ux_info "Location: ${UX_BOLD}\$HOME/.zshrc.d/${UX_RESET}"


    if [ -n "$(find "$snippets_dir" -maxdepth 1 -name "*.zsh" 2>/dev/null)" ]; then
        ux_section "Available Snippets"
        find "$snippets_dir" -maxdepth 1 -name "*.zsh" -printf '%f\n' | sed 's/\.zsh$//' | sort | nl

        ux_section "Usage"
        ux_bullet "View snippet: ${UX_BOLD}cat \$HOME/.zshrc.d/<snippet-name>.zsh${UX_RESET}"
        ux_bullet "Edit snippet: ${UX_BOLD}zsh-snippet <snippet-name>${UX_RESET}"
        ux_bullet "Delete snippet: ${UX_BOLD}rm \$HOME/.zshrc.d/<snippet-name>.zsh${UX_RESET}"
    else
        ux_info "No snippets found. Create one with: ${UX_BOLD}zsh-snippet <name>${UX_RESET}"
    fi
}

# SSOT cleaner for p10k caches. Removes every variant the user may carry
# across reboots — instant-prompt cache, compiled dump, and the per-user
# scratch directory. Returns the number of artifacts removed via stdout
# so callers can decide whether to print a "nothing to do" hint.
#
# Issue #705: the prior cleaner only matched `p10k-instant-prompt-${USER}.zsh`,
# missing the `.zwc` byte-compiled dump and the `p10k-dump-${USER}*` files
# that zsh auto-loads ahead of the source. A worktree-spawn race could then
# replay a stale precmd snapshot, producing a frozen prompt that only
# `exec zsh` recovered from.
_zsh_clear_p10k_caches() {
    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
    local removed=0
    local target

    # File patterns: instant-prompt + dump, both .zsh and .zwc variants.
    # Only count artifacts that actually got removed — `rm -f` returns 1 on
    # permission-denied even though it suppresses ENOENT (PR #706 review).
    for target in \
        "${cache_dir}/p10k-instant-prompt-${USER}.zsh" \
        "${cache_dir}/p10k-instant-prompt-${USER}.zsh.zwc" \
        "${cache_dir}/p10k-dump-${USER}.zsh" \
        "${cache_dir}/p10k-dump-${USER}.zsh.zwc"; do
        if [ -e "$target" ] || [ -L "$target" ]; then
            rm -f "$target" && removed=$((removed + 1))
        fi
    done

    # Per-user scratch dir (e.g. ~/.cache/p10k-bwyoon/) — p10k creates it
    # on first prompt and may stash transient state there.
    local p10k_user_dir="${cache_dir}/p10k-${USER}"
    if [ -d "$p10k_user_dir" ]; then
        rm -rf "$p10k_user_dir" && removed=$((removed + 1))
    fi

    printf '%d\n' "$removed"
}

# User-facing wrapper: clears every p10k cache variant and reports what
# happened. Reload zsh (`exec zsh`) or open a new terminal to verify.
zsh_clear_p10k_caches() {
    local removed
    removed="$(_zsh_clear_p10k_caches)"
    # ${var:-0} guard: subshell could in theory yield an empty string under
    # exotic failure modes, which would make `[ "$removed" -eq 0 ]` fail
    # with `unary operator expected` (PR #706 review).
    if [ "${removed:-0}" -eq 0 ]; then
        ux_info "No p10k caches found."
        return 0
    fi
    ux_success "Cleared p10k caches (${removed} artifact(s))."
    ux_info "Reload to verify: ${UX_BOLD}exec zsh${UX_RESET}"
}

# Fix VS Code terminal prompt after VS Code update
# Clears stale caches that cause default prompt (HOSTNAME%) instead of p10k
zsh_fix_vscode() {
    local fixed=0

    # Remove stale .zcompdump from VS Code temp ZDOTDIR
    local vscode_zdotdir="/tmp/${USER}-code-zsh"
    if [ -d "$vscode_zdotdir" ]; then
        rm -f "$vscode_zdotdir"/.zcompdump*
        ux_success "Cleared VS Code ZDOTDIR cache: $vscode_zdotdir/.zcompdump*"
        fixed=1
    fi

    # Delegate p10k cache cleanup to the SSOT helper (issue #705).
    # ${var:-0} guard mirrors zsh_clear_p10k_caches (PR #706 review).
    local removed
    removed="$(_zsh_clear_p10k_caches)"
    if [ "${removed:-0}" -gt 0 ]; then
        ux_success "Cleared p10k caches (${removed} artifact(s))."
        fixed=1
    fi

    if [ "$fixed" -eq 0 ]; then
        ux_info "No stale caches found."
    else
        ux_info "Open a new VS Code terminal to verify the fix."
    fi
}

# Restore .git/config after all worktrees removed (issue #968).
# gitstatusd v1.5.4 treats repositoryformatversion=1 as "not a git repo",
# breaking p10k's branch display. Run after `gwt teardown --all`.
zsh_git_fix() {
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        ux_error "Not a git repository."
        return 1
    fi

    local rfv
    rfv="$(git config core.repositoryformatversion 2>/dev/null)"
    if [ "${rfv:-0}" = "0" ]; then
        ux_info "Already OK: repositoryformatversion=0"
        return 0
    fi

    local wt_count
    wt_count="$(git worktree list --porcelain | grep -c "^worktree ")"
    if [ "${wt_count:-1}" -gt 1 ]; then
        ux_warning "Active worktrees present (${wt_count}). Run ${UX_BOLD}gwt teardown --all${UX_RESET} first."
        return 1
    fi

    git config --unset extensions.worktreeConfig 2>/dev/null || true
    if ! git config --name-only --get-regexp '^extensions\.' >/dev/null 2>&1; then
        git config core.repositoryformatversion 0
        ux_success "Fixed: repositoryformatversion=0, worktreeConfig removed."
    else
        ux_success "Fixed: worktreeConfig removed (kept repositoryformatversion=1 due to other active extensions)."
    fi
    ux_info "Verify: ${UX_BOLD}exec zsh${UX_RESET}"
}

# ═══════════════════════════════════════════════════════════════
# Naming Convention: Function uses underscore, alias provides dash format
# ═══════════════════════════════════════════════════════════════
# Functions: zsh_version, zsh_themes, etc. (underscore format - POSIX compatible)
# Help command is defined in shell-common/functions/zsh_help.sh
# User calls: zsh-help, zsh-version, etc. (dash format - user friendly)
alias zsh-version='zsh_version'
alias zsh-themes='zsh_themes'
alias zsh-theme='zsh_theme'
alias zsh-theme-current='zsh_theme_current'
alias zsh-plugins='zsh_plugins'
alias zsh-update='zsh_update'
alias zsh-reload='zsh_reload'
alias zsh-edit='zsh_edit'
alias zsh-snippet='zsh_snippet'
alias zsh-snippets='zsh_snippets'
alias zsh-fix-vscode='zsh_fix_vscode'
alias zsh-clear-p10k-caches='zsh_clear_p10k_caches'
alias zsh-git-fix='zsh_git_fix'
