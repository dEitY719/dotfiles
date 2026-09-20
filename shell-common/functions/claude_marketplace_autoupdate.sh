#!/bin/sh
# shell-common/functions/claude_marketplace_autoupdate.sh
#
# claude-marketplace-autoupdate — turn on auto-update for EVERY installed
# Claude Code marketplace in one shot, instead of opening `/plugin` and
# choosing "Enable auto-update" on each card. With ~30 marketplaces the UI
# route is the whole problem.
#
# Auto-update state lives per marketplace in known_marketplaces.json as an
# optional `"autoUpdate": true`. There is no CLI flag and no settings.json
# default for it (settings' `autoUpdatesChannel` is Claude Code's OWN updater),
# so editing that file is the only route. Claude Code re-reads it at session
# start, so the change applies on the next session, not this one.
#
# The file is machine-local and carries absolute installLocation paths, so it
# is deliberately NOT synced through dotfiles — this function travels instead,
# and each machine runs it once.
#
# Files are discovered, never hardcoded: $CLAUDE_CONFIG_DIR/plugins first, then
# every ~/.claude*/plugins. Several of those are commonly symlinks to one real
# directory, so targets are de-duplicated by device:inode and each real file is
# written once.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# Inline help (`_<prefix>_help`) — Type 1 simple function, 0 sub-commands, so
# help lives beside the dispatcher per command-design-pattern.md §7.
_cma_help() {
    ux_info "Usage: claude-marketplace-autoupdate [--dry-run]"
    ux_bullet "모든 마켓플레이스에 autoUpdate=true 를 설정 (기본: 적용)"
    ux_bullet_sub "--dry-run: 바뀔 개수만 보고, 파일은 그대로"
    ux_bullet_sub "대상: \${CLAUDE_CONFIG_DIR}/plugins, ~/.claude*/plugins (심링크 중복 제거)"
    ux_bullet_sub "쓰기 전 .bak.<timestamp> 백업, autoUpdate 외 필드 불변을 검증"
    ux_bullet_sub "적용은 다음 세션부터 — 파일은 세션 시작 시 읽힌다"
}

# device:inode identity, so two paths into one real file collapse to one target.
# GNU stat first, BSD/macOS second; a shell with neither just gets no dedup.
_cma_fileid() {
    stat -c '%d:%i' "$1" 2>/dev/null || stat -f '%d:%i' "$1" 2>/dev/null
}

# Every known_marketplaces.json worth touching, one per line, de-duplicated.
_cma_targets() {
    local cand f id seen
    seen=""
    for cand in "${CLAUDE_CONFIG_DIR:+$CLAUDE_CONFIG_DIR/plugins}" "$HOME"/.claude*/plugins; do
        [ -n "$cand" ] || continue
        f="$cand/known_marketplaces.json"
        [ -f "$f" ] || continue
        id=$(_cma_fileid "$f")
        # No id (stat unavailable) means no dedup rather than no output.
        if [ -n "$id" ]; then
            case " $seen " in *" $id "*) continue ;; esac
            seen="$seen $id"
        fi
        printf '%s\n' "$f"
    done
}

claude_marketplace_autoupdate() {
    local dry f tmp bak total off rest_before rest_after rc touched

    dry=0
    case "${1:-}" in
    -h | --help | help)
        _cma_help
        return 0
        ;;
    --dry-run | -n)
        dry=1
        ;;
    "") ;;
    *)
        ux_error "알 수 없는 인자: $1"
        _cma_help
        return 1
        ;;
    esac

    if ! command -v jq >/dev/null 2>&1; then
        ux_error "jq가 필요합니다."
        return 1
    fi

    rc=0
    touched=0
    ux_header "Claude marketplace auto-update"

    for f in $(_cma_targets); do
        touched=$((touched + 1))
        total=$(jq -r 'length' "$f" 2>/dev/null)
        off=$(jq -r '[to_entries[] | select(.value.autoUpdate != true)] | length' "$f" 2>/dev/null)
        if [ -z "$total" ] || [ -z "$off" ]; then
            ux_error "JSON 파싱 실패: $f"
            rc=1
            continue
        fi

        if [ "$off" = "0" ]; then
            ux_bullet "$(printf '%-52s %s' "$f" "이미 전부 ON ($total)")"
            continue
        fi

        if [ "$dry" = "1" ]; then
            ux_bullet "$(printf '%-52s %s' "$f" "$off/$total 변경 예정 (dry-run)")"
            continue
        fi

        tmp="$f.tmp.$$"
        if ! jq 'map_values(.autoUpdate = true)' "$f" >"$tmp" 2>/dev/null; then
            ux_error "변환 실패: $f"
            rm -f "$tmp"
            rc=1
            continue
        fi

        # Guard the blast radius: everything except autoUpdate must survive
        # byte-for-byte. A stray jq edit to installLocation would repoint a
        # marketplace at a directory that does not exist.
        rest_before=$(jq -S 'map_values(del(.autoUpdate))' "$f" 2>/dev/null)
        rest_after=$(jq -S 'map_values(del(.autoUpdate))' "$tmp" 2>/dev/null)
        if [ "$rest_before" != "$rest_after" ]; then
            ux_error "autoUpdate 외 필드가 바뀌었습니다 — 적용 취소: $f"
            rm -f "$tmp"
            rc=1
            continue
        fi

        bak="$f.bak.$(date +%Y%m%d-%H%M%S)"
        if ! cp "$f" "$bak"; then
            ux_error "백업 실패 — 적용 취소: $f"
            rm -f "$tmp"
            rc=1
            continue
        fi
        if ! mv "$tmp" "$f"; then
            ux_error "쓰기 실패: $f (백업: $bak)"
            rm -f "$tmp"
            rc=1
            continue
        fi
        ux_bullet "$(printf '%-52s %s' "$f" "$off/$total ON (backup: ${bak##*/})")"
    done

    if [ "$touched" = "0" ]; then
        ux_error "known_marketplaces.json 을 찾을 수 없습니다."
        ux_info "확인 경로: \${CLAUDE_CONFIG_DIR}/plugins, ~/.claude*/plugins"
        return 1
    fi

    [ "$dry" = "1" ] || ux_info "적용됨 — 새 세션부터 반영됩니다."
    return "$rc"
}

alias claude-marketplace-autoupdate='claude_marketplace_autoupdate'
