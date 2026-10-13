#!/bin/bash

# scripts/update-skills.sh: skills 업데이트 5단계를 한 번에 실행 (#1825, #1903)
#
#   1. claude/plugin/git-clone-skills.sh      — manifest 의 누락 repo clone (idempotent, --dry-run 만 전달)
#   2. claude/plugin/git-pull-skills.sh "$@"  — workspace repo pull
#   3. claude/setup.sh                        — 계정 디렉토리 링크 + 남은 평면 스킬 링크 정리
#                                               (스킬 자체는 4단계 plugin store 에서 로드)
#   4. claude/plugin/update-plugins.sh        — Claude Code plugin store 갱신
#                                               (marketplace update + plugin update)
#   5. scripts/setup-skills-ssot.sh           — OpenCode/Codex/agy 합성 + Hermes external_dirs (#1829)
#
# 4단계가 필요한 이유: Claude Code 는 workspace clone 이 아니라 plugin store
# (plugins/marketplaces, plugins/cache/<mkt>/<plugin>/<ver>) 에서 스킬을 로드한다.
# 2단계 pull 만으로는 설치 버전이 갱신되지 않는다.
#
# 출력 (#2126): 기본은 요약 모드 — shared step runner
# (shell-common/tools/ux_lib/step_runner.sh) 로 스텝당 1줄, 경고/실패만 상세,
# 전체 출력은 ${TMPDIR:-/tmp}/skills-sync-<ts>.log (경고/실패 시에만 경로 표시).
# -v / --verbose 또는 SKILLS_SYNC_VERBOSE=1 이면 하위 스크립트 출력을 전부 흘린다.
# -v 는 여기서 소비하고 2단계로 넘기지 않는다.
#
# 종료 코드: 1·2·3·5단계 실패는 즉시 비0 종료 (critical). 4단계 실패는 5단계를
# 막지 않고 (optional), 마지막에 그 종료 코드로 끝난다. 나머지 인자는 2단계로
# 전달되고, clone/update-plugins 단계에는 --dry-run 만 전달된다. --dry-run 이
# 있으면 clone/pull/update-plugins dry-run 만 실행하고 합성은 건너뛴다.
# Alias: skills-sync (shell-common/aliases/skills_sync.sh)

set -euo pipefail

_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
DOTFILES_ROOT="$(cd "$(dirname "$_SCRIPT_PATH")/.." && pwd)"

# shellcheck source=../shell-common/tools/ux_lib/ux_lib.sh
source "${DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh"
# shellcheck source=../shell-common/tools/ux_lib/step_runner.sh
source "${DOTFILES_ROOT}/shell-common/tools/ux_lib/step_runner.sh"

verbose="${SKILLS_SYNC_VERBOSE:-0}"
dry_run=0
pull_args=()
for arg in "$@"; do
    case "$arg" in
    -v | --verbose) verbose=1 ;;
    *)
        if [ "$arg" = --dry-run ]; then dry_run=1; fi
        pull_args+=("$arg")
        ;;
    esac
done
clone_args=()
if [ "$dry_run" = 1 ]; then clone_args=(--dry-run); fi

# Last "◆ <key>: <n>" (or ux_lib-fallback "* <key>: <n>") Summary count in the
# step's captured output; empty when the line is missing. <key> is an ERE.
# shellcheck disable=SC2317  # reached only via the STEP_*_FN callbacks
_us_count() {
    sed 's/\x1b\[[0-9;]*m//g' "$STEP_OUT" |
        sed -En "s/^[[:space:]]*(◆|\*) $1: ([0-9]+).*$/\2/p" | tail -n 1
}

# STEP_DIGEST_FN: change counts from the sub-script's Summary block (F-3).
# A missing/changed Summary format just drops the digest.
# shellcheck disable=SC2317  # reached only via the STEP_*_FN callbacks
_us_digest() {
    local n up fail
    case "$1" in
    git-clone-skills*)
        n=$(_us_count Cloned)
        if [ -z "$n" ]; then n=$(_us_count "Would clone"); fi
        if [ -n "$n" ] && [ "$n" != 0 ]; then STEP_DIGEST="신규 clone $n"; fi
        ;;
    git-pull-skills*)
        n=$(_us_count Updated)
        if [ -z "$n" ]; then n=$(_us_count "Updates available"); fi
        up=$(_us_count "Up to date")
        if [ -n "$n" ] && [ -n "$up" ]; then STEP_DIGEST="갱신 $n / 최신 $up"; fi
        ;;
    update-plugins*)
        n=$(_us_count "Plugins updated")
        up=$(_us_count "Plugins up to date")
        fail=$(_us_count Failed)
        if [ -n "$n" ] && [ -n "$up" ]; then
            STEP_DIGEST="갱신 $n / 최신 $up"
        else
            n=$(_us_count "Plugins \\(would update\\)")
            if [ -n "$n" ]; then STEP_DIGEST="갱신 예정 $n"; fi
        fi
        if [ -n "$STEP_DIGEST" ] && [ -n "$fail" ] && [ "$fail" != 0 ]; then
            STEP_DIGEST="$STEP_DIGEST / 실패 $fail"
        fi
        ;;
    esac
    return 0
}

# STEP_HINT_FN: per-step fix hint on failure.
# shellcheck disable=SC2317  # reached only via the STEP_*_FN callbacks
_us_hint() {
    case "$1" in
    git-clone-skills*) ux_bullet_sub "manifest(claude/plugin/marketplaces.json) 와 네트워크/인증 확인" ;;
    git-pull-skills*) ux_bullet_sub "충돌/분기된 repo 확인 — skills-sync --dry-run 으로 대상 미리보기" ;;
    update-plugins*) ux_bullet_sub "네트워크/claude CLI 확인 후 skills-sync 재실행 (5단계는 이미 진행됨)" ;;
    esac
    return 0
}

# _us_step <n> <label> <critical|optional> <cmd...> — verbose mode keeps the
# per-step section header so the streamed output reads as before.
_us_step() {
    local n="$1"
    shift
    if [ "$STEP_VERBOSE" = 1 ]; then ux_section "$n/5 $1"; fi
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

if [ "$dry_run" = 1 ]; then
    _us_step 1 "git-clone-skills (dry-run)" critical \
        "${DOTFILES_ROOT}/claude/plugin/git-clone-skills.sh" "${clone_args[@]}"
    _us_step 2 "git-pull-skills (dry-run)" critical \
        "${DOTFILES_ROOT}/claude/plugin/git-pull-skills.sh" "${pull_args[@]}"
    _us_step 4 "update-plugins (dry-run)" optional \
        "${DOTFILES_ROOT}/claude/plugin/update-plugins.sh" --dry-run
    plugins_rc=$STEP_LAST_RC
    ux_info "--dry-run: 합성 단계(claude/setup.sh, setup-skills-ssot.sh)를 건너뜁니다"
    step_summary "skills-sync (dry-run)"
    exit "$plugins_rc"
fi

_us_step 1 git-clone-skills critical \
    "${DOTFILES_ROOT}/claude/plugin/git-clone-skills.sh" ${clone_args[@]+"${clone_args[@]}"}
_us_step 2 git-pull-skills critical \
    "${DOTFILES_ROOT}/claude/plugin/git-pull-skills.sh" ${pull_args[@]+"${pull_args[@]}"}
_us_step 3 claude/setup.sh critical "${DOTFILES_ROOT}/claude/setup.sh"
# plugin 갱신 실패(네트워크 등)는 5단계 합성을 막지 않는다 — 끝까지 진행한 뒤
# 그 종료 코드로 끝낸다.
_us_step 4 update-plugins optional "${DOTFILES_ROOT}/claude/plugin/update-plugins.sh"
plugins_rc=$STEP_LAST_RC
_us_step 5 setup-skills-ssot critical "${DOTFILES_ROOT}/scripts/setup-skills-ssot.sh"

step_summary skills-sync
exit "$plugins_rc"
