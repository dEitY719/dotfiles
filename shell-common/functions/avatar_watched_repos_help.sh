#!/bin/sh
# shell-common/functions/avatar_watched_repos_help.sh
# Help for avatar-watched-repos (logic: tools/custom/avatar_watched_repos.sh,
# merge: tools/py/dotfiles_tools/issue_watcher/watched_repos.py, #2285).

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_avatar_watched_repos_help_summary() {
    ux_info "Usage: avatar-watched-repos [--dry-run|-h|--help]"
    ux_bullet "Renders avatar/watched-repos.public.json (repo + HOME-relative rel)"
    ux_bullet_sub "into ~/.avatars/issue-watcher/watched-repos.json (\$IW_WATCHED_REPOS)"
    ux_bullet "sections: commands, rules (avatar-watched-repos-help <section>)"
}

_avatar_watched_repos_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "commands"
    ux_bullet_sub "rules"
}

_avatar_watched_repos_help_rows_commands() {
    ux_table_row "avatar-watched-repos" "Render" "Merge the tracked list into this PC's watch list (backup on change)"
    ux_table_row "avatar-watched-repos --dry-run" "Preview" "Print the diff only, write nothing"
    ux_table_row "./setup.sh" "Setup" "Runs the render as the optional avatar-watched-repos step"
}

_avatar_watched_repos_help_rows_rules() {
    ux_table_row "local-only entry" "Keep" "Repos only in the local file (private repos) stay as they are"
    ux_table_row "repo in both" "Merge" "Local path wins (per-PC override); host/post_merge_verify/post_merge_verify_skill come from the tracked file"
    ux_table_row "old verify_skill" "Migrate" "Local verify_skill: X becomes post_merge_verify: true + post_merge_verify_skill: X (new keys win)"
    ux_table_row "repo on another host" "Keep" "A local entry whose host differs (GHES mirror) is left as it is"
    ux_table_row "tracked-only repo" "Add" "Added as \$HOME/<rel> when that directory exists, else skipped with a warning"
    ux_table_row "same result" "Idempotent" "No write, no backup; on change: watched-repos.json.bak-<ts> then write (0600)"
    ux_table_row "broken JSON" "Abort" "Either file unreadable: error, local file left untouched"
}

_avatar_watched_repos_help_full() {
    _avatar_watched_repos_help_summary
    ux_section "commands"
    _avatar_watched_repos_help_rows_commands
    ux_section "rules"
    _avatar_watched_repos_help_rows_rules
}

avatar_watched_repos_help() {
    case "${1:-}" in
    "" | -h | --help | help) _avatar_watched_repos_help_full ;;
    --list | list | section | sections) _avatar_watched_repos_help_list_sections ;;
    --all | all) _avatar_watched_repos_help_full ;;
    commands | cmds) _avatar_watched_repos_help_rows_commands ;;
    rules) _avatar_watched_repos_help_rows_rules ;;
    *)
        ux_error "Unknown avatar-watched-repos-help section: $1"
        ux_info "Try: avatar-watched-repos-help --list"
        return 1
        ;;
    esac
}

alias avatar-watched-repos-help='avatar_watched_repos_help'

# Help registry (#2135): skipped when sourced without util/help_registry.sh.
command -v _register_help >/dev/null 2>&1 || return 0
_register_help avatar_watched_repos_help "[Development] render the tracked issue-watcher watch list on this PC" development
