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
# 1·2단계가 실패하면 set -e 로 합성 없이 중단한다. 4단계 실패는 5단계를 막지
# 않고, 마지막에 그 종료 코드로 끝난다. 인자는 2단계로 전달되고,
# clone/update-plugins 단계에는 --dry-run 만 전달된다. --dry-run 이 있으면
# clone/pull/update-plugins dry-run 만 실행하고 합성은 건너뛴다.
# Alias: skills-sync (shell-common/aliases/skills_sync.sh)

set -euo pipefail

_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
DOTFILES_ROOT="$(cd "$(dirname "$_SCRIPT_PATH")/.." && pwd)"

# shellcheck source=../shell-common/tools/ux_lib/ux_lib.sh
source "${DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh"

clone_args=()
case " $* " in
*' --dry-run '*) clone_args=(--dry-run) ;;
esac

ux_section "1/5 git-clone-skills"
"${DOTFILES_ROOT}/claude/plugin/git-clone-skills.sh" ${clone_args[@]+"${clone_args[@]}"}

ux_section "2/5 git-pull-skills"
"${DOTFILES_ROOT}/claude/plugin/git-pull-skills.sh" "$@"

case " $* " in
*' --dry-run '*)
    ux_section "4/5 update-plugins (dry-run)"
    "${DOTFILES_ROOT}/claude/plugin/update-plugins.sh" --dry-run
    ux_info "--dry-run: 합성 단계(claude/setup.sh, setup-skills-ssot.sh)를 건너뜁니다"
    exit 0
    ;;
esac

ux_section "3/5 claude/setup.sh"
"${DOTFILES_ROOT}/claude/setup.sh"

# plugin 갱신 실패(네트워크 등)는 5단계 합성을 막지 않는다 — 끝까지 진행한 뒤
# 그 종료 코드로 끝낸다.
ux_section "4/5 update-plugins"
plugins_rc=0
"${DOTFILES_ROOT}/claude/plugin/update-plugins.sh" || plugins_rc=$?

ux_section "5/5 setup-skills-ssot.sh"
"${DOTFILES_ROOT}/scripts/setup-skills-ssot.sh"

if [ "$plugins_rc" -ne 0 ]; then
    ux_warning "update-plugins 단계에 실패 항목이 있습니다 (exit ${plugins_rc})"
    exit "$plugins_rc"
fi
ux_success "skills 업데이트 완료"
