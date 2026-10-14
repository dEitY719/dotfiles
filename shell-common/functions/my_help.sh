#!/bin/sh
# shellcheck shell=bash
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac
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

# The registry (arrays + _register_help) normally comes from dotfiles_load_all;
# load it here when my_help.sh is sourced on its own (tests, preview helper).
if ! command -v _register_func >/dev/null 2>&1; then
    . "${SHELL_COMMON}/util/help_registry.sh"
fi

# Source all *_help.sh files from the functions directory.
# MY_HELP_SKIP_TOPIC_SOURCES=1 loads the registry and renderers without the
# ~380KB of topic files. Only the fzf preview helper sets it, and only for
# alias/func rows: those render from ux_lib alone, and fzf re-runs the helper
# on every cursor move.
if [ -z "${MY_HELP_SKIP_TOPIC_SOURCES-}" ]; then
    for _help_file in "${SHELL_COMMON}/functions"/*_help.sh; do
        if [ -f "$_help_file" ] && [ "$_help_file" != "${SHELL_COMMON}/functions/my_help.sh" ]; then
            source "$_help_file" 2>/dev/null || true
        fi
    done
    unset _help_file
fi

# ═══════════════════════════════════════════════════════════════
# Help Registry Lookups (registry itself: util/help_registry.sh)
# ═══════════════════════════════════════════════════════════════

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
# Category member iteration
# ═══════════════════════════════════════════════════════════════

# One member per line, sorted: members arrive in file-load order now that each
# *_help.sh registers itself (#2135), so sorting keeps category pages stable.
# The command substitution at every call site also forces word splitting in
# zsh, which a bare "$members" expansion does not do.
_my_help_split_members() {
    printf '%s\n' "$1" | tr ' ' '\n' | LC_ALL=C sort
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
        for topic in $(_my_help_split_members "$members"); do
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

    # FIX: Suppress zsh debug output - redirect stdout during local declaration.
    # `desc` is declared here too: a bare "local desc" inside the loop below
    # makes zsh echo "desc=..." on every iteration after the first.
    { local label desc; } >/dev/null 2>&1
    label=$(_my_help_category_label "$category")

    ux_header "Help Category: ${label}"
    ux_info "${HELP_CATEGORIES[$category]}"

    # FIX: Don't declare topic separately - it causes zsh debug output
    local total=0
    for topic in $(_my_help_split_members "$members"); do
        total=$((total + 1))
    done

    ux_section "Topics (${total})"
    ux_table_header "Topic" "Description"

    for topic in $(_my_help_split_members "$members"); do
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

# Internal: enumerate discovered help-function names in dash form, one per
# line. Shared filter rule for _my_help_show_all and _my_help_search — keep
# the match/exclude logic here so both stay in sync.
_my_help_enumerate_topic_names() {
    local func
    while IFS= read -r func; do
        # Extract function name (before '(' or first space)
        local func_name="${func%%[( ]*}"
        # The `_*` arm below already excludes the adapter's internal helpers
        # (_help_std_orig_*, _help_std_summary_*, _help_std_rows_*,
        # _help_std_full_*, _help_std_list_*): they end in the topic name, and
        # only today's leading-underscore convention keeps them out of the
        # `*help` match.
        case "$func_name" in
            my-help|run-help|_*) ;;
            *help)
                # Normalize to dash format for display
                printf '%s\n' "$(printf "%s" "$func_name" | tr '_' '-')"
                ;;
        esac
    done << EOF
$(_get_help_functions)
EOF
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
    local temp_sorted

    if command -v mktemp >/dev/null 2>&1; then
        temp_funcs=$(mktemp "${tmp_dir%/}/my_help_funcs.XXXXXX" 2>/dev/null) || temp_funcs="${tmp_dir%/}/.help_funcs_$$"
        temp_sorted=$(mktemp "${tmp_dir%/}/my_help_sorted.XXXXXX" 2>/dev/null) || temp_sorted="${tmp_dir%/}/.help_sorted_$$"
    else
        temp_funcs="${tmp_dir%/}/.help_funcs_$$"
        temp_sorted="${tmp_dir%/}/.help_sorted_$$"
    fi

    # Ensure clean slate even under noclobber.
    rm -f "$temp_funcs" "$temp_sorted" 2>/dev/null || true

    _my_help_enumerate_topic_names > "$temp_funcs"

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
        ux_bullet "Give them a category (3rd arg of _register_help) in my_help.sh"
        ux_bullet "Examples: ${uncategorized}"
    fi

    rm -f "$temp_sorted" "$temp_funcs" 2>/dev/null || true

    return 0
}

# ═══════════════════════════════════════════════════════════════
# Alias Search Index (issue #1261)
# ═══════════════════════════════════════════════════════════════
#
# The `*_help.sh` topics answer "what is csm?" but not "what was that one
# alias called?" — there are two orders of magnitude more aliases than
# topics. The index below widens `my-help search` to every `alias name=...`
# definition in the repo (~460) so name recall works at the alias level too.
#
# Index record (tab-separated, 5 fields):
#   1 name        alias name                    (fzf column 1)
#   2 desc        trailing `# comment`, else `relpath:line`   (fzf column 2)
#   3 kind        literal "alias" — tells _my_help_search how to render it
#   4 location    relpath:line
#   5 definition  the alias body, quotes and trailing comment stripped
#
# Fields 3-5 are hidden from fzf (`--with-nth=1,2`) and read back off the
# selected line, so no second lookup is needed after picking an entry.
#
# A name may legitimately appear more than once: 12 alias names in this repo
# are defined in two places with *different* bodies (`llm-help` is
# `litellm_help` in ai_tools_help.sh and `ollama_help` in
# help_system_aliases.sh). Collapsing those to one row would have to pick a
# winner, and the only correct winner is whichever file the shell sourced
# last — which this file-level scan cannot know. An arbitrary pick would
# actively lie about what the alias resolves to, so every distinct
# (name, location, definition) triple is kept and the conflict shows up as
# two adjacent rows in the picker. `sort -u` therefore dedupes whole records
# only, never on the name key.

# Measured on ext4 the cold scan and the cached read are within ~1ms of each
# other at ~470 aliases, so the cache is not a local speed win — it is
# insurance for the trees that live on a slow mount (WSL /mnt, NFS home,
# AV-scanned corporate disk), where a 105-file recursive grep costs orders of
# magnitude more than one file read. Same 24h TTL as csm's manifest cache.
MY_HELP_ALIAS_CACHE_MAX_AGE="${MY_HELP_ALIAS_CACHE_MAX_AGE:-86400}"  # 24 hours

# Internal: resolve the alias-index cache path. Computed per call (not frozen
# at source time) so a test that re-points HOME/XDG_CACHE_HOME after sourcing
# still lands in its own sandbox. Override wholesale with MY_HELP_ALIAS_CACHE_PATH.
_my_help_alias_cache_path() {
    if [ -n "${MY_HELP_ALIAS_CACHE_PATH-}" ]; then
        printf '%s\n' "$MY_HELP_ALIAS_CACHE_PATH"
        return 0
    fi
    printf '%s\n' "${XDG_CACHE_HOME:-${HOME}/.cache}/dotfiles/my-help-alias-index.tsv"
}

# Internal: scan the repo for alias definitions and emit index records.
# Writes nothing and returns 1 when the tree is missing or the scan finds
# nothing — the caller then falls back to topics-only (issue #1261 Error Cases).
_my_help_build_alias_index() {
    local root
    root="${DOTFILES_ROOT:-${SHELL_COMMON%/shell-common}}"
    [ -n "$root" ] && [ -d "$root" ] || return 1

    local scanned
    # --include keeps prose out of the index: shell-common/README.md opens a
    # line with "alias and function defined within." which the regex would
    # otherwise happily accept as an alias named "and".
    scanned=$(
        grep -rnE '^alias [^ =]+=' \
            --include='*.sh' --include='*.bash' --include='*.zsh' \
            "$root/bash" "$root/zsh" "$root/shell-common" 2>/dev/null |
            awk -v root="${root}/" '
            function trim(s) {
                sub(/^[ \t]+/, "", s)
                sub(/[ \t]+$/, "", s)
                return s
            }
            {
                # grep -n emits <path>:<line>:<content>. Anchor on the first
                # ":<digits>:" rather than the first two colons — splitting on
                # bare colons hands back a path of "a" and a line number of
                # "b/c.sh" the moment a parent directory contains one
                # (PR #1266 review).
                if (!match($0, /:[0-9]+:/)) next
                path = substr($0, 1, RSTART - 1)
                lineno = substr($0, RSTART + 1, RLENGTH - 2)
                body = substr($0, RSTART + RLENGTH)
                if (substr(body, 1, 6) != "alias ") next

                kv = substr(body, 7)
                eq = index(kv, "=")
                if (eq < 2) next
                name = substr(kv, 1, eq - 1)
                expansion = substr(kv, eq + 1)

                # Split the trailing "# comment" off the body. When the value is
                # quoted only a "#" past the closing quote counts, otherwise
                # `alias x='"'"'echo #1'"'"'` would lose everything after the hash.
                q = substr(expansion, 1, 1)
                defn = expansion
                tail = ""
                ce = 0
                if (q == "\"") {
                    # Inside double quotes a backslash escapes the next
                    # character, so `alias x="echo \"hi\""` must not terminate
                    # on the escaped quote (PR #1266 review). No alias in this
                    # repo is double-quoted today; this keeps the first one
                    # that is from being silently truncated.
                    for (i = 2; i <= length(expansion); i++) {
                        c = substr(expansion, i, 1)
                        if (c == "\\") { i++; continue }
                        if (c == q) { ce = i; break }
                    }
                } else if (q == "'"'"'") {
                    # POSIX single quotes admit no escape at all — the very
                    # next quote always closes the string, so a plain index()
                    # is exact here rather than a heuristic.
                    p = index(substr(expansion, 2), q)
                    if (p > 0) ce = p + 1
                }
                if (ce > 0) {
                    defn = substr(expansion, 2, ce - 2)
                    tail = substr(expansion, ce + 1)
                } else if (q != "'"'"'" && q != "\"") {
                    si = index(expansion, " ")
                    if (si > 0) {
                        defn = substr(expansion, 1, si - 1)
                        tail = substr(expansion, si)
                    }
                }

                note = ""
                hi = index(tail, "#")
                if (hi > 0) note = trim(substr(tail, hi + 1))

                defn = trim(defn)

                # Drop the dash-form aliases that only re-expose a help topic
                # (`agy-help` -> `agy_help`). The topic stream already lists
                # every one of them, with a real description instead of a
                # file:line — keeping both would duplicate ~72 picker rows and
                # let the user land on "definition: agy_help" instead of the
                # actual help text. Aliases that point elsewhere (`doc-help`
                # -> `show_doc_help`) are genuinely new names, so they stay.
                if (name ~ /-help$/) {
                    canonical = name
                    gsub(/-/, "_", canonical)
                    if (defn == canonical) next
                }

                rel = path
                if (index(rel, root) == 1) rel = substr(rel, length(root) + 1)

                loc = rel ":" lineno
                desc = (note != "") ? note : loc
                printf "%s\t%s\talias\t%s\t%s\n", name, desc, loc, defn
            }' |
            LC_ALL=C sort -u
    )

    [ -n "$scanned" ] || return 1
    printf '%s\n' "$scanned"
}

# Internal: true (0) when the cache needs rebuilding.
_my_help_alias_cache_stale() {
    local cache="$1"

    # Missing, empty, or unreadable — all "rebuild".
    [ -s "$cache" ] && [ -r "$cache" ] || return 0

    # Truncated or hand-mangled file: every valid record is 5 fields with
    # "alias" in the kind column. Checking only the first line would serve a
    # TSV truncated mid-write for the full TTL (PR #1266 review), so validate
    # every record — one awk pass over ~400 lines, and fewer forks than the
    # head|grep pair it replaces.
    awk -F'\t' 'NF != 5 || $3 != "alias" { exit 1 }' "$cache" 2>/dev/null || return 0

    local mtime
    if [ "$(uname -s 2>/dev/null)" = "Darwin" ]; then
        mtime=$(stat -f %m "$cache" 2>/dev/null)
    else
        mtime=$(stat -c %Y "$cache" 2>/dev/null)
    fi
    [ -n "$mtime" ] || return 0

    local age
    age=$(( $(date +%s) - mtime ))
    [ "$age" -le "${MY_HELP_ALIAS_CACHE_MAX_AGE:-86400}" ] || return 0
    return 1
}

# Internal: emit the alias index, rebuilding the cache when stale.
# Returns 1 (and emits nothing) if the scan came up empty — never fatal.
_my_help_alias_index() {
    # Users may run with noclobber set; keep the temp-file redirection below
    # working without leaking the option change (same guard as _my_help_show_all).
    if [ -n "$ZSH_VERSION" ]; then
        setopt localoptions clobber 2>/dev/null || true
    fi

    local cache
    cache=$(_my_help_alias_cache_path)

    if ! _my_help_alias_cache_stale "$cache"; then
        cat "$cache" 2>/dev/null
        return 0
    fi

    local fresh
    fresh=$(_my_help_build_alias_index) || return 1

    # Write via a temp file + mv so a concurrent reader never sees a half-built
    # index. An unwritable cache dir is not an error — just skip persisting.
    local dir tmp
    dir=$(dirname "$cache")
    if mkdir -p "$dir" 2>/dev/null; then
        tmp="${cache}.$$"
        # A failed write or mv just means no cache this round. The unconditional
        # rm covers both failure paths and is a no-op once mv consumed the temp.
        printf '%s\n' "$fresh" > "$tmp" 2>/dev/null &&
            mv -f "$tmp" "$cache" 2>/dev/null
        rm -f "$tmp" 2>/dev/null
    fi

    printf '%s\n' "$fresh"
    return 0
}

# Internal: render one alias index record picked out of fzf.
# Also renders `func` records (#1740): the schema is identical, only the
# heading differs — a second renderer would be the same code with one word
# changed.
_my_help_show_alias_entry() {
    local record="$1"
    local name desc location defn kind label tab
    # One `read` rather than five `printf | cut` pipelines: fzf re-runs the
    # preview (and therefore this renderer) on every cursor move.
    tab=$(printf '\t')
    IFS="$tab" read -r name desc kind location defn <<EOF
$record
EOF

    case "$kind" in
        func) label="Function" ;;
        *) label="Alias" ;;
    esac

    ux_section "${label}: ${name}"
    ux_bullet "definition: ${defn}"
    # Field 4 is always populated for an alias record (see the record layout
    # above), so no emptiness guard is needed here.
    ux_bullet "source:     ${location}"
    # desc doubles as the location when the alias carries no comment; only
    # print it when it is a real note.
    if [ -n "$desc" ] && [ "$desc" != "$location" ]; then
        ux_bullet "note:       ${desc}"
    fi
    return 0
}

# ═══════════════════════════════════════════════════════════════
# Public function candidates (issue #1740, Phase 3a)
# ═══════════════════════════════════════════════════════════════
#
# Registry, not a full source scan. Scanning every `name() {` in bash/, zsh/
# and shell-common/ yields 578 names and a scan narrowed to the documented
# "utility function" home (shell-common/functions/*.sh) still yields 111 —
# both dominated by internal helpers that happen to lack the `_` prefix
# (aicron_crontab_write, devx_pr_review_all_parse, ...). The picker would drown
# in them, which is exactly the noise Phase 3b was gated behind. Only what a
# user actually types is registered — each defining file ends with a
# `_register_func <name> "<desc>"` row (util/help_registry.sh, #2135);
# locations are resolved from the source tree at read time so a moved
# definition cannot go stale here.
#
# Rules the registry must keep (pinned by test P10, which reads the emitted
# index rather than this list): no `_`-prefixed names, no `*_help` names —
# those are already `topic` candidates and the topic row carries a real
# description.
_my_help_func_registry() {
    # name <TAB> description, sorted
    local name
    if [ -n "${BASH_VERSION-}" ]; then
        # eval: zsh must not parse bash-only ${!array[@]} at source time.
        eval 'for name in "${!HELP_FUNCS[@]}"; do printf "%s\t%s\n" "$name" "${HELP_FUNCS[$name]}"; done'
    elif [ -n "${ZSH_VERSION-}" ]; then
        eval 'for name in ${(k)HELP_FUNCS}; do printf "%s\t%s\n" "$name" "${HELP_FUNCS[$name]}"; done'
    fi | LC_ALL=C sort
}

# Internal: emit `func` index records (same 5-field schema as the alias index).
# One grep resolves every registered name at once. No cache: this is the same
# tree sweep the alias index caches, so the honest reason is that it has not
# been worth a second cache file — fold it into _my_help_build_alias_index's
# grep if the palette ever feels slow on a slow mount. Emits nothing and
# returns 1 when the tree is missing.
_my_help_function_index() {
    local root names pattern
    root="${DOTFILES_ROOT:-${SHELL_COMMON%/shell-common}}"
    [ -n "$root" ] && [ -d "$root" ] || return 1

    names=$(_my_help_func_registry | cut -f1 | tr '\n' '|')
    [ -n "$names" ] || return 1
    pattern="^(${names%|})\\(\\)[[:space:]]*\\{"

    local found
    found=$(
        {
            _my_help_func_registry
            # Sentinel: awk switches from "reading the registry" to "reading
            # grep output" here. A literal FS byte keeps it unmatchable by any
            # real line.
            printf '\034\n'
            grep -rnE "$pattern" \
                --include='*.sh' --include='*.bash' --include='*.zsh' \
                "$root/bash" "$root/zsh" "$root/shell-common" 2>/dev/null
        } | awk -v root="${root}/" '
            BEGIN { mode = 1 }
            mode == 1 {
                if ($0 == "\034") { mode = 2; next }
                t = index($0, "\t")
                if (t < 2) next
                desc[substr($0, 1, t - 1)] = substr($0, t + 1)
                next
            }
            {
                # grep -n emits <path>:<line>:<content>; anchor on the first
                # ":<digits>:" so a colon in a parent directory name cannot
                # split the path (same rule as the alias indexer).
                if (!match($0, /:[0-9]+:/)) next
                path = substr($0, 1, RSTART - 1)
                lineno = substr($0, RSTART + 1, RLENGTH - 2)
                body = substr($0, RSTART + RLENGTH)

                p = index(body, "(")
                if (p < 2) next
                name = substr(body, 1, p - 1)
                if (!(name in desc)) next

                rel = path
                if (index(rel, root) == 1) rel = substr(rel, length(root) + 1)
                printf "%s\t%s\tfunc\t%s:%s\t%s()\n", name, desc[name], rel, lineno, name
            }' | LC_ALL=C sort -u
    )

    [ -n "$found" ] || return 1
    printf '%s\n' "$found"
}

# Internal: emit one `category` record per registered help category (F-5).
_my_help_category_candidates() {
    # Pre-declared for the same reason as _my_help_search_candidates below.
    local category members total topic
    for category in $(_my_help_get_category_keys 2>/dev/null); do
        members="${HELP_CATEGORY_MEMBERS[$category]}"
        total=0
        for topic in $(_my_help_split_members "$members"); do
            total=$((total + 1))
        done
        printf '%s\t%s\tcategory\t%s topics\t\n' \
            "$category" "${HELP_CATEGORIES[$category]}" "$total"
    done
}

# Internal: emit fzf candidates for one scope — topics, categories, aliases,
# public functions, or (default) all four.
# Split out of _my_help_search so it can be exercised without a TTY or fzf.
_my_help_search_candidates() {
    local scope="${1:-all}"

    # Declare the loop-body variables once, up front: `local x=$(cmd)` inside
    # the piped while-read makes zsh echo the assignment as a stray stdout line
    # (#1248) and also masks $cmd's exit status behind the `local` builtin's.
    # Pre-declaring keeps the in-loop assignments plain and does neither.
    local underscore_name desc

    case "$scope" in
        all | topic)
            _my_help_enumerate_topic_names | while IFS= read -r display_name; do
                underscore_name="${display_name//-/_}"
                desc=$(_my_help_topic_description "${underscore_name%_help}")
                printf '%s\t%s\ttopic\t\t\n' "$display_name" "$desc"
            done
            ;;
    esac

    case "$scope" in
        all | category)
            _my_help_category_candidates 2>/dev/null || true
            ;;
    esac

    # Aliases and functions extend the same stream. A failed/empty scan writes
    # nothing, leaving the topic list exactly as it was before #1261.
    case "$scope" in
        all | alias)
            _my_help_alias_index 2>/dev/null || true
            ;;
    esac

    case "$scope" in
        all | func)
            _my_help_function_index 2>/dev/null || true
            ;;
    esac
}

# Internal: parse a palette query that opens with a slash scope command (F-4).
# Prints "<scope>\t<remaining query>" and returns 0; returns 1 for anything
# that is not a scope switch, which the caller treats as an ordinary query.
_my_help_parse_scope() {
    local raw="$1"
    local word rest scope

    case "$raw" in
        /*) ;;
        *) return 1 ;;
    esac

    raw="${raw#/}"
    word="${raw%% *}"
    rest="${raw#"$word"}"
    while [ "${rest# }" != "$rest" ]; do
        rest="${rest# }"
    done

    case "$word" in
        all) scope="all" ;;
        topic | t) scope="topic" ;;
        alias | a) scope="alias" ;;
        func | f) scope="func" ;;
        cat | c) scope="category" ;;
        *) return 1 ;;
    esac

    printf '%s\t%s\n' "$scope" "$rest"
}

# Internal: true (0) when the interactive palette can run.
_my_help_palette_available() {
    command -v fzf >/dev/null 2>&1 && [ -t 0 ] && [ -t 1 ]
}

# Internal: fzf command palette over help topics, categories, aliases and
# public functions (#1740).
#
# Scope switching runs as a loop in *this* function rather than an fzf action:
# fzf 0.44.1 (the version this repo targets) has no `transform`, and every
# alternative binding would have to interpolate state into the action string.
# With `--print-query` the parent simply reads back whatever the user typed,
# and a leading slash re-invokes fzf with a different candidate stream. `/`
# therefore stays an ordinary query character — no ZLE/readline binding, so
# bash and zsh behave identically (NF-5).
_my_help_search() {
    # Degrade to the static category table when fzf is missing or there is no
    # TTY (piped output, scripts, test harness) — fzf needs an interactive terminal.
    if ! _my_help_palette_available; then
        _my_help_show_categories
        return $?
    fi

    # Users may run with noclobber set; keep the temp-file redirection below
    # working without leaking the option change (same guard as _my_help_show_all).
    if [ -n "$ZSH_VERSION" ]; then
        setopt localoptions clobber 2>/dev/null || true
    fi

    local preview tmp_dir tmp scope query out rc parsed selected kind count

    preview="${SHELL_COMMON}/tools/custom/my_help_preview.sh"
    tmp_dir="${TMPDIR:-/tmp}"
    # Fail closed rather than fall back to a predictable name: `$TMPDIR` is
    # world-writable, so a guessable path lets another user pre-plant a symlink
    # and have the palette truncate a file of their choosing (PR #1745 review,
    # codex BLOCKER + agy). A missing mktemp fails the substitution, so this
    # covers both "no mktemp" and "mktemp refused".
    if ! tmp=$(mktemp "${tmp_dir%/}/my_help_palette.XXXXXX" 2>/dev/null); then
        ux_warning "임시 파일을 만들 수 없습니다 — 정적 카테고리 목록으로 대체합니다."
        _my_help_show_categories
        return $?
    fi

    # D-1: 550+ candidates make /all a noisy first screen; start on topics.
    # An unknown MY_HELP_DEFAULT_SCOPE would otherwise open an empty palette
    # with no hint as to why (PR #1745 review, codex).
    scope="${MY_HELP_DEFAULT_SCOPE:-topic}"
    case "$scope" in
        all | topic | alias | func | category) ;;
        *) scope="topic" ;;
    esac
    query=""

    while :; do
        # Truncate in place — never `rm` then recreate. Re-opening the path
        # each round reopens the symlink-race window that mktemp closed.
        _my_help_search_candidates "$scope" > "$tmp" 2>/dev/null || true

        # Best-effort count for the header (F-10); "${count:-?}" covers an
        # empty result.
        count=$(wc -l < "$tmp" 2>/dev/null | tr -d ' ')

        # No path is interpolated into the fzf action strings at all: they are
        # single-quoted, so the shell fzf spawns expands the three MY_HELP_*
        # variables itself. A path containing a quote would otherwise break the
        # action's own parsing (PR #1745 review, codex + agy). A candidate value
        # still never reaches a command string (NF-2) — fzf hands the preview
        # `{n}`, the integer row index, and the helper reads the record back out
        # of the records file itself.
        # `|| rc=$?` rather than a bare assignment: callers may be running under
        # `set -e` / `err_exit`, where fzf's non-zero abort status would take
        # the whole shell down (PR #1247).
        rc=0
        # SC2016: the single quotes are the fix, not an oversight — the three
        # MY_HELP_* names must reach fzf's own shell unexpanded.
        # SC2094: `$tmp` is written by the command above and only *read* here;
        # the env-assignment prefix makes shellcheck read it as one pipeline.
        # shellcheck disable=SC2016,SC2094
        out=$(
            MY_HELP_PREVIEW="$preview" \
            MY_HELP_RECORDS="$tmp" \
            MY_HELP_SCOPE="$scope" \
                fzf --delimiter='\t' --with-nth=1,3,2 \
                    --height=80% --layout=reverse --border \
                    --print-query --query="$query" \
                    --prompt="my-help /${scope}> " \
                    --header="scope /${scope} · ${count:-?} items · / scope · ? keys · esc quit" \
                    --preview '"$MY_HELP_PREVIEW" "$MY_HELP_RECORDS" {n}' \
                    --preview-window='right,55%,border-left,<80(down,60%,border-top)' \
                    --bind '?:preview("$MY_HELP_PREVIEW" --keys "$MY_HELP_SCOPE")' \
                    < "$tmp"
        ) || rc=$?

        # 130 = Esc / Ctrl-C — the user quit, print nothing.
        if [ "$rc" -eq 130 ]; then
            rm -f "$tmp" 2>/dev/null || true
            return 0
        fi
        # 2 (and anything else >= 2) is fzf failing on its own terms: an option
        # this build does not understand, a lost tty. Treating that as a quit
        # left the palette silently printing nothing with no way to tell why
        # (PR #1745 review, agy BLOCKER). Degrade to the static table instead —
        # the same fallback the fzf-absent path already uses.
        if [ "$rc" -ge 2 ]; then
            rm -f "$tmp" 2>/dev/null || true
            ux_warning "fzf 실행 실패 (rc=${rc}) — 정적 카테고리 목록으로 대체합니다."
            _my_help_show_categories
            return $?
        fi

        # --print-query puts the typed query on its own line ahead of the
        # selection. Split them on the tab rather than the line number: a query
        # can never contain a tab (fzf's prompt does not accept one) and a
        # candidate record always does, so this also stays correct for a caller
        # that stubs fzf and prints the selected record alone.
        query=$(printf '%s\n' "$out" | awk -F'\t' 'NF == 1 { print; exit }')
        selected=$(printf '%s\n' "$out" | awk -F'\t' 'NF > 1 { print; exit }')

        # A slash query is a scope switch even when it happened to fuzzy-match
        # a row (locations contain slashes), so it is checked before the
        # selection is honoured.
        if parsed=$(_my_help_parse_scope "$query"); then
            scope=$(printf '%s' "$parsed" | cut -f1)
            query=$(printf '%s' "$parsed" | cut -f2)
            continue
        fi

        break
    done

    # Explicit cleanup rather than `trap ... EXIT`: this runs inside the user's
    # interactive shell, where an EXIT trap would both clobber theirs and only
    # fire when the shell itself exits.
    rm -f "$tmp" 2>/dev/null || true

    # Esc / empty selection: nothing to show.
    if [ -z "$selected" ]; then
        return 0
    fi

    # F-9: Enter is read-only. alias/func print their definition and source;
    # topic/category go through the existing my_help_impl routing. Nothing is
    # ever executed.
    kind=$(printf "%s" "$selected" | cut -f3)
    case "$kind" in
        alias | func)
            _my_help_show_alias_entry "$selected"
            return $?
            ;;
    esac

    local topic
    topic=$(printf "%s" "$selected" | cut -f1)
    my_help_impl "$topic"
    return $?
}

_my_help_summary() {
    ux_info "Usage: my-help [topic|category|section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "categories: ai | cli | config | development | devops | docs | meta | system"
    ux_bullet_sub "popular: git | docker | claude | uv | fzf"
    ux_bullet_sub "navigation: my-help <topic> [args] / my-help <category>"
    ux_bullet_sub "details: my-help <section>  (example: my-help categories)"
    ux_bullet_sub "search: my-help search  (fzf fuzzy finder over topics + aliases, needs fzf)"
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
        case $- in
            *x*)
                _my_help_restore_xtrace=1
                unsetopt xtrace
                ;;
        esac
    fi

    case "${1:-}" in
        "")
            # F-1: bare `my-help` opens the palette on an interactive terminal
            # that has fzf. Everywhere else (pipes, CI, scripts, fzf absent)
            # the 6-line usage summary is byte-identical to what it always was
            # (NF-4). `-h`/`--help`/`help` stay on the summary unconditionally.
            if _my_help_palette_available; then
                _my_help_search
            else
                _my_help_summary
            fi
            rc=$?
            ;;
        -h|--help|help)
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
        search|find)
            _my_help_search
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

# HELP_CONTENT is a global (declare -gA / typeset -gA) registry populated for
# consumption from the interactive shell and by user overrides, so nothing in
# this file reads it back (SC2034).
# shellcheck disable=SC2034
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
# shellcheck disable=SC2154 # assoc key (array declared in util/help_registry.sh), not a variable
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

            # Generic `<topic>-help` fallback (issue #1287). The adapter registers
            # dash-form topics as aliases only, so a non-interactive shell or one
            # with `setopt no_aliases` lands here; map back to the canonical
            # underscore helper and dispatch only when it is a real function
            # (never for aliases that point at a binary, e.g. `codex --help`).
            case "$cmd_name" in
                *-help)
                    local _cnf_helper
                    _cnf_helper="${cmd_name//-/_}"
                    # _my_help_is_function, not `typeset -f`: in zsh the latter
                    # declares a local when called inside a function (see its
                    # definition above).
                    if _my_help_is_function "$_cnf_helper"; then
                        "$_cnf_helper" "$@"
                        return $?
                    fi
                    ;;
            esac

            if typeset -f _dotfiles_prev_command_not_found_handler >/dev/null 2>&1; then
                _dotfiles_prev_command_not_found_handler "$cmd_name" "$@"
                return $?
            fi

            print -u2 -- "zsh: command not found: ${cmd_name}"
            return 127
        }
    fi
fi
