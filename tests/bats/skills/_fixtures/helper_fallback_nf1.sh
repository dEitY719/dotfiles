#!/usr/bin/env bash
# tests/bats/skills/_fixtures/helper_fallback_nf1.sh
# Source-of-truth mirror for the canonical F-2 helper-fallback pattern
# documented in issue #644 and applied across:
#   claude/skills/gh-pr-merge/SKILL.md           (Step 2-B, Step 4)
#   claude/skills/gh-commit/SKILL.md             (Step 5)
#   claude/skills/gh-pr-reply/SKILL.md           (Step 6.5)
#   claude/skills/gh-pr/references/project-board-sync.md
#   claude/skills/gh-pr-merge/references/project-board-sync.md
#   claude/skills/gh-pr-merge-emergency/references/project-board-sync.md
#
# Tests inject SHELL_COMMON pointing at a real fixture dir (helper present)
# or a non-existent dir (helper missing). The wrapper must:
#   - call _gh_project_status_sync when helper is readable
#   - silently skip (no command-not-found) when helper is missing
#   - never abort the calling skill on either branch (NF-1 guarantee)

# Mirrors the canonical F-2 block. Keep this in sync with the SKILL.md
# edits made for issue #644.
nf1_canonical_block() {
    local _PR="$1"
    local _STATE="$2"

    local _HELPER="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_project_status.sh"
    if [ -r "$_HELPER" ]; then
        # shellcheck disable=SC1090
        . "$_HELPER"
        _gh_project_status_sync pr "$_PR" "$_STATE" || true
        echo "BLOCK_RAN sync_called"
    fi
    echo "BLOCK_COMPLETED"
}

# Synthesise a minimal helper file at the given path. Defines a stub
# _gh_project_status_sync that records its call and returns 0.
nf1_install_fake_helper() {
    local _path="$1"
    mkdir -p "$(dirname "$_path")"
    cat >"$_path" <<'EOF'
_gh_project_status_sync() {
    printf 'fake-helper invoked with: %s\n' "$*" >&2
    return 0
}
EOF
}
