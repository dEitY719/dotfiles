#!/usr/bin/env bash
# git/global-hooks/lib/lfs.sh
#
# git-lfs chaining for the global hook wrappers. `git lfs install` writes
# pre-push / post-commit / post-checkout / post-merge into core.hooksPath —
# the same directory our wrappers own. git/setup.sh replaces those files with
# our symlinks (backing them up as <name>.original), so without this step an
# LFS repo silently stops uploading LFS objects on push and loses lockable-file
# handling. `git lfs install --local` cannot repair that: git-lfs resolves the
# hooks dir through core.hooksPath too and refuses ("Hook already exists"),
# and `--force` would overwrite our wrappers until the next setup.sh run.
#
# WHAT IT DOES
#   lfs_chain "$@" runs `git lfs <hook> "$@"` — exactly what the git-lfs hook
#   it replaced did — before delegate.sh forwards to the project hook. It is a
#   silent no-op (no output, no stdin read) unless ALL hold:
#   - HOOK_NAME is one of the four hooks git-lfs installs
#   - `git-lfs` is on PATH (git-lfs's own hook exits 2 when it is missing,
#     which in a non-LFS repo would break every push — we skip instead)
#   - the repo uses LFS: <git-common-dir>/lfs exists. git-lfs creates it the
#     first time its clean/smudge filter stores an object, so it exists in
#     every repo that can have LFS objects to push or check out. One stat,
#     worktree-safe via --git-common-dir, and unlike grepping .gitattributes
#     it also covers nested .gitattributes and .git/info/attributes.
#   - RUN_HOOK does not already call `git lfs <hook>` itself (a repo-local
#     .git/hooks/<name> from `git lfs install --local`, or Husky + lfs) —
#     running it twice would double the pre-push upload negotiation.
#
# EXIT CODES
#   pre-push: stdin (the ref list) is buffered once to an unlinked temp file
#     and replayed: git lfs pre-push reads one copy, and on success the
#     caller's stdin is swapped for the second copy so the project delegate
#     still sees every line. A non-zero exit aborts the push right here
#     (exit with git-lfs's code), before the delegate runs.
#   post-*: stdin is left untouched for the delegate (git-lfs gets
#     /dev/null). A non-zero exit sets LFS_HOOK_RC; delegate.sh still runs
#     the project hook and then exits with git-lfs's code, mirroring the
#     original git-lfs hook (git ignores post-* exit codes anyway).
#
# Requires HOOK_NAME, REPO_ROOT and RUN_HOOK set by delegate.sh.

LFS_HOOK_RC=0

# 0 = this invocation must chain into git-lfs, 1 = stay out of the way.
lfs_hook_applies() {
    case "$HOOK_NAME" in
        pre-push | post-commit | post-checkout | post-merge) ;;
        *) return 1 ;;
    esac

    command -v git-lfs >/dev/null 2>&1 || return 1

    local common_dir
    common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || return 1
    case "$common_dir" in
        /*) : ;;
        ?*) common_dir="$REPO_ROOT/$common_dir" ;;
        *) return 1 ;;
    esac
    [ -d "$common_dir/lfs" ] || return 1

    if [ -n "$RUN_HOOK" ] &&
        grep -Eqs "^[[:space:]]*(command[[:space:]]+)?git[[:space:]]+lfs[[:space:]]+${HOOK_NAME}([[:space:]]|$)" "$RUN_HOOK"; then
        [ "$DEBUG" = "1" ] && echo "[Debug] ${RUN_HOOK} already runs git lfs ${HOOK_NAME}"
        return 1
    fi
    return 0
}

lfs_chain() {
    lfs_hook_applies || return 0

    [ "$DEBUG" = "1" ] && echo "[Debug] Chaining: git lfs ${HOOK_NAME}"

    if [ "$HOOK_NAME" != "pre-push" ]; then
        git lfs "$HOOK_NAME" "$@" </dev/null || LFS_HOOK_RC=$?
        return 0
    fi

    local buf rc=0
    buf=$(mktemp "${TMPDIR:-/tmp}/git-lfs-pre-push.XXXXXX") || {
        echo -e "${RED}✗ [Global Hook] Cannot buffer pre-push stdin for git lfs — push aborted${NC}" >&2
        exit 1
    }
    cat >"$buf"
    # Two independent read offsets on the same data; unlinking right away
    # means no trap is needed for cleanup on any exit path.
    exec 3<"$buf" 4<"$buf"
    rm -f "$buf"

    git lfs pre-push "$@" <&3 || rc=$?
    exec 3<&-

    if [ "$rc" -ne 0 ]; then
        echo -e "${RED}✗ [Global Hook] git lfs pre-push failed (exit ${rc}) — push aborted${NC}" >&2
        exit "$rc"
    fi

    # Replay the untouched copy as the delegate's stdin.
    exec 0<&4 4<&-
}
