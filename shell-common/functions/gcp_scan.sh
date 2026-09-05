#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/gcp_scan.sh
#
# Portable cherry-pick scanner - works in bash, zsh, and other POSIX shells
# Intelligently identifies and cherry-picks missing commits.
#
# Exposed via the gcp dispatcher (Type 2A — see gcp.sh and
# docs/.ssot/command-design-pattern.md §4):
#
#   gcp scan [base] [src] [--author=<name|all>]
#
# The deprecated 'gcp_scan' / 'gcp-scan' forms remain available as aliases
# (defined in gcp.sh) for backward compatibility — issue #697.
#
# FILE RULE (issue #1663, #1149 3차 재발) — every `cp`/`rm`/`mv` call site in
# this file MUST keep its `command ` prefix. zsh expands aliases at PARSE time,
# so a bare word here gets `-i` imprinted from shell-common/aliases/core.sh
# before the function is ever called. Do not strip the prefix as noise; the
# guard is `alias-immunity #1663` in tests/bats/functions/gcp.bats.
#
# Note: git cherry marks commits as:
#   '+' = present in source, missing in base (will be cherry-picked)
#   '-' = already merged in base
#
# Redundant-commit handling (issue #913, supersedes #903/#907/#908/#910;
# UX improved by issue #961): each candidate is probed with
# `_gcp_scan_preflight_is_noop` (Stage-2) during the Analysis phase, BEFORE
# displaying the commit list. Noop commits are excluded from the display and
# the cherry-pick count so users never see a commit that will immediately be
# skipped. The execution loop reuses the Stage-2 result (noop_list) to avoid
# a double-probe. The probe uses git's own merge engine (`cherry-pick -n`) so
# it is immune to context-drift failures (comment rewrites, refactors) that
# broke earlier file-compare / reverse-patch heuristics.
#

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

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
        echo "Error: Not in a git repository" >&2
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
        git diff --cached --quiet && result=0
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
    # Shared "Failed at $sha, resolve manually" message for the execution
    # loop's two abort-the-batch exits (--stop-on-conflict, and the rollback
    # itself failing to clear the sequencer) — issue #1647, defect B.
    #
    # Names `--abort` as well as `--continue` (issue #1753): the sequencer is
    # left ACTIVE on both of these exits, and git's own hint block — which
    # used to spell out the full menu right here — is now filtered out by
    # `_gcp_scan_cherry_pick_quiet`. `_gcp_assert_no_cherry_pick` shows the
    # same pair, but only on the NEXT gcp invocation.
    local sha="$1"
    if type ux_error >/dev/null 2>&1; then
        ux_error "Failed at $sha. Resolve and run: git cherry-pick --continue"
        ux_error "  (or abandon it with: git cherry-pick --abort)"
    fi
}

_gcp_scan_cherry_pick_quiet() {
    #   $1  commit to pick
    #   $2  the repo's git dir (the loop's $_gcp_git_dir) — scratch lives there
    #
    # `git cherry-pick "$1"`, minus git's unactionable conflict-advice block
    # (issue #1753). On conflict git appends 5-6 `hint: ... --continue /
    # --skip / --abort` lines on STDERR, but the execution loop resolves the
    # sequencer itself — it rolls the single commit back and continues, and
    # both abort-the-batch exits print their own recovery line via
    # `_gcp_scan_report_conflict_stop`. So those hints are advice the user
    # cannot act on, printed immediately above the loop's own `Deferred ...`
    # summary of the same event.
    #
    # Two git-side knobs plus one filter, because no single one covers every
    # git (PR #1755 review, agy + codex FOLLOW-UP):
    #
    #   advice.mergeConflict=false — git >= 2.45 never emits the block at all,
    #     so nothing has to be pattern-matched there (a translated `hint:`
    #     prefix included). Silently ignored by older git, where `advise()` is
    #     ungated — which is why the filter below still has to exist.
    #   color.advice=false — makes the filter's `^hint: ` anchor unbreakable.
    #     A user running `color.advice=always` gets each hint line prefixed
    #     with an ANSI SGR escape, so the anchor misses and all six lines leak
    #     (verified on git 2.43). `-c` on the command line outranks any
    #     user config, so this cannot be turned back on from the outside.
    #   grep -v '^hint: ' — the actual removal on git < 2.45.
    #
    # Residual, accepted: git < 2.45 with git's own translations installed AND
    # a non-English locale would emit a translated prefix the filter misses.
    # That combination degrades to today's behaviour (hints shown), never to a
    # lost cherry-pick.
    #
    # Scratch file lives in the git dir under a fixed name, not `mktemp` in
    # $TMPDIR: an interrupt mid-pick used to strand a `gcp_cp_err.*` file per
    # commit (agy + codex FOLLOW-UP). A fixed path is truncated by the next
    # `>` instead of accumulating, is scoped to the repo being picked into,
    # and removes the `mktemp`-failure branch entirely.
    #
    # No information is lost: `Auto-merging` and `CONFLICT (content): ...` go
    # to STDOUT and are never touched, and `error: could not apply ...`
    # survives the filter because only `hint:` lines are dropped.
    local _err _rc
    _err="${2:-}/gcp-scan-cp-stderr"
    # Unwritable git dir (read-only checkout, odd permissions) — never trade
    # the cherry-pick itself for tidier output.
    if [ -z "${2:-}" ] || ! : >"$_err" 2>/dev/null; then
        git -c advice.mergeConflict=false -c color.advice=false cherry-pick "$1"
        return $?
    fi
    git -c advice.mergeConflict=false -c color.advice=false cherry-pick "$1" 2>"$_err"
    _rc=$?
    grep -v '^hint: ' "$_err" >&2
    command rm -f "$_err"
    return "$_rc"
}

_gcp_scan_pick_list_prior() {
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

_gcp_scan_check_file_deps() {
    # File-dependency pre-check (issue #1033). Returns 1 when cherry-picking
    # commit $1 would hit a modify/delete conflict because a file it
    # modifies/deletes is ABSENT from $2 (base) and the upstream commit in $3
    # (source) that creates that file is NOT itself among the commits we are
    # about to pick ($4, the author-filtered candidate list). Returns 0 when no
    # such missing dependency exists.
    #
    # Why $4 (pick_list) is load-bearing: with --author=all the creating commit
    # IS in the candidate list and gets cherry-picked first, so the file is no
    # longer "missing" — checking base existence alone would false-positive
    # there. Membership in pick_list is the guard that keeps --author=all clean.
    #
    # For every missing dependency it prints one "F<TAB>short_creator_sha" line
    # to stdout so the caller can name the offending file + precedent commit.
    #
    # pick_list ORDER matters (issue #1647, defect A): the execution loop
    # applies pick_list in order, so a creator commit AFTER $sha in that order
    # cannot have run yet — it is not a precedent. `_gcp_scan_pick_list_prior`
    # (shared with _gcp_scan_predict_content_conflict) gives only the commits
    # BEFORE $sha. This prefix is itself an over-approximation (an earlier
    # entry may still get skipped as a dup/no-op/path-excluded and never
    # actually apply), but that bias is deliberately toward DEFERRING
    # judgment rather than wrongly skipping a real dependency — the execution
    # loop's own rollback-and-continue handling absorbs any false negative
    # that slips through.
    local sha="$1" base="$2" source="$3" pick_list="$4"
    local changes st f up_add rc=0 tab prior_prefix
    tab=$(printf '\t')
    prior_prefix=$(_gcp_scan_pick_list_prior "$sha" "$pick_list")
    # name-status of the candidate (single-parent diff -> one status letter).
    changes=$(git diff-tree --no-commit-id -r --name-status "$sha" 2>/dev/null)
    while IFS="$tab" read -r st f; do
        [ -z "$st" ] && continue
        [ -z "$f" ] && continue
        # Only modify (M) / delete (D) require the file to pre-exist in base.
        # Adds (A) create the file themselves; renames/copies (R/C) carry two
        # path fields and are out of scope for this heuristic.
        case "$st" in
            M* | D*) ;;
            *) continue ;;
        esac
        # File already present in base -> modify/delete can proceed (content
        # conflicts, if any, are Stage-2 / real-cherry-pick territory).
        if git cat-file -e "${base}:${f}" >/dev/null 2>&1; then
            continue
        fi
        # File absent in base. Find the upstream commit that creates it.
        up_add=$(git log "$source" --diff-filter=A --format='%H' -- "$f" 2>/dev/null | head -n 1)
        # No known creator in source -> not a recognizable dependency; leave it
        # for Stage-2 / the real cherry-pick rather than guess.
        [ -z "$up_add" ] && continue
        # Creator is among the commits we will pick BEFORE $sha -> not missing
        # (the --author=all path). Newline-wrapped match avoids prefix
        # collisions, mirroring the Stage-2 noop_list membership test.
        case "
$prior_prefix
" in
            *"
$up_add
"*) continue ;;
        esac
        printf '%s\t%s\n' "$f" "$(git rev-parse --short "$up_add" 2>/dev/null)"
        rc=1
    done <<EOF
$changes
EOF
    return $rc
}

_gcp_scan_json_leaves() {
    # Render JSON file $1 as one `[path, value]` record per node, for the
    # structural comparison in `_gcp_scan_conflict_adds_new_content` (#1688,
    # PR #1690 review). Returns non-zero when $1 is not valid JSON — the
    # caller then falls back to byte-exact line comparison.
    #
    # Why `[path, value]` and not canonical text: canonicalizing with `jq -S .`
    # still emits a trailing comma on every element but the last, so a
    # line-based comparison over canonical text reproduces the exact bug this
    # replaces. Paths carry array indices, so element ORDER stays visible while
    # comma/indentation noise disappears. Containers are recorded as the
    # literal (unquoted) empty-container values `{}`/`[]` — not the STRINGS
    # `"{}"`/`"[]"` — so adding an empty object or array is content, not a
    # no-op. The leading `[[], ...]` record covers a top-level scalar, for
    # which `paths` is empty.
    #
    # Unquoted is load-bearing (codex BLOCKER, PR #1690 round-3): a JSON
    # string leaf whose bytes happen to be `{}`/`[]` (e.g. `{"note": "{}"}`)
    # serializes, quoted, as `"{}"`. Collapsing a container to that same
    # quoted string would make the two indistinguishable in the compact
    # output the awk set-comparison below reads. `jq -c` renders an actual
    # empty object/array as the bare `{}`/`[]` — no valid JSON scalar ever
    # serializes to those exact unquoted bytes — so keeping the real
    # container value (rather than converting it to a string) preserves the
    # distinction.
    #
    # `-S` sorts object keys so a pure key reordering — not meaningful in JSON
    # — does not read as new content. An empty file yields no records and rc 0,
    # which is the correct reading of "the commit adds this file".
    jq -Sc '
        [[], (if type == "object" then {} elif type == "array" then [] else . end)],
        (paths as $p | [$p, (getpath($p) | if type == "object" then {} elif type == "array" then [] else . end)])
    ' "$1"
}

_gcp_scan_conflict_adds_new_content() {
    # Context-drift discriminator (issue #913 regression, #1151, #1688). Returns 0
    # (true) when cherry-picking commit $1 introduces content to file $2 that
    # HEAD does NOT already contain — a GENUINE content conflict. Returns 1
    # (false) when every line the commit adds (relative to its parent, the
    # cherry-pick merge base) is already present in HEAD: the textual conflict
    # is pure context drift (an unrelated adjacent region moved), so the commit
    # is effectively a no-op that Stage-2's merge probe will absorb as "already
    # in HEAD" rather than a conflict a human must resolve.
    #
    # Why this exists: `git merge-tree` flags BOTH a real same-line divergence
    # (HEAD and the commit set the line to different values) AND a spurious
    # adjacency conflict (the commit's real change already matches HEAD, but an
    # unrelated neighbouring line drifted) as the same rc=1 conflict. Stage-2's
    # reset-conflicted-to-HEAD probe cannot tell them apart either — it reports
    # both as no-ops. The line-level "did theirs add anything HEAD lacks?" test
    # below is what distinguishes the two, letting Stage-1.6 defer the drift
    # case to Stage-2 (no-op) while still flagging the real one. Non-destructive:
    # reads blobs only (no checkout / cherry-pick).
    local sha="$1" f="$2" parent td _b _o _t
    parent=$(git rev-parse -q --verify "${sha}^1" 2>/dev/null) || return 0
    td=$(mktemp -d "${TMPDIR:-/tmp}/gcp_drift.XXXXXX" 2>/dev/null) || return 0
    # base = the file in the commit's parent (the cherry-pick merge base);
    # ours = HEAD; theirs = the commit. A missing base blob (the commit ADDS the
    # file) leaves an empty base so every theirs line counts as added.
    git cat-file -p "${parent}:${f}" >"${td}/base" 2>/dev/null || : >"${td}/base"
    git cat-file -p "HEAD:${f}" >"${td}/ours" 2>/dev/null || : >"${td}/ours"
    if ! git cat-file -p "${sha}:${f}" >"${td}/theirs" 2>/dev/null; then
        # The commit has no such file (a delete) — it adds no content. Treat as
        # drift (return 1); the delete, if it matters, surfaces at cherry-pick.
        command rm -rf "$td"
        return 1
    fi
    # The commit brings content HEAD lacks (rc 0, real) in EITHER direction:
    #   * an ADD  — a theirs line absent from both base (the commit added it)
    #     and ours (HEAD lacks it); or
    #   * a DELETE — a base line absent from theirs (the commit removed it) yet
    #     still present in ours (HEAD has not removed it).
    # Checking adds alone would misclassify a delete-only commit as drift and
    # let Stage-2 silently skip it — silent data loss (gemini PR #1157 review).
    # Set membership; no sort needed (order-independent).
    #
    # WHAT IS COMPARED (issue #1688, redesigned in PR #1690 review): comparing
    # raw LINES promotes syntactic noise to a semantic difference. The reported
    # shape is a JSON object — appending an entry puts a trailing comma on the
    # line before it, so a line the commit added verbatim (`  "x": "y"`, last
    # entry at the time) no longer matches HEAD's copy (`  "x": "y",`, no
    # longer last) and the fully absorbed commit reads as real work forever.
    #
    # Stripping that comma textually was tried and rejected across three review
    # rounds — each round found another place the stripped character carries
    # meaning (a Python tuple `x = 1,`; a CSV empty trailing field; a Markdown
    # hard break; a commit whose only work IS deleting a stray comma; and a
    # JSON array reorder, where the comma is the sole positional signal). Every
    # one was measured flipping a real commit to "drift", i.e. silently dropped
    # — the #1177 data-loss direction. A line-textual rule was approximating a
    # structural property, so the structure is now read directly (#1688 안 B).
    #
    # `_gcp_scan_json_leaves` renders each side as one `[path, value]` record
    # per node, which answers the noise and the ordering question at once:
    # trailing commas and indentation do not survive parsing, while an array
    # index lives IN the path, so a reorder (`["b","a"]` vs `["a","b"]`) yields
    # different records and stays visible. Object keys are sorted (`jq -S`), so
    # a pure key reordering — which JSON does not consider meaningful — does
    # not read as content.
    #
    # The structural path is taken ONLY when jq is present AND all three sides
    # parse; otherwise the original byte-exact line comparison runs unchanged.
    # That fallback is what keeps every non-JSON file behaving exactly as it
    # did before #1688, and it needs no extension list: a Python, CSV or
    # Markdown file does not parse as JSON, while an extensionless or
    # oddly-cased JSON config (`.eslintrc`, `.JSON`) does (agy FOLLOW-UP).
    # Invalid JSON also fails to parse — the correct outcome for the
    # stray-trailing-comma commit, whose whole purpose is to make the file
    # valid: it falls back to exact comparison and stays visible.
    # NOTE: a bare `exit` (not `exit 0`) is required on a hit — `exit 0` would
    # still run END, whose `exit 1` would override it back to "drift".
    _b="${td}/base" _o="${td}/ours" _t="${td}/theirs"
    if command -v jq >/dev/null 2>&1 &&
        _gcp_scan_json_leaves "${td}/base" >"${td}/base.j" 2>/dev/null &&
        _gcp_scan_json_leaves "${td}/ours" >"${td}/ours.j" 2>/dev/null &&
        _gcp_scan_json_leaves "${td}/theirs" >"${td}/theirs.j" 2>/dev/null; then
        _b="${td}/base.j" _o="${td}/ours.j" _t="${td}/theirs.j"
    fi
    if awk '
        FILENAME == B { base[$0] = 1; next }
        FILENAME == O { ours[$0] = 1; next }
        {
            theirs[$0] = 1
            if (!($0 in base) && !($0 in ours)) { found = 1; exit }
        }
        END {
            if (!found) {
                for (l in base) {
                    if (!(l in theirs) && (l in ours)) { found = 1; break }
                }
            }
            exit(found ? 0 : 1)
        }
    ' B="${_b}" O="${_o}" "${_b}" "${_o}" "${_t}"; then
        command rm -rf "$td"
        return 0
    fi
    command rm -rf "$td"
    return 1
}

_gcp_scan_predict_content_conflict() {
    # Content-conflict pre-check (issue #1037, extends Stage-1.5 #1033). Returns
    # 1 when cherry-picking commit $1 onto HEAD is predicted to hit a 3-way
    # *content* conflict — HEAD and the commit change the same region of a file
    # that exists on both sides. This is the case Stage-1.5 does NOT cover
    # (modify/delete of a file absent from base); here both sides edited the
    # same lines. Returns 0 when the merge is predicted clean OR when the
    # verdict is deferred (see the --author=all guard AND the context-drift
    # guard below).
    #
    # Probe: `git merge-tree --write-tree --merge-base=<sha>^ HEAD <sha>`. This
    # drives git's REAL merge engine as a non-destructive dry-run (no checkout,
    # no index/worktree mutation) using the cherry-pick's own merge base — the
    # candidate's parent — so the exit status mirrors exactly what
    # `git cherry-pick <sha>` would hit. rc 0 = clean, rc 1 = conflict; rc > 1 =
    # usage/unsupported (git < 2.38 lacks --write-tree, < 2.40 lacks
    # --merge-base) -> treated as "clean" so pre-#1037 behavior is preserved on
    # older git. The legacy `git merge-tree <base> <a> <b>` form is deliberately
    # NOT used: it is a trivial merge that prints conflict markers for
    # adjacent-but-cleanly-mergeable hunks, producing false positives (#1037
    # investigation).
    #
    # --author=all guard ($2 = pick_list): a predicted conflict is a FALSE
    # positive when an earlier, not-yet-applied pick_list commit also touches
    # the conflicting file — the execution loop applies that precedent first,
    # after which the merge is clean. The verdict is evaluated PER conflicting
    # file: a file ALSO modified by another pick commit may be a precedent
    # artifact (skip it), but a conflicting file touched by NO other pick
    # commit is guaranteed to still conflict (no precedent changes HEAD's
    # copy) — so the commit is flagged as soon as one such file is found.
    # Only when EVERY conflicting file is covered by a precedent is the verdict
    # deferred (return 0). Mirrors Stage-1.5's pick_list membership guard, so
    # --author=all stays false-positive-free.
    #
    # Context-drift guard (issue #913 regression, #1151): a conflicting file
    # whose divergence is pure context drift — the commit's real change already
    # matches HEAD and only an unrelated adjacent region moved — is NOT a
    # content conflict. `_gcp_scan_conflict_adds_new_content` detects it (theirs
    # adds no line HEAD lacks) so the commit is left for Stage-2, which absorbs
    # it as a no-op ("already in HEAD"), instead of surfacing a phantom conflict
    # the user is told to resolve by hand. Only a file where the commit brings
    # content HEAD lacks flags the commit.
    #
    # Prints the first guaranteed-conflict file path to stdout when it flags.
    local sha="$1" pick_list="$2"
    local parent merge_out conflicted f other_files p rc prior_shas
    # Root commit (no parent) or merge commit (2+ parents): the cherry-pick
    # merge base is undefined/ambiguous -> out of scope, defer to the real
    # cherry-pick rather than probe with the wrong base.
    parent=$(git rev-parse -q --verify "${sha}^1" 2>/dev/null) || return 0
    if git rev-parse -q --verify "${sha}^2" >/dev/null 2>&1; then
        return 0
    fi
    # Single invocation with --name-only: rc carries the conflict verdict, and
    # stdout is the merged tree OID on line 1, then the conflicted paths (one
    # per line), then a blank line and an "Informational messages" block
    # (Auto-merging / CONFLICT lines). On older git the unknown flags exit > 1
    # and we bail to "clean".
    merge_out=$(git merge-tree --write-tree --name-only --merge-base="$parent" HEAD "$sha" 2>/dev/null)
    rc=$?
    [ "$rc" -eq 1 ] || return 0
    # Keep ONLY the path list: drop the OID (line 1) and stop at the blank line
    # before the informational block — otherwise "Auto-merging <f>" / "CONFLICT"
    # lines would be misread as conflicting file paths.
    conflicted=$(printf '%s\n' "$merge_out" | awk 'NR>1 { if ($0=="") exit; print }')
    [ -z "$conflicted" ] && return 0
    # Build the set of paths touched by every pick_list commit BEFORE $sha, for
    # the --author=all false-positive guard. pick_list ORDER matters (issue
    # #1647, defect A): the execution loop applies picks in order, so nothing
    # AFTER $sha can have changed HEAD's copy by the time $sha is picked — it
    # is not a precedent. `_gcp_scan_pick_list_prior` stops at the self-match
    # so only genuinely-prior candidates count; if $sha is absent from
    # pick_list it reads the whole list as a fallback (unchanged from before).
    other_files=""
    prior_shas=$(_gcp_scan_pick_list_prior "$sha" "$pick_list")
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        other_files="${other_files}$(git diff-tree --no-commit-id -r --name-only "$p" 2>/dev/null)
"
    done <<EOF
$prior_shas
EOF
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        # Deferral guard, per-file: a conflicting file ALSO touched by another
        # pick commit may be an artifact of an unapplied precedent -> skip it.
        # But a conflicting file touched by NO other pick commit is guaranteed
        # to still conflict at the real cherry-pick (no precedent can change
        # HEAD's copy), so flag the commit immediately on the first such file
        # rather than deferring the whole commit (gemini PR #1038 review).
        # Newline-wrapped match avoids prefix collisions (Stage-1.5 pattern).
        case "
$other_files" in
            *"
$f
"*) ;;
            *)
                # Uncovered by any precedent — but flag ONLY if the commit
                # brings content HEAD lacks. A pure context-drift conflict
                # (issue #913/#1151) adds nothing new and is left for Stage-2's
                # merge probe to absorb as a no-op, not surfaced as a conflict.
                if _gcp_scan_conflict_adds_new_content "$sha" "$f"; then
                    printf '%s\n' "$f"
                    return 1
                fi
                ;;
        esac
    done <<EOF
$conflicted
EOF
    # Every conflicting file is covered by an earlier pick_list commit -> defer
    # the whole verdict to the real cherry-pick (it applies precedents first).
    return 0
}

_gcp_scan_skip_file() {
    # Resolve the known-resolved skip-list file path (issue #1039). Honors the
    # GCP_SCAN_SKIP_FILE override (absolute or cwd-relative); otherwise defaults
    # to <repo-toplevel>/git/config/gcp-scan-skip.conf so the list is a tracked
    # SSOT alongside the other git/config/*.conf rule files. Prints the path
    # (it may not exist yet — callers must -f check).
    if [ -n "${GCP_SCAN_SKIP_FILE-}" ]; then
        printf '%s\n' "$GCP_SCAN_SKIP_FILE"
        return 0
    fi
    local top
    top=$(git rev-parse --show-toplevel 2>/dev/null) || top="."
    printf '%s/git/config/gcp-scan-skip.conf\n' "$top"
}

_gcp_scan_clean_token() {
    # Shared line-cleaning for the skip-list parsers below: drop an inline
    # `#` comment, then trim leading/trailing whitespace. Pure
    # parameter-expansion (no awk/sed fork), matching this file's style.
    local token="${1%%#*}"                         # drop inline comment
    token=${token%"${token##*[![:space:]]}"}       # trim trailing space
    token=${token#"${token%%[![:space:]]*}"}       # trim leading space
    printf '%s\n' "$token"
}

_gcp_scan_load_skip_list() {
    # Parse the known-resolved skip-list file (issue #1039) into one cleaned
    # SHA token per line. Each line is `<sha> [# free-text reason]`; inline
    # comments, full-comment lines, and blank lines are stripped.
    local file line token
    file=$(_gcp_scan_skip_file)
    [ -f "$file" ] || return 0
    # `|| [ -n "$line" ]` flushes a final newline-less line (POSIX read idiom).
    while IFS= read -r line || [ -n "$line" ]; do
        token=$(_gcp_scan_clean_token "$line")
        [ -z "$token" ] && continue
        # Hardening (gemini PR #1040 review): the token is later used UNESCAPED
        # as a `case` glob in _gcp_scan_in_skip_list ("$tok"*), so a stray `*`,
        # `?`, or `[` would match every candidate SHA and silently skip ALL
        # commits. Accept only hex (a valid abbreviated SHA) and require >=4
        # chars so an over-short prefix can't over-match. Reject otherwise.
        case "$token" in
            *[!0-9a-fA-F]*) continue ;;
        esac
        case "$token" in
            ????*) ;;
            *) continue ;;
        esac
        printf '%s\n' "$token"
    done <"$file"
}

_gcp_scan_in_skip_list() {
    # True (0) when candidate full SHA $1 is covered by the skip tokens in $2.
    # Tokens may be abbreviated, so a prefix match handles short SHAs while a
    # full token still matches exactly. Mirrors the no-fork here-doc read style.
    local cand="$1" tok
    while IFS= read -r tok; do
        [ -z "$tok" ] && continue
        case "$cand" in
            "$tok"*) return 0 ;;
        esac
    done <<EOF
$2
EOF
    return 1
}

_gcp_scan_show_skip_generic() {
    # Shared renderer behind --show-skip-list (issue #1039) and
    # --show-skip-paths (issue #1215): section title, resolved file path, and
    # every registered entry. $1=title $2=file $3=entries $4=no-file-message
    # $5=no-entries-message.
    local title="$1" file="$2" entries="$3" no_file_msg="$4" no_entries_msg="$5"
    if type ux_section >/dev/null 2>&1; then
        ux_section "$title"
        ux_bullet "File: $file"
    else
        echo "=== $title ==="
        echo "  File: $file"
    fi
    if [ ! -f "$file" ]; then
        if type ux_info >/dev/null 2>&1; then
            ux_info "$no_file_msg"
        else
            echo "  $no_file_msg"
        fi
        return 0
    fi
    if [ -z "$entries" ]; then
        if type ux_info >/dev/null 2>&1; then
            ux_info "$no_entries_msg"
        else
            echo "  $no_entries_msg"
        fi
        return 0
    fi
    printf '%s\n' "$entries" | while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        if type ux_bullet >/dev/null 2>&1; then
            ux_bullet "$entry"
        else
            echo "  $entry"
        fi
    done
}

_gcp_scan_show_skip_list() {
    # Render the current known-resolved skip list for `gcp scan --show-skip-list`
    # (issue #1039): the resolved file path plus every registered SHA token.
    local file entries
    file=$(_gcp_scan_skip_file)
    entries=$(_gcp_scan_load_skip_list)
    _gcp_scan_show_skip_generic "Known-resolved skip list" "$file" "$entries" \
        "(no skip-list file — nothing registered)" \
        "(file present but no SHAs registered)"
}

_gcp_scan_skip_paths_file() {
    # Resolve the path-excluded skip-list file path (issue #1215). Honors the
    # GCP_SCAN_SKIP_PATHS_FILE override (absolute or cwd-relative); otherwise
    # defaults to <repo-toplevel>/git/config/gcp-scan-skip-paths.conf so the
    # list is a tracked SSOT alongside the SHA-based gcp-scan-skip.conf. Prints
    # the path (it may not exist yet — callers must -f check). Mirrors
    # _gcp_scan_skip_file().
    if [ -n "${GCP_SCAN_SKIP_PATHS_FILE-}" ]; then
        printf '%s\n' "$GCP_SCAN_SKIP_PATHS_FILE"
        return 0
    fi
    local top
    top=$(git rev-parse --show-toplevel 2>/dev/null) || top="."
    printf '%s/git/config/gcp-scan-skip-paths.conf\n' "$top"
}

_gcp_scan_load_skip_paths() {
    # Parse the path-excluded skip-list file (issue #1215) into one cleaned
    # LITERAL path per line. Each line is `<path> [# free-text reason]`; inline
    # comments, full-comment lines, and blank lines are stripped. Shares
    # _gcp_scan_clean_token() with _gcp_scan_load_skip_list() but does NOT
    # validate/reject glob characters: the path matcher is string-EQUALITY
    # (not a `case` glob), so a stray `*` is harmless — it simply matches
    # nothing.
    local file line token
    file=$(_gcp_scan_skip_paths_file)
    [ -f "$file" ] || return 0
    # `|| [ -n "$line" ]` flushes a final newline-less line (POSIX read idiom).
    while IFS= read -r line || [ -n "$line" ]; do
        token=$(_gcp_scan_clean_token "$line")
        [ -z "$token" ] && continue
        printf '%s\n' "$token"
    done <"$file"
}

_gcp_scan_path_in_list() {
    # True (0) when candidate path $1 EXACTLY equals one of the allowlist paths
    # in $2 (newline-separated). Deliberately a string-equality test
    # ([ "$cand" = "$entry" ]), NEVER a `case` glob like the SHA matcher's
    # intentional prefix-glob: a path allowlist must match literally so a stray
    # `*`/`?`/`[` in the config cannot over-match every file (the glob-over-match
    # bug class gemini PR #1040 flagged for the SHA matcher). Mirrors the no-fork
    # here-doc read style.
    local cand="$1" entry
    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        if [ "$cand" = "$entry" ]; then
            return 0
        fi
    done <<EOF
$2
EOF
    return 1
}

_gcp_scan_is_path_excluded() {
    # True (0) when commit $1's full changed-file set is NON-EMPTY and EVERY
    # changed path is in the allowlist $2 (issue #1215). A single miss (a file
    # not in the allowlist) disqualifies the whole commit, so a commit carrying
    # any real, unrelated content still surfaces. Uses `git diff-tree` for the
    # complete changed-file set of the commit.
    local sha="$1" paths="$2" file seen=0
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        seen=1
        if ! _gcp_scan_path_in_list "$file" "$paths"; then
            return 1
        fi
    done <<EOF
$(git diff-tree --no-commit-id --name-only -r "$sha" 2>/dev/null)
EOF
    [ "$seen" -eq 1 ]
}

_gcp_scan_show_skip_paths() {
    # Render the current path-excluded skip list for `gcp scan --show-skip-paths`
    # (issue #1215): the resolved file path plus every registered literal path.
    local file entries
    file=$(_gcp_scan_skip_paths_file)
    entries=$(_gcp_scan_load_skip_paths)
    _gcp_scan_show_skip_generic "Path-excluded skip list" "$file" "$entries" \
        "(no skip-paths file — nothing registered)" \
        "(file present but no paths registered)"
}

_gcp_scan() {
    # zsh compatibility: emulate POSIX sh to ensure consistent behavior
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    # zsh/bash compatibility: disable debug tracing
    local _xtrace_set=0
    case $- in *x*) _xtrace_set=1 ;; esac
    set +x 2>/dev/null

    local base="main"
    local source="upstream/main"
    local author="dEitY719"
    local arg1="" arg2=""
    local show_skip_list=0
    local show_skip_paths=0
    local stop_on_conflict=0

    # Check for incomplete cherry-pick
    if git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null 2>&1; then
        if type ux_error >/dev/null 2>&1; then
            ux_error "Cherry-pick currently in progress!"
            ux_error "Please resolve it first:"
            ux_error "  git cherry-pick --continue  (or)"
            ux_error "  git cherry-pick --abort"
        else
            echo "Error: Cherry-pick currently in progress!" >&2
            echo "Please resolve it first:" >&2
            echo "  git cherry-pick --continue  (or)" >&2
            echo "  git cherry-pick --abort" >&2
        fi
        return 1
    fi

    # Parse arguments (simpler than bash array approach, works in all shells)
    while [ $# -gt 0 ]; do
        case "$1" in
        --author=*)
            author="${1#--author=}"
            ;;
        --author)
            if [ -n "${2-}" ]; then
                author="$2"
                shift
            else
                if type ux_error >/dev/null 2>&1; then
                    ux_error "--author requires a value"
                else
                    echo "Error: --author requires a value" >&2
                fi
                return 1
            fi
            ;;
        --show-skip-list)
            show_skip_list=1
            ;;
        --show-skip-paths)
            show_skip_paths=1
            ;;
        --stop-on-conflict)
            stop_on_conflict=1
            ;;
        *)
            # Store positional arguments without array syntax
            if [ -z "$arg1" ]; then
                arg1="$1"
            elif [ -z "$arg2" ]; then
                arg2="$1"
            fi
            ;;
        esac
        shift
    done

    # Apply positional arguments
    if [ -n "$arg1" ]; then
        base="$arg1"
    fi
    if [ -n "$arg2" ]; then
        source="$arg2"
    fi

    # --show-skip-list (issue #1039): print the known-resolved skip list and
    # return without scanning. Handled before the header so it stays a clean,
    # standalone query that works outside a configured base/source.
    if [ "$show_skip_list" -eq 1 ]; then
        _gcp_scan_show_skip_list
        if [ $_xtrace_set -eq 1 ]; then
            set -x
        fi
        return 0
    fi

    # --show-skip-paths (issue #1215): print the path-excluded skip list and
    # return without scanning. Mirrors --show-skip-list above.
    if [ "$show_skip_paths" -eq 1 ]; then
        _gcp_scan_show_skip_paths
        if [ $_xtrace_set -eq 1 ]; then
            set -x
        fi
        return 0
    fi

    # Use ux_header if available
    if type ux_header >/dev/null 2>&1; then
        ux_header "Scanning for missing commits from '$source' in '$base'..."
    else
        echo "=== Scanning for missing commits from '$source' in '$base'... ==="
    fi

    # Verify branches exist
    if ! git rev-parse --verify "$base" >/dev/null 2>&1; then
        if type ux_error >/dev/null 2>&1; then
            ux_error "Base branch '$base' does not exist."
        else
            echo "Error: Base branch '$base' does not exist." >&2
        fi
        return 1
    fi
    if ! git rev-parse --verify "$source" >/dev/null 2>&1; then
        if type ux_error >/dev/null 2>&1; then
            ux_error "Source branch '$source' does not exist."
        else
            echo "Error: Source branch '$source' does not exist." >&2
        fi
        return 1
    fi

    # Find missing commits (present in source, missing in base)
    local missing_list
    missing_list=$(git cherry "$base" "$source" | grep "^+" | awk '{print $2}')

    if [ -z "$missing_list" ]; then
        if type ux_success >/dev/null 2>&1; then
            ux_success "No missing commits found! '$base' is up to date with '$source'."
        else
            echo "✓ No missing commits found! '$base' is up to date with '$source'."
        fi
        return 0
    fi

    local total_count
    total_count=$(echo "$missing_list" | wc -l)
    local author_lc
    author_lc=$(printf '%s' "$author" | tr '[:upper:]' '[:lower:]')

    # Filter by author unless explicitly showing all
    local selected_list=""
    if [ "$author_lc" = "all" ]; then
        selected_list="$missing_list"
    else
        while IFS= read -r sha; do
            [ -z "$sha" ] && continue
            local commit_author
            commit_author=$(git show -s --format='%an' "$sha")
            if [ "$(printf '%s' "$commit_author" | tr '[:upper:]' '[:lower:]')" = "$author_lc" ]; then
                if [ -z "$selected_list" ]; then
                    selected_list="$sha"
                else
                    selected_list="${selected_list}"$'\n'"$sha"
                fi
            fi
        done <<EOF
$missing_list
EOF
    fi

    if [ -z "$selected_list" ]; then
        if type ux_warning >/dev/null 2>&1; then
            ux_warning "No missing commits match author '$author'."
            ux_info "Use --author=all to show all missing commits."
        else
            echo "⚠ No missing commits match author '$author'." >&2
            echo "ℹ Use --author=all to show all missing commits." >&2
        fi
        return 0
    fi

    local count
    count=$(echo "$selected_list" | wc -l)

    # Stage-1: subject-based duplicate detection (same subject already in base).
    local final_selected_list=""
    local duplicate_list=""
    local duplicate_map=""
    local duplicate_count=0

    # Cache the base branch's subjects ONCE (PR #812 review): running
    # `git log` per source commit was an O(N) process-fork bottleneck. The
    # per-commit lookup below is then a pure-shell here-doc `while read`
    # (no git/awk fork, no pipe subshell).
    #
    # Cache base subjects over the DIVERGED range `$source..$base`, not a fixed
    # `-n 200` window (issue #1134). A twin whose subject sat beyond commit 200
    # (e.g. main's 218th commit) was never matched, so its counterpart — still
    # "missing" by patch-id — slipped past Stage-1 as a phantom commit that
    # showed up as "1 commit" yet had an empty range/list and immediately became
    # an empty cherry-pick.
    #
    # `$source..$base` (not the full base history — PR #1135 gemini review) is
    # both the complete AND the minimal set to match against: a source candidate
    # can only be a "already applied under a different SHA" dup of a base commit
    # that diverged after the merge-base; base commits before the merge-base are
    # in source's own history too, so matching them would wrongly flag a
    # genuinely new source commit that merely reuses an old subject. On this
    # scan (`main <- upstream/main`) the reported twin is a base-local
    # cherry-pick absent from upstream, so it stays inside the range and is
    # still caught — while large-repo performance/memory stays bounded.
    local base_log tab
    base_log=$(git log "$source..$base" --format='%H%x09%s' 2>/dev/null)
    tab=$(printf '\t')

    # stdin guard (issue #1134): every git/helper call inside these analysis
    # `while read … <<EOF` loops redirects `</dev/null`. Without it a git
    # subprocess that reads stdin (TTY/environment-dependent) would swallow the
    # loop's remaining here-doc input and terminate the loop after one
    # iteration — silently dropping later commits from the analysis and
    # producing the count-vs-list mismatch users saw as a phantom commit.
    while IFS= read -r sha; do
        [ -z "$sha" ] && continue
        local subject
        subject=$(git show -s --format='%s' "$sha" </dev/null)

        # Find a base commit that is a TRUE duplicate of this source candidate
        # and capture its SHA so the individual cherry-pick loop can report what
        # it was already applied as (issue #811 F-1/F-3).
        #
        # Subject equality is only a first-pass CANDIDATE filter — it must never
        # confirm a skip on its own (issue #1136). Repos that reuse a subject
        # ("chore: sync manifest", "bump", auto-generated commits) otherwise map
        # several DISTINCT upstream commits onto one base commit and silently
        # drop the ones carrying real, different content — a data-loss bug. So a
        # subject match is confirmed only when the patches are actually identical
        # by `git patch-id --stable`, the same equivalence test cherry-pick uses.
        # This also rules out the 1:many mis-mapping: two different source
        # commits can never share a patch-id, so at most one binds to a base SHA.
        local match_base_sha="" _b_sha _b_subj src_pid="" _src_pid_done=0
        while IFS="$tab" read -r _b_sha _b_subj; do
            [ "$_b_subj" = "$subject" ] || continue
            # Subject collides — compute the source patch-id once (lazily, so the
            # common no-collision path forks nothing) and require content parity.
            # `--no-color --no-ext-diff` shield the diff from user git config
            # (color.ui=always, diff.external) that would otherwise corrupt the
            # patch-id; stderr is silenced so a warning can't leak into the pipe.
            if [ "$_src_pid_done" -eq 0 ]; then
                src_pid=$(git show --no-color --no-ext-diff "$sha" 2>/dev/null </dev/null | git patch-id --stable 2>/dev/null)
                src_pid=${src_pid%% *}
                _src_pid_done=1
            fi
            local _base_pid=""
            _base_pid=$(git show --no-color --no-ext-diff "$_b_sha" 2>/dev/null </dev/null | git patch-id --stable 2>/dev/null)
            _base_pid=${_base_pid%% *}
            # An empty src_pid (e.g. a merge commit) never equals a non-empty
            # base patch-id, so such a commit is kept, never silently skipped.
            if [ -n "$src_pid" ] && [ "$_base_pid" = "$src_pid" ]; then
                match_base_sha="$_b_sha"
                break
            fi
        done <<EOF
$base_log
EOF
        if [ -n "$match_base_sha" ]; then
            duplicate_list="${duplicate_list}${sha}"$'\n'
            duplicate_map="${duplicate_map}${sha} ${match_base_sha}"$'\n'
            duplicate_count=$((duplicate_count + 1))
        else
            if [ -z "$final_selected_list" ]; then
                final_selected_list="$sha"
            else
                final_selected_list="${final_selected_list}"$'\n'"${sha}"
            fi
        fi
    done <<EOF
$selected_list
EOF

    # Update count if duplicates exist
    if [ $duplicate_count -gt 0 ]; then
        count=$((count - duplicate_count))
    fi

    # Stage-1.4: known-resolved skip list (issue #1039). SHAs registered in
    # git/config/gcp-scan-skip.conf (override: GCP_SCAN_SKIP_FILE) are commits a
    # human already reconciled into HEAD (manual conflict resolution) or that
    # depend on an unmergeable precedent — Stage-1.5/1.6 detect them correctly
    # every run, but re-warning about an already-known skip is pure UX noise.
    # Drop them here, BEFORE Stage-1.5/1.6, so no warning is emitted, and count
    # them under a dedicated "Known-resolved" line. The list is IGNORED under
    # --author=all so the full detection (safety net) is never silenced there.
    local known_resolved_list="" known_resolved_count=0 kr_survivor_list=""
    local skip_list=""
    if [ "$author_lc" != "all" ]; then
        skip_list=$(_gcp_scan_load_skip_list)
    fi
    if [ -n "$skip_list" ]; then
        while IFS= read -r sha; do
            [ -z "$sha" ] && continue
            if _gcp_scan_in_skip_list "$sha" "$skip_list"; then
                known_resolved_list="${known_resolved_list}${sha}
"
                known_resolved_count=$((known_resolved_count + 1))
            else
                if [ -z "$kr_survivor_list" ]; then
                    kr_survivor_list="$sha"
                else
                    kr_survivor_list="${kr_survivor_list}
${sha}"
                fi
            fi
        done <<EOF
$final_selected_list
EOF
        final_selected_list="$kr_survivor_list"
        count=$((count - known_resolved_count))
    fi

    # Stage-1.4b: path-excluded skip list. Independent of and parallel to the
    # SHA-based Stage-1.4 above: instead of matching a specific SHA, it matches
    # a commit's whole changed-file SET against a path allowlist
    # (git/config/gcp-scan-skip-paths.conf, override GCP_SCAN_SKIP_PATHS_FILE).
    # A commit whose every changed file is in the allowlist (e.g. an
    # auto-generated `chore(claude-plugin): sync manifest` touching only the
    # machine-local plugin manifests) is silently dropped here — no per-SHA
    # registration, so a class of ever-new SHAs stops being whack-a-mole. A
    # commit that also touches any other file is left to surface (it carries
    # real content). Like Stage-1.4 this is IGNORED under --author=all so the
    # full detection safety net is never silenced.
    local path_excluded_list="" path_excluded_count=0 pe_survivor_list=""
    local skip_paths=""
    if [ "$author_lc" != "all" ]; then
        skip_paths=$(_gcp_scan_load_skip_paths)
    fi
    if [ -n "$skip_paths" ]; then
        while IFS= read -r sha; do
            [ -z "$sha" ] && continue
            if _gcp_scan_is_path_excluded "$sha" "$skip_paths" </dev/null; then
                path_excluded_list="${path_excluded_list}${sha}
"
                path_excluded_count=$((path_excluded_count + 1))
            else
                if [ -z "$pe_survivor_list" ]; then
                    pe_survivor_list="$sha"
                else
                    pe_survivor_list="${pe_survivor_list}
${sha}"
                fi
            fi
        done <<EOF
$final_selected_list
EOF
        final_selected_list="$pe_survivor_list"
        count=$((count - path_excluded_count))
    fi

    # Stage-1.5: file-dependency pre-check (issue #1033). A candidate that
    # modifies/deletes a file absent from base — because the upstream commit
    # that creates it was filtered out (e.g. a non-author commit) and is not
    # itself in the pick set — would hit a modify/delete conflict. Detect and
    # skip such commits up front with a clear message. Runs on
    # final_selected_list (Stage-1 dups already pruned), BEFORE the Stage-2
    # noop pre-flight so we never waste a probe (or surface a conflict) on them.
    local dep_missing_list="" dep_missing_count=0 dep_survivor_list=""
    while IFS= read -r sha; do
        [ -z "$sha" ] && continue
        local _dep_out=""
        if _dep_out=$(_gcp_scan_check_file_deps "$sha" "$base" "$source" "$selected_list" </dev/null); then
            if [ -z "$dep_survivor_list" ]; then
                dep_survivor_list="$sha"
            else
                dep_survivor_list="${dep_survivor_list}
${sha}"
            fi
        else
            dep_missing_list="${dep_missing_list}${sha}
"
            dep_missing_count=$((dep_missing_count + 1))
            local _dep_file="" _dep_sha="" _c_short
            # Parse only the first "F<TAB>sha" line of _dep_out with a pure
            # here-doc read (no printf/head/cut forks) — mirrors the file's
            # established no-fork style (PR #812); gemini PR #1034 review.
            while IFS="$tab" read -r _dep_file _dep_sha; do
                break
            done <<EOF
$_dep_out
EOF
            _c_short=$(git rev-parse --short "$sha" 2>/dev/null)
            if type ux_warning >/dev/null 2>&1; then
                ux_warning "Skipping ${_c_short} — depends on ${_dep_sha} (creates/deletes ${_dep_file}) not yet in ${base}."
                ux_info "Cherry-pick that commit first, or re-run with --author=all to include the dependency."
            else
                echo "⚠ Skipping ${_c_short} — depends on ${_dep_sha} (creates/deletes ${_dep_file}) not yet in ${base}." >&2
                echo "ℹ Cherry-pick that commit first, or re-run with --author=all to include the dependency." >&2
            fi
        fi
    done <<EOF
$final_selected_list
EOF
    final_selected_list="$dep_survivor_list"
    if [ "$dep_missing_count" -gt 0 ]; then
        count=$((count - dep_missing_count))
    fi

    # Stage-1.6: content-conflict pre-check (issue #1037, extends Stage-1.5). A
    # candidate whose change overlaps the same region HEAD already changed in a
    # file present on both sides would hit a 3-way *content* conflict — the case
    # Stage-1.5 (modify/delete of an absent file) does not cover. Probe each
    # Stage-1.5 survivor with `git merge-tree` (a non-destructive dry-run of the
    # cherry-pick merge) and skip the ones predicted to conflict, mirroring the
    # Stage-1.5 warning + counter pattern. Runs BEFORE the Stage-2 noop
    # pre-flight so we never surface a conflict on a commit that is genuinely
    # redundant. A predicted conflict that is pure context drift (the commit's
    # real change already matches HEAD, issue #913/#1151) is deliberately NOT
    # flagged here — it falls through as a survivor and Stage-2 absorbs it as a
    # no-op, so a commit already in HEAD is never mislabelled a content conflict.
    local conflict_list="" conflict_count=0 conflict_survivor_list=""
    while IFS= read -r sha; do
        [ -z "$sha" ] && continue
        local _cf_out=""
        if _cf_out=$(_gcp_scan_predict_content_conflict "$sha" "$selected_list" </dev/null); then
            if [ -z "$conflict_survivor_list" ]; then
                conflict_survivor_list="$sha"
            else
                conflict_survivor_list="${conflict_survivor_list}
${sha}"
            fi
        else
            conflict_list="${conflict_list}${sha}
"
            conflict_count=$((conflict_count + 1))
            local _cf_short
            _cf_short=$(git rev-parse --short "$sha" 2>/dev/null)
            if type ux_warning >/dev/null 2>&1; then
                ux_warning "Skipping ${_cf_short} — predicted content conflict in ${_cf_out} (same region changed in ${base})."
                ux_info "Cherry-pick it manually and resolve, or rebase the change onto the latest ${base}."
            else
                echo "⚠ Skipping ${_cf_short} — predicted content conflict in ${_cf_out} (same region changed in ${base})." >&2
                echo "ℹ Cherry-pick it manually and resolve, or rebase the change onto the latest ${base}." >&2
            fi
        fi
    done <<EOF
$final_selected_list
EOF
    final_selected_list="$conflict_survivor_list"
    if [ "$conflict_count" -gt 0 ]; then
        count=$((count - conflict_count))
    fi

    # Stage-2: no-op pre-flight in Analysis phase — filters phantom commits
    # before display so users never see commits that will immediately be skipped
    # (issue #961). Runs on final_selected_list (Stage-1 dups already removed).
    local noop_list="" noop_count=0 real_final_list=""
    while IFS= read -r sha; do
        [ -z "$sha" ] && continue
        if _gcp_scan_preflight_is_noop "$sha" </dev/null; then
            noop_list="${noop_list}${sha}
"
            noop_count=$((noop_count + 1))
        else
            if [ -z "$real_final_list" ]; then
                real_final_list="$sha"
            else
                real_final_list="${real_final_list}
${sha}"
            fi
        fi
    done <<EOF
$final_selected_list
EOF
    final_selected_list="$real_final_list"
    count=$((count - noop_count))

    # Early return: all commits are duplicates (already applied)
    if [ $count -eq 0 ]; then
        if type ux_section >/dev/null 2>&1; then
            ux_section "Analysis Result"
            ux_bullet "Missing (all authors): $total_count"
            ux_bullet "Author filter: $author -> 0 new commit(s)"
            ux_bullet "Duplicates (already applied): $duplicate_count"
            if [ "$known_resolved_count" -gt 0 ]; then
                printf "%s  ◆ Known-resolved (skipped): %d%s\n" "${UX_MUTED-}" "$known_resolved_count" "${UX_RESET-}"
            fi
            if [ "$path_excluded_count" -gt 0 ]; then
                printf "%s  ◆ Path-excluded (skipped): %d%s\n" "${UX_MUTED-}" "$path_excluded_count" "${UX_RESET-}"
            fi
            if [ "$dep_missing_count" -gt 0 ]; then
                printf "%s  ◆ Dep-missing (skipped): %d%s\n" "${UX_MUTED-}" "$dep_missing_count" "${UX_RESET-}"
            fi
            if [ "$conflict_count" -gt 0 ]; then
                printf "%s  ◆ Content-conflict (skipped): %d%s\n" "${UX_MUTED-}" "$conflict_count" "${UX_RESET-}"
            fi
            if [ "$noop_count" -gt 0 ]; then
                printf "%s  ◆ Already in HEAD (no-op): %d%s\n" "${UX_MUTED-}" "$noop_count" "${UX_RESET-}"
            fi
        else
            echo "=== Analysis Result ==="
            echo "  Missing (all authors): $total_count"
            echo "  Author filter: $author -> 0 new commit(s)"
            echo "  Duplicates (already applied): $duplicate_count"
            if [ "$known_resolved_count" -gt 0 ]; then
                echo "  Known-resolved (skipped): $known_resolved_count"
            fi
            if [ "$path_excluded_count" -gt 0 ]; then
                echo "  Path-excluded (skipped): $path_excluded_count"
            fi
            if [ "$dep_missing_count" -gt 0 ]; then
                echo "  Dep-missing (skipped): $dep_missing_count"
            fi
            if [ "$conflict_count" -gt 0 ]; then
                echo "  Content-conflict (skipped): $conflict_count"
            fi
            if [ "$noop_count" -gt 0 ]; then
                echo "  Already in HEAD (no-op): $noop_count"
            fi
        fi
        if type ux_success >/dev/null 2>&1; then
            ux_success "All matching commits are already applied to '$base'. Nothing to do."
        else
            echo "✓ All matching commits are already applied to '$base'. Nothing to do."
        fi
        return 0
    fi

    # Calculate the (informational) range from non-duplicate commits only.
    local first_sha
    first_sha=$(echo "$final_selected_list" | head -n 1)
    local last_sha
    last_sha=$(echo "$final_selected_list" | tail -n 1)
    local range_str="${first_sha}^..${last_sha}"

    # Display Summary
    if type ux_section >/dev/null 2>&1; then
        ux_section "Analysis Result"
        ux_bullet "Missing (all authors): $total_count"
        ux_bullet "Author filter: $author -> $count commit(s)"
        if [ $duplicate_count -gt 0 ]; then
            ux_bullet "Duplicates (already applied): $duplicate_count"
        fi
        if [ "$known_resolved_count" -gt 0 ]; then
            printf "%s  ◆ Known-resolved (skipped): %d%s\n" "${UX_MUTED-}" "$known_resolved_count" "${UX_RESET-}"
        fi
        if [ "$path_excluded_count" -gt 0 ]; then
            printf "%s  ◆ Path-excluded (skipped): %d%s\n" "${UX_MUTED-}" "$path_excluded_count" "${UX_RESET-}"
        fi
        if [ "$dep_missing_count" -gt 0 ]; then
            printf "%s  ◆ Dep-missing (skipped): %d%s\n" "${UX_MUTED-}" "$dep_missing_count" "${UX_RESET-}"
        fi
        if [ "$conflict_count" -gt 0 ]; then
            printf "%s  ◆ Content-conflict (skipped): %d%s\n" "${UX_MUTED-}" "$conflict_count" "${UX_RESET-}"
        fi
        if [ "$noop_count" -gt 0 ]; then
            printf "%s  ◆ Already in HEAD (no-op): %d%s\n" "${UX_MUTED-}" "$noop_count" "${UX_RESET-}"
        fi
        ux_bullet "Suggested Range: $range_str"
    else
        echo "=== Analysis Result ==="
        echo "  Missing (all authors): $total_count"
        echo "  Author filter: $author -> $count commit(s)"
        if [ $duplicate_count -gt 0 ]; then
            echo "  Duplicates (already applied): $duplicate_count"
        fi
        if [ "$known_resolved_count" -gt 0 ]; then
            echo "  Known-resolved (skipped): $known_resolved_count"
        fi
        if [ "$path_excluded_count" -gt 0 ]; then
            echo "  Path-excluded (skipped): $path_excluded_count"
        fi
        if [ "$dep_missing_count" -gt 0 ]; then
            echo "  Dep-missing (skipped): $dep_missing_count"
        fi
        if [ "$conflict_count" -gt 0 ]; then
            echo "  Content-conflict (skipped): $conflict_count"
        fi
        if [ "$noop_count" -gt 0 ]; then
            echo "  Already in HEAD (no-op): $noop_count"
        fi
        echo "  Suggested Range: $range_str"
    fi

    # Display Commits
    if type ux_section >/dev/null 2>&1; then
        ux_section "Commit List"
    else
        echo "=== Commit List ==="
    fi
    if type ux_info >/dev/null 2>&1; then
        ux_info "Commits to cherry-pick:"
    else
        echo "Commits to cherry-pick:"
    fi

    local line_num=0
    while IFS= read -r sha; do
        [ -z "$sha" ] && continue
        line_num=$((line_num + 1))

        local line
        line=$(git log --no-walk --format="%C(auto)%h %C(green)%ad %C(blue)%an%C(auto)%d %s" --date=short "$sha")

        printf " %d. %s\n" "$line_num" "$line"
    done <<EOF
$final_selected_list
EOF

    # Clean-worktree precondition (issue #1647, defect C): the execution
    # loop's rollback path (below) recovers from an unpredicted conflict with
    # `git cherry-pick --abort` / `git reset --hard`, either of which would
    # also wipe unrelated uncommitted work. Refuse to even prompt on a dirty
    # tree. The read-only Analysis phase above (including Stage-2's
    # stash/pop'd probes) is unaffected — only the confirm+execute phase gates
    # here.
    #
    # `git status --porcelain` (not `git diff` / `git diff --cached`) is
    # deliberate: it also catches UNTRACKED files, which neither `diff`
    # variant reports (agy review, PR #1649). That coverage is what makes the
    # execution loop's own untracked cleanup below safe — it can only assume
    # "any untracked file present after a rollback came from the failed
    # cherry-pick" because this gate already proved none pre-existed.
    if [ -n "$(git status --porcelain)" ]; then
        if type ux_error >/dev/null 2>&1; then
            ux_error "Working tree is dirty — cherry-pick execution refuses to start."
            ux_error "Run 'git stash push -u' first, then re-run this scan."
        else
            echo "Error: Working tree is dirty — cherry-pick execution refuses to start." >&2
            echo "Run 'git stash push -u' first, then re-run this scan." >&2
        fi
        if [ $_xtrace_set -eq 1 ]; then
            set -x
        fi
        return 1
    fi

    # Interactive Confirmation
    if ! type ux_confirm >/dev/null 2>&1; then
        return 0
    fi
    if ! ux_confirm "Do you want to cherry-pick these $count commits?" "n"; then
        if type ux_info >/dev/null 2>&1; then
            ux_info "Cancelled. You can use the range above manually: git cherry-pick $range_str"
        fi
        # Restore tracing if it was enabled
        if [ $_xtrace_set -eq 1 ]; then
            set -x
        fi
        return 0
    fi

    # Always iterate individually (issue #913): the contiguous range shortcut
    # is gone so the no-op pre-flight below can NEVER be bypassed. Iterate the
    # full author-filtered list (selected_list) — not the dup-pruned
    # final_selected_list — so Stage-1 dups are skipped *with a log line*
    # instead of being silently dropped (issue #811 F-1/F-2).
    local picked=0
    local empty_skipped=0
    local noop_skipped=0
    local dup_skipped=0
    local dep_skipped=0
    local conflict_skipped=0
    local kr_skipped=0
    local pe_skipped=0
    local deferred_list="" deferred_count=0
    # Cache the .git dir BEFORE any cherry-pick runs, while config is still
    # readable (issue #1213). A real conflict in a tracked-and-[include]-d
    # git/.gitconfig poisons config, so the later CHERRY_PICK_HEAD check must
    # be a plain file test — `git rev-parse` itself would die on the poison.
    local _gcp_git_dir
    _gcp_git_dir=$(git rev-parse --git-dir 2>/dev/null) || _gcp_git_dir=".git"
    while IFS= read -r sha; do
        [ -z "$sha" ] && continue

        # Stage-1.4b path-excluded (issue #1215): silently skip — the Analysis
        # phase already counted it; the user configured a path allowlist
        # precisely to stop seeing this class of auto-generated commit. No log
        # line here (that is the point); the summary's "(N skipped —
        # path-excluded)" line is the only trace. Mirrors the known-resolved
        # skip below.
        local _in_pe=0
        case "
$path_excluded_list" in
            *"
$sha
"*) _in_pe=1 ;;
        esac
        if [ "$_in_pe" -eq 1 ]; then
            pe_skipped=$((pe_skipped + 1))
            continue
        fi

        # Stage-1.4 known-resolved (issue #1039): silently skip — the Analysis
        # phase already counted it and the user registered it precisely to stop
        # seeing a warning. No log line here (that is the whole point); the
        # summary's "(N skipped — known-resolved)" line is the only trace.
        local _in_kr=0
        case "
$known_resolved_list" in
            *"
$sha
"*) _in_kr=1 ;;
        esac
        if [ "$_in_kr" -eq 1 ]; then
            kr_skipped=$((kr_skipped + 1))
            continue
        fi

        # Stage-1.5 dependency-missing (issue #1033): skip with a log line so
        # the commit is never attempted — it would conflict on a modify/delete
        # of a file absent from base. Newline-wrapped membership match mirrors
        # the Stage-2 noop_list test below.
        local _in_dep=0
        case "
$dep_missing_list" in
            *"
$sha
"*) _in_dep=1 ;;
        esac
        if [ "$_in_dep" -eq 1 ]; then
            dep_skipped=$((dep_skipped + 1))
            continue
        fi

        # Stage-1.6 content-conflict (issue #1037): skip with a log line so the
        # commit is never attempted — it would hit a 3-way content conflict on a
        # file both sides changed. Membership match mirrors the dep_missing test.
        local _in_conflict=0
        case "
$conflict_list" in
            *"
$sha
"*) _in_conflict=1 ;;
        esac
        if [ "$_in_conflict" -eq 1 ]; then
            conflict_skipped=$((conflict_skipped + 1))
            continue
        fi

        # Stage-1 subject duplicate: skip without a cherry-pick attempt,
        # naming the base SHA it matches (issue #811 F-2/F-3).
        local dup_base_sha
        dup_base_sha=$(_gcp_scan_dup_base_sha "$sha" "$duplicate_map")
        if [ -n "$dup_base_sha" ]; then
            if type ux_info >/dev/null 2>&1; then
                ux_info "Skipping ${sha} — already applied as ${dup_base_sha} (duplicate subject)"
            else
                echo "ℹ Skipping ${sha} — already applied as ${dup_base_sha} (duplicate subject)"
            fi
            dup_skipped=$((dup_skipped + 1))
            continue
        fi

        # No-op check (issue #961): Stage-2 pre-flight already probed each commit
        # in the Analysis phase; reuse that result to avoid a double-probe.
        # POSIX case-pattern match avoids O(N*M) nested loop overhead.
        local _in_noop=0
        case "
$noop_list" in
            *"
$sha
"*) _in_noop=1 ;;
        esac
        if [ "$_in_noop" -eq 1 ]; then
            noop_skipped=$((noop_skipped + 1))
            continue
        fi

        if type ux_info >/dev/null 2>&1; then
            ux_info "Cherry-picking $sha..."
        fi
        if _gcp_scan_cherry_pick_quiet "$sha" "$_gcp_git_dir"; then
            picked=$((picked + 1))
        else
            # Defensive: a commit that becomes empty against HEAD (no conflict)
            # still needs an explicit --skip in some git versions.
            while _gcp_scan_is_empty_cherry_pick; do
                if type ux_warning >/dev/null 2>&1; then
                    ux_warning "Empty commit at $sha; skipping..."
                fi
                if git cherry-pick --skip; then
                    empty_skipped=$((empty_skipped + 1))
                    break
                fi
                break
            done
            # Plain file test, not `git rev-parse` (issue #1213): a poisoned
            # config makes any git call fail, which the old code misread as
            # "no conflict → skip", silently dropping the real conflict.
            if [ ! -f "${_gcp_git_dir}/CHERRY_PICK_HEAD" ]; then
                continue
            fi
            # Genuine conflict (the pre-flight already excluded redundant
            # ones — Stage-1.5/1.6 are static approximations that WILL miss
            # some at scale, issue #1647). `--stop-on-conflict` restores the
            # legacy behavior: abort the whole remaining batch here, exactly
            # as before.
            if [ "$stop_on_conflict" -eq 1 ]; then
                _gcp_scan_report_conflict_stop "$sha"
                return 1
            fi

            # Default (issue #1647, defect B): roll back this ONE commit and
            # keep going, instead of losing the whole remaining batch to a
            # single unpredicted conflict. Read the conflicted files first —
            # the rollback below erases that information.
            local _conflict_files _short_sha
            _conflict_files=$(git diff --name-only --diff-filter=U 2>/dev/null | tr '\n' ' ')
            _short_sha=$(git rev-parse --short "$sha" 2>/dev/null)
            git cherry-pick --abort >/dev/null 2>&1 || {
                git cherry-pick --quit >/dev/null 2>&1
                git reset --hard HEAD >/dev/null 2>&1
            }
            # Verify the rollback actually cleared the sequencer with a plain
            # file test, not `git rev-parse` (issue #1213: the conflict itself
            # can poison a tracked, [include]-d git config, and every git
            # invocation dies from that instant on). If it's still there,
            # never continue the batch on top of a live sequencer — fall
            # through to the legacy error path instead.
            if [ -f "${_gcp_git_dir}/CHERRY_PICK_HEAD" ]; then
                _gcp_scan_report_conflict_stop "$sha"
                return 1
            fi
            # `--abort` / `reset --hard` only restore TRACKED content — a
            # failed cherry-pick can also leave behind untracked files (e.g.
            # a conflict side that added a new file) that neither command
            # touches (agy review, PR #1649). Safe to sweep unconditionally
            # here: the defect-C precondition above already refused to start
            # on a tree with ANY pre-existing untracked file, so anything
            # untracked now present was created by this failed attempt.
            git clean -fd >/dev/null 2>&1
            deferred_list="${deferred_list}${sha}
"
            deferred_count=$((deferred_count + 1))
            if type ux_warning >/dev/null 2>&1; then
                ux_warning "Deferred ${_short_sha} — unpredicted conflict in ${_conflict_files}; rolled back, continuing with the rest."
            else
                echo "⚠ Deferred ${_short_sha} — unpredicted conflict in ${_conflict_files}; rolled back, continuing with the rest." >&2
            fi
            continue
        fi
    done <<EOF
$selected_list
EOF

    # Reaching here means no UNRESOLVED sequencer state is left behind (a
    # rollback failure returns 1 above) — deferred_count carries how many
    # commits hit a real, unpredicted conflict and were rolled back rather
    # than applied (issue #1647, defect D; was hardcoded "0 conflicts"
    # regardless of outcome).
    if type ux_success >/dev/null 2>&1; then
        ux_success "$picked applied, $dup_skipped skipped (dup), $deferred_count deferred (conflict)"
        if [ "$kr_skipped" -gt 0 ]; then
            ux_info "($kr_skipped commit(s) skipped — known-resolved)"
        fi
        if [ "$pe_skipped" -gt 0 ]; then
            ux_info "($pe_skipped commit(s) skipped — path-excluded)"
        fi
        if [ "$dep_skipped" -gt 0 ]; then
            ux_info "($dep_skipped commit(s) skipped — file dependency missing in $base)"
        fi
        if [ "$conflict_skipped" -gt 0 ]; then
            ux_info "($conflict_skipped commit(s) skipped — predicted content conflict with $base)"
        fi
        if [ "$noop_skipped" -gt 0 ]; then
            ux_info "($noop_skipped commit(s) skipped — already in HEAD, no-op pre-flight)"
        fi
        if [ "$empty_skipped" -gt 0 ]; then
            ux_info "($empty_skipped empty commit(s) also skipped)"
        fi
    else
        echo "✓ $picked applied, $dup_skipped skipped (dup), $deferred_count deferred (conflict)"
        if [ "$kr_skipped" -gt 0 ]; then
            echo "  ($kr_skipped commit(s) skipped — known-resolved)"
        fi
        if [ "$pe_skipped" -gt 0 ]; then
            echo "  ($pe_skipped commit(s) skipped — path-excluded)"
        fi
        if [ "$dep_skipped" -gt 0 ]; then
            echo "  ($dep_skipped commit(s) skipped — file dependency missing in $base)"
        fi
        if [ "$conflict_skipped" -gt 0 ]; then
            echo "  ($conflict_skipped commit(s) skipped — predicted content conflict with $base)"
        fi
        if [ "$noop_skipped" -gt 0 ]; then
            echo "  ($noop_skipped commit(s) skipped — already in HEAD, no-op pre-flight)"
        fi
        if [ "$empty_skipped" -gt 0 ]; then
            echo "  ($empty_skipped empty commit(s) also skipped)"
        fi
    fi

    # "Needs manual resolution" (issue #1647, defect D): name every deferred
    # commit with a copy-pasteable retry line, plus how to permanently silence
    # a false positive (the known-resolved skip list).
    if [ "$deferred_count" -gt 0 ]; then
        if type ux_section >/dev/null 2>&1; then
            ux_section "Needs manual resolution"
        else
            echo "=== Needs manual resolution ==="
        fi
        while IFS= read -r _def_sha; do
            [ -z "$_def_sha" ] && continue
            local _def_line
            _def_line=$(git log --no-walk --format='%h %s' "$_def_sha" 2>/dev/null)
            if type ux_bullet >/dev/null 2>&1; then
                ux_bullet "${_def_line}"
                ux_bullet "  git cherry-pick ${_def_sha}"
            else
                echo "  ${_def_line}"
                echo "  git cherry-pick ${_def_sha}"
            fi
        done <<EOF
$deferred_list
EOF
        if type ux_info >/dev/null 2>&1; then
            ux_info "Resolve each manually, or — if HEAD is already a superset of the change — register it in git/config/gcp-scan-skip.conf."
            ux_info "Also review the commits that DID apply after the ones above: static prediction can't see cross-file dependencies, so an already-applied commit may silently assume content a deferred commit was supposed to add (issue #1647, codex review PR #1649)."
        else
            echo "ℹ Resolve each manually, or — if HEAD is already a superset of the change — register it in git/config/gcp-scan-skip.conf." >&2
            echo "ℹ Also review the commits that DID apply after the ones above: static prediction can't see cross-file dependencies, so an already-applied commit may silently assume content a deferred commit was supposed to add (issue #1647, codex review PR #1649)." >&2
        fi
    fi

    # Restore tracing if it was enabled
    if [ $_xtrace_set -eq 1 ]; then
        set -x
    fi

    # Unfinished work (>=1 deferred commit) must not read as success to a
    # caller/script (issue #1647, defect D).
    if [ "$deferred_count" -gt 0 ]; then
        return 1
    fi
    return 0
}

# Note: 'gcp_scan' / 'gcp-scan' aliases live in gcp.sh and route through
# the dispatcher (issue #697). Do not add them here.
