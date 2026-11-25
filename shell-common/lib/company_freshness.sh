#!/bin/sh
# shell-common/lib/company_freshness.sh
# SSOT for "is claude/plugin/company/ current with origin/main, and which
# exact command fixes it" (#2446). skills-register (claude/plugin/register.sh)
# refuses on anything but fresh; skills-sync (scripts/update-skills.sh) pulls a
# behind main and warns otherwise — both print the same state and command.
#
# No interactive guard on purpose: a function-only library sourced by scripts
# and bats (same rationale as util/setup_mode_read.sh).

# _company_freshness <company-dir> — classify company/ against origin/main.
# The caller fetches origin first. Sets:
#   CF_STATE   fresh | behind | stale-branch | diverged-branch
#   CF_BRANCH  current branch ("HEAD" when detached)
#   CF_FIX     exact fix command ("" for fresh and diverged-branch)
#   CF_MSG     one-line explanation ("" for fresh)
# A main that is ahead of origin/main (unpublished commits) counts as fresh.
_company_freshness() {
    _cf_dir=$1
    CF_STATE=fresh
    CF_FIX=""
    CF_MSG=""
    CF_BRANCH=$(git -C "$_cf_dir" symbolic-ref --quiet --short HEAD 2>/dev/null) || CF_BRANCH=HEAD
    if [ "$CF_BRANCH" = main ]; then
        git -C "$_cf_dir" merge-base --is-ancestor origin/main HEAD 2>/dev/null && return 0
        CF_STATE=behind
        # --autostash: works with uncommitted changes (e.g. *.local.json).
        CF_FIX="git -C $_cf_dir pull --rebase --autostash origin main"
        CF_MSG="company/ main 이 origin/main 보다 뒤처져 있습니다"
        return 0
    fi
    # Safe to drop the branch only when its committed AND working-tree manifests
    # already equal origin/main: nothing unpublished can be lost.
    # `switch -C main origin/main` also resets a local main, so refuse when that
    # branch holds commits origin/main lacks.
    if git -C "$_cf_dir" diff --quiet origin/main HEAD -- marketplaces.json plugins.json 2>/dev/null &&
        git -C "$_cf_dir" diff --quiet HEAD -- marketplaces.json plugins.json 2>/dev/null &&
        { ! git -C "$_cf_dir" show-ref --verify --quiet refs/heads/main ||
            git -C "$_cf_dir" merge-base --is-ancestor main origin/main 2>/dev/null; }; then
        CF_STATE=stale-branch
        CF_FIX="git -C $_cf_dir switch -C main origin/main"
        CF_MSG="company/ 가 main 이 아닌 '$CF_BRANCH' 브랜치입니다 (manifest 는 origin/main 과 같아 main 으로 전환해도 안전)"
    else
        CF_STATE=diverged-branch
        CF_MSG="company/ 가 main 이 아닌 '$CF_BRANCH' 브랜치이고 manifest 가 origin/main 과 다릅니다 — 미게시 변경이 있을 수 있어 자동 처리하지 않습니다 (확인: git -C $_cf_dir diff origin/main -- marketplaces.json plugins.json)"
    fi
    return 0
}
