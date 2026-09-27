#!/bin/bash

# scripts/update-skills.sh: skills 업데이트 3단계를 한 번에 실행 (#1825)
#
#   1. claude/plugin/git-pull-skills.sh "$@"  — marketplace repo pull
#   2. claude/setup.sh                        — Claude Code 합성
#   3. scripts/setup-skills-ssot.sh           — OpenCode/Codex/Gemini/Hermes 합성
#
# 1단계가 실패하면 set -e 로 합성 없이 중단한다. 인자는 1단계로만 전달되며,
# --dry-run 이 있으면 pull dry-run 만 실행하고 합성은 건너뛴다.
# Alias: skills-sync (shell-common/aliases/skills_sync.sh)

set -euo pipefail

_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
DOTFILES_ROOT="$(cd "$(dirname "$_SCRIPT_PATH")/.." && pwd)"

# shellcheck source=../shell-common/tools/ux_lib/ux_lib.sh
source "${DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh"

ux_section "1/3 git-pull-skills"
"${DOTFILES_ROOT}/claude/plugin/git-pull-skills.sh" "$@"

case " $* " in
*' --dry-run '*)
    ux_info "--dry-run: 합성 단계(claude/setup.sh, setup-skills-ssot.sh)를 건너뜁니다"
    exit 0
    ;;
esac

ux_section "2/3 claude/setup.sh"
"${DOTFILES_ROOT}/claude/setup.sh"

ux_section "3/3 setup-skills-ssot.sh"
"${DOTFILES_ROOT}/scripts/setup-skills-ssot.sh"

ux_success "skills 업데이트 완료"
