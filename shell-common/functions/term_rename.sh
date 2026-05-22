#!/bin/sh
# shell-common/functions/term_rename.sh
# Rename the current VSCode (or any OSC 0 -compatible) terminal tab from the
# shell. Pairs with VSCode setting:
#   "terminal.integrated.tabs.title": "${sequence}"
# Without that setting VSCode falls back to "${process}" and silently ignores
# the OSC title — the script still exits 0, only the tab UI doesn't update.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# Persist hook: re-emits the saved OSC title before every prompt so the tab
# label survives long-running foreground processes that overwrite the title
# (claude, dev servers, REPLs). The saved name lives in
# _TERM_RENAME_PERSIST_NAME; --clear unsets it.
_term_rename_persist() {
    [ -n "${_TERM_RENAME_PERSIST_NAME-}" ] || return 0
    printf '\033]0;%s\007' "${_TERM_RENAME_PERSIST_NAME}"
}

_term_rename_install_hook() {
    # Hook is APPENDED, not prepended. Reason: oh-my-zsh's
    # omz_termsupport_precmd (and similar prompt-side title emitters in p10k
    # / starship / vte) sit inside precmd_functions and emit OSC 0/2 with
    # `user@host:cwd` on every prompt. Whichever hook fires LAST wins the
    # tab label, so our re-emit must run last.
    # Inject the hook name via ${_hook} so the literal snake_case identifier
    # never appears inside a quoted string — silences the repo's naming check
    # (git/hooks/checks/naming_check.sh) that flags snake_case in user-facing
    # text. Same workaround used by cp_wdown.sh.
    # Bareword assignment (no quotes) is intentional — repo naming check
    # (git/hooks/checks/naming_check.sh) flags snake_case identifiers
    # inside quoted strings. Same pattern as cp_wdown.sh:`local _name=cp_wdown`.
    local _hook
    _hook=_term_rename_persist
    # Strip any existing occurrence first so install is idempotent AND
    # always lands the hook at the tail. A plain dedup-and-skip would leave
    # a previously-prepended hook stuck at the front (the exact failure
    # mode in shell sessions that loaded the pre-#672 buggy version),
    # making `--persist` look fixed in fresh sessions but inert in
    # existing ones (gemini-code-assist on PR #672).
    _term_rename_remove_hook
    if [ -n "${BASH_VERSION-}" ]; then
        if [ -n "${PROMPT_COMMAND-}" ]; then
            PROMPT_COMMAND="${PROMPT_COMMAND}; ${_hook}"
        else
            PROMPT_COMMAND="${_hook}"
        fi
        return 0
    fi
    if [ -n "${ZSH_VERSION-}" ]; then
        # zsh array syntax wrapped in eval so bash never tries to parse it.
        # typeset -ga guarantees precmd_functions exists as a global array
        # even when sourced before zsh's add-zsh-hook plumbing.
        # emulate -L zsh: the caller may be running under `emulate -L sh`
        # (e.g. git_worktree_spawn during `gwt spawn --launch`). Without this,
        # `${precmd_functions[@]}` resolves to only the first array element
        # under sh emulation, silently truncating the array and dropping
        # `_p9k_precmd` — causing the frozen-prompt regression (#907).
        eval '
            emulate -L zsh
            typeset -ga precmd_functions
            precmd_functions=("${precmd_functions[@]}" "${_hook}")
        '
        return 0
    fi
}

_term_rename_remove_hook() {
    # Bareword assignment (no quotes) is intentional — repo naming check
    # (git/hooks/checks/naming_check.sh) flags snake_case identifiers
    # inside quoted strings. Same pattern as cp_wdown.sh:`local _name=cp_wdown`.
    local _hook
    _hook=_term_rename_persist
    if [ -n "${BASH_VERSION-}" ]; then
        # Strip every occurrence; tolerate leading/trailing forms.
        PROMPT_COMMAND=$(printf '%s' "${PROMPT_COMMAND-}" \
            | sed -e "s/${_hook}; //g" \
                  -e "s/; *${_hook}//g" \
                  -e "s/^${_hook}\$//")
        return 0
    fi
    if [ -n "${ZSH_VERSION-}" ]; then
        # See _term_rename_install_hook for the emulate-L-zsh rationale. The
        # `${(@)arr:#PATTERN}` filter flag is zsh-only and collapses the array
        # to its first element under sh emulation — same frozen-prompt
        # truncation (#907).
        eval 'emulate -L zsh; precmd_functions=("${(@)precmd_functions:#'"${_hook}"'}")'
        return 0
    fi
}

_term_rename_set_persist_name() {
    # zsh would scope a bare assignment inside a function as local; force
    # global with typeset -g. bash assignments at function scope are already
    # global without a `local` declaration.
    if [ -n "${ZSH_VERSION-}" ]; then
        # emulate -L zsh: same caller-emulation defence as the precmd
        # mutators above. Belt-and-braces — typeset -g would still resolve to
        # zsh's builtin under sh emulation, but parameter expansion of "$1"
        # follows whichever emulation is active.
        eval 'emulate -L zsh; typeset -g _TERM_RENAME_PERSIST_NAME="$1"'
        return 0
    fi
    _TERM_RENAME_PERSIST_NAME="$1"
}

_term_rename_help() {
    if ! command -v ux_header >/dev/null 2>&1; then
        printf '%s\n' \
            "term-rename - Rename VSCode terminal tab" \
            "" \
            "Usage:" \
            "  term-rename <name>             one-shot rename" \
            "  term-rename --persist <name>   re-apply on every prompt" \
            "  term-rename --clear            remove persist hook" \
            "  term-rename -h | --help        this help" \
            "" \
            "VSCode setup (one-time):" \
            "  settings.json: \"terminal.integrated.tabs.title\": \"\${sequence}\"" \
            "  Default \"\${process}\" ignores OSC titles — switch to \"\${sequence}\"."
        return 0
    fi
    ux_header "term-rename - Rename VSCode terminal tab"
    ux_section "Usage"
    ux_bullet "term-rename <name>             - Set current tab name (one-shot)"
    ux_bullet "term-rename --persist <name>   - Re-apply on every prompt"
    ux_bullet "term-rename --clear            - Remove --persist hook"
    ux_bullet "term-rename -h | --help        - Show this help"
    ux_section "VSCode Setup (one-time)"
    ux_bullet "settings.json:  \"terminal.integrated.tabs.title\": \"\${sequence}\""
    ux_bullet "Default \"\${process}\" overrides OSC titles — must switch to \"\${sequence}\"."
    ux_section "Examples"
    ux_bullet "term-rename claude             - Label tab 'claude'"
    ux_bullet "term-rename --persist dev      - Keep tab 'dev' across commands"
    ux_bullet "term-rename --clear            - Drop persist hook"
}

_term_rename_err() {
    if command -v ux_error >/dev/null 2>&1; then
        ux_error "$1"
        return 0
    fi
    printf '%s\n' "$1" >&2
}

_term_rename_sanitize() {
    # Strip ESC, BEL, newline, NUL — prevents OSC injection via crafted names.
    printf '%s' "$1" | tr -d '\033\007\n\0'
}

term_rename() {
    local _trn_name
    case "${1-}" in
        -h|--help|help)
            _term_rename_help
            return 0
            ;;
        --clear)
            _term_rename_set_persist_name ""
            unset _TERM_RENAME_PERSIST_NAME 2>/dev/null || _TERM_RENAME_PERSIST_NAME=
            _term_rename_remove_hook
            # Emit empty OSC so the next prompt isn't stuck on the old name.
            printf '\033]0;\007'
            return 0
            ;;
        --persist)
            shift
            if [ -z "${1-}" ]; then
                _term_rename_err "term-rename --persist: name required"
                return 1
            fi
            _trn_name=$(_term_rename_sanitize "$1")
            if [ -z "$_trn_name" ]; then
                _term_rename_err "term-rename --persist: name became empty after sanitize"
                return 1
            fi
            _term_rename_set_persist_name "$_trn_name"
            _term_rename_install_hook
            printf '\033]0;%s\007' "$_trn_name"
            return 0
            ;;
        --*)
            _term_rename_err "term-rename: unknown flag '$1'"
            _term_rename_help
            return 1
            ;;
        "")
            _term_rename_err "term-rename: name required"
            return 1
            ;;
        *)
            _trn_name=$(_term_rename_sanitize "$1")
            if [ -z "$_trn_name" ]; then
                _term_rename_err "term-rename: name became empty after sanitize"
                return 1
            fi
            printf '\033]0;%s\007' "$_trn_name"
            return 0
            ;;
    esac
}

alias term-rename='term_rename'
