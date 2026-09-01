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
  ".git/hooks/${HOOK_NAME}"      # Standard/Local hook (e.g. Husky)
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

if [ -z "$RUN_HOOK" ]; then
    [ "$DEBUG" = "1" ] && echo "[Debug] No project-level ${HOOK_NAME} hook found"
    exit 0
fi

echo -e "${BLUE}[Global Hook] Delegating to project hook: $RUN_HOOK${NC}"

if "$RUN_HOOK" "$@"; then
    [ "$DEBUG" = "1" ] && echo -e "${GREEN}✓ Project hook completed successfully${NC}"
    exit 0
else
    PROJECT_EXIT=$?
    echo -e "${RED}✗ Project hook failed with exit code $PROJECT_EXIT${NC}"
    exit $PROJECT_EXIT
fi
