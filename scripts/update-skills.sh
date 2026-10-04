#!/bin/bash

# scripts/update-skills.sh: skills 업데이트 4단계를 한 번에 실행 (#1825, #1903)
#
#   1. claude/plugin/git-clone-skills.sh      — manifest 의 누락 repo clone (idempotent, --dry-run 만 전달)
#   2. claude/plugin/git-pull-skills.sh "$@"  — marketplace repo pull
#   3. claude/setup.sh                        — Claude Code 합성
#   4. scripts/setup-skills-ssot.sh           — OpenCode/Codex/agy 합성 + Hermes external_dirs (#1829)
#
# 1·2단계가 실패하면 set -e 로 합성 없이 중단한다. 인자는 2단계로 전달되고,
# clone 단계에는 --dry-run 만 전달된다. --dry-run 이 있으면 clone/pull dry-run 만
# 실행하고 합성은 건너뛴다.
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

ux_section "1/4 git-clone-skills"
"${DOTFILES_ROOT}/claude/plugin/git-clone-skills.sh" "${clone_args[@]}"

ux_section "2/4 git-pull-skills"
"${DOTFILES_ROOT}/claude/plugin/git-pull-skills.sh" "$@"

case " $* " in
*' --dry-run '*)
    ux_info "--dry-run: 합성 단계(claude/setup.sh, setup-skills-ssot.sh)를 건너뜁니다"
    exit 0
    ;;
esac

ux_section "3/4 claude/setup.sh"
"${DOTFILES_ROOT}/claude/setup.sh"

ux_section "4/4 setup-skills-ssot.sh"
"${DOTFILES_ROOT}/scripts/setup-skills-ssot.sh"

ux_success "skills 업데이트 완료"
