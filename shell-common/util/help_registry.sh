#!/bin/sh
# shellcheck shell=bash
# shell-common/util/help_registry.sh
# Help registry (#2135): the arrays my-help reads plus the functions every
# help provider calls to register itself. dotfiles_load_all sources it after
# env and before functions/, so a functions/*.sh file can end with its own
# `_register_help` / `_register_func` rows instead of editing my_help.sh.
#
# No interactive guard on purpose (shell-common/AGENTS.md "Guard-free pure
# lib"): it only declares arrays and functions and prints nothing, and
# my_help.sh / tools/custom/my_help_preview.sh source it directly when the
# loader did not run.
#
# Usage (at the end of the file that defines the function):
#   _register_help <topic>_help "[Category] description" [category]
#   _register_func <name> "description"        # user-typed function, palette /func

# Global associative arrays (bash declare -gA / zsh typeset -gA, #1889).
# Always declared fresh: a reload (`src`) re-sources every provider, which
# registers itself again, so a renamed or deleted topic does not linger.
unset HELP_DESCRIPTIONS HELP_CATEGORIES HELP_CATEGORY_MEMBERS \
    HELP_COMMAND_TO_CATEGORY HELP_FUNCS
if [ -n "${BASH_VERSION-}" ]; then
    declare -gA HELP_DESCRIPTIONS=() HELP_CATEGORIES=() HELP_CATEGORY_MEMBERS=() \
        HELP_COMMAND_TO_CATEGORY=() HELP_FUNCS=()
elif [ -n "${ZSH_VERSION-}" ]; then
    typeset -gA HELP_DESCRIPTIONS=() HELP_CATEGORIES=() HELP_CATEGORY_MEMBERS=() \
        HELP_COMMAND_TO_CATEGORY=() HELP_FUNCS=()
fi

# Register a help topic in one call: description plus optional category.
# The first description registered wins. The category appends <topic> to
# HELP_CATEGORY_MEMBERS[category] once and fills the HELP_COMMAND_TO_CATEGORY
# reverse map; category pages sort members, so load order does not matter.
_register_help() {
    local func_name="$1"
    local description="$2"
    local category="${3-}"
    local topic="${func_name%_help}"
    if [ -z "${HELP_DESCRIPTIONS[$func_name]-}" ]; then
        HELP_DESCRIPTIONS[$func_name]="$description"
    fi
    [ -n "$category" ] || return 0
    case " ${HELP_CATEGORY_MEMBERS[$category]-} " in
        *" $topic "*) ;;
        *) HELP_CATEGORY_MEMBERS[$category]="${HELP_CATEGORY_MEMBERS[$category]:+${HELP_CATEGORY_MEMBERS[$category]} }$topic" ;;
    esac
    HELP_COMMAND_TO_CATEGORY[$topic]="$category"
}

# Register a function the user types directly, for the my-help palette's
# /func scope (#1740). Never a `_`-prefixed or `*_help` name: those are
# internals or already topic rows (pinned by my_help_palette.bats P10).
_register_func() {
    HELP_FUNCS[$1]="$2"
}

# Register a category's description (shown on its detail page). The first
# description wins, like _register_help.
_register_help_category() {
    if [ -z "${HELP_CATEGORIES[$1]-}" ]; then
        HELP_CATEGORIES[$1]="$2"
    fi
}

_register_help_category ai "AI/LLM assistants (Claude, Gemini, Codex, etc.)"
_register_help_category cli "CLI utilities (search, navigation, snippets, shell helpers)"
_register_help_category config "Configuration and setup (prompt, certs, package managers)"
_register_help_category development "Development tools (Git, Python, package managers, UX)"
_register_help_category devops "DevOps and infrastructure (Docker, proxy, DB, system)"
_register_help_category docs "Documentation and knowledge (dotfiles docs, notes, work logs)"
_register_help_category meta "Help system utilities (category browsing, registration)"
_register_help_category system "System tools (directory navigation, opencode)"
