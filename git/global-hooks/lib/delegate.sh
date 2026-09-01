#!/usr/bin/env bash
# git/global-hooks/lib/delegate.sh
#
# Shared delegation body for the non-pre-commit global hook wrappers
# (commit-msg, post-commit, pre-push, prepare-commit-msg — issue #1664).
# Each wrapper sets HOOK_NAME then sources this file; everything else in the
# wrapper's own file is header documentation.
#
# WHAT IT DOES — DELEGATION ONLY
#   Forwards the hook to the project-level hook of the repository being
#   acted on (.githooks/ -> git/hooks/ -> .git/hooks/), passing through
#   arguments, stdin and the exit code unchanged. In a repository that ships
#   no hook of this type it is a silent no-op — repo-specific logic must
#   never fire in unrelated repositories.
#
# Requires HOOK_NAME to already be set by the caller. Uses "$0"/"$@" as
# inherited from the sourcing wrapper's own invocation (source does not
# reset positional parameters).
#
# To debug: export GIT_HOOKS_DEBUG=1

DEBUG=${GIT_HOOKS_DEBUG:-0}

# Colors (same palette as git/global-hooks/pre-commit)
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$REPO_ROOT" ]; then
    [ "$DEBUG" = "1" ] && echo "[Debug] Not in a git repository, exiting"
    exit 0
fi

# Candidate hooks in priority order (same order as the pre-commit wrapper)
CANDIDATE_HOOKS=(
  ".githooks/${HOOK_NAME}"       # Team shared hook (highest priority)
  "git/hooks/${HOOK_NAME}"       # Dotfiles/Custom structure
)

RUN_HOOK=""

for hook in "${CANDIDATE_HOOKS[@]}"; do
    HOOK_PATH="$REPO_ROOT/$hook"

    [ "$DEBUG" = "1" ] && echo "[Debug] Checking: $HOOK_PATH"

    if [ -x "$HOOK_PATH" ]; then
        # Prevent self-execution loop. `-ef` compares device+inode through
        # symlinks, so no realpath helper is needed here.
        if [ "$HOOK_PATH" -ef "$0" ]; then
            [ "$DEBUG" = "1" ] && echo "[Debug] Skipping self: $HOOK_PATH"
            continue
        fi

        RUN_HOOK="$HOOK_PATH"
        [ "$DEBUG" = "1" ] && echo "[Debug] Found executable hook: $RUN_HOOK"
        break
    fi
done

# Standard/Local hook (e.g. Husky). Resolved via `git rev-parse
# --git-common-dir`, not `$REPO_ROOT/.git/hooks/<name>`: in a linked
# worktree `.git` is a file, not a directory, so a plain path join can never
# find anything there and this candidate silently disappears (agy + codex
# review, PR #1674). `--git-common-dir` resolves the actual (shared)
# .git directory correctly both for a normal repo and for every worktree of
# it — unlike `git rev-parse --git-path hooks/<name>`, which was tried
# first and rejected: it honors `core.hooksPath` when set, so on a machine
# that already ran this repo's own setup.sh it resolves to the *global*
# hooks directory instead of the repo-local one — the exact wrapper we are
# inside, for every repo on the machine, defeating both the worktree fix and
# the pre-existing "no-op in an unrelated repo" guarantee.
if [ -z "$RUN_HOOK" ]; then
    GIT_COMMON_DIR=$(git rev-parse --git-common-dir 2>/dev/null)
    case "$GIT_COMMON_DIR" in
        /*) : ;;
        ?*) GIT_COMMON_DIR="$REPO_ROOT/$GIT_COMMON_DIR" ;;
    esac
    HOOK_PATH="${GIT_COMMON_DIR:+$GIT_COMMON_DIR/hooks/${HOOK_NAME}}"

    [ "$DEBUG" = "1" ] && echo "[Debug] Checking: $HOOK_PATH"

    if [ -n "$HOOK_PATH" ] && [ -x "$HOOK_PATH" ] && ! [ "$HOOK_PATH" -ef "$0" ]; then
        RUN_HOOK="$HOOK_PATH"
        [ "$DEBUG" = "1" ] && echo "[Debug] Found executable hook: $RUN_HOOK"
    elif [ "$DEBUG" = "1" ] && [ -n "$HOOK_PATH" ] && [ -x "$HOOK_PATH" ]; then
        echo "[Debug] Skipping self: $HOOK_PATH"
    fi
fi

if [ -z "$RUN_HOOK" ]; then
    [ "$DEBUG" = "1" ] && echo "[Debug] No project-level ${HOOK_NAME} hook found"
    exit 0
fi

echo -e "${BLUE}[Global Hook] Delegating to project hook: $RUN_HOOK${NC}"

# `exec` replaces this wrapper's own process image with the project hook
# instead of running it as a waited-on child (agy review, PR #1674) — one
# fewer process, and git sees $RUN_HOOK's own exit code directly rather than
# this wrapper relaying it. Nothing below this line runs on the success
# path.
exec "$RUN_HOOK" "$@"

# Reached only if exec itself could not launch $RUN_HOOK (e.g. a
# binary-format mismatch) — the earlier `[ -x ]` check already ruled out
# "missing" or "not executable".
echo -e "${RED}✗ Failed to exec project hook: $RUN_HOOK${NC}" >&2
exit 126
