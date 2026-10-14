#!/bin/sh
# shellcheck shell=bash
# shell-common/tools/custom/lib/gcp_scan_conflict.sh
# gcp scan: file-dependency and content-conflict prediction (issues #1033, #1647, #1759).
#
# Source-only, no interactive guard: loaded by tools/custom/gcp_scan.sh (the
# `gcp scan` executable, #2155) and by tests/bats/functions/gcp.bats through it.
# Function definitions only. Split out of functions/gcp_scan.sh, whose FILE RULE
# still holds here: every cp/rm/mv call site keeps its `command ` prefix (#1663).

_gcp_scan_check_file_deps() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
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
    # no-op. The leading `[ [], ...]` record covers a top-level scalar, for
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
    #
    # $2 (optional, issue #1775) is a JSON array of array paths whose ELEMENT
    # records are suppressed — see `_gcp_scan_json_absorbed_array_paths`. The
    # array's own `[$p, []]` record still shows, so the array cannot vanish.
    jq -Sc --argjson drop "${2:-[]}" '
        def dropped($p): any($drop[]; . as $d | ($p | length) > ($d | length) and $p[0:($d | length)] == $d);
        [ [], (if type == "object" then {} elif type == "array" then [] else . end)],
        (paths as $p | select(dropped($p) | not) | [$p, (getpath($p) | if type == "object" then {} elif type == "array" then [] else . end)])
    ' "$1"
}

_gcp_scan_json_absorbed_array_paths() {
    # Issue #1775. Emits (as one compact JSON array) the paths of the scalar
    # arrays whose base/$1 -> theirs/$3 -> ours/$2 difference is pure INDEX
    # SHIFT rather than content, so the caller can compare them by value order
    # instead of by absolute index.
    #
    # Why #1688's index-in-the-path design needs this exception: in an
    # alphabetically sorted registry (`claude/plugin/plugins.json`) both
    # branches append. If HEAD independently inserted an earlier-sorting entry,
    # every later element shifts one slot, so the value the commit adds — which
    # HEAD ALREADY HAS — carries a different index and reads as "content HEAD
    # lacks" forever. That is the #1688 bug in a new coordinate.
    #
    # The discriminator is RELATIVE order, which an index shift cannot change:
    # an array qualifies only when base is a subsequence of theirs (the commit
    # only INSERTED — a removal must stay visible, the #1177 data-loss
    # direction) AND theirs is a subsequence of ours (HEAD already holds every
    # value the commit has, in the same relative order). The #1688 reorder case
    # (`["b","a"]` vs `["a","b"]`) fails the second test — the two branches
    # disagree about which of two shared values comes first — so it still reads
    # as real content.
    #
    # Scalar arrays only — a deliberately conservative carve-out, not a
    # technical limit: the subsequence/equality machinery below would work
    # just as well if `sc` also allowed object/array elements. It is narrowed
    # to scalars because an array of objects/arrays is judged far likelier to
    # have order that IS meaningful; those keep the #1688 index-sensitive
    # comparison until evidence says otherwise.
    jq -nc --slurpfile b "$1" --slurpfile o "$2" --slurpfile t "$3" '
        def sc: type == "array" and all(.[]; type != "object" and type != "array");
        # true when $a is a subsequence of the input array (greedy is exact here).
        def subseq($a): (reduce .[] as $y ($a; if length > 0 and .[0] == $y then .[1:] else . end)) | length == 0;
        # every path in the input, root ([]) included — the builtin `paths`
        # filter is this same generator with the root filtered back out.
        def scalar_array_paths: . as $root | path(..) | select(. as $p | $root | getpath($p) | sc);
        # $x at $p if that side holds a scalar array there, else null (a
        # missing or shape-mismatched side never qualifies as absorbed).
        def side($x; $p): (try ($x | getpath($p)) catch null) // [] | if sc then . else null end;
        ($b[0]) as $B | ($o[0]) as $O | ($t[0]) as $T |
        if ($O | type) == "null" or ($T | type) == "null" then []
        else
            [ ($T | scalar_array_paths) as $p
              | ($T | getpath($p)) as $Ta
              | (side($O; $p)) as $Oa
              | (side($B; $p)) as $Ba
              | select($Oa != null and $Ba != null)
              | select(($Ta | subseq($Ba)) and ($Oa | subseq($Ta)))
              | $p
            ]
        end
    '
}

_gcp_scan_conflict_adds_new_content() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
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
    local sha="$1" f="$2" parent td _b _o _t _drop
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
    #
    # `_gcp_scan_json_absorbed_array_paths` (#1775) is the one exception to the
    # index-in-the-path rule: for a scalar array the commit only INSERTED into
    # and whose values HEAD already holds in the same relative order, the
    # per-element records are suppressed on all three sides, so an unrelated
    # insertion earlier in a sorted registry cannot re-brand an already-applied
    # value as new content. A reorder still fails its subsequence test.
    _b="${td}/base" _o="${td}/ours" _t="${td}/theirs"
    if command -v jq >/dev/null 2>&1 &&
        _drop=$(_gcp_scan_json_absorbed_array_paths "${td}/base" "${td}/ours" "${td}/theirs" 2>/dev/null) &&
        _gcp_scan_json_leaves "${td}/base" "$_drop" >"${td}/base.j" 2>/dev/null &&
        _gcp_scan_json_leaves "${td}/ours" "$_drop" >"${td}/ours.j" 2>/dev/null &&
        _gcp_scan_json_leaves "${td}/theirs" "$_drop" >"${td}/theirs.j" 2>/dev/null; then
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

_gcp_scan_staged_is_duplicate_append() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    # True (0) when the CURRENTLY STAGED tree (a `cherry-pick -n` that applied
    # CLEANLY) differs from HEAD only by re-inserting blocks HEAD's own copy of
    # the same file already contains — issue #1759.
    #
    # Why the clean path needed its own discriminator: Stage-2's two verdicts
    # both ask "does the staged tree still differ from HEAD?". That is the right
    # question when the payload landed identically (empty staged diff) or
    # collided (conflict -> `_gcp_scan_conflict_adds_new_content` decides). It is
    # the WRONG question when HEAD holds the payload at a DIFFERENT position
    # than the commit puts it: the two insertions do not overlap, so git's merge
    # has nothing to resolve, appends the block a SECOND time, and leaves a
    # non-empty staged diff that reads as real work. The commit is then
    # re-recommended and re-applied on every scan, one more copy each time
    # (`1 file changed, 54 insertions(+)`, six copies deep in the report).
    # A cross-repo cherry-pick produces that shape whenever the base-side copy
    # of a block landed somewhere other than where the source commit put it.
    #
    # THREE preconditions, all of them narrowing toward "this cannot be new
    # work", because a wrong verdict here drops a commit silently — the #1177
    # data-loss direction:
    #
    #   1. Every staged path is a plain modification (`M`). An add, delete,
    #      rename or typechange is never a re-application of content HEAD
    #      already holds.
    #   2. Every hunk is addition-only. One deleted line means the commit
    #      changes what HEAD has, not merely repeats it — and a pure MOVE
    #      (delete here, add there) lands in exactly that shape, so this is
    #      what keeps a reordering commit visible.
    #   3. Every added block appears verbatim and CONTIGUOUSLY in HEAD's copy
    #      of that same file, and is at least GCP_SCAN_DUP_BLOCK_MIN_LINES
    #      long.
    #
    # Contiguity is the deliberate difference from the set-membership test
    # `_gcp_scan_conflict_adds_new_content` uses: a set test accepts a commit
    # whose every added line happens to exist SOMEWHERE in the file, which for
    # boilerplate (`    return 0`, a lone `}`, a blank line) is coincidence
    # rather than duplication. Requiring the whole hunk to match as one run
    # rules that out for anything but the shortest blocks, and the line floor
    # covers those. Default 3: long enough that an accidental verbatim run is
    # implausible, short enough to catch a real appended stanza.
    #
    # Reads the index and HEAD blobs only — no checkout, no mutation. The
    # caller's `git reset --hard HEAD` is what clears the probe.
    local sha="$1"
    local floor="${GCP_SCAN_DUP_BLOCK_MIN_LINES:-3}"
    local files f td rc=0 subject="" subject_seen=0
    # Precondition 1. `grep -v` answers 0 as soon as ONE staged path is not a
    # plain modification.
    if git diff --cached --name-status 2>/dev/null | grep -qv '^M'; then
        return 1
    fi
    files=$(git diff --cached --name-only 2>/dev/null)
    [ -n "$files" ] || return 1
    td=$(mktemp -d "${TMPDIR:-/tmp}/gcp_dup.XXXXXX" 2>/dev/null) || return 1
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        git cat-file -p "HEAD:${f}" >"${td}/head" 2>/dev/null || { rc=1; break; }
        # `-U0`: no context lines, so every `+`/`-` line inside a hunk is real
        # payload and the hunk headers alone delimit the blocks.
        git diff --cached -U0 -- "$f" >"${td}/diff" 2>/dev/null || { rc=1; break; }
        # `seen` skips the per-file diff header, whose `--- a/x` / `+++ b/x`
        # lines would otherwise read as payload; anchoring on those two
        # prefixes instead would mis-skip a deleted line that starts with
        # `-- `. A bare `exit` on a hit is deliberate — `exit 0` would still
        # run END, whose own exit would override the verdict.
        awk -v min="$floor" -v HF="${td}/head" '
            # O(n*m) sliding window: n = HEAD line count, m = block length.
            # Bounded in practice by when this runs at all — only on a clean
            # apply whose staged diff is non-empty, at most once per staged
            # file. `b[1..bn]` is the whole block: entries left over from a
            # LONGER previous hunk sit past bn and are never read, so bn = 0
            # is a complete reset and `delete b` would be dead code (PR #1760
            # review, agy; pinned by the multi-hunk bats cases).
            function block_ok(   i, j, ok) {
                if (bn == 0) { return 1 }
                if (bn < min) { return 0 }
                for (i = 1; i + bn - 1 <= n; i++) {
                    ok = 1
                    for (j = 1; j <= bn; j++) {
                        if (h[i + j - 1] != b[j]) { ok = 0; break }
                    }
                    if (ok) { nblocks++; return 1 }
                }
                return 0
            }
            FILENAME == HF { h[++n] = $0; next }
            /^@@/ { if (!block_ok()) { bad = 1; exit } bn = 0; seen = 1; next }
            !seen { next }
            /^-/ { bad = 1; exit }
            /^\+/ { b[++bn] = substr($0, 2); next }
            # nblocks == 0 means nothing was actually matched — a mode-only
            # or binary change has a non-empty staged diff but no hunks at
            # all, and "every block matched" is vacuously true for it.
            END { if (!bad && !block_ok()) { bad = 1 } exit((bad || nblocks == 0) ? 1 : 0) }
        ' "${td}/head" "${td}/diff" || { rc=1; break; }
    done <<EOF
$files
EOF
    command rm -rf "$td"
    [ "$rc" -eq 0 ] || return 1
    # Precondition 4 — corroborating evidence that THIS commit was already
    # applied (PR #1760 review, agy + codex BLOCKER, independently).
    #
    # Preconditions 1-3 establish that the payload is a verbatim repeat of
    # content HEAD holds. They cannot, on their own, distinguish that from a
    # commit deliberately adding a second copy of an existing stanza —
    # repeated boilerplate, a config block, another table row. Absorbing one
    # of those is the #1177 data-loss direction, and no threshold on block
    # length fixes it: the repeat is verbatim in both cases.
    #
    # What separates them is not the diff, it is the history. A duplicate
    # RE-application carries the subject of the commit that already landed —
    # a cherry-pick copies the message — so HEAD's own log for the touched
    # files already contains that exact subject. A commit legitimately adding
    # a repeated stanza is new work with a subject of its own, which HEAD has
    # never seen, so it stays visible. That is the same signal #1136 uses as
    # its duplicate CANDIDATE filter, here as the corroborating half of a
    # verdict the payload comparison has already narrowed to one commit.
    #
    # ANY touched file matching is enough: the reported case touched four
    # files but only one carried the duplicated block, the other three having
    # been absorbed silently by the 3-way merge.
    #
    # Deliberately last: it is the only precondition that walks history, and
    # by here the candidate set is already down to "payload is a verbatim
    # repeat", which is rare.
    subject=$(git log -1 --format=%s "$sha" 2>/dev/null)
    [ -n "$subject" ] || return 1
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        if git log --format=%s HEAD -- "$f" 2>/dev/null | grep -Fxq "$subject"; then
            subject_seen=1
            break
        fi
    done <<EOF
$files
EOF
    [ "$subject_seen" -eq 1 ] || return 1
    return 0
}

_gcp_scan_predict_content_conflict() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
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
