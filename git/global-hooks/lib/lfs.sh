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
#   lfs_run_and_delegate "$@" runs `git lfs <hook> "$@"` — exactly what the
#   git-lfs hook it replaced did — together with the project hook delegate.sh
#   resolved (RUN_HOOK, may be empty), then exits. delegate.sh calls it only
#   when lfs_hook_applies, which is false (no output, no stdin read) unless
#   ALL hold:
#   - HOOK_NAME is one of the four hooks git-lfs installs
#   - `git-lfs` is on PATH (git-lfs's own hook exits 2 when it is missing,
#     which in a non-LFS repo would break every push — we skip instead)
#   - the repo uses LFS, i.e. ANY of (cheapest first):
#       <git-common-dir>/lfs exists (git-lfs creates it on the first stored
#         object; --git-common-dir keeps it worktree-safe)
#       `lfs.storage` is configured (objects relocated out of <common>/lfs)
#       <git-common-dir>/info/attributes contains filter=lfs
#       a tracked .gitattributes (root or nested) contains filter=lfs —
#         covers GIT_LFS_SKIP_SMUDGE clones and fresh repos with no object yet
#   - RUN_HOOK does not already call `git lfs <hook>` itself (a repo-local
#     .git/hooks/<name> from `git lfs install --local`, or Husky + lfs) —
#     running it twice would double the pre-push upload negotiation. This is
#     a line-start grep heuristic: it misses one-line `if ...; then git lfs
#     ...; fi`, `git -c k=v lfs ...` and Husky-style wrappers that reach git
#     lfs through another script — those get git-lfs run twice (harmless
#     but slower), never zero times.
#
# ORDER + EXIT CODES
#   pre-push: the project hook runs FIRST, so its gates (protected-branch
#     block, upstream leak guard) reject a push before git-lfs uploads any
#     blob. stdin (the ref list) is buffered once to an unlinked temp file
#     and both get their own copy. A failing project hook exits with its
#     code and git-lfs never runs; otherwise exit with git-lfs's code.
#   post-*: git-lfs runs first (as the original git-lfs hook did; git ignores
#     post-* exit codes, so order is not a safety question) with /dev/null
#     as stdin, leaving stdin for the project hook. A non-zero git-lfs code
#     wins over the project hook's code.
#
# Requires HOOK_NAME, REPO_ROOT, RUN_HOOK and the color vars set by
# delegate.sh. git/setup.sh also sources this file for lfs_hook_cmd_ere.

# ERE matching the start of a `git lfs <hook>` command line: shared by the
# double-run guard below and git/setup.sh's git-lfs hook classification.
lfs_hook_cmd_ere() {
    printf '%s' "^[[:space:]]*(command[[:space:]]+)?git[[:space:]]+lfs[[:space:]]+${1}"
}

# 0 = the repo at REPO_ROOT uses LFS (see "the repo uses LFS" above).
lfs_repo_uses_lfs() {
    local common_dir
    common_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
    [ -n "$common_dir" ] || return 1

    [ -d "$common_dir/lfs" ] && return 0
    [ -n "$(git config --get lfs.storage 2>/dev/null)" ] && return 0
    grep -qs 'filter=lfs' "$common_dir/info/attributes" && return 0
    git -C "$REPO_ROOT" grep -q -e 'filter=lfs' -- ':(glob)**/.gitattributes' >/dev/null 2>&1
}

# 0 = this invocation must chain into git-lfs, 1 = stay out of the way.
lfs_hook_applies() {
    case "$HOOK_NAME" in
    pre-push | post-commit | post-checkout | post-merge) ;;
    *) return 1 ;;
    esac

    command -v git-lfs >/dev/null 2>&1 || return 1
    lfs_repo_uses_lfs || return 1

    if [ -n "$RUN_HOOK" ] &&
        grep -Eqs "$(lfs_hook_cmd_ere "$HOOK_NAME")([[:space:]]|$)" "$RUN_HOOK"; then
        [ "$DEBUG" = "1" ] && echo "[Debug] ${RUN_HOOK} already runs git lfs ${HOOK_NAME}"
        return 1
    fi
    return 0
}

# Run git-lfs + the project hook in the order above, then exit. Never returns.
lfs_run_and_delegate() {
    local rc=0 lfs_rc=0 buf

    [ "$DEBUG" = "1" ] && echo "[Debug] Chaining: git lfs ${HOOK_NAME}"

    if [ "$HOOK_NAME" = "pre-push" ]; then
        if [ -z "$RUN_HOOK" ]; then
            [ "$DEBUG" = "1" ] && echo "[Debug] No project-level ${HOOK_NAME} hook found"
            git lfs pre-push "$@" || rc=$?
        else
            buf=$(mktemp "${TMPDIR:-/tmp}/git-lfs-pre-push.XXXXXX") || {
                echo -e "${RED}✗ [Global Hook] Cannot buffer pre-push stdin for git lfs — push aborted${NC}" >&2
                exit 1
            }
            cat >"$buf"
            # Two independent read offsets on the same data; unlinking right
            # away means no trap is needed for cleanup on any exit path.
            exec 3<"$buf" 4<"$buf"
            rm -f "$buf"

            echo -e "${BLUE}[Global Hook] Delegating to project hook: $RUN_HOOK${NC}"
            "$RUN_HOOK" "$@" <&3 3<&- 4<&- || exit $?
            exec 3<&-
            git lfs pre-push "$@" <&4 4<&- || rc=$?
        fi
        if [ "$rc" -ne 0 ]; then
            echo -e "${RED}✗ [Global Hook] git lfs pre-push failed (exit ${rc}) — push aborted${NC}" >&2
        fi
        exit "$rc"
    fi

    git lfs "$HOOK_NAME" "$@" </dev/null || lfs_rc=$?
    if [ -n "$RUN_HOOK" ]; then
        echo -e "${BLUE}[Global Hook] Delegating to project hook: $RUN_HOOK${NC}"
        "$RUN_HOOK" "$@" || rc=$?
    else
        [ "$DEBUG" = "1" ] && echo "[Debug] No project-level ${HOOK_NAME} hook found"
    fi
    [ "$lfs_rc" -ne 0 ] && exit "$lfs_rc"
    exit "$rc"
}
