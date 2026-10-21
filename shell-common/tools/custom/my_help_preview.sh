#!/bin/bash
# shell-common/tools/custom/my_help_preview.sh
# fzf preview renderer for the `my-help` command palette (#1740, cards #2263).
#
# Usage:
#   my_help_preview.sh <records.tsv> <zero-based-index> [query]  # one card
#   my_help_preview.sh --keys <scope>                            # key sheet
#   my_help_preview.sh --scopes <records.tsv>                    # `/` menu rows
#
# The palette never interpolates a candidate value into the fzf preview
# command string (#1740 NF-2): fzf passes `{n}`, the *integer* index of the
# highlighted row, and this script reads that row back out of the temp file the
# palette wrote. `{q}` is only compared against a `/*` pattern: a query that
# starts with a slash means the list currently shows the scope menu, so `{n}`
# indexes the `--scopes` rows instead. Nothing here writes a file or runs a
# candidate's definition (NF-3) — source excerpts are read with sed/bat only.
#
# Every card has the same shape (#2263 F-6): line 1 `<kind> · <name> · <where>`,
# line 2 the description, a kind-specific body, and a dim last line saying what
# Enter does. Output is clipped to $FZF_PREVIEW_COLUMNS.
#
# Lives under tools/custom/ because shell-common/functions/ is auto-sourced by
# both loaders and this file has a main body. It is invoked directly (the
# shebang picks bash) — my_help.sh needs associative arrays, so it must not be
# run by dash.

# No `set -u`: my_help.sh probes optional globals ($ZSH_VERSION,
# $MY_HELP_SKIP_TOPIC_SOURCES, ...) with bare expansions, so nounset kills the
# source before a single record is rendered.

# Static, scope-aware key sheet (F-8). No candidate data reaches this text.
_myhp_keys() {
    local scope="$1"
    local enter

    case "$scope" in
        topic) enter="open the help topic" ;;
        category) enter="open the category listing" ;;
        alias) enter="show the alias definition, source and note (never runs it)" ;;
        func) enter="show the function signature and source (never runs it)" ;;
        *) enter="show the highlighted entry (read-only)" ;;
    esac

    ux_section "Keys — scope /${scope}"
    ux_bullet "Enter      ${enter}"
    ux_bullet "Tab        next scope (topic, alias, func, cat, all)"
    ux_bullet "Shift-Tab  previous scope"
    ux_bullet "/          scope menu — pick a row and press Enter"
    ux_bullet "Alt-P      show / hide the preview"
    ux_bullet "?          this key sheet"
    ux_bullet "Esc        quit without printing anything"

    ux_section "Scope switches"
    [ "$scope" = "all" ] || ux_bullet "/all          every candidate kind"
    [ "$scope" = "topic" ] || ux_bullet "/topic  /t    help topics"
    [ "$scope" = "alias" ] || ux_bullet "/alias  /a    repo aliases"
    [ "$scope" = "func" ] || ux_bullet "/func   /f    public shell functions"
    [ "$scope" = "category" ] || ux_bullet "/cat    /c    help categories"
    ux_bullet "Append a term to filter: /alias docker"
}

# The `/` menu as 5-field records (name, desc, kind=scope, count, scope key).
# Counts come from the kind column of <records> — the current scope's stream —
# so a kind outside it shows no count rather than a wrong one. Reads one file,
# sources nothing: the palette renders this once per fzf round.
_myhp_scopes() {
    awk -F'\t' '
        { c[$3]++; total++ }
        END {
            kinds = 0
            for (k in c) kinds++
            row("/topic", "Help topics", c["topic"], "topic")
            row("/alias", "Repo aliases", c["alias"], "alias")
            row("/func", "Public shell functions", c["func"], "func")
            row("/cat", "Categories", c["category"], "category")
            row("/all", "Everything", (kinds > 1) ? total : 0, "all")
        }
        function row(name, desc, n, key) {
            printf "%s\t%s\tscope\t%s\t%s\n", name, desc, (n > 0) ? n : "", key
        }' "$1" 2>/dev/null
}

# Card chrome. printf with ux_lib's UX_* variables (the way ux_lib itself
# draws): ux_section's leading blank line and underline would push the
# `kind · name · where` title off line 1.
_myhp_title() {
    printf '%s%s · %s%s%s\n' "${UX_BOLD}" "$1" "$2" "${UX_RESET}" \
        "${3:+${UX_MUTED} · $3${UX_RESET}}"
    [ -z "$4" ] || printf '%s\n' "$4"
}

_myhp_enter() {
    printf '\n%s⏎ %s%s\n' "${UX_DIM}${UX_MUTED}" "$1" "${UX_RESET}"
}

# Clip every line to the preview width, counting only visible characters
# (ESC sequences are copied through uncounted).
# shortcut: one column per character, so a wide (CJK) glyph counts as 1 and a
# Korean line can still overflow — fzf clips it; measure widths if that shows.
_myhp_clip() {
    local width="${FZF_PREVIEW_COLUMNS:-}"
    case "$width" in '' | *[!0-9]*) cat; return 0 ;; esac
    awk -v w="$width" '{
        out = ""; vis = 0; s = $0
        while (s != "") {
            if (substr(s, 1, 1) == "\033") {
                if (match(s, /^\033\[[0-9;?]*[A-Za-z]/) || match(s, /^\033[()][A-Za-z0-9]/)) {
                    out = out substr(s, 1, RLENGTH); s = substr(s, RLENGTH + 1); continue
                }
            }
            if (vis >= w) { s = substr(s, 2); continue }
            out = out substr(s, 1, 1); vis++; s = substr(s, 2)
        }
        print out
    }'
}

_myhp_card_scope() {
    local name="$1" desc="$2" count="$3"
    _myhp_title scope "$name" "$count" "$desc"
    ux_bullet "Enter switches the palette to ${name} and clears the query."
    ux_bullet "Tab / Shift-Tab cycle scopes without the menu."
    _myhp_enter "switches scope"
}

_myhp_card_topic() {
    local name="$1" desc="$2"
    local key label
    key=$(printf '%s' "${name%-help}" | tr '-' '_')
    label=$(_my_help_category_label "${HELP_COMMAND_TO_CATEGORY[$key]-}")
    desc=$(printf '%s' "$desc" | sed 's/^\[[^]]*\][[:space:]]*//')

    _myhp_title topic "$name" "$label" "$desc"
    # Only a real help *function* is ever called: my_help_impl's last resort
    # is `<name> --help`, and a preview must never reach that.
    if _my_help_is_function "_${key}_help_summary"; then
        "_${key}_help_summary"
    elif _my_help_is_function "${key}_help"; then
        my_help_impl "$name"
    fi
    _myhp_enter "prints this · ${name} · my-help ${name%-help}"
}

_myhp_card_alias() {
    local name="$1" desc="$2" location="$3" defn="$4"
    local note="" bat_bin
    [ "$desc" = "$location" ] || note="$desc"

    _myhp_title alias "$name" "$location" "${note:-$defn}"
    bat_bin=$(_my_help_bat_bin)
    if [ -n "$bat_bin" ]; then
        printf '%s\n' "$defn" | "$bat_bin" --style=plain --color=always \
            --paging=never -l sh 2>/dev/null || ux_bullet "$defn"
    else
        ux_bullet "$defn"
    fi
    printf '\n'
    _my_help_source_excerpt "$location" 3 3 || ux_bullet "source: ${location}"
    _myhp_enter "prints definition · never runs it"
}

_myhp_card_func() {
    local name="$1" desc="$2" location="$3"
    _myhp_title func "$name" "$location" "$desc"
    _my_help_source_excerpt "$location" 0 24 || ux_bullet "source: ${location}"
    # A same-named help topic is worth a pointer; grep, because the topic
    # sources are skipped for func cards to keep the preview fast.
    case "$name" in
        *[!A-Za-z0-9_]*) ;;
        *)
            if grep -qsE "^${name}_help[[:space:]]*\(\)" "${SHELL_COMMON}"/functions/*.sh; then
                printf '\n'
                ux_bullet "also: $(printf '%s' "$name" | tr '_' '-')-help"
            fi
            ;;
    esac
    _myhp_enter "prints signature + source · never runs it"
}

_myhp_card_category() {
    local name="$1" desc="$2" count="$3"
    local topic tdesc
    _myhp_title category "$name" "$count" "$desc"
    ux_section "Topics"
    for topic in $(_my_help_split_members "${HELP_CATEGORY_MEMBERS[$name]-}"); do
        # Inline lookups, no $(...): a category holds ~20 members and two
        # forks each blew the 150 ms preview budget.
        tdesc="${HELP_DESCRIPTIONS[${topic}_help]-}"
        [ -n "$tdesc" ] || tdesc="${HELP_DESCRIPTIONS[${topic//_/-}-help]-}"
        case "$tdesc" in \[*\]*) tdesc="${tdesc#*]}"; tdesc="${tdesc# }" ;; esac
        printf '  %-16s %s%s%s\n' "${topic//_/-}" "${UX_DIM}" "$tdesc" "${UX_RESET}"
    done
    _myhp_enter "opens category page · my-help ${name}"
}

# Render the card for <index> of <records.tsv>, or the key sheet / menu.
main() {
    # Executable script: resolving via $0 is the sanctioned form
    # (shell-common/AGENTS.md). Self-resolution wins over an inherited
    # SHELL_COMMON so a worktree's palette previews that worktree's tree.
    local self_dir
    self_dir=$(cd "$(dirname "$0")/../.." && pwd 2>/dev/null) || return 0
    SHELL_COMMON="$self_dir"
    export SHELL_COMMON

    # my_help.sh returns early in a non-interactive shell unless this is set.
    export DOTFILES_FORCE_INIT=1

    # --scopes feeds the per-round menu file and needs no colour at all.
    if [ "${1:-}" = "--scopes" ]; then
        [ -f "${2:-}" ] && _myhp_scopes "$2"
        return 0
    fi

    # The key sheet is static text needing only ux_lib, so it skips the
    # my_help.sh load entirely.
    if [ "${1:-}" = "--keys" ]; then
        . "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" >/dev/null 2>&1 || return 0
        _myhp_keys "${2:-all}"
        return 0
    fi

    local records="${1:-}"
    local index="${2:-}"
    local query="${3:-}"

    # {n} is always an integer; refuse anything else rather than feed it to sed.
    case "$index" in
        '' | *[!0-9]*) return 0 ;;
    esac
    [ -f "$records" ] || return 0

    local record tab name desc kind location defn
    tab=$(printf '\t')

    # A `/` query means fzf is showing the scope menu: {n} indexes its rows.
    case "$query" in
        /*)
            record=$(_myhp_scopes "$records" | sed -n "$((index + 1)){p;q}")
            [ -n "$record" ] || return 0
            # cut, not `read`: tab is IFS whitespace, so `read` would collapse
            # an empty count field and shift the scope key into its place.
            . "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" >/dev/null 2>&1 || return 0
            _myhp_card_scope "$(printf '%s' "$record" | cut -f1)" \
                "$(printf '%s' "$record" | cut -f2)" \
                "$(printf '%s' "$record" | cut -f4)" | _myhp_clip
            return 0
            ;;
    esac

    record=$(sed -n "$((index + 1)){p;q}" "$records" 2>/dev/null) || return 0
    [ -n "$record" ] || return 0

    IFS="$tab" read -r name desc kind location defn <<EOF
$record
EOF

    # alias/func cards render out of ux_lib alone; skip sourcing the 37
    # *_help.sh topic files that only the topic/category cards need.
    case "$kind" in
        alias | func) export MY_HELP_SKIP_TOPIC_SOURCES=1 ;;
    esac

    # shellcheck source=../../functions/my_help.sh
    . "${SHELL_COMMON}/functions/my_help.sh" >/dev/null 2>&1 || return 0

    {
        case "$kind" in
            alias) _myhp_card_alias "$name" "$desc" "$location" "$defn" ;;
            func) _myhp_card_func "$name" "$desc" "$location" ;;
            category) _myhp_card_category "$name" "$desc" "$location" ;;
            topic) _myhp_card_topic "$name" "$desc" ;;
        esac
    } 2>/dev/null | _myhp_clip

    return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "${BASH_SOURCE[0]}" ]; then
    main "$@"
fi
