#!/bin/sh
# shell-common/functions/zz_help_standard_adapter.sh
# Normalizes my-help topic functions to the command-guidelines interface.

_help_std_is_function() {
    if [ -n "${ZSH_VERSION:-}" ]; then
        whence -w "$1" 2>/dev/null | grep -q ": function$"
    else
        declare -f "$1" >/dev/null 2>&1
    fi
}

_help_std_get_definition() {
    if [ -n "${ZSH_VERSION:-}" ]; then
        typeset -f "$1" 2>/dev/null
    else
        declare -f "$1" 2>/dev/null
    fi
}

_help_std_is_wrapped() {
    _help_std_is_function "_help_std_orig_$1"
}

_help_std_is_guideline_compliant() {
    local func_name="$1"

    # SSOT pattern: presence of paired _<func>_summary helper indicates
    # the topic has been refactored into native summary/list/full helpers
    # that the dispatcher delegates to. This avoids redundant wrapping.
    if _help_std_is_function "_${func_name}_summary"; then
        return 0
    fi

    local def
    local get_definition_fn='_help_std_get_definition'
    def="$($get_definition_fn "$func_name")" || return 1

    printf "%s\n" "$def" | grep -Fq "[section|--list|--all]" || return 1
    printf "%s\n" "$def" | grep -Fq 'ux_bullet "sections"' || return 1
    return 0
}

_help_std_func_to_alias() {
    local func_name="$1"
    local topic="${func_name%_help}"
    printf "%s-help" "${topic//_/-}"
}

_help_std_strip_category_prefix() {
    printf "%s\n" "$1" | sed "s/^\[[^]]*\][[:space:]]*//"
}

_help_std_get_description() {
    local func_name="$1"
    local value=""

    if [ -n "${BASH_VERSION:-}" ] || [ -n "${ZSH_VERSION:-}" ]; then
        eval "value=\${HELP_DESCRIPTIONS[$func_name]:-}"
    fi

    if [ -n "$value" ]; then
        _help_std_strip_category_prefix "$value"
    else
        local topic="${func_name%_help}"
        printf "%s command reference" "${topic//_/ }"
    fi
}

_help_std_clone_original() {
    local func_name="$1"
    local def
    local cloned_name="_help_std_orig_${func_name}"
    local get_definition_fn='_help_std_get_definition'

    def="$($get_definition_fn "$func_name")" || return 1
    def="$(printf "%s\n" "$def" | sed "1s/^${func_name}[[:space:]]*()/${cloned_name}()/")"
    eval "$def"
}

_help_std_define_wrapper() {
    local func_name="$1"
    local alias_name="$2"
    local description="$3"

    eval "
_help_std_summary_${func_name}() {
    ux_info \"Usage: ${alias_name} [section|--list|--all]\"
    ux_bullet \"sections\"
    ux_bullet_sub \"overview: ${description}\"
    ux_bullet_sub \"details: ${alias_name} <section>  (example: ${alias_name} overview)\"
}

_help_std_list_${func_name}() {
    ux_bullet \"overview\"
}

_help_std_rows_${func_name}_overview() {
    _help_std_orig_${func_name}
}

_help_std_full_${func_name}() {
    _help_std_rows_${func_name}_overview
}

${func_name}() {
    case \"\${1:-}\" in
        \"\"|-h|--help|help)
            _help_std_summary_${func_name}
            ;;
        --list|list|section|sections)
            _help_std_list_${func_name}
            ;;
        --all|all)
            _help_std_full_${func_name}
            ;;
        overview)
            _help_std_rows_${func_name}_overview
            ;;
        *)
            _help_std_orig_${func_name} \"\$@\"
            ;;
    esac
}
"
}

_help_std_define_zsh_dash_function() {
    local alias_name="$1"
    local func_name="$2"

    [ -n "${ZSH_VERSION:-}" ] || return 0

    if _help_std_is_function "$alias_name"; then
        return 0
    fi

    setopt localoptions no_aliases
    eval "
${alias_name}() {
    ${func_name} \"\$@\"
}
"
}

_help_std_wrap_one() {
    local func_name="$1"
    local alias_name
    local description
    local get_description_fn='_help_std_get_description'

    _help_std_is_function "$func_name" || return 0
    alias_name="$(_help_std_func_to_alias "$func_name")"
    _help_std_define_zsh_dash_function "$alias_name" "$func_name"

    case "$func_name" in
        git_help|gwt_help)
            alias "${alias_name}=${func_name}" 2>/dev/null || true
            return 0
            ;;
    esac

    _help_std_is_wrapped "$func_name" && return 0
    _help_std_is_guideline_compliant "$func_name" && return 0

    description="$($get_description_fn "$func_name")"

    _help_std_clone_original "$func_name" || return 1
    _help_std_define_wrapper "$func_name" "$alias_name" "$description"

    alias "${alias_name}=${func_name}" 2>/dev/null || true
    return 0
}

_help_std_wrap_topics() {
    local topic
    local helper_name

    while IFS= read -r topic; do
        [ -n "$topic" ] || continue
        helper_name="${topic}_help"
        _help_std_wrap_one "$helper_name" || true
    done <<'EOF'
git
gwt
uv
py
nvm
npm
bun
pp
cli
ux
du
psql
mytool
docker
dproxy
sys
proxy
ssl
mount
mysql
redis
gpu
network
claude
cc
gemini
codex
litellm
ollama
claude_plugins
claude_skills_marketplace
superpowers
fzf
fd
fasd
ripgrep
pet
bat
zsh
zsh_autosuggestions
gc
tmux
p10k
crt
apt
pip
ghostty
dot
show_doc
notion
work_log
work
dir
opencode
category
register
EOF
}

apply_help_standard_adapter() {
    if _help_std_is_function "_register_default_help_descriptions"; then
        _register_default_help_descriptions >/dev/null 2>&1 || true
    fi

    _help_std_wrap_topics
}

# Apply once for help functions sourced from shell-common/functions/.
# bash/zsh loader re-applies after integrations are sourced.
apply_help_standard_adapter
