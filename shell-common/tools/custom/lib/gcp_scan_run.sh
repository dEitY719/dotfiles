#!/bin/sh
# shellcheck shell=bash
# shell-common/tools/custom/lib/gcp_scan_run.sh
# gcp scan: the scan/pick driver _gcp_scan_run (analysis, confirm, per-commit cherry-pick, report).
#
# Source-only, no interactive guard: loaded by tools/custom/gcp_scan.sh (the
# `gcp scan` executable, #2155) and by tests/bats/functions/gcp.bats through it.
# Function definitions only. Split out of functions/gcp_scan.sh, whose FILE RULE
# still holds here: every cp/rm/mv call site keeps its `command ` prefix (#1663).

_gcp_scan_run() {
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
    local arg1="" arg2=""
    local show_skip_list=0
    local show_skip_paths=0
    local show_deferred=0
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
        --show-skip-list)
            show_skip_list=1
            ;;
        --show-skip-paths)
            show_skip_paths=1
            ;;
        --show-deferred)
            show_deferred=1
            ;;
        --stop-on-conflict)
            stop_on_conflict=1
            ;;
        -*)
            if type ux_error >/dev/null 2>&1; then
                ux_error "Unknown option: $1"
            else
                echo "Error: Unknown option: $1" >&2
            fi
            return 1
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

    # --show-deferred (issue #1795): print the deferred commit cache and
    # return without scanning. Mirrors --show-skip-list above.
    if [ "$show_deferred" -eq 1 ]; then
        _gcp_scan_show_deferred
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
    local selected_list="$missing_list"

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
    # them under a dedicated "Known-resolved" line.
    local known_resolved_list="" known_resolved_count=0 kr_survivor_list=""
    local skip_list=""
    skip_list=$(_gcp_scan_load_skip_list)
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
    # real content).
    local path_excluded_list="" path_excluded_count=0 pe_survivor_list=""
    local skip_paths=""
    skip_paths=$(_gcp_scan_load_skip_paths)
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

    # Stage-1.4c: deferred commit cache (issue #1795). Commits that hit an
    # unpredicted conflict and were rolled back in a prior scan against the SAME
    # base HEAD are recorded in the deferred cache. When current base HEAD
    # matches the recorded base_head_sha, re-attempting real cherry-pick is a
    # guaranteed identical conflict. Filter them out here with a warning line so
    # they are not re-attempted, while invalidating automatically if HEAD changes.
    local deferred_cached_list="" deferred_cached_count=0 dc_survivor_list=""
    local current_base_head="" deferred_cache=""
    current_base_head=$(git rev-parse --verify "$base" 2>/dev/null)
    if [ -n "$current_base_head" ]; then
        deferred_cache=$(_gcp_scan_load_deferred_cache "$current_base_head")
    fi
    if [ -n "$deferred_cache" ]; then
        while IFS= read -r sha; do
            [ -z "$sha" ] && continue
            local _dc_hit=0 _dc_entry="" _dc_sha="" _dc_ts=""
            while IFS="$tab" read -r _dc_sha _dc_ts; do
                case "$sha" in
                    "$_dc_sha"*)
                        _dc_hit=1
                        break
                        ;;
                esac
            done <<EOF
$deferred_cache
EOF
            if [ "$_dc_hit" -eq 1 ]; then
                deferred_cached_list="${deferred_cached_list}${sha}
"
                deferred_cached_count=$((deferred_cached_count + 1))
                local _dc_short
                _dc_short=$(git rev-parse --short "$sha" 2>/dev/null)
                if type ux_warning >/dev/null 2>&1; then
                    ux_warning "Skipping ${_dc_short} — still deferred from previous attempt (last attempt: ${_dc_ts}); resolve manually or re-run after HEAD changes."
                else
                    echo "⚠ Skipping ${_dc_short} — still deferred from previous attempt (last attempt: ${_dc_ts}); resolve manually or re-run after HEAD changes." >&2
                fi
            else
                if [ -z "$dc_survivor_list" ]; then
                    dc_survivor_list="$sha"
                else
                    dc_survivor_list="${dc_survivor_list}
${sha}"
                fi
            fi
        done <<EOF
$final_selected_list
EOF
        final_selected_list="$dc_survivor_list"
        count=$((count - deferred_cached_count))
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
        if _dep_out=$(_gcp_scan_check_file_deps "$sha" "$base" "$source" "$final_selected_list" </dev/null); then
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
                ux_info "Cherry-pick that commit first to include the dependency."
            else
                echo "⚠ Skipping ${_c_short} — depends on ${_dep_sha} (creates/deletes ${_dep_file}) not yet in ${base}." >&2
                echo "ℹ Cherry-pick that commit first to include the dependency." >&2
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
        if _cf_out=$(_gcp_scan_predict_content_conflict "$sha" "$final_selected_list" </dev/null); then
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
            ux_bullet "Missing commits: $total_count"
            ux_bullet "Duplicates (already applied): $duplicate_count"
            if [ "$known_resolved_count" -gt 0 ]; then
                printf "%s  ◆ Known-resolved (skipped): %d%s\n" "${UX_MUTED-}" "$known_resolved_count" "${UX_RESET-}"
            fi
            if [ "$path_excluded_count" -gt 0 ]; then
                printf "%s  ◆ Path-excluded (skipped): %d%s\n" "${UX_MUTED-}" "$path_excluded_count" "${UX_RESET-}"
            fi
            if [ "$deferred_cached_count" -gt 0 ]; then
                printf "%s  ◆ Deferred-cached (skipped): %d%s\n" "${UX_MUTED-}" "$deferred_cached_count" "${UX_RESET-}"
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
            echo "  Missing commits: $total_count"
            echo "  Duplicates (already applied): $duplicate_count"
            if [ "$known_resolved_count" -gt 0 ]; then
                echo "  Known-resolved (skipped): $known_resolved_count"
            fi
            if [ "$path_excluded_count" -gt 0 ]; then
                echo "  Path-excluded (skipped): $path_excluded_count"
            fi
            if [ "$deferred_cached_count" -gt 0 ]; then
                echo "  Deferred-cached (skipped): $deferred_cached_count"
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
        ux_bullet "Missing commits: $total_count"
        if [ $duplicate_count -gt 0 ]; then
            ux_bullet "Duplicates (already applied): $duplicate_count"
        fi
        if [ "$known_resolved_count" -gt 0 ]; then
            printf "%s  ◆ Known-resolved (skipped): %d%s\n" "${UX_MUTED-}" "$known_resolved_count" "${UX_RESET-}"
        fi
        if [ "$path_excluded_count" -gt 0 ]; then
            printf "%s  ◆ Path-excluded (skipped): %d%s\n" "${UX_MUTED-}" "$path_excluded_count" "${UX_RESET-}"
        fi
        if [ "$deferred_cached_count" -gt 0 ]; then
            printf "%s  ◆ Deferred-cached (skipped): %d%s\n" "${UX_MUTED-}" "$deferred_cached_count" "${UX_RESET-}"
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
        echo "  Missing commits: $total_count"
        if [ $duplicate_count -gt 0 ]; then
            echo "  Duplicates (already applied): $duplicate_count"
        fi
        if [ "$known_resolved_count" -gt 0 ]; then
            echo "  Known-resolved (skipped): $known_resolved_count"
        fi
        if [ "$path_excluded_count" -gt 0 ]; then
            echo "  Path-excluded (skipped): $path_excluded_count"
        fi
        if [ "$deferred_cached_count" -gt 0 ]; then
            echo "  Deferred-cached (skipped): $deferred_cached_count"
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

        if type ux_numbered >/dev/null 2>&1; then
            ux_numbered "$line_num" "$line"
        else
            printf " %d. %s\n" "$line_num" "$line"
        fi
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
    local dc_skipped=0
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

        # Stage-1.4c deferred commit cache (issue #1795): skip commits that were
        # already identified as deferred in the Analysis phase.
        local _in_dc=0
        case "
$deferred_cached_list" in
            *"
$sha
"*) _in_dc=1 ;;
        esac
        if [ "$_in_dc" -eq 1 ]; then
            dc_skipped=$((dc_skipped + 1))
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
        if _gcp_scan_cherry_pick_quiet "$sha"; then
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
            # Record into deferred cache (issue #1795)
            local _head_at_defer
            _head_at_defer=$(git rev-parse HEAD 2>/dev/null)
            _gcp_scan_record_deferred "$sha" "$_head_at_defer" "$_conflict_files"
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
        if [ "$dc_skipped" -gt 0 ]; then
            ux_info "($dc_skipped commit(s) skipped — still deferred from previous attempt)"
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
        if [ "$dc_skipped" -gt 0 ]; then
            echo "  ($dc_skipped commit(s) skipped — still deferred from previous attempt)"
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
