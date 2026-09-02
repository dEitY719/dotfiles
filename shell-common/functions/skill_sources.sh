#!/bin/sh
# shell-common/functions/skill_sources.sh
# Enumerate the skill sources every harness composes from.
#
# SSOT for the skill-source list (issue #1652, completed by #1680 —
# #1410 F-6/Phase 4). Locally cloned marketplace repos sit side by side
# under a single root:
#
#     ${WORKSPACE_ROOT:-$HOME/para/project/skills}/<repo>/skills/<skill>/SKILL.md
#
# and every harness links them as entry-level symlinks. This workspace is
# now the *only* source: #1680 deleted the dotfiles `claude/skills/` tree
# after #1410 copied all 73 skills out into 15 marketplace repos.
#
# Two consumers share these helpers so their notion of "what counts as a
# workspace skill" cannot drift apart:
#   - scripts/setup-skills-ssot.sh              (Codex / OpenCode / Gemini+agy / Hermes)
#   - shell-common/tools/integrations/claude.sh (Claude Code accounts)
#
# No interactive guard — this file only defines functions and prints
# nothing when sourced (same posture as functions/gh_host.sh, PR #704).

# _skill_workspace_root — print the effective workspace root, or nothing.
#
# Returns 1 without printing when the root is missing or set to a value
# too broad to be safe. The breadth guard is load-bearing: callers decide
# what they may delete by asking "does this symlink point under the
# root?", so a root of `/` or `$HOME` would make every unrelated user
# symlink look like ours.
_skill_workspace_root() {
    _sws_root="${WORKSPACE_ROOT:-$HOME/para/project/skills}"

    # Compare resolved paths, not raw strings: with a symlinked $HOME the two
    # spellings of the same directory would otherwise slip past the guard.
    # Mirrors scripts/setup-skills-ssot.sh's _realpath_or_self handling.
    _sws_real=$(readlink -f "$_sws_root" 2>/dev/null || printf '%s' "$_sws_root")
    _sws_home=$(readlink -f "$HOME" 2>/dev/null || printf '%s' "$HOME")

    case "$_sws_root" in
        "" | "/" | "$HOME" | "$HOME/") return 1 ;;
    esac
    case "$_sws_real" in
        "" | "/" | "$_sws_home") return 1 ;;
    esac

    [ -d "$_sws_root" ] || return 1

    printf '%s\n' "${_sws_root%/}"
}

# _skill_workspace_dirs [root] — print one workspace skill directory per
# line (no trailing slash), in glob order.
#
# Resolves the root itself when the argument is omitted, and prints
# nothing when there is none. A repo with no `skills/` subdirectory and a
# `skills/` entry with no `SKILL.md` are both silent skips: a workspace
# holds ordinary clones, not a curated tree, so neither is an error.
_skill_workspace_dirs() {
    _swd_root="${1:-}"
    if [ -z "$_swd_root" ]; then
        # Unquoted on purpose: an assignment RHS is not word-split, and the
        # pre-commit naming check flags a locally-defined function name that
        # appears inside double quotes.
        _swd_root=$(_skill_workspace_root) || return 0
    fi

    # `find` rather than a shell glob: zsh aborts the enclosing function on
    # an unmatched glob (`nomatch`), and "workspace exists but holds no
    # skills yet" is the ordinary first-run state — the same reason
    # functions/devops_help.sh reaches for find. `sort` makes the order
    # explicit so a name collision between two repos resolves the same way
    # on every run rather than following directory order.
    find "$_swd_root" -mindepth 4 -maxdepth 4 ! -type d -name SKILL.md \
        -path "${_swd_root}/*/skills/*/SKILL.md" 2>/dev/null \
        | sed 's|/SKILL\.md$||' \
        | LC_ALL=C sort \
        | while IFS= read -r _swd_dir; do
            _swd_repo="${_swd_dir%/skills/*}"
            # A linked git worktree keeps `.git` as a regular *file*
            # pointing back at the main clone; a normal clone has a `.git`
            # directory. Worktrees are skipped: they are a transient
            # checkout of a repo that is usually already in the workspace,
            # and `<repo>-<branch>` sorts ahead of `<repo>` under LC_ALL=C
            # (`-` < `/`), so a feature worktree would silently shadow the
            # canonical clone's skills.
            [ -f "${_swd_repo}/.git" ] && continue
            printf '%s\n' "$_swd_dir"
        done
}
