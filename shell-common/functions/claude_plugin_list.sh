#!/bin/sh
# shell-common/functions/claude_plugin_list.sh
#
# claude-plugin-list — human-readable summary of installed Claude Code plugins,
# grouped by the marketplace that provided them. Answers the question the
# `/plugins` card UI makes tedious: "did this `superpowers` come from
# claude-plugins-official or superpowers-dev?".
#
# SSOT is ~/.claude-shared/plugins/installed_plugins.json (+ known_marketplaces
# .json for the repo/url per marketplace). Path is overridable via
# CLAUDE_SHARED_PLUGINS_DIR, then falls back to $CLAUDE_CONFIG_DIR/plugins.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# Resolve the plugins state dir: explicit override → default shared dir →
# CLAUDE_CONFIG_DIR-derived. First one that actually holds the SSOT wins.
_claude_plugin_list_dir() {
    for cand in \
        "${CLAUDE_SHARED_PLUGINS_DIR:-}" \
        "$HOME/.claude-shared/plugins" \
        "${CLAUDE_CONFIG_DIR:+$CLAUDE_CONFIG_DIR/plugins}"; do
        [ -n "$cand" ] || continue
        [ -f "$cand/installed_plugins.json" ] && {
            printf '%s' "$cand"
            return 0
        }
    done
    return 1
}

claude_plugin_list() {
    case "${1:-}" in
    -h | --help | help)
        ux_info "Usage: claude-plugin-list"
        ux_bullet "설치된 플러그인을 마켓플레이스별로 그룹핑해 출력"
        ux_bullet_sub "SSOT: ~/.claude-shared/plugins/installed_plugins.json"
        ux_bullet_sub "override: CLAUDE_SHARED_PLUGINS_DIR / CLAUDE_CONFIG_DIR"
        return 0
        ;;
    esac

    command -v jq >/dev/null 2>&1 || {
        ux_error "jq가 필요합니다."
        return 1
    }

    shared_dir=$(_claude_plugin_list_dir) || {
        ux_error "installed_plugins.json 을 찾을 수 없습니다."
        ux_info "확인 경로: \${CLAUDE_SHARED_PLUGINS_DIR}, ~/.claude-shared/plugins, \${CLAUDE_CONFIG_DIR}/plugins"
        return 1
    }
    pl_src="$shared_dir/installed_plugins.json"
    mp_src="$shared_dir/known_marketplaces.json"

    # marketplace → repo|url|path map (empty object if the file is absent).
    mp_json=$(jq -c '
        [to_entries[] | {(.key): (.value.source.repo // .value.source.url // .value.source.path // "")}]
        | add // {}
    ' "$mp_src" 2>/dev/null)
    [ -n "$mp_json" ] || mp_json='{}'

    ux_header "Installed Claude Code Plugins"

    count=$(jq -r '(.plugins // {}) | length' "$pl_src" 2>/dev/null)
    if [ -z "$count" ] || [ "$count" = "0" ]; then
        ux_info "설치된 플러그인이 없습니다: $pl_src"
        return 0
    fi

    # Emit a pipe-delimited stream: one MP line per marketplace group, then a
    # PL line per install record. `|` never appears in marketplace repos,
    # plugin names, versions, scopes, or ISO dates, so it is a safe delimiter.
    jq -r --argjson mp "$mp_json" '
        (.plugins // {}) | to_entries
        | map(. + {mp: (.key | split("@") | last), name: (.key | sub("@[^@]*$"; ""))})
        | group_by(.mp) | .[]
        | ("MP|" + .[0].mp + "|" + (($mp[.[0].mp]) // "unknown")),
          (.[] | . as $e | $e.value[]
            | "PL|" + $e.name
              + "|" + (.version // "unknown")
              + "|" + (.scope // "?")
              + "|" + ((.installedAt // "")[0:10]))
    ' "$pl_src" 2>/dev/null |
        while IFS='|' read -r kind a b c d; do
            case "$kind" in
            MP) ux_section "$a  ($b)" ;;
            PL) ux_bullet "$(printf '%-22s %-9s %-6s %s' "$a" "$b" "$c" "$d")" ;;
            esac
        done
}

alias claude-plugin-list='claude_plugin_list'
