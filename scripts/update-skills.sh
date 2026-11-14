#!/bin/bash

# scripts/update-skills.sh: skills 업데이트와 drift 점검을 한 번에 실행 (#1825, #1903, #2344, #2366)
#
#   1. claude/plugin/git-clone-skills.sh      — manifest 의 누락 repo clone (idempotent, --dry-run 만 전달)
#   2. claude/plugin/git-pull-skills.sh "$@"  — workspace repo pull
#   3. claude/setup.sh                        — 계정 디렉토리 링크 + 남은 평면 스킬 링크 정리
#                                               (스킬 자체는 4·5단계 plugin store 에서 로드)
#   4. claude/plugin/update-plugins.sh        — Claude Code plugin store 갱신
#                                               (marketplace update + plugin update)
#   5. claude/plugin/restore.sh --check       — 읽기 전용 설치 drift 경고
#   6. scripts/setup-skills-ssot.sh           — OpenCode/Codex/agy 합성 + Hermes external_dirs (#1829)
#   --restore 시 4a. restore.sh               — 명시적으로 누락 항목 add/install, update 전에 실행
#
# 4·5단계가 필요한 이유: Claude Code 는 workspace clone 이 아니라 plugin store
# (plugins/marketplaces, plugins/cache/<mkt>/<plugin>/<ver>) 에서 스킬을 로드한다.
# 2단계 pull 만으로는 설치도 설치 버전 갱신도 일어나지 않는다. 설치는 느리고 인증을
# 요구하므로 기본은 5단계의 읽기 전용 점검만 한다. --restore 는 3단계가 계정 plugins
# 링크를 맞춘 뒤, update 전에 명시적으로 설치를 수행한다.
#
# 출력 (#2126): 기본은 요약 모드 — shared step runner
# (shell-common/tools/ux_lib/step_runner.sh) 로 스텝당 1줄, 경고/실패만 상세,
# 전체 출력은 ${TMPDIR:-/tmp}/skills-sync-<ts>.log (경고/실패 시에만 경로 표시).
# -v / --verbose 또는 SKILLS_SYNC_VERBOSE=1 이면 하위 스크립트 출력을 전부 흘린다.
# -v 는 여기서 소비하고 2단계로 넘기지 않는다.
#
# 종료 코드: 1·2·3·6단계 실패는 즉시 비0 종료 (critical). 선택 설치·갱신·점검 실패는 이후
# 단계를 막지 않고 (optional), 마지막에 그중 첫 비0 종료 코드로 끝난다. git-pull
# 옵션은 2단계로 전달되고, clone/restore/update-plugins 단계에는 --dry-run 만
# 전달된다. --dry-run 이 있으면 clone/pull/restore/update-plugins dry-run 만
# 실행하고 합성은 건너뛴다. claude CLI 가 없는 PC 에서 4단계는 실패가 아닌
# 건너뜀이다 (restore.sh --skip-without-claude).
#
# --only <step> 은 한 스텝만 실행한다 (clone pull setup restore-plugins
# update-plugins restore-check ssot; 예: skills-sync --only restore-check).
# 인자는 부작용 전에 검증한다 — 위 옵션과 git-pull-skills 옵션
# (--all-branches, --target) 외는 exit 2, 스텝 이름이면 --only 를 안내한다.
# 요약 끝에 repo 갱신 수와 플러그인 갱신 수가 어긋난 이유를 한 줄 덧붙인다.
# Alias: skills-sync (shell-common/aliases/skills_sync.sh)

set -euo pipefail

_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
DOTFILES_ROOT="$(cd "$(dirname "$_SCRIPT_PATH")/.." && pwd)"

# shellcheck source=../shell-common/tools/ux_lib/ux_lib.sh
source "${DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh"
# shellcheck source=../shell-common/tools/ux_lib/step_runner.sh
source "${DOTFILES_ROOT}/shell-common/tools/ux_lib/step_runner.sh"

# --only 값 = 스텝 이름 (실행 순서). restore-plugins 는 --restore 스텝이다.
US_STEPS="clone pull setup restore-plugins update-plugins restore-check ssot"

_us_help() {
    ux_usage "skills-sync" "[-v|--verbose] [--dry-run] [--restore] [--only <step>] [git-pull-skills options]" \
        "clone -> pull -> claude/setup.sh -> update-plugins -> restore --check -> setup-skills-ssot.sh"
    ux_bullet "-v, --verbose: stream full sub-script output (SKILLS_SYNC_VERBOSE=1 is the same)"
    ux_bullet "--restore: restore missing plugins before update (default is read-only drift check only)"
    ux_bullet "--dry-run: preview clone/pull/update/check; with --restore, preview installation too; skip synthesis"
    ux_bullet "--only <step>: run just that one step — ${US_STEPS// /, }"
    ux_bullet "--jobs <N>: repos / marketplaces synced in parallel by pull and update-plugins (default 4, DOTFILES_SKILLS_JOBS)"
    ux_bullet "git-pull-skills options (passed to pull): --all-branches, --target <dir> (see: claude/plugin/git-pull-skills.sh --help)"
}

# _us_bad_arg <msg> [arg] — usage error before any side effect: exit 2. A
# step-like word (`skills-sync restore --check`) points at --only <step>.
_us_bad_arg() {
    local word="${2:-}" step=""
    ux_error "$1"
    word="${word#"${word%%[!-]*}"}" # leading dashes off: --check reads as check
    case "$word" in
    clone | pull | setup | ssot | update-plugins | restore-plugins | restore-check) step="$word" ;;
    restore | check) step="restore-check" ;;
    update | plugins) step="update-plugins" ;;
    synthesis | setup-skills-ssot) step="ssot" ;;
    esac
    if [ -n "$step" ]; then
        ux_info "스텝 단독 실행은 --only <step>: skills-sync --only $step"
    fi
    _us_help >&2
    exit 2
}

verbose="${SKILLS_SYNC_VERBOSE:-0}"
dry_run=0
restore=0
only=""
pull_args=()
prev=""
for arg in "$@"; do
    # A --target value is git-pull-skills' own, even when it reads "-v"/"help".
    if [ "$prev" = --target ]; then
        pull_args+=("$arg")
        prev=""
        continue
    fi
    # --jobs feeds both parallel steps (pull + update-plugins) through the env
    # var they share; each validates the value itself (#2198).
    if [ "$prev" = --jobs ]; then
        export DOTFILES_SKILLS_JOBS="$arg"
        prev=""
        continue
    fi
    if [ "$prev" = --only ]; then
        only="$arg"
        prev=""
        continue
    fi
    prev="$arg"
    case "$arg" in
    --jobs | --only) ;;
    --jobs=*) export DOTFILES_SKILLS_JOBS="${arg#*=}" ;;
    --only=*) only="${arg#*=}" ;;
    -h | --help | help)
        # Before any side effect — summary mode would otherwise swallow
        # git-pull-skills' help text and still run the full sync.
        _us_help
        exit 0
        ;;
    -v | --verbose) verbose=1 ;;
    --restore) restore=1 ;;
    --dry-run)
        dry_run=1
        pull_args+=("$arg")
        ;;
    # Mirrors git-pull-skills.sh's option case (--jobs/-h are handled above);
    # update_skills.bats pins that list. Anything else would only fail inside
    # step 2 after clone already ran, so reject it here.
    --all-branches | --target | --target=*) pull_args+=("$arg") ;;
    *) _us_bad_arg "알 수 없는 인자: $arg" "$arg" ;;
    esac
done
case "$prev" in --only | --jobs | --target) _us_bad_arg "$prev 에 값이 필요합니다" ;; esac
if [ -n "$only" ]; then
    case " $US_STEPS " in
    *" $only "*) ;;
    *) _us_bad_arg "알 수 없는 스텝: $only (--only 허용값: ${US_STEPS// /, })" ;;
    esac
    if [ "$dry_run" = 1 ]; then
        case "$only" in setup | ssot) _us_bad_arg "--dry-run 은 합성 스텝($only)을 실행하지 않습니다" ;; esac
    fi
    if [ "$only" = restore-plugins ]; then restore=1; fi
fi

# Last "◆ <key>: <n>" (or ux_lib-fallback "* <key>: <n>") Summary count in
# $_US_CLEAN (the step output with ANSI escapes stripped, set by _us_digest);
# empty when the line is missing. <key> is an ERE.
# shellcheck disable=SC2317  # reached only via the STEP_*_FN callbacks
_us_count() {
    sed -En "s/^[[:space:]]*(◆|\*) $1: ([0-9]+).*$/\2/p" <<<"$_US_CLEAN" | tail -n 1
}

# Per-item success lines ("✅ <msg>", or ux_lib-fallback "OK: <msg>") in
# $_US_CLEAN: the <msg> part, rewritten by the sed ERE "<pattern>/<replacement>"
# pair(s) in "$@" (each run as s/^<pattern>/<replacement>/p, first match wins:
# `t` ends the cycle so a rewritten line is never re-matched) — the STEP_DETAIL
# source (#2337). No match -> empty. The patterns mirror the sub-scripts'
# ux_success wording; tests/bats/scripts/update_skills.bats pins that wording.
# shellcheck disable=SC2317  # reached only via the STEP_*_FN callbacks
_us_items() {
    local args=() e
    for e in "$@"; do args+=(-e "s/^$e/p" -e t); done
    sed -En 's/^[[:space:]]*(✅|OK:)[[:space:]]+//p' <<<"$_US_CLEAN" | sed -En "${args[@]}"
}

# STEP_DIGEST_FN: change counts from the sub-script's Summary block (F-3),
# plus STEP_DETAIL — one line per updated / cloned item (#2337).
# A missing/changed Summary or per-item format just drops the digest/detail.
# shellcheck disable=SC2317  # reached only via the STEP_*_FN callbacks
_us_digest() {
    local n up odd
    # Strip SGR (\e[..m) and charset selects (\e(B — part of `tput sgr0` on
    # xterm-like TERMs, which ux_lib emits even when output is redirected).
    _US_CLEAN=$(sed -e 's/\x1b\[[0-9;]*m//g' -e 's/\x1b[()][0-9A-Za-z]//g' "$STEP_OUT")
    case "$1" in
    git-clone-skills*)
        n=$(_us_count Cloned)
        if [ -z "$n" ]; then n=$(_us_count "Would clone"); fi
        if [ -n "$n" ] && [ "$n" != 0 ]; then
            STEP_DIGEST="신규 clone $n"
            # Dry-run ("Would clone") prints no "cloned from" line, so no detail.
            STEP_DETAIL=$(_us_items '([^[:space:]]+): cloned from .*$/\1')
        fi
        ;;
    git-pull-skills*)
        n=$(_us_count Updated)
        if [ -z "$n" ]; then n=$(_us_count "Updates available"); fi
        up=$(_us_count "Up to date")
        if [ -n "$n" ] && [ -n "$up" ]; then
            STEP_DIGEST="갱신 $n / 최신 $up"
            # Detail only under a digest; dry-run ("Updates available") has no
            # "updated via" lines, so it shows the count alone.
            if [ "$n" != 0 ]; then
                STEP_DETAIL=$(_us_items \
                    '([^[:space:]]+): (updated via (ff-only|rebase)|synced and pushed to origin) .*$/\1')
            fi
            # Real run only ("Updated", not dry-run's "Updates available").
            if [ -n "$(_us_count Updated)" ]; then
                _US_PULL_N=$n
                _US_PULLED=$STEP_DETAIL
            fi
        fi
        ;;
    restore-plugins*)
        # restore.sh's plain (non-TTY) ux_success has no ✅/OK: prefix, so the
        # per-item lines are matched with the prefix optional, not via _us_items.
        n=$(_us_count "Plugins installed")
        up=$(_us_count "Marketplaces added")
        if [ -n "$n" ]; then
            STEP_DIGEST="신규 설치 $n"
        else
            n=$(_us_count "Plugins \\(would install\\)")
            up=$(_us_count "Marketplaces \\(would add\\)")
            if [ -n "$n" ]; then STEP_DIGEST="설치 예정 $n"; fi
        fi
        if [ -n "$up" ] && [ "$up" != 0 ]; then STEP_DIGEST="${STEP_DIGEST:+$STEP_DIGEST / }마켓플레이스 $up"; fi
        if [ -n "$n" ] && [ "$n" != 0 ]; then
            # A real install needs a new session to load it (dry-run installs nothing).
            case "$STEP_DIGEST" in 신규*) STEP_DIGEST="$STEP_DIGEST (새 Claude Code 세션 시작 필요)" ;; esac
            STEP_DETAIL=$(sed -En 's/^[[:space:]]*(✅|OK:)?[[:space:]]*install: ([^[:space:]]+)$/\2/p' <<<"$_US_CLEAN")
        fi
        # Skips exit 0 with no WARN: prefix, so name them in the digest.
        if grep -q 'claude CLI 없음' <<<"$_US_CLEAN"; then STEP_DIGEST="claude CLI 없음 — 건너뜀"; fi
        if grep -q '플러그인 저장소 없음' <<<"$_US_CLEAN"; then
            STEP_DIGEST="${STEP_DIGEST:+$STEP_DIGEST / }plugins 저장소 없음 skip (claude/setup.sh 확인)"
        fi
        ;;
    update-plugins*)
        # Failed>0 exits 1, so a digest (rc 0 only) never needs a failure count.
        n=$(_us_count "Plugins updated")
        up=$(_us_count "Plugins up to date")
        if [ -n "$n" ] && [ -n "$up" ]; then
            STEP_DIGEST="갱신 $n / 최신 $up"
            # update-plugins' restart hint is ux_info, so summary mode would hide it.
            if [ "$n" != 0 ]; then
                STEP_DIGEST="$STEP_DIGEST (실행 중인 Claude Code 세션 재시작 필요)"
                STEP_DETAIL=$(_us_items '([^[:space:]]+): updated (.+)$/\1: \2' \
                    '([^[:space:]]+): updated$/\1')
            fi
            _US_PLUG_N=$n
            _US_PLUGGED=$STEP_DETAIL
        else
            n=$(_us_count "Plugins \\(would update\\)")
            if [ -n "$n" ]; then STEP_DIGEST="갱신 예정 $n"; fi
        fi
        for odd in "Plugins with an unrecognized result:미인식" "Plugins skipped \\(not installed\\):미설치 skip" \
            "Marketplaces skipped \\(not registered\\):미등록 skip"; do
            n=$(_us_count "${odd%%:*}")
            if [ -n "$n" ] && [ "$n" != 0 ]; then STEP_DIGEST="${STEP_DIGEST:+$STEP_DIGEST / }${odd#*:} $n"; fi
        done
        ;;
    esac
    return 0
}

# Repo-vs-plugin update sets, filled by _us_digest from the pull / update-plugins
# STEP_DETAIL (repo names; "<plugin>@<marketplace>[: old -> new]" lines).
_US_PULL_N=""
_US_PULLED=""
_US_PLUG_N=""
_US_PLUGGED=""

# _us_mismatch_note — one info line on why "repo 갱신 N" and "플러그인 갱신 M"
# differ: a pulled repo whose marketplace (same name as the repo) got no
# plugin update (no version bump, or not a marketplace), and a plugin updated
# from a marketplace that was not pulled here (external). Silent when they match.
_us_mismatch_note() {
    local mkts r id stale="" extra="" note
    if [ -z "$_US_PULL_N" ] || [ -z "$_US_PLUG_N" ]; then return 0; fi
    mkts=$(sed -E 's/:.*$//; s/^.*@//' <<<"$_US_PLUGGED")
    while IFS= read -r r; do
        if [ -n "$r" ] && ! grep -Fxq -- "$r" <<<"$mkts"; then stale="${stale:+$stale, }$r"; fi
    done <<<"$_US_PULLED"
    while IFS= read -r id; do
        id=${id%%:*}
        if [ -n "$id" ] && ! grep -Fxq -- "${id##*@}" <<<"$_US_PULLED"; then extra="${extra:+$extra, }$id"; fi
    done <<<"$_US_PLUGGED"
    if [ -z "$stale$extra" ]; then return 0; fi
    note="repo 갱신 $_US_PULL_N / 플러그인 갱신 $_US_PLUG_N —"
    if [ -n "$stale" ]; then note="$note pull 됐으나 플러그인 버전 불변: $stale"; fi
    if [ -n "$extra" ]; then note="$note${stale:+ ·} pull 없이 갱신(외부 marketplace): $extra"; fi
    ux_info "$note"
}

# STEP_HINT_FN: per-step fix hint on failure.
# shellcheck disable=SC2317  # reached only via the STEP_*_FN callbacks
_us_hint() {
    # The plugin sub-scripts all exit 2 on a usage error; then the network /
    # conflict hints below would point the wrong way. step_run sets
    # STEP_LAST_RC before calling this hint.
    if [ "${STEP_LAST_RC:-0}" = 2 ]; then
        case "$1" in
        git-* | restore* | update-plugins*)
            ux_bullet_sub "인자 확인 — skills-sync -h (사용법 오류, exit 2; 스텝 단독 실행은 --only <step>)"
            return 0
            ;;
        esac
    fi
    case "$1" in
    git-clone-skills*) ux_bullet_sub "manifest(claude/plugin/marketplaces.json) 와 네트워크/인증 확인" ;;
    git-pull-skills*) ux_bullet_sub "충돌/분기된 repo 확인 — skills-sync --dry-run 으로 대상 미리보기" ;;
    restore-plugins*) ux_bullet_sub "네트워크/인증 확인 후 skills-sync 재실행 — 남은 항목만 다시 설치 (이후 단계는 이미 진행됨)" ;;
    update-plugins*) ux_bullet_sub "네트워크/claude CLI 확인 후 skills-sync 재실행 (6단계는 이미 진행됨)" ;;
    esac
    return 0
}

# Planned steps, in run order — numbered "n/total" in verbose mode, so an
# --only run reads 1/1 instead of borrowing its full-run position.
planned=(clone pull)
if [ "$dry_run" != 1 ]; then planned+=(setup); fi
if [ "$restore" = 1 ]; then planned+=(restore-plugins); fi
planned+=(update-plugins restore-check)
if [ "$dry_run" != 1 ]; then planned+=(ssot); fi
if [ -n "$only" ]; then planned=("$only"); fi
step_total=${#planned[@]}
step_n=0

# _us_want <step> — is <step> in this run's plan?
_us_want() {
    case " ${planned[*]} " in *" $1 "*) return 0 ;; esac
    return 1
}

# _us_step <label> <critical|optional> <cmd...> — verbose mode keeps the
# per-step section header so the streamed output reads as before.
_us_step() {
    step_n=$((step_n + 1))
    if [ "$STEP_VERBOSE" = 1 ]; then ux_section "$step_n/$step_total $1"; fi
    step_run "$@"
}

STEP_NAME=skills-sync
STEP_RERUN=skills-sync
STEP_HINT_FN=_us_hint
STEP_DIGEST_FN=_us_digest
STEP_LOG_ALWAYS=0
step_init skills-sync "$verbose"
if [ "$STEP_VERBOSE" != 1 ]; then
    ux_info "skills-sync (요약 모드 — 전체 출력은 skills-sync -v)"
fi

# --dry-run: clone/pull/update/check preview; synthesis (3/6) is skipped.
clone_args=()
plugins_args=()
sfx=""
if [ "$dry_run" = 1 ]; then
    clone_args=(--dry-run)
    plugins_args=(--dry-run)
    sfx=" (dry-run)"
fi

if _us_want clone; then
    _us_step "git-clone-skills$sfx" critical \
        "${DOTFILES_ROOT}/claude/plugin/git-clone-skills.sh" ${clone_args[@]+"${clone_args[@]}"}
fi
if _us_want pull; then
    _us_step "git-pull-skills$sfx" critical \
        "${DOTFILES_ROOT}/claude/plugin/git-pull-skills.sh" ${pull_args[@]+"${pull_args[@]}"}
fi
if _us_want setup; then
    _us_step claude/setup.sh critical "${DOTFILES_ROOT}/claude/setup.sh"
fi
# 선택 설치/갱신/점검 실패(네트워크 등)는 합성을 막지 않는다 — 끝까지 진행한
# 뒤 첫 비0 종료 코드로 끝낸다.
final_rc=0
if _us_want restore-plugins; then
    restore_args=(--skip-without-claude)
    [ "$dry_run" = 1 ] && restore_args=(--dry-run)
    _us_step "restore-plugins$sfx" optional \
        "${DOTFILES_ROOT}/claude/plugin/restore.sh" "${restore_args[@]}"
    final_rc=$STEP_LAST_RC
fi
if _us_want update-plugins; then
    _us_step "update-plugins$sfx" optional \
        "${DOTFILES_ROOT}/claude/plugin/update-plugins.sh" ${plugins_args[@]+"${plugins_args[@]}"}
    if [ "$final_rc" = 0 ]; then final_rc=$STEP_LAST_RC; fi
fi
# shellcheck disable=SC2317  # reached only via step_run
_us_restore_check() {
    "${DOTFILES_ROOT}/claude/plugin/restore.sh" --check
    local rc=$?
    [ "$rc" -eq 1 ] && return 0
    return "$rc"
}
if _us_want restore-check; then
    _us_step "restore --check" optional _us_restore_check
    if [ "$final_rc" = 0 ]; then final_rc=$STEP_LAST_RC; fi
fi
if _us_want ssot; then
    _us_step setup-skills-ssot critical "${DOTFILES_ROOT}/scripts/setup-skills-ssot.sh"
elif [ "$dry_run" = 1 ] && [ -z "$only" ]; then
    ux_info "--dry-run: 합성 단계(claude/setup.sh, setup-skills-ssot.sh)를 건너뜁니다"
fi

_us_mismatch_note
step_summary "skills-sync$sfx"
exit "$final_rc"
