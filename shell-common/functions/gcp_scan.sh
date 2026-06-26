#!/bin/sh
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
    local sha="$1" result=1 had_stash=0 conflicted f
    if ! git diff --quiet || ! git diff --cached --quiet; then
        git stash push -q --include-untracked -m "gcp_preflight_probe" && had_stash=1
        # Data-loss guard (PR #916 review): a failed stash leaves the tree
        # dirty, and the `git reset --hard HEAD` below would then wipe the
        # uncommitted work. Bail out (treat as "not a no-op") instead.
        if [ "$had_stash" -ne 1 ]; then
            return 1
        fi
    fi
    # Self-protection against a config-poisoning probe (issue #1016). When the
    # probed commit edits `git/.gitconfig` (symlinked from ~/.gitconfig), the
    # `cherry-pick -n` below can leave the symlink target unreadable by git:
    # a conflict writes `<<<<<<<` markers into it, and even a clean apply may
    # stage a syntactically broken .gitconfig carried by the commit itself.
    # From that instant EVERY subsequent git invocation — including the
    # `git reset --hard HEAD` recovery — dies with `fatal: bad config line N`,
    # so the breakage can never be cleared. Snapshot the real config file first
    # with a plain `cp` (no git needed) so we can restore it before git reads it.
    local _gcfg_real="" _gcfg_bak="" _gcp_cp_rc=0
    # Resolve the file behind ~/.gitconfig portably: prefer GNU `readlink -f`,
    # fall back to plain `readlink` + manual absolutisation for BSD/macOS (where
    # `-f` is unsupported, PR #1018 review), then to the path itself when it is a
    # regular (non-symlink) file.
    _gcfg_real=$(readlink -f "${HOME}/.gitconfig" 2>/dev/null)
    if [ -z "$_gcfg_real" ]; then
        _gcfg_real=$(readlink "${HOME}/.gitconfig" 2>/dev/null)
        if [ -n "$_gcfg_real" ]; then
            case "$_gcfg_real" in
                /*) ;;
                *) _gcfg_real="${HOME}/${_gcfg_real}" ;;
            esac
        else
            _gcfg_real="${HOME}/.gitconfig"
        fi
    fi
    if [ -n "$_gcfg_real" ] && [ -f "$_gcfg_real" ]; then
        # Explicit template + fallback dir keeps mktemp portable to BSD/macOS,
        # where a bare `mktemp` errors out (PR #1018 review).
        _gcfg_bak=$(mktemp "${TMPDIR:-/tmp}/gcfg_bak.XXXXXX" 2>/dev/null) &&
            cp "$_gcfg_real" "$_gcfg_bak" 2>/dev/null || _gcfg_bak=""
    fi
    git cherry-pick -n "$sha" >/dev/null 2>&1 || _gcp_cp_rc=$?
    # Restore the working-tree gitconfig UNCONDITIONALLY and immediately, before
    # any further git command reads it — covers both the conflict path and the
    # clean-apply-of-broken-config path (PR #1018 review). `cp` touches only the
    # worktree, never the index, so the staged-diff no-op verdict below is
    # unaffected.
    if [ -n "$_gcfg_bak" ] && [ -f "$_gcfg_bak" ]; then
        cp "$_gcfg_bak" "$_gcfg_real" 2>/dev/null
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
            echo "$conflicted" | while IFS= read -r f; do
                [ -z "$f" ] && continue
                git checkout HEAD -- "$f"
            done
            git diff --cached --quiet && result=0
        fi
    fi
    [ -n "$_gcfg_bak" ] && rm -f "$_gcfg_bak"
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
    local sha="$1" base="$2" source="$3" pick_list="$4"
    local changes st f up_add rc=0 tab
    tab=$(printf '\t')
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
        # Creator is among the commits we will pick first -> not missing
        # (the --author=all path). Newline-wrapped match avoids prefix
        # collisions, mirroring the Stage-2 noop_list membership test.
        case "
$pick_list
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

_gcp_scan_predict_content_conflict() {
    # Content-conflict pre-check (issue #1037, extends Stage-1.5 #1033). Returns
    # 1 when cherry-picking commit $1 onto HEAD is predicted to hit a 3-way
    # *content* conflict — HEAD and the commit change the same region of a file
    # that exists on both sides. This is the case Stage-1.5 does NOT cover
    # (modify/delete of a file absent from base); here both sides edited the
    # same lines. Returns 0 when the merge is predicted clean OR when the
    # verdict is deferred (see the --author=all guard below).
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
    # after which the merge is clean. When any conflicting file is modified by
    # ANOTHER commit in the pick set, defer (return 0) and let the real
    # cherry-pick decide. Mirrors Stage-1.5's pick_list membership guard, so
    # --author=all stays false-positive-free.
    #
    # Prints the first conflicting file path to stdout on the conflict path.
    local sha="$1" pick_list="$2"
    local parent merge_out conflicted f other_files p rc first
    # Root commit (no parent) or merge commit (2+ parents): the cherry-pick
    # merge base is undefined/ambiguous -> out of scope, defer to the real
    # cherry-pick rather than probe with the wrong base.
    parent=$(git rev-parse -q --verify "${sha}^1" 2>/dev/null) || return 0
    if git rev-parse -q --verify "${sha}^2" >/dev/null 2>&1; then
        return 0
    fi
    # Single invocation with --name-only: rc carries the conflict verdict, and
    # stdout is the merged tree OID on line 1 followed by one conflicted path
    # per line. On older git the unknown flags exit > 1 and we bail to "clean".
    merge_out=$(git merge-tree --write-tree --name-only --merge-base="$parent" HEAD "$sha" 2>/dev/null)
    rc=$?
    [ "$rc" -eq 1 ] || return 0
    conflicted=$(printf '%s\n' "$merge_out" | tail -n +2)
    [ -z "$conflicted" ] && return 0
    # Build the set of paths touched by every OTHER pick_list commit, for the
    # --author=all false-positive guard.
    other_files=""
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        [ "$p" = "$sha" ] && continue
        other_files="${other_files}$(git diff-tree --no-commit-id -r --name-only "$p" 2>/dev/null)
"
    done <<EOF
$pick_list
EOF
    first=""
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        # Deferral guard: the conflicting file is also touched by another pick
        # commit -> the conflict is an artifact of an unapplied precedent.
        # Newline-wrapped match avoids prefix collisions (Stage-1.5 pattern).
        case "
$other_files" in
            *"
$f
"*) return 0 ;;
        esac
        [ -z "$first" ] && first="$f"
    done <<EOF
$conflicted
EOF
    [ -z "$first" ] && return 0
    printf '%s\n' "$first"
    return 1
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

    # Cache the base branch's recent subjects ONCE (PR #812 review): running
    # `git log` per source commit was an O(N) process-fork bottleneck. The
    # per-commit lookup below is then a pure-shell here-doc `while read`
    # (no git/awk fork, no pipe subshell).
    local base_log tab
    base_log=$(git log "$base" -n 200 --format='%H%x09%s' 2>/dev/null)
    tab=$(printf '\t')

    while IFS= read -r sha; do
        [ -z "$sha" ] && continue
        local subject
        subject=$(git show -s --format='%s' "$sha")

        # Find a base commit with the same subject and capture its SHA so the
        # individual cherry-pick loop can report what each dup was already
        # applied as (issue #811 F-1/F-3). Exact subject match via tab split.
        local match_base_sha="" _b_sha _b_subj
        while IFS="$tab" read -r _b_sha _b_subj; do
            if [ "$_b_subj" = "$subject" ]; then
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
        if _dep_out=$(_gcp_scan_check_file_deps "$sha" "$base" "$source" "$selected_list"); then
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
    # redundant.
    local conflict_list="" conflict_count=0 conflict_survivor_list=""
    while IFS= read -r sha; do
        [ -z "$sha" ] && continue
        local _cf_out=""
        if _cf_out=$(_gcp_scan_predict_content_conflict "$sha" "$selected_list"); then
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
        if _gcp_scan_preflight_is_noop "$sha"; then
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
    while IFS= read -r sha; do
        [ -z "$sha" ] && continue

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
        if git cherry-pick "$sha"; then
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
            if ! git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null 2>&1; then
                continue
            fi
            # Genuine conflict (the pre-flight already excluded redundant ones):
            # leave it in place with git's own conflict output for the user.
            if type ux_error >/dev/null 2>&1; then
                ux_error "Failed at $sha. Resolve and run: git cherry-pick --continue"
            fi
            return 1
        fi
    done <<EOF
$selected_list
EOF

    # Reaching here means no unresolved conflict (a real conflict returns 1
    # above), so report 0 conflicts.
    if type ux_success >/dev/null 2>&1; then
        ux_success "$picked applied, $dup_skipped skipped (dup), 0 conflicts"
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
        echo "✓ $picked applied, $dup_skipped skipped (dup), 0 conflicts"
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

    # Restore tracing if it was enabled
    if [ $_xtrace_set -eq 1 ]; then
        set -x
    fi
}

# Note: 'gcp_scan' / 'gcp-scan' aliases live in gcp.sh and route through
# the dispatcher (issue #697). Do not add them here.
