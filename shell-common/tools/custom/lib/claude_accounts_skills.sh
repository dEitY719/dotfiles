#!/bin/sh
# shellcheck shell=bash
# shell-common/tools/custom/lib/claude_accounts_skills.sh
# Claude Code account skills/ directory helpers: workspace-link pruning and
# `claude-accounts link / unlink` (moved out of tools/integrations/claude.sh,
# #2146).
#
# Source-only, no interactive guard: same consumers as
# claude_accounts_lifecycle.sh. Function definitions only.
#
# Needs: ux_lib, functions/mount.sh (_is_mounted),
# functions/skill_sources.sh (_skill_workspace_root, _skill_under_workspace), and
# claude_accounts_lifecycle.sh (_claude_backup_original, _claude_link_lib,
# _claude_accounts_help).

# _claude_dir_sync_one / _claude_count_dir_sync / claude_skills_sync —
# REMOVED (issue #575).
#
# These used to maintain per-skill / per-doc symlinks under
# "<cdir>/skills/" and "<cdir>/docs/" as a sudo-free replacement for the
# legacy bind-mount design (#342, #344). Issue #575 collapses that into
# a single top-level symlink — "<cdir>/skills" / "<cdir>/docs" — so
# per-entry sync is no longer needed; the SSOT is reflected atomically
# and new skills appear instantly without re-running setup. The
# `claude-skills-sync` alias and `claude-accounts skills-sync`
# sub-command went away with them.

# _claude_prepare_skills_dir <target_skills_dir>
#
# F-8 (issue #707): make <tgt> a real directory that entry-level symlinks
# can be composed into, converting whatever legacy shape is there now.
# This is what lets externally added symlinks (marketplace `npx skills
# add` results, manually linked skills) and the workspace composer layer
# entries into the same <tgt>.
#
# Idempotent, and performs two migrations in place:
#   1. If <tgt> is a legacy directory-symlink (#575 / #1680's deleted
#      dotfiles SSOT), remove it and replace with a real directory.
#   2. If <tgt> is a legacy bind-mount (#287/#342 era), unmount it.
# An unexpected regular file at <tgt> is backed up rather than clobbered.
_claude_prepare_skills_dir() {
    _cpsd_tgt="${1:-}"
    if [ -z "$_cpsd_tgt" ]; then
        ux_error "_claude_prepare_skills_dir: tgt required"
        return 1
    fi

    if [ -L "$_cpsd_tgt" ]; then
        ux_info "  legacy dir-symlink at $_cpsd_tgt — converting to entry composition"
        rm -f "$_cpsd_tgt"
    elif _is_mounted "$_cpsd_tgt" 2>/dev/null; then
        ux_warning "  bind-mount detected at $_cpsd_tgt — unmounting (sudo may prompt)"
        if ! sudo umount "$_cpsd_tgt"; then
            ux_error "  unmount failed: $_cpsd_tgt"
            return 1
        fi
        # Post-umount the underlying directory is revealed. If empty,
        # rmdir clears it and `mkdir -p` below creates a fresh slot. If
        # populated (stale skill data from before the bind-mount era),
        # back it up so the entry-composition loop does not mingle
        # symlinks with the user's data. Shares _claude_ensure_symlink's
        # latest-only backup helper so both sites use one naming convention.
        if [ -e "$_cpsd_tgt" ] && ! rmdir "$_cpsd_tgt" 2>/dev/null; then
            _claude_backup_original "$_cpsd_tgt" "revealed directory" || return 1
        fi
    elif [ -e "$_cpsd_tgt" ] && [ ! -d "$_cpsd_tgt" ]; then
        _claude_backup_original "$_cpsd_tgt" "unexpected file" || return 1
    fi
    mkdir -p "$_cpsd_tgt"
}

# _claude_prune_workspace_skills <target_skills_dir>
#
# Claude Code 는 워크스페이스 스킬을 플러그인으로만 로드한다 — 플러그인이
# Claude Code 스킬의 단일 SSOT 다. 각 marketplace repo 는
# claude/plugin/plugins.json 에 선언되고 claude/plugin/restore.sh 가 설치하며
# (예: gh-flow@gh-flow-skills → /gh-flow:issue), 같은 스킬을
# <tgt>/<skill> → <workspace>/<repo>/skills/<skill> flat 링크로도 합성하면
# 네임스페이스 없는 명령(/issue)으로 한 번 더 등록돼 중복된다. 그래서 예전의
# workspace 합성(#1652 / #1680, _claude_compose_workspace_skills)은 Claude Code
# 계정에서 폐지됐고, 이 함수는 그 합성이 남긴 링크를 정리하는 마이그레이션만
# 맡는다. 다른 harness(OpenCode / Codex / agy / Hermes)는 플러그인 기반이
# 아니므로 scripts/setup-skills-ssot.sh 의 flat 합성을 그대로 유지한다.
#
# 정리 대상 (<tgt> 의 직계 symlink):
#   1. target 이 존재하지 않는 dangling 링크 — 어디를 가리키든(워크스페이스 밖
#      포함: #1680 이전 ~/dotfiles/claude/skills/*, 사라진 company-skills 등)
#      스킬을 제공하지 못하므로 지워도 잃는 것이 없다 (#2018). 워크스페이스
#      루트를 판정할 수 없어도 동작한다.
#   2. target 이 워크스페이스 루트 안에 있는 링크. 판정은 _skill_under_workspace
#      (raw / resolved 양쪽 철자)를 그대로 쓴다 — `claude-accounts link` 가
#      워크스페이스 entry 로 보고 fan-out 에서 건너뛰는 기준과 같은 정의다.
# 워크스페이스 밖을 가리키는 정상 링크(graphify, `claude-accounts link` 결과 등),
# 실디렉토리(agentmemory-*, synced/, .trash/), 일반 파일은 절대 건드리지 않는다.
#
# <tgt> 자체는 계속 실디렉토리로 정규화한다 (_claude_prepare_skills_dir,
# #707 F-8) — 외부에서 추가된 entry 가 계속 들어올 자리다.
#
# 정리한 개수는 CLAUDE_WS_SKILLS_PRUNED 에 누적된다 (claude/setup.sh 의 변경
# 요약 라인, #997). Idempotent: 두 번째 실행은 아무것도 지우지 않는다.
# 워크스페이스 루트가 없거나 너무 넓으면(_skill_workspace_root 의 breadth
# guard) 2번(워크스페이스 링크) 판정은 건너뛴다 — 무엇이 "워크스페이스 링크"
# 인지 판정할 수 없을 때는 지우지 않는 쪽이 안전하다. 1번(dangling)은 그대로 처리.
_claude_prune_workspace_skills() {
    _cpws_tgt="${1:-}"
    [ -n "$_cpws_tgt" ] || return 0
    _claude_prepare_skills_dir "$_cpws_tgt" || return 1

    # Defense-in-depth (#724 lesson): a caller that sources this file but not
    # functions/skill_sources.sh has no workspace rule (_skill_under_workspace),
    # and the workspace cleanup would silently no-op. Say so
    # instead. Dangling links are still pruned (they need no root).
    _cpws_root=""
    _cpws_rroot=""
    if command -v _skill_workspace_root >/dev/null 2>&1; then
        _cpws_root="$(_skill_workspace_root)" || _cpws_root=""
        # Resolve once: _skill_under_workspace would fork readlink per call.
        [ -z "$_cpws_root" ] ||
            _cpws_rroot=$(readlink -f "$_cpws_root" 2>/dev/null || printf '%s' "$_cpws_root")
    else
        ux_warning "  workspace skill sources unavailable — shell-common/functions/skill_sources.sh not sourced (#1652)"
    fi

    # `find` rather than a glob: zsh aborts the enclosing function on an
    # unmatched glob (`nomatch`), and an empty skills/ is the normal state.
    _cpws_links="$(find "$_cpws_tgt" -mindepth 1 -maxdepth 1 -type l 2>/dev/null)"
    _cpws_pruned=0
    while IFS= read -r _cpws_existing; do
        [ -n "$_cpws_existing" ] || continue
        # Dangling (#2018): `-e` follows the link, so false == target missing.
        if [ -e "$_cpws_existing" ]; then
            # Live link: only ours when it points into the workspace. Without
            # a usable root we cannot tell, so keep it.
            [ -n "$_cpws_root" ] || continue
            # `readlink` gives the raw target; a relative or non-normalized
            # link would not match the root, so test the resolved spelling too.
            _cpws_raw=$(readlink "$_cpws_existing")
            _cpws_real=$(readlink -f "$_cpws_existing" 2>/dev/null || printf '%s' "$_cpws_raw")
            if ! _skill_under_workspace "$_cpws_raw" "$_cpws_root" "$_cpws_rroot" &&
                ! _skill_under_workspace "$_cpws_real" "$_cpws_root" "$_cpws_rroot"; then
                continue
            fi
        fi
        if rm -f "$_cpws_existing"; then
            _cpws_pruned=$((_cpws_pruned + 1))
            ux_info "  removed stale skill link: ${_cpws_existing##*/}"
        else
            ux_error "  rm failed: $_cpws_existing"
        fi
    done <<CPWS_LINKS
$_cpws_links
CPWS_LINKS

    CLAUDE_WS_SKILLS_PRUNED=$((${CLAUDE_WS_SKILLS_PRUNED:-0} + _cpws_pruned))
    if [ "$_cpws_pruned" -gt 0 ]; then
        ux_success "  pruned stale skill links: $_cpws_tgt (removed=$_cpws_pruned root=${_cpws_root:-none})"
    fi
    return 0
}

# _claude_account_skill_dirs — print every account skills dir, one per line
# (issue #1847 F-4): ~/.claude-*/skills minus -shared/-backups. Falls back to
# ~/.claude/skills on a single-account PC. Enumerates real directories rather
# than `_claude_resolve_account --list`, whose ENABLED default omits work1.
# `find` instead of a glob: zsh `nomatch` aborts on an unmatched pattern.
_claude_account_skill_dirs() {
    _casd_found=0
    _casd_dirs="$(find "$HOME" -mindepth 1 -maxdepth 1 -name '.claude-*' 2>/dev/null | sort)"
    while IFS= read -r _casd_d; do
        [ -n "$_casd_d" ] || continue
        case "$_casd_d" in *-shared | *-backups) continue ;; esac
        [ -d "$_casd_d/skills" ] || continue
        printf '%s\n' "$_casd_d/skills"
        _casd_found=1
    done <<CASD_DIRS
$_casd_dirs
CASD_DIRS
    if [ "$_casd_found" = "0" ] && [ -d "$HOME/.claude/skills" ]; then
        printf '%s\n' "$HOME/.claude/skills"
    fi
    return 0
}

# _claude_link_one <src_real> <name> <dry> <force> <targets> — fan one source
# out into every target dir. rc 1 only when a link failed somewhere.
_claude_link_one() {
    _clo_src="$1"
    _clo_name="$2"
    _clo_dry="$3"
    _clo_force="$4"
    _clo_rc=0
    while IFS= read -r _clo_tgt; do
        [ -n "$_clo_tgt" ] || continue
        _clo_link="$_clo_tgt/$_clo_name"
        if [ -L "$_clo_link" ]; then
            if [ "$(readlink -f "$_clo_link" 2>/dev/null)" = "$_clo_src" ]; then
                ux_info "  already linked: $_clo_link"
                continue
            fi
            if [ "$_clo_force" != "1" ]; then
                ux_warning "  skip (symlink to $(readlink "$_clo_link")): $_clo_link — use --force to replace"
                continue
            fi
            if [ "$_clo_dry" = "1" ]; then
                ux_info "  would replace: $_clo_link -> $_clo_src"
                continue
            fi
            rm -f "$_clo_link" || {
                ux_error "  rm failed: $_clo_link"
                _clo_rc=1
                continue
            }
        elif [ -e "$_clo_link" ]; then
            ux_warning "  skip (real file/dir, never replaced): $_clo_link"
            continue
        elif [ "$_clo_dry" = "1" ]; then
            ux_info "  would link: $_clo_link -> $_clo_src"
            continue
        fi
        if _claude_link_lib && dotfiles_ensure_link "$_clo_src" "$_clo_link"; then
            ux_success "  linked: $_clo_link -> $_clo_src"
        else
            ux_error "  link failed: $_clo_link -> $_clo_src"
            _clo_rc=1
        fi
    done <<CLO_TGTS
$5
CLO_TGTS
    return "$_clo_rc"
}

# _claude_link_list <targets> — per account, the symlinks pointing outside the
# workspace root (issue #1847 F-3); dangling ones are marked BROKEN.
_claude_link_list() {
    while IFS= read -r _cll_tgt; do
        [ -n "$_cll_tgt" ] || continue
        ux_section "$_cll_tgt"
        _cll_links="$(find "$_cll_tgt" -mindepth 1 -maxdepth 1 -type l 2>/dev/null | sort)"
        while IFS= read -r _cll_l; do
            [ -n "$_cll_l" ] || continue
            _cll_raw=$(readlink "$_cll_l")
            _cll_real=$(readlink -f "$_cll_l" 2>/dev/null || printf '%s' "$_cll_raw")
            if _skill_under_workspace "$_cll_raw" || _skill_under_workspace "$_cll_real"; then
                continue
            fi
            if [ -e "$_cll_l" ]; then
                ux_info "  ${_cll_l##*/} -> $_cll_raw"
            else
                ux_warning "  BROKEN ${_cll_l##*/} -> $_cll_raw"
            fi
        done <<CLL_LINKS
$_cll_links
CLL_LINKS
    done <<CLL_TGTS
$1
CLL_TGTS
}

# claude_accounts_link — fan external skill symlinks out into every account
# (issue #1847). Usage:
#   claude-accounts link <path|name> [--name <n>] [--dry-run] [--force]
#   claude-accounts link [--apply] [--force]   # all of ~/.claude/skills/*, dry-run unless --apply
#   claude-accounts link --list
claude_accounts_link() {
    _cal_src=""
    _cal_name=""
    _cal_dry=0
    _cal_apply=0
    _cal_force=0
    _cal_list=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --name)
                [ $# -ge 2 ] || { ux_error "--name requires a value"; return 1; }
                shift
                _cal_name="$1"
                ;;
            --dry-run | -n) _cal_dry=1 ;;
            --apply) _cal_apply=1 ;;
            --force) _cal_force=1 ;;
            --list) _cal_list=1 ;;
            -h | --help) _claude_accounts_help; return 0 ;;
            -*) ux_error "Unknown option: $1"; return 1 ;;
            *)
                [ -z "$_cal_src" ] || { ux_error "Only one <src> allowed (got: $_cal_src, $1)"; return 1; }
                _cal_src="$1"
                ;;
        esac
        shift
    done

    ux_header "claude-accounts link — external skills into every account (issue #1847)"
    _cal_tgts="$(_claude_account_skill_dirs)"
    if [ -z "$_cal_tgts" ]; then
        ux_warning "No account skills dir found (~/.claude-*/skills or ~/.claude/skills)"
        ux_info "  Run: claude-accounts setup"
        return 0
    fi

    if [ "$_cal_list" = "1" ]; then
        _claude_link_list "$_cal_tgts"
        return 0
    fi

    _cal_land="$HOME/.claude/skills"

    # Explicit source: applied immediately (--dry-run previews).
    if [ -n "$_cal_src" ]; then
        case "$_cal_src" in
            */*) ;;
            *) _cal_src="$_cal_land/$_cal_src" ;;
        esac
        if [ ! -f "$_cal_src/SKILL.md" ]; then
            ux_error "Not a skill directory (missing SKILL.md): $_cal_src"
            return 1
        fi
        _cal_real=$(readlink -f "$_cal_src")
        [ -n "$_cal_name" ] || _cal_name="${_cal_src%/}"
        _cal_name="${_cal_name##*/}"
        [ "$_cal_dry" = "1" ] && ux_info "Mode: dry-run (no files will be modified)"
        _claude_link_one "$_cal_real" "$_cal_name" "$_cal_dry" "$_cal_force" "$_cal_tgts"
        return $?
    fi

    # No source: every ~/.claude/skills entry, dry-run unless --apply.
    _cal_dry=1
    [ "$_cal_apply" = "1" ] && _cal_dry=0
    _cal_entries="$(find "$_cal_land" -mindepth 1 -maxdepth 1 2>/dev/null | sort)"
    if [ -z "$_cal_entries" ]; then
        ux_info "Nothing to link: $_cal_land is missing or empty"
        return 0
    fi
    [ "$_cal_dry" = "1" ] && ux_info "Mode: dry-run (no files will be modified) — add --apply to link"
    _cal_rc=0
    _cal_planned=0
    while IFS= read -r _cal_e; do
        [ -n "$_cal_e" ] || continue
        [ -f "$_cal_e/SKILL.md" ] || continue
        _cal_real=$(readlink -f "$_cal_e")
        # Workspace-backed entries are plugin-loaded in Claude Code and
        # setup prunes their flat links — never fan them out.
        _skill_under_workspace "$_cal_real" && continue
        _cal_n="${_cal_e##*/}"
        # Already the same target in every account — nothing to plan.
        _cal_todo=0
        while IFS= read -r _cal_t; do
            [ -n "$_cal_t" ] || continue
            [ "$(readlink -f "$_cal_t/$_cal_n" 2>/dev/null)" = "$_cal_real" ] || _cal_todo=1
        done <<CAL_TGTS
$_cal_tgts
CAL_TGTS
        [ "$_cal_todo" = "1" ] || continue
        _cal_planned=1
        ux_info "$_cal_n -> $_cal_real"
        _claude_link_one "$_cal_real" "$_cal_n" "$_cal_dry" "$_cal_force" "$_cal_tgts" || _cal_rc=1
    done <<CAL_ENTRIES
$_cal_entries
CAL_ENTRIES
    [ "$_cal_planned" = "1" ] || ux_info "Nothing to link: every external entry is already in all accounts"
    return "$_cal_rc"
}

# claude_accounts_unlink <name> — remove <name> from every account skills dir,
# symlinks only; real files/dirs are never deleted (issue #1847 F-2).
claude_accounts_unlink() {
    case "${1:-}" in -h | --help) _claude_accounts_help; return 0 ;; esac
    _cau_name="${1:-}"
    case "$_cau_name" in
        "" | */*) ux_error "Usage: claude-accounts unlink <name>"; return 1 ;;
    esac
    ux_header "claude-accounts unlink — $_cau_name"
    _cau_tgts="$(_claude_account_skill_dirs)"
    _cau_rc=0
    while IFS= read -r _cau_t; do
        [ -n "$_cau_t" ] || continue
        _cau_link="$_cau_t/$_cau_name"
        if [ -L "$_cau_link" ]; then
            if rm -f "$_cau_link"; then
                ux_success "  removed: $_cau_link"
            else
                ux_error "  rm failed: $_cau_link"
                _cau_rc=1
            fi
        elif [ -e "$_cau_link" ]; then
            ux_warning "  skip (not a symlink, left untouched): $_cau_link"
        fi
    done <<CAU_TGTS
$_cau_tgts
CAU_TGTS
    return "$_cau_rc"
}
