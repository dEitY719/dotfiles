#!/bin/sh
# shellcheck shell=bash
# shell-common/tools/custom/lib/gcp_scan_probe.sh
# gcp scan: Stage-2 no-op probe and quiet cherry-pick helpers (issue #913).
#
# Source-only, no interactive guard: loaded by tools/custom/gcp_scan.sh (the
# `gcp scan` executable, #2155) and by tests/bats/functions/gcp.bats through it.
# Function definitions only. Split out of functions/gcp_scan.sh, whose FILE RULE
# still holds here: every cp/rm/mv call site keeps its `command ` prefix (#1663).

_gcp_scan_is_empty_cherry_pick() {
    # True when cherry-pick is in progress, has no conflicts, and results in an empty commit
    # (git suggests: git cherry-pick --skip).
    git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null 2>&1 || return 1
    git ls-files -u 2>/dev/null | grep -q . && return 1
    git diff --quiet >/dev/null 2>&1 || return 1
    git diff --cached --quiet >/dev/null 2>&1 || return 1
    return 0
}

_gcp_scan_preflight_is_noop() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    # True (0) when cherry-picking commit $1 onto HEAD would add nothing — the
    # commit is already absorbed in HEAD (issue #913). Probes with git's own
    # merge engine instead of textual heuristics, so it survives context drift:
    #
    #   * Clean apply, empty staged diff  -> already in HEAD            -> noop.
    #   * Conflict that, once every conflicted file is reset to HEAD,
    #     leaves an empty staged diff     -> only context drifted       -> noop.
    #   * Anything that leaves a non-empty staged diff (a clean change, or a
    #     conflict carrying genuinely new content) -> real work         -> keep.
    #
    # The probe is NON-DESTRUCTIVE: a dirty working tree is stashed first and
    # popped at the end, and the index/tree are restored with `git reset --hard`
    # (a `cherry-pick -n` never records sequencer state, so no --abort needed).
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        if type ux_error >/dev/null 2>&1; then
            ux_error "Not in a git repository"
        else
            echo "Error: Not in a git repository" >&2
        fi
        return 1
    fi
    local sha="$1" result=1 had_stash=0 conflicted f real_content_conflict=0
    if ! git diff --quiet || ! git diff --cached --quiet; then
        git stash push -q --include-untracked -m "gcp_preflight_probe" && had_stash=1
        # Data-loss guard (PR #916 review): a failed stash leaves the tree
        # dirty, and the `git reset --hard HEAD` below would then wipe the
        # uncommitted work. Bail out (treat as "not a no-op") instead.
        if [ "$had_stash" -ne 1 ]; then
            return 1
        fi
    fi
    # Self-protection against a config-poisoning probe (issues #1016, #1149).
    # When the probed commit edits `git/.gitconfig`, the `cherry-pick -n` below
    # can leave the active git config unreadable: a conflict writes `<<<<<<<`
    # markers into the worktree file, and even a clean apply may stage a
    # syntactically broken .gitconfig carried by the commit itself. From that
    # instant EVERY subsequent git invocation — including the `git reset --hard
    # HEAD` recovery — dies with `fatal: bad config line N`, so the breakage can
    # never be cleared. Snapshot the file(s) first with a plain `cp` (no git
    # needed) so we can restore them before git reads config again.
    #
    # Two topologies poison DIFFERENT files, so snapshot BOTH candidate targets
    # (#1016/#1018 covered only the symlink case, hence the #1149 regression):
    #   * symlink:  ~/.gitconfig -> git/.gitconfig. `readlink -f` resolves to the
    #     tracked file, which is both the active global config AND the cherry-pick
    #     target — one file, caught by slot 1.
    #   * [include]: ~/.gitconfig is a REGULAR file whose `[include] path =` pulls
    #     in the tracked git/.gitconfig (documented setup-mode `internal`, see
    #     git/AGENTS.md). `readlink -f` returns ~/.gitconfig itself — the wrong
    #     file — so slot 1 misses the real target. Slot 2 snapshots the tracked
    #     git/.gitconfig in the worktree, which is what the cherry-pick corrupts
    #     regardless of topology.
    local _gcfg1="" _gcfg1_bak="" _gcfg2="" _gcfg2_bak="" _gcp_cp_rc=0 _top=""
    # Slot 1 — the file behind ~/.gitconfig. Prefer GNU `readlink -f`, fall back
    # to plain `readlink` + manual absolutisation for BSD/macOS (where `-f` is
    # unsupported, PR #1018 review), then to the path itself when it is a regular
    # (non-symlink) file.
    _gcfg1=$(readlink -f "${HOME}/.gitconfig" 2>/dev/null)
    if [ -z "$_gcfg1" ]; then
        _gcfg1=$(readlink "${HOME}/.gitconfig" 2>/dev/null)
        if [ -n "$_gcfg1" ]; then
            case "$_gcfg1" in
                /*) ;;
                *) _gcfg1="${HOME}/${_gcfg1}" ;;
            esac
        else
            _gcfg1="${HOME}/.gitconfig"
        fi
    fi
    # Slot 2 — the tracked git/.gitconfig in this worktree (the real [include]
    # target). Resolve the toplevel NOW, before `cherry-pick -n` corrupts config:
    # `git rev-parse` reads config, so once the file carries markers this lookup
    # would itself die with `fatal: bad config line`. Deduped against slot 1 so
    # the symlink topology snapshots the shared file only once.
    _top=$(git rev-parse --show-toplevel 2>/dev/null) && _gcfg2="${_top}/git/.gitconfig"
    if [ -n "$_gcfg2" ] && [ "$_gcfg2" = "$_gcfg1" ]; then
        _gcfg2=""
    fi
    # Explicit template + fallback dir keeps mktemp portable to BSD/macOS, where
    # a bare `mktemp` errors out (PR #1018 review). On a `cp` failure after a
    # successful mktemp, remove the now-orphan temp before clearing the var so a
    # failed snapshot leaks no file (gemini PR #1150 review).
    # `-p` preserves the ORIGINAL file's mode onto the snapshot (codex review,
    # PR #1686). It matters only on the restore's `-f` path below: `mktemp`
    # creates 0600, and when `cp -f` has to unlink a read-only destination and
    # recreate it, the new file takes the SOURCE's mode — so a plain snapshot
    # would silently rewrite a 0644 git/.gitconfig as 0600. With `-p` the
    # snapshot carries 0644 and the recreated file comes back at 0644.
    # Ownership is trivially preserved (the mktemp file is ours), so `-p` has
    # no root-only failure mode here.
    if [ -n "$_gcfg1" ] && [ -f "$_gcfg1" ]; then
        if _gcfg1_bak=$(mktemp "${TMPDIR:-/tmp}/gcfg_bak.XXXXXX" 2>/dev/null); then
            command cp -p "$_gcfg1" "$_gcfg1_bak" 2>/dev/null || { command rm -f "$_gcfg1_bak"; _gcfg1_bak=""; }
        fi
    fi
    if [ -n "$_gcfg2" ] && [ -f "$_gcfg2" ]; then
        if _gcfg2_bak=$(mktemp "${TMPDIR:-/tmp}/gcfg_bak.XXXXXX" 2>/dev/null); then
            command cp -p "$_gcfg2" "$_gcfg2_bak" 2>/dev/null || { command rm -f "$_gcfg2_bak"; _gcfg2_bak=""; }
        fi
    fi
    git cherry-pick -n "$sha" >/dev/null 2>&1 || _gcp_cp_rc=$?
    # Restore BOTH snapshots UNCONDITIONALLY and immediately, before any further
    # git command reads config — covers both the conflict path and the
    # clean-apply-of-broken-config path (PR #1018 review). `cp` touches only the
    # worktree, never the index, so the staged-diff no-op verdict below is
    # unaffected.
    #
    # `-f` on the RESTORE only (agy review, PR #1686): a plain `cp` onto a
    # read-only destination fails with "Permission denied", and the `2>/dev/null`
    # here turns that into exactly the silent restore failure this function was
    # hardened against — the corruption would survive. `-f` unlinks and recreates
    # instead. The snapshot `cp`s above deliberately do NOT take it: their
    # destination is a fresh `mktemp` file, always writable, so `-f` would only
    # widen what they may clobber. `_gcfg1`/`_gcfg2` are resolved real paths
    # (slot 1 is `readlink`-ed above), never the symlink itself, so `-f` cannot
    # replace a symlink with a regular file here.
    if [ -n "$_gcfg1_bak" ] && [ -f "$_gcfg1_bak" ]; then
        command cp -f "$_gcfg1_bak" "$_gcfg1" 2>/dev/null
    fi
    if [ -n "$_gcfg2_bak" ] && [ -f "$_gcfg2_bak" ]; then
        command cp -f "$_gcfg2_bak" "$_gcfg2" 2>/dev/null
    fi
    if [ "$_gcp_cp_rc" -eq 0 ]; then
        if git diff --cached --quiet; then
            result=0
        elif _gcp_scan_staged_is_duplicate_append "$sha"; then
            # A clean apply whose whole payload HEAD already holds, just
            # elsewhere in the file (issue #1759). Announced, never silent: this
            # is the one verdict that drops a commit the staged diff still shows
            # as real work, so a wrong call has to be auditable from the scan
            # output alone.
            local _dup_files _dup_short
            _dup_files=$(git diff --cached --name-only 2>/dev/null | tr '\n' ' ')
            _dup_short=$(git rev-parse --short "$sha" 2>/dev/null)
            if type ux_warning >/dev/null 2>&1; then
                ux_warning "Absorbing ${_dup_short} — its added block is already in HEAD (duplicate append): ${_dup_files}"
            else
                echo "[gcp-scan] Absorbing ${_dup_short} — its added block is already in HEAD (duplicate append): ${_dup_files}" >&2
            fi
            result=0
        fi
    else
        conflicted=$(git diff --name-only --diff-filter=U)
        # Only a real merge conflict is eligible for the context-drift no-op
        # verdict. An EMPTY list means `cherry-pick -n` failed fatally (bad
        # SHA, index lock, …) on a clean index — leaving result=1 so the
        # commit is never silently skipped (PR #916 review). `git checkout
        # HEAD -- <f>` already stages each resolved file, so no extra
        # `git add` is needed (and `git add -A` would wrongly stage untracked
        # files, breaking the empty-diff check).
        if [ -n "$conflicted" ]; then
            while IFS= read -r f; do
                [ -z "$f" ] && continue
                # Keep genuine content conflicts intact: resetting those files
                # to HEAD would erase the commit's only real work and
                # misclassify the probe as "already in HEAD" (#1177).
                if _gcp_scan_conflict_adds_new_content "$sha" "$f"; then
                    real_content_conflict=1
                    break
                fi
                # `$f` may not exist in HEAD at all (e.g. both sides added it
                # independently) -> checkout fails with a stray "pathspec …
                # did not match" that used to leak into scan output (issue
                # #1647, defect E). Silence it explicitly: a file that can't
                # be restored to a HEAD state can't be called a no-op, so it
                # is deliberately left unresolved — the resulting unmerged
                # index already fails the staged-diff check below, which is
                # the SAME "real work" verdict this produced before. Judgment
                # unchanged, only the noise is gone.
                git checkout HEAD -- "$f" 2>/dev/null || :
            done <<EOF
$conflicted
EOF
            if [ "$real_content_conflict" -eq 0 ]; then
                git diff --cached --quiet && result=0
            fi
        fi
    fi
    [ -n "$_gcfg1_bak" ] && command rm -f "$_gcfg1_bak"
    [ -n "$_gcfg2_bak" ] && command rm -f "$_gcfg2_bak"
    git reset --hard HEAD >/dev/null 2>&1
    [ "$had_stash" -eq 1 ] && git stash pop -q >/dev/null 2>&1
    return $result
}

_gcp_scan_dup_base_sha() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    # Look up the base-branch SHA that a duplicate source SHA matches.
    # $1 = candidate source SHA; $2 = duplicate map ("SRC_SHA BASE_SHA" lines).
    # Prints the matching base SHA (or nothing) — issue #811 F-3. Pure shell
    # (here-doc `while read`, no awk fork) per PR #812 review.
    local target="$1"
    local src_sha base_sha
    while read -r src_sha base_sha; do
        if [ "$src_sha" = "$target" ]; then
            printf '%s\n' "$base_sha"
            return 0
        fi
    done <<EOF
$2
EOF
}

_gcp_scan_report_conflict_stop() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    # Shared "Failed at $sha, resolve manually" message for the execution
    # loop's two abort-the-batch exits (--stop-on-conflict, and the rollback
    # itself failing to clear the sequencer) — issue #1647, defect B.
    #
    # Names `--abort` as well as `--continue` (issue #1753): the sequencer is
    # left ACTIVE on both of these exits, and git's own hint block — which
    # used to spell out the full menu right here — is now filtered out by
    # `_gcp_scan_cherry_pick_quiet`. Matches the same pair printed by this
    # file's inline CHERRY_PICK_HEAD guard on the NEXT gcp scan.
    local sha="$1"
    if type ux_error >/dev/null 2>&1; then
        ux_error "Failed at $sha. Resolve and run: git cherry-pick --continue"
        ux_error "  (or abandon it with: git cherry-pick --abort)"
    fi
}

_gcp_scan_cherry_pick_quiet() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    # `git cherry-pick "$1"`, minus git's unactionable conflict-advice block
    # (issue #1753). On conflict git appends 5-6 `hint: ... --continue /
    # --skip / --abort` lines on STDERR, but the execution loop resolves the
    # sequencer itself — it rolls the single commit back and continues, and
    # both abort-the-batch exits print their own recovery line via
    # `_gcp_scan_report_conflict_stop`. So those hints are advice the user
    # cannot act on, printed right above the loop's own `Deferred ...` summary.
    #
    # Two git-side knobs plus one filter, because no single one covers every
    # git (PR #1755 review, agy + codex FOLLOW-UP):
    #
    #   advice.mergeConflict=false — git >= 2.45 never emits the block at all,
    #     so nothing has to be pattern-matched there (a translated `hint:`
    #     prefix included). Silently ignored by older git, where `advise()` is
    #     ungated — which is why the filter below still has to exist.
    #   color.advice=false — keeps the filter's `^hint: ` anchor unbreakable.
    #     Under `color.advice=always` each hint line carries an ANSI SGR prefix,
    #     so the anchor misses and all six leak (verified on git 2.43). `-c` on
    #     the command line outranks user config, so this cannot be re-enabled
    #     from the outside.
    #   grep -v '^hint: ' — the actual removal on git < 2.45.
    #
    # Residual, accepted: git < 2.45 with git's own translations installed AND
    # a non-English locale would emit a translated prefix the filter misses.
    # That degrades to today's behaviour (hints shown), never to a lost
    # cherry-pick.
    #
    # STDERR is captured through an fd swap, not a scratch file: `$(...)` sets
    # `$?` from the command it ran, so git's exit status survives without the
    # temp file a pipeline would force (`grep` would otherwise become `$?`, and
    # PIPESTATUS is not POSIX). fd 3 carries STDOUT through untouched, so
    # `Auto-merging` and `CONFLICT (content): ...` are never even captured;
    # `error: could not apply ...` is, and survives the `hint:`-only filter.
    local _err _rc
    { _err=$(git -c advice.mergeConflict=false -c color.advice=false \
        cherry-pick "$1" 2>&1 1>&3); _rc=$?; } 3>&1
    [ -z "$_err" ] || printf '%s\n' "$_err" | grep -v '^hint: ' >&2
    return "$_rc"
}

_gcp_scan_pick_list_prior() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    # Return the newline-joined pick_list entries strictly BEFORE $1 in $2's
    # order (issue #1647, defect A). pick_list ORDER matters: the execution
    # loop applies picks in order, so an entry AFTER $1 cannot have run yet
    # and is not a precedent — `break` (not `continue`) on the self-match
    # stops accumulation there. Shared by _gcp_scan_check_file_deps and
    # _gcp_scan_predict_content_conflict, which used to each hand-roll this
    # walk separately.
    local target="$1" pick_list="$2"
    local _p prior="" found=0
    while IFS= read -r _p; do
        [ -z "$_p" ] && continue
        if [ "$_p" = "$target" ]; then
            found=1
            break
        fi
        prior="${prior}${_p}
"
    done <<EOF
$pick_list
EOF
    # $target absent from pick_list entirely -> the whole list was just
    # accumulated as `prior` above (unchanged pre-#1647 fallback behavior).
    # stderr-only (agy review, PR #1649): callers read this function's stdout
    # as data, so a warning on stdout would corrupt it. Not expected to fire
    # in practice — every call site draws $target from the same list it
    # passes as pick_list — so this is a silent-drift detector, not a normal
    # code path.
    if [ "$found" -eq 0 ]; then
        printf '[gcp-scan] %s not found in its own pick_list — using the full list as precedent (unexpected).\n' "$target" >&2
    fi
    printf '%s' "$prior"
}
