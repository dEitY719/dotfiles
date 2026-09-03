#!/bin/bash
# shell-common/tools/custom/my_help_preview.sh
# fzf preview renderer for the `my-help` command palette (issue #1740).
#
# Usage:
#   my_help_preview.sh <records.tsv> <zero-based-index>   # render one candidate
#   my_help_preview.sh --keys <scope>                     # static key/slash help
#
# The palette never interpolates a candidate value into the fzf preview
# command string (#1740 NF-2): fzf passes `{n}`, the *integer* index of the
# highlighted row, and this script reads that row back out of the temp file the
# palette wrote. Nothing here writes a file or runs a candidate's definition
# (NF-3) — it only calls the existing renderers in my_help.sh (F-3).
#
# Lives under tools/custom/ because shell-common/functions/ is auto-sourced by
# both loaders and this file has a main body. It is invoked directly (the
# shebang picks bash) — my_help.sh needs associative arrays, so it must not be
# run by dash.

# No `set -u`: my_help.sh probes optional globals ($ZSH_VERSION,
# $_HELP_DEFAULTS_REGISTERED, ...) with bare expansions, so nounset kills the
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
    ux_bullet "Enter  ${enter}"
    ux_bullet "?      this key sheet"
    ux_bullet "Esc    quit without printing anything"

    ux_section "Scope switches"
    [ "$scope" = "all" ] || ux_bullet "/all          every candidate kind"
    [ "$scope" = "topic" ] || ux_bullet "/topic  /t    help topics"
    [ "$scope" = "alias" ] || ux_bullet "/alias  /a    repo aliases"
    [ "$scope" = "func" ] || ux_bullet "/func   /f    public shell functions"
    [ "$scope" = "category" ] || ux_bullet "/cat    /c    help categories"
    ux_bullet "Append a term to filter: /alias docker"
}

# Render the record at <index> of <records.tsv>, or the key sheet for --keys.
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

    # shellcheck source=../../functions/my_help.sh
    . "${SHELL_COMMON}/functions/my_help.sh" >/dev/null 2>&1 || return 0

    if [ "${1:-}" = "--keys" ]; then
        _myhp_keys "${2:-all}"
        return 0
    fi

    local records="${1:-}"
    local index="${2:-}"

    # {n} is always an integer; refuse anything else rather than feed it to sed.
    case "$index" in
        '' | *[!0-9]*) return 0 ;;
    esac
    [ -f "$records" ] || return 0

    local record name kind helper
    record=$(sed -n "$((index + 1))p" "$records" 2>/dev/null) || return 0
    [ -n "$record" ] || return 0

    name=$(printf '%s' "$record" | cut -f1)
    kind=$(printf '%s' "$record" | cut -f3)

    case "$kind" in
        alias | func)
            _my_help_show_alias_entry "$record"
            ;;
        category)
            my_help_impl "$name"
            ;;
        topic)
            # Route through my_help_impl only when the topic resolves to a real
            # help *function*. my_help_impl's last resort is `<name> --help`, and
            # a preview must never reach that.
            helper=$(printf '%s' "$name" | tr '-' '_')
            if _my_help_is_function "$helper"; then
                my_help_impl "$name"
            else
                ux_section "Topic: ${name}"
                ux_bullet "$(printf '%s' "$record" | cut -f2)"
            fi
            ;;
        *)
            ux_section "${name}"
            ux_bullet "$(printf '%s' "$record" | cut -f2)"
            ;;
    esac

    return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "${BASH_SOURCE[0]}" ]; then
    main "$@"
fi
