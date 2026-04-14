#!/bin/sh
# shell-common/functions/my_help.sh
# Help system for bash/zsh dotfiles
# Provides centralized help registry for all commands
# Bash/Zsh/POSIX compatible

# ═══════════════════════════════════════════════════════════════
# UX Library Loading (bash/zsh compatible)
# ═══════════════════════════════════════════════════════════════

if ! type ux_header >/dev/null 2>&1; then
    # Try to load UX library if not already loaded
    if [ -z "$SHELL_COMMON" ]; then
        # Detect shell type and set path accordingly
        if [ -n "$ZSH_VERSION" ]; then
            # We're in zsh
            _MYHELP_DIR="${0:h}"
        else
            # We're in bash
            _MYHELP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        fi
        SHELL_COMMON="${_MYHELP_DIR%/functions}"
    fi
    if [ -f "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" ]; then
        source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" 2>/dev/null
    fi
fi

# ═══════════════════════════════════════════════════════════════
# Load Help Function Files (bash/zsh compatible)
# ═══════════════════════════════════════════════════════════════
if [ -z "$SHELL_COMMON" ]; then
    if [ -n "$ZSH_VERSION" ]; then
        _MYHELP_DIR="${0:h}"
    else
        _MYHELP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    fi
    SHELL_COMMON="${_MYHELP_DIR%/functions}"
fi

# Source all *_help.sh files from the functions directory
for _help_file in "${SHELL_COMMON}/functions"/*_help.sh; do
    if [ -f "$_help_file" ] && [ "$_help_file" != "${SHELL_COMMON}/functions/my_help.sh" ]; then
        source "$_help_file" 2>/dev/null || true
    fi
done
unset _help_file

# ═══════════════════════════════════════════════════════════════
# Help Registry Initialization (bash/zsh compatible)
# ═══════════════════════════════════════════════════════════════

# Initialize global help descriptions associative array (bash/zsh compatible)
if [ -z "${HELP_DESCRIPTIONS+_}" ]; then
    if [ -n "$BASH_VERSION" ]; then
        declare -gA HELP_DESCRIPTIONS=()
    elif [ -n "$ZSH_VERSION" ]; then
        typeset -gA HELP_DESCRIPTIONS=()
    fi
fi

# Initialize help category registries (bash/zsh compatible)
if [ -z "${HELP_CATEGORIES+_}" ]; then
    if [ -n "$BASH_VERSION" ]; then
        declare -gA HELP_CATEGORIES=()
    elif [ -n "$ZSH_VERSION" ]; then
        typeset -gA HELP_CATEGORIES=()
    fi
fi

if [ -z "${HELP_CATEGORY_MEMBERS+_}" ]; then
    if [ -n "$BASH_VERSION" ]; then
        declare -gA HELP_CATEGORY_MEMBERS=()
    elif [ -n "$ZSH_VERSION" ]; then
        typeset -gA HELP_CATEGORY_MEMBERS=()
    fi
fi

if [ -z "${HELP_COMMAND_TO_CATEGORY+_}" ]; then
    if [ -n "$BASH_VERSION" ]; then
        declare -gA HELP_COMMAND_TO_CATEGORY=()
    elif [ -n "$ZSH_VERSION" ]; then
        typeset -gA HELP_COMMAND_TO_CATEGORY=()
    fi
fi

# ═══════════════════════════════════════════════════════════════
# Help Registry Functions
# ═══════════════════════════════════════════════════════════════

# Register a help function
# Usage: _register_help "function_name" "Description of function"
_register_help() {
    local func_name="$1"
    local description="$2"
    HELP_DESCRIPTIONS["$func_name"]="$description"
}

# Get help description
# Usage: get_help_description "function_name"
get_help_description() {
    local func_name="$1"
    echo "${HELP_DESCRIPTIONS[$func_name]:-No description available}"
}

# ═══════════════════════════════════════════════════════════════
# Helper: Get all help functions (bash/zsh compatible)
# ═══════════════════════════════════════════════════════════════

# Cross-shell function existence check.
# - bash: typeset -f inside a function is reliable
# - zsh:  typeset -f inside a function can shadow/declare a local variable;
#         use whence -w instead which only inspects, never declares
_my_help_is_function() {
    if [ -n "$ZSH_VERSION" ]; then
        # whence -w prints "name: function" for functions
        whence -w "$1" 2>/dev/null | grep -q ": function$"
    else
        declare -f "$1" >/dev/null 2>&1
    fi
}

_get_help_functions() {
    # Prefer bash builtin when available.
    if command -v compgen >/dev/null 2>&1; then
        compgen -A function | { grep 'help$' || true; } | LC_ALL=C sort
        return 0
    fi

    # zsh fallback: compgen is not available unless bashcompinit is enabled.
    if [ -n "$ZSH_VERSION" ]; then
        # NOTE: Use eval to avoid zsh-only syntax being parsed by bash at source time.
        eval 'print -rl -- ${(k)functions}' | { grep 'help$' || true; } | LC_ALL=C sort
        return 0
    fi

    return 0
}

# ═══════════════════════════════════════════════════════════════
# Default Help Descriptions Registration
# ═══════════════════════════════════════════════════════════════

_register_default_help_categories() {
    # Suppress zsh debug output - must be first command
    [ -n "$ZSH_VERSION" ] && { setopt localoptions no_xtrace 2>/dev/null || true; }

    # Category descriptions (values) are used for category detail pages.
    HELP_CATEGORIES[ai]="${HELP_CATEGORIES[ai]:-AI/LLM assistants (Claude, Gemini, Codex, etc.)}"
    HELP_CATEGORIES[cli]="${HELP_CATEGORIES[cli]:-CLI utilities (search, navigation, snippets, shell helpers)}"
    HELP_CATEGORIES[config]="${HELP_CATEGORIES[config]:-Configuration and setup (prompt, certs, package managers)}"
    HELP_CATEGORIES[development]="${HELP_CATEGORIES[development]:-Development tools (Git, Python, package managers, UX)}"
    HELP_CATEGORIES[devops]="${HELP_CATEGORIES[devops]:-DevOps and infrastructure (Docker, proxy, DB, system)}"
    HELP_CATEGORIES[docs]="${HELP_CATEGORIES[docs]:-Documentation and knowledge (dotfiles docs, notes, work logs)}"
    HELP_CATEGORIES[meta]="${HELP_CATEGORIES[meta]:-Help system utilities (category browsing, registration)}"
    HELP_CATEGORIES[system]="${HELP_CATEGORIES[system]:-System tools (directory navigation, opencode)}"

    # Category membership (space-separated topic keys)
    HELP_CATEGORY_MEMBERS[development]="${HELP_CATEGORY_MEMBERS[development]:-git gwt gbr uv py nvm npm bun pp cli ux du psql mytool}"
    HELP_CATEGORY_MEMBERS[devops]="${HELP_CATEGORY_MEMBERS[devops]:-docker dproxy sys proxy ssl mount mysql redis gpu network}"
    HELP_CATEGORY_MEMBERS[ai]="${HELP_CATEGORY_MEMBERS[ai]:-claude cc gemini codex litellm ollama claude_plugins claude_skills_marketplace superpowers}"
    HELP_CATEGORY_MEMBERS[cli]="${HELP_CATEGORY_MEMBERS[cli]:-fzf fd fasd ripgrep pet bat zsh zsh_autosuggestions gc tmux}"
    HELP_CATEGORY_MEMBERS[config]="${HELP_CATEGORY_MEMBERS[config]:-p10k crt apt pip ghostty}"
    HELP_CATEGORY_MEMBERS[docs]="${HELP_CATEGORY_MEMBERS[docs]:-dot show_doc notion work_log work}"
    HELP_CATEGORY_MEMBERS[system]="${HELP_CATEGORY_MEMBERS[system]:-dir opencode}"
    HELP_CATEGORY_MEMBERS[meta]="${HELP_CATEGORY_MEMBERS[meta]:-category register}"

    # Reverse lookup map: topic -> category
    if [ -z "${_HELP_CATEGORY_MAP_BUILT:-}" ]; then
        _HELP_CATEGORY_MAP_BUILT=1

        # Clear any existing mapping to avoid stale entries.
        if [ -n "$BASH_VERSION" ] || [ -n "$ZSH_VERSION" ]; then
            HELP_COMMAND_TO_CATEGORY=()
        fi

        local category
        for category in $(_my_help_get_category_keys 2>/dev/null); do
            local members="${HELP_CATEGORY_MEMBERS[$category]}"
            # FIX: Don't declare topic separately - declare it in the for loop
            for topic in $members; do
                HELP_COMMAND_TO_CATEGORY["$topic"]="$category"
            done
        done
    fi
}

_register_default_help_descriptions() {
    _register_default_help_categories
    _register_default_help_content

    # Only set if not already registered by the module itself
    # Use simple unconditional assignment (modules load first, so they take precedence)
    # This approach works in both bash and zsh
    HELP_DESCRIPTIONS[uv_help]="${HELP_DESCRIPTIONS[uv_help]:-[Development] UV packages and environments}"
    HELP_DESCRIPTIONS[git_help]="${HELP_DESCRIPTIONS[git_help]:-[Development] Git version control shortcuts}"
    HELP_DESCRIPTIONS[gwt_help]="${HELP_DESCRIPTIONS[gwt_help]:-[Development] Git worktree command guide}"
    HELP_DESCRIPTIONS[gbr_help]="${HELP_DESCRIPTIONS[gbr_help]:-[Development] Git feature-branch teardown guide}"
    HELP_DESCRIPTIONS[py_help]="${HELP_DESCRIPTIONS[py_help]:-[Development] Python environments and tooling}"
    HELP_DESCRIPTIONS[dir_help]="${HELP_DESCRIPTIONS[dir_help]:-[System] Directory navigation shortcuts}"
    HELP_DESCRIPTIONS[sys_help]="${HELP_DESCRIPTIONS[sys_help]:-[DevOps] System management helpers}"
    HELP_DESCRIPTIONS[ssh_help]="${HELP_DESCRIPTIONS[ssh_help]:-[DevOps] SSH hosts and file transfer}"
    HELP_DESCRIPTIONS[pp_help]="${HELP_DESCRIPTIONS[pp_help]:-[Development] Python quality tools}"
    HELP_DESCRIPTIONS[cli_help]="${HELP_DESCRIPTIONS[cli_help]:-[Development] Custom project CLIs}"
    HELP_DESCRIPTIONS[du_help]="${HELP_DESCRIPTIONS[du_help]:-[Development] Disk usage analysis}"
    HELP_DESCRIPTIONS[psql_help]="${HELP_DESCRIPTIONS[psql_help]:-[Development] PostgreSQL helpers}"
    HELP_DESCRIPTIONS[cc_help]="${HELP_DESCRIPTIONS[cc_help]:-[AI/LLM] Claude Code CLI basics}"
    HELP_DESCRIPTIONS[claude_help]="${HELP_DESCRIPTIONS[claude_help]:-[AI/LLM] Claude Code + MCP integration}"
    HELP_DESCRIPTIONS[docker_help]="${HELP_DESCRIPTIONS[docker_help]:-[DevOps] Docker commands and aliases}"
    HELP_DESCRIPTIONS[apt_help]="${HELP_DESCRIPTIONS[apt_help]:-[Config] APT package manager}"
    HELP_DESCRIPTIONS[gemini_help]="${HELP_DESCRIPTIONS[gemini_help]:-[AI/LLM] Gemini CLI commands}"
    HELP_DESCRIPTIONS[codex_help]="${HELP_DESCRIPTIONS[codex_help]:-[AI/LLM] Codex CLI commands}"
    HELP_DESCRIPTIONS[dproxy_help]="${HELP_DESCRIPTIONS[dproxy_help]:-[DevOps] Docker corporate proxy}"
    HELP_DESCRIPTIONS[npm_help]="${HELP_DESCRIPTIONS[npm_help]:-[Development] npm package manager}"
    HELP_DESCRIPTIONS[bun_help]="${HELP_DESCRIPTIONS[bun_help]:-[Development] Bun runtime and bunx}"
    HELP_DESCRIPTIONS[nvm_help]="${HELP_DESCRIPTIONS[nvm_help]:-[Development] nvm node versions}"
    HELP_DESCRIPTIONS[litellm_help]="${HELP_DESCRIPTIONS[litellm_help]:-[AI/LLM] LiteLLM proxy and routing}"
    HELP_DESCRIPTIONS[gpu_help]="${HELP_DESCRIPTIONS[gpu_help]:-[DevOps] GPU monitoring (WSL)}"
    HELP_DESCRIPTIONS[ux_help]="${HELP_DESCRIPTIONS[ux_help]:-[Development] UX library usage}"
    HELP_DESCRIPTIONS[gc_help]="${HELP_DESCRIPTIONS[gc_help]:-[CLI] git-crypt encryption}"
    HELP_DESCRIPTIONS[mytool_help]="${HELP_DESCRIPTIONS[mytool_help]:-[Development] Custom tools and scripts}"
    HELP_DESCRIPTIONS[mysql_help]="${HELP_DESCRIPTIONS[mysql_help]:-[DevOps] MySQL service management}"
    HELP_DESCRIPTIONS[redis_help]="${HELP_DESCRIPTIONS[redis_help]:-[DevOps] Redis service management}"
    HELP_DESCRIPTIONS[zsh_help]="${HELP_DESCRIPTIONS[zsh_help]:-[CLI] Zsh shell management}"
    HELP_DESCRIPTIONS[zsh_autosuggestions_help]="${HELP_DESCRIPTIONS[zsh_autosuggestions_help]:-[CLI] zsh-autosuggestions plugin}"
    HELP_DESCRIPTIONS[bat_help]="${HELP_DESCRIPTIONS[bat_help]:-[CLI] bat file viewer}"
    HELP_DESCRIPTIONS[dot_help]="${HELP_DESCRIPTIONS[dot_help]:-[Docs] Dotfiles overview and setup}"
    HELP_DESCRIPTIONS[proxy_help]="${HELP_DESCRIPTIONS[proxy_help]:-[DevOps] Proxy config and diagnostics}"
    HELP_DESCRIPTIONS[network_help]="${HELP_DESCRIPTIONS[network_help]:-[DevOps] Internet connectivity diagnostics}"
    HELP_DESCRIPTIONS[ssl_help]="${HELP_DESCRIPTIONS[ssl_help]:-[DevOps] SSL certificate config and diagnostics}"
    HELP_DESCRIPTIONS[fasd_help]="${HELP_DESCRIPTIONS[fasd_help]:-[CLI] fasd directory jump}"
    HELP_DESCRIPTIONS[fd_help]="${HELP_DESCRIPTIONS[fd_help]:-[CLI] fd file finder}"
    HELP_DESCRIPTIONS[fzf_help]="${HELP_DESCRIPTIONS[fzf_help]:-[CLI] fzf keybindings and usage}"
    HELP_DESCRIPTIONS[pet_help]="${HELP_DESCRIPTIONS[pet_help]:-[CLI] pet snippet manager}"
    HELP_DESCRIPTIONS[ripgrep_help]="${HELP_DESCRIPTIONS[ripgrep_help]:-[CLI] rg (ripgrep) search}"
    HELP_DESCRIPTIONS[p10k_help]="${HELP_DESCRIPTIONS[p10k_help]:-[Config] Powerlevel10k prompt}"
    HELP_DESCRIPTIONS[crt_help]="${HELP_DESCRIPTIONS[crt_help]:-[Config] CA certificate management}"
    HELP_DESCRIPTIONS[pip_help]="${HELP_DESCRIPTIONS[pip_help]:-[Config] pip config and diagnostics}"
    HELP_DESCRIPTIONS[mount_help]="${HELP_DESCRIPTIONS[mount_help]:-[DevOps] Mount helpers}"
    HELP_DESCRIPTIONS[claude_plugins_help]="${HELP_DESCRIPTIONS[claude_plugins_help]:-[AI/LLM] Claude plugins setup}"
    HELP_DESCRIPTIONS[claude_skills_marketplace_help]="${HELP_DESCRIPTIONS[claude_skills_marketplace_help]:-[AI/LLM] Skills marketplace system}"
    HELP_DESCRIPTIONS[superpowers_help]="${HELP_DESCRIPTIONS[superpowers_help]:-[AI/LLM] Superpowers plugin skills reference}"
    HELP_DESCRIPTIONS[notion_help]="${HELP_DESCRIPTIONS[notion_help]:-[Docs] Notion integration}"
    HELP_DESCRIPTIONS[ollama_help]="${HELP_DESCRIPTIONS[ollama_help]:-[AI/LLM] Ollama local models}"
    HELP_DESCRIPTIONS[tmux_help]="${HELP_DESCRIPTIONS[tmux_help]:-[CLI] tmux terminal multiplexer}"
    HELP_DESCRIPTIONS[ghostty_help]="${HELP_DESCRIPTIONS[ghostty_help]:-[Config] Ghostty terminal config}"
    HELP_DESCRIPTIONS[opencode_help]="${HELP_DESCRIPTIONS[opencode_help]:-[System] OpenCode CLI setup}"
    HELP_DESCRIPTIONS[show_doc_help]="${HELP_DESCRIPTIONS[show_doc_help]:-[Docs] Documentation viewer}"
    HELP_DESCRIPTIONS[category_help]="${HELP_DESCRIPTIONS[category_help]:-[Meta] Browse help categories}"
    HELP_DESCRIPTIONS[register_help]="${HELP_DESCRIPTIONS[register_help]:-[Meta] Register help descriptions}"
    HELP_DESCRIPTIONS[work_log_help]="${HELP_DESCRIPTIONS[work_log_help]:-[Docs] Work log tracking}"
    HELP_DESCRIPTIONS[work_help]="${HELP_DESCRIPTIONS[work_help]:-[Docs] Work management}"
}

# ═══════════════════════════════════════════════════════════════
# Main Help Functions
# ═══════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════
# Category helpers (bash/zsh compatible)
# ═══════════════════════════════════════════════════════════════

_my_help_to_lower() {
    printf "%s" "$1" | tr '[:upper:]' '[:lower:]'
}

_my_help_get_category_keys() {
    if [ -n "$BASH_VERSION" ]; then
        # NOTE: Use eval to avoid zsh parsing bash-only parameter expansion at source time.
        eval 'for k in "${!HELP_CATEGORIES[@]}"; do printf "%s\n" "$k"; done' | LC_ALL=C sort
        return 0
    fi

    if [ -n "$ZSH_VERSION" ]; then
        eval 'print -rl -- ${(k)HELP_CATEGORIES}' | LC_ALL=C sort
        return 0
    fi

    return 0
}

_my_help_category_label() {
    case "$1" in
        ai) printf "%s" "AI/LLM" ;;
        cli) printf "%s" "CLI Utilities" ;;
        config) printf "%s" "Configuration" ;;
        development) printf "%s" "Development" ;;
        devops) printf "%s" "DevOps/Infra" ;;
        docs) printf "%s" "Documentation" ;;
        meta) printf "%s" "Meta/Help" ;;
        system) printf "%s" "System/Tools" ;;
        *) printf "%s" "$1" ;;
    esac
}

_my_help_topic_description() {
    local topic="$1"

    local key="${topic}_help"
    local desc="${HELP_DESCRIPTIONS[$key]}"

    if [ -z "$desc" ]; then
        local dash_key
        dash_key=$(printf "%s" "$key" | tr '_' '-')
        desc="${HELP_DESCRIPTIONS[$dash_key]}"
    fi

    if [ -z "$desc" ]; then
        desc="No description available"
    fi

    printf "%s" "$desc"
}

_my_help_get_category_matches() {
    local raw="$1"
    local token
    token=$(_my_help_to_lower "$raw")

    # Exact match always wins. Prefix matching is only enabled for 3+ chars to
    # reduce collisions with real topics (e.g., "do" vs "docker").
    local category
    for category in $(_my_help_get_category_keys 2>/dev/null); do
        if [ "$category" = "$token" ]; then
            printf "%s\n" "$category"
            return 0
        fi
    done

    if [ "${#token}" -lt 3 ]; then
        return 0
    fi

    for category in $(_my_help_get_category_keys 2>/dev/null); do
        case "$category" in
            "$token"*) printf "%s\n" "$category" ;;
        esac
    done
}

_my_help_show_categories() {
    # Suppress zsh debug output - must be first command
    [ -n "$ZSH_VERSION" ] && { setopt localoptions no_xtrace no_warn_create_global 2>/dev/null || true; }

    ux_section "Categories"
    ux_table_header "Category" "Topics"

    local category
    for category in $(_my_help_get_category_keys 2>/dev/null); do
        local members="${HELP_CATEGORY_MEMBERS[$category]}"

        local preview=""
        local shown=0
        local total=0

        # FIX: Don't declare topic/label separately in zsh - causes debug output
        for topic in $members; do
            total=$((total + 1))
            if [ "$shown" -lt 5 ]; then
                if [ -n "$preview" ]; then
                    preview="${preview}, ${topic}"
                else
                    preview="${topic}"
                fi
                shown=$((shown + 1))
            fi
        done

        if [ "$total" -gt "$shown" ]; then
            preview="${preview}, +$((total - shown)) more"
        fi

        # FIX: Suppress zsh debug output - redirect stdout during local declaration
        { local label; } >/dev/null 2>&1
        label=$(_my_help_category_label "$category")
        ux_table_row "${label} (${total})" "$preview"
    done
}

_my_help_show_category() {
    # Suppress zsh debug output - must be first command
    [ -n "$ZSH_VERSION" ] && { setopt localoptions no_xtrace no_warn_create_global 2>/dev/null || true; }

    local category="$1"

    local members="${HELP_CATEGORY_MEMBERS[$category]}"
    if [ -z "$members" ]; then
        ux_error "Category '$category' not found."
        return 1
    fi

    # FIX: Suppress zsh debug output - redirect stdout during local declaration
    { local label; } >/dev/null 2>&1
    label=$(_my_help_category_label "$category")

    ux_header "Help Category: ${label}"
    ux_info "${HELP_CATEGORIES[$category]}"

    # FIX: Don't declare topic separately - it causes zsh debug output
    local total=0
    for topic in $members; do
        total=$((total + 1))
    done

    ux_section "Topics (${total})"
    ux_table_header "Topic" "Description"

    for topic in $members; do
        # FIX: Combine declaration and assignment
        local desc
        desc=$(_my_help_topic_description "$topic")
        ux_table_row "$topic" "$desc"
    done

    ux_divider
    ux_info "Run: my-help <topic> [args] (example: my-help git stash)"
    ux_bullet "Tip: Use dash form too (example: git-help)"

    if [ "$category" = "cli" ]; then
        ux_bullet "Custom project CLIs: my-help cli-help"
    fi

    return 0
}

# Internal: Show all available commands
_my_help_show_all() {
    ux_header "Dotfiles Help Functions"

    # In zsh, users may enable strict options (e.g., noclobber) that break temp-file
    # redirections. Make these option changes local to this function only.
    if [ -n "$ZSH_VERSION" ]; then
        setopt localoptions clobber 2>/dev/null || true
    fi

    # Collect help functions (using temp file instead of array)
    local tmp_dir="${TMPDIR:-/tmp}"
    local temp_funcs
    local temp_raw
    local temp_sorted

    if command -v mktemp >/dev/null 2>&1; then
        temp_funcs=$(mktemp "${tmp_dir%/}/my_help_funcs.XXXXXX" 2>/dev/null) || temp_funcs="${tmp_dir%/}/.help_funcs_$$"
        temp_raw=$(mktemp "${tmp_dir%/}/my_help_raw.XXXXXX" 2>/dev/null) || temp_raw="${tmp_dir%/}/.help_raw_$$"
        temp_sorted=$(mktemp "${tmp_dir%/}/my_help_sorted.XXXXXX" 2>/dev/null) || temp_sorted="${tmp_dir%/}/.help_sorted_$$"
    else
        temp_funcs="${tmp_dir%/}/.help_funcs_$$"
        temp_raw="${tmp_dir%/}/.help_raw_$$"
        temp_sorted="${tmp_dir%/}/.help_sorted_$$"
    fi

    # Ensure clean slate even under noclobber.
    rm -f "$temp_funcs" "$temp_raw" "$temp_sorted" 2>/dev/null || true
    : > "$temp_funcs"
    : > "$temp_raw"

    _get_help_functions > "$temp_raw"

    while IFS= read -r func; do
        # Extract function name (before '(' or first space)
        local func_name="${func%%[( ]*}"

        # Include functions ending with 'help' (both dash and underscore)
        # Exclude: my-help, run-help, _* (internal functions)
        case "$func_name" in
            *help)
                case "$func_name" in
                    my-help|run-help) ;;
                    _*) ;;
                    *)
                        # Normalize to dash format for display
                        local display_name=""
                        display_name=$(echo "$func_name" | tr '_' '-')
                        echo "$display_name" >> "$temp_funcs"
                        ;;
                esac
                ;;
        esac
    done < "$temp_raw"

    rm -f "$temp_raw"

    # Remove duplicates and sort
    local unique_count
    unique_count=$(sort -u "$temp_funcs" | wc -l)

    # Render hierarchical help categories (no flat list).
    _my_help_show_categories

    ux_divider

    ux_section "Popular Topics"
    ux_table_header "Topic" "Description"
    local desc
    desc=$(_my_help_topic_description git)
    ux_table_row "git" "$desc"
    desc=$(_my_help_topic_description docker)
    ux_table_row "docker" "$desc"
    desc=$(_my_help_topic_description claude)
    ux_table_row "claude" "$desc"
    desc=$(_my_help_topic_description uv)
    ux_table_row "uv" "$desc"
    desc=$(_my_help_topic_description fzf)
    ux_table_row "fzf" "$desc"

    ux_divider

    ux_section "Navigation"
    ux_bullet "my-help                 - Show categories"
    ux_bullet "my-help <category>      - Show a category (example: my-help ai)"
    ux_bullet "my-help <topic> [args]  - Show a topic (example: my-help git stash)"
    ux_bullet "category-help           - Browse categories"
    ux_bullet "register-help           - How to add new topics"

    ux_info "Discovered help functions: ${unique_count}"

    # Warn if there are help functions not covered by the category registry.
    sort -u "$temp_funcs" > "$temp_sorted"
    local uncategorized=""
    local uncategorized_count=0
    local func
    while IFS= read -r func; do
        local base="$func"
        case "$base" in
            *-help) base="${base%-help}" ;;
        esac
        base=$(printf "%s" "$base" | tr '-' '_')

        if [ -z "${HELP_COMMAND_TO_CATEGORY[$base]}" ]; then
            uncategorized_count=$((uncategorized_count + 1))
            if [ "$uncategorized_count" -le 10 ]; then
                if [ -n "$uncategorized" ]; then
                    uncategorized="${uncategorized}, ${base}"
                else
                    uncategorized="${base}"
                fi
            fi
        fi
    done < "$temp_sorted"

    if [ "$uncategorized_count" -gt 0 ]; then
        ux_warning "Uncategorized help topics detected (${uncategorized_count})"
        ux_bullet "Add them to HELP_CATEGORY_MEMBERS[...] in my_help.sh"
        ux_bullet "Examples: ${uncategorized}"
    fi

    rm -f "$temp_sorted" "$temp_funcs" 2>/dev/null || true

    return 0
}

_my_help_summary() {
    ux_info "Usage: my-help [topic|category|section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "categories: ai | cli | config | development | devops | docs | meta | system"
    ux_bullet_sub "popular: git | docker | claude | uv | fzf"
    ux_bullet_sub "navigation: my-help <topic> [args] / my-help <category>"
    ux_bullet_sub "details: my-help <section>  (example: my-help categories)"
}

_my_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "categories"
    ux_bullet_sub "popular"
    ux_bullet_sub "navigation"
}

_my_help_show_popular() {
    ux_section "Popular Topics"
    ux_table_header "Topic" "Description"
    local desc
    desc=$(_my_help_topic_description git)
    ux_table_row "git" "$desc"
    desc=$(_my_help_topic_description docker)
    ux_table_row "docker" "$desc"
    desc=$(_my_help_topic_description claude)
    ux_table_row "claude" "$desc"
    desc=$(_my_help_topic_description uv)
    ux_table_row "uv" "$desc"
    desc=$(_my_help_topic_description fzf)
    ux_table_row "fzf" "$desc"
}

_my_help_show_navigation() {
    ux_section "Navigation"
    ux_bullet "my-help <category>      - Show a category (example: my-help ai)"
    ux_bullet "my-help <topic> [args]  - Show a topic (example: my-help git stash)"
    ux_bullet "category-help           - Browse categories"
    ux_bullet "register-help           - How to add new topics"
}

_my_help_section_rows() {
    case "$1" in
        categories)
            _my_help_show_categories
            ;;
        popular)
            _my_help_show_popular
            ;;
        navigation)
            _my_help_show_navigation
            ;;
        *)
            ux_error "Unknown my-help section: $1"
            ux_info "Try: my-help --list"
            return 1
            ;;
    esac
}

# Main help function - displays all registered commands or specific help
my_help_impl() {
    local rc=0

    # Keep output clean even when users enable tracing (set -x / setopt xtrace).
    local _my_help_restore_xtrace=0
    if [ -n "$BASH_VERSION" ]; then
        case "$-" in
            *x*)
                _my_help_restore_xtrace=1
                set +x
                ;;
        esac
    elif [ -n "$ZSH_VERSION" ]; then
        if [[ -o xtrace ]]; then
            _my_help_restore_xtrace=1
            unsetopt xtrace
        fi
    fi

    # Register default descriptions (only once)
    if [ -z "${_HELP_DEFAULTS_REGISTERED}" ]; then
        _register_default_help_descriptions
        _HELP_DEFAULTS_REGISTERED=1
    fi

    case "${1:-}" in
        ""|-h|--help|help)
            _my_help_summary
            rc=$?
            ;;
        --list|list|section|sections)
            _my_help_list_sections
            rc=$?
            ;;
        --all|all)
            _my_help_show_all
            rc=$?
            ;;
        categories|popular|navigation)
            _my_help_section_rows "$1"
            rc=$?
            ;;
        *)
        # If argument is provided, show specific help for that command
        local cmd_name="$1"
        shift || true

        # Category browsing: exact or unique prefix match (case-insensitive).
        local cat_matches=0
        local resolved_category=""
        local match
        for match in $(_my_help_get_category_matches "$cmd_name"); do
            cat_matches=$((cat_matches + 1))
            resolved_category="$match"
        done

        if [ "$cat_matches" -eq 1 ]; then
            _my_help_show_category "$resolved_category"
            rc=$?
        elif [ "$cat_matches" -gt 1 ]; then
            local suggestions=""
            for match in $(_my_help_get_category_matches "$cmd_name"); do
                if [ -n "$suggestions" ]; then
                    suggestions="${suggestions} ${match}"
                else
                    suggestions="$match"
                fi
            done
            ux_error "Category '$cmd_name' is ambiguous."
            ux_bullet "Try one of: $suggestions"
            rc=1
        else
            # Prefer canonical underscore helpers to avoid alias-only lookups (bash cannot
            # execute aliases when the name comes from parameter expansion)
            local normalized
            normalized=$(echo "$cmd_name" | tr '-' '_')
            local helper_name="$normalized"
            case "$helper_name" in
                *_help) ;;
                *) helper_name="${helper_name}_help" ;;
            esac

            if _my_help_is_function "$helper_name"; then
                "$helper_name" "$@"
                rc=$?
            else
                # Some modules only expose a dash-style function (e.g., apt-help). Only
                # call dash-style names if they resolve to actual *functions* — not aliases
                # that point to binaries (e.g., codex-help='codex --help').
                case "$cmd_name" in
                    *[!A-Za-z0-9_-]*)
                        rc=1
                        ;;
                    *)
                        local dash_name
                        dash_name=$(echo "$cmd_name" | tr '_' '-')
                        case "$dash_name" in
                            *-help) ;;
                            *) dash_name="${dash_name}-help" ;;
                        esac
                        if _my_help_is_function "$dash_name"; then
                            "$dash_name" "$@"
                            rc=$?
                        elif _my_help_is_function "$cmd_name"; then
                            "$cmd_name" "$@"
                            rc=$?
                        elif type "$cmd_name" >/dev/null 2>&1; then
                            # Try calling command with --help
                            "$cmd_name" --help 2>/dev/null || {
                                ux_info "Help for '${cmd_name}' not available."
                                ux_bullet "Try: ${UX_BOLD}$cmd_name --help${UX_RESET} or ${UX_BOLD}$cmd_name -h${UX_RESET}"
                            }
                            rc=0
                        else
                            ux_error "Category or topic '$cmd_name' not found."
                            local categories=""
                            local category
                            for category in $(_my_help_get_category_keys 2>/dev/null); do
                                if [ -n "$categories" ]; then
                                    categories="${categories} ${category}"
                                else
                                    categories="$category"
                                fi
                            done
                            ux_bullet "Try: my-help (category overview)"
                            ux_bullet "Categories: $categories"
                            rc=1
                        fi
                        ;;
                esac
            fi
        fi
            ;;
    esac

    if [ "$_my_help_restore_xtrace" = "1" ]; then
        if [ -n "$BASH_VERSION" ]; then
            set -x
        elif [ -n "$ZSH_VERSION" ]; then
            setopt xtrace
        fi
    fi

    return "$rc"
}

# ═══════════════════════════════════════════════════════════════
# Help Content (Detailed information for topics)
# ═══════════════════════════════════════════════════════════════

_register_default_help_content() {
    # Initialize HELP_CONTENT as associative array (if not already)
    if [ -n "$BASH_VERSION" ]; then
        declare -gA HELP_CONTENT 2>/dev/null || true
    elif [ -n "$ZSH_VERSION" ]; then
        typeset -gA HELP_CONTENT 2>/dev/null || true
    fi

    # Git content
    HELP_CONTENT[git]="Git is a distributed version control system.
Key Features:
- Distributed repository model
- Branching and merging
- Fast performance
- Cryptographic history integrity
- Staging area for selective commits

Common Workflows:
- Feature branches for isolation
- Commit messages for documentation
- Rebase for clean history
- Tags for releases
- Hooks for automation"

    # Docker content
    HELP_CONTENT[docker]="Docker is a containerization platform.
Benefits:
- Lightweight virtualization
- Environment consistency
- Easy deployment
- Container orchestration ready
- Multi-platform support
- Image layering for efficiency

Concepts:
- Images: Blueprints for containers
- Containers: Running instances
- Registries: Image storage
- Volumes: Persistent data
- Networks: Container communication"

    # Python content
    HELP_CONTENT[py]="Python is a high-level programming language.
Strengths:
- Readable and expressive syntax
- Extensive standard library
- Large ecosystem of packages
- Dynamic typing
- Support for multiple paradigms
- Strong community support

Popular Frameworks:
- Django: Web framework
- FastAPI: Modern async API framework
- NumPy: Numerical computing
- Pandas: Data analysis
- Matplotlib: Data visualization
- PyTorch: Machine learning"
}

_register_default_help_content

# ═══════════════════════════════════════════════════════════════
# Initial Help Descriptions
# ═══════════════════════════════════════════════════════════════

# Register built-in help functions (can be overridden)
HELP_DESCRIPTIONS[my_help_impl]="Main help system"

# Alias for my-help format (using dash instead of underscore)
alias my-help='my_help_impl'

# zsh compatibility: when `setopt no_aliases` is enabled, dash-style aliases won't expand.
# Provide a narrow `command_not_found_handler` shim so typing `my-help` still works.
if [ -n "$ZSH_VERSION" ]; then
    if [ -z "${_DOTFILES_MY_HELP_CNF_INSTALLED:-}" ]; then
        _DOTFILES_MY_HELP_CNF_INSTALLED=1

        # Preserve any existing handler.
        if typeset -f command_not_found_handler >/dev/null 2>&1; then
            eval 'functions[_dotfiles_prev_command_not_found_handler]=$functions[command_not_found_handler]'
        fi

        command_not_found_handler() {
            local cmd_name="$1"
            shift || true

            if [ "$cmd_name" = "my-help" ]; then
                my_help_impl "$@"
                return $?
            fi

            if [ "$cmd_name" = "category-help" ]; then
                category_help "$@"
                return $?
            fi

            if [ "$cmd_name" = "register-help" ]; then
                register_help "$@"
                return $?
            fi

            if [ "$cmd_name" = "gwt-help" ]; then
                gwt_help "$@"
                return $?
            fi

            if typeset -f _dotfiles_prev_command_not_found_handler >/dev/null 2>&1; then
                _dotfiles_prev_command_not_found_handler "$cmd_name" "$@"
                return $?
            fi

            print -u2 -- "zsh: command not found: ${cmd_name}"
            return 127
        }
    fi
fi
