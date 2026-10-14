#!/bin/sh
# shellcheck shell=bash
# shell-common/tools/custom/lib/gcp_scan_lists.sh
# gcp scan: skip list, path-excluded skip list and deferred-commit cache (issues #1039, #1215, #1795).
#
# Source-only, no interactive guard: loaded by tools/custom/gcp_scan.sh (the
# `gcp scan` executable, #2155) and by tests/bats/functions/gcp.bats through it.
# Function definitions only. Split out of functions/gcp_scan.sh, whose FILE RULE
# still holds here: every cp/rm/mv call site keeps its `command ` prefix (#1663).

_gcp_scan_skip_file() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
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
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    # Shared line-cleaning for the skip-list parsers below: drop an inline
    # `#` comment, then trim leading/trailing whitespace. Pure
    # parameter-expansion (no awk/sed fork), matching this file's style.
    local token="${1%%#*}"                         # drop inline comment
    token=${token%"${token##*[![:space:]]}"}       # trim trailing space
    token=${token#"${token%%[![:space:]]*}"}       # trim leading space
    printf '%s\n' "$token"
}

_gcp_scan_load_skip_list() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
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
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
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
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
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
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
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
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
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
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
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
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
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
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
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
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    # Render the current path-excluded skip list for `gcp scan --show-skip-paths`
    # (issue #1215): the resolved file path plus every registered literal path.
    local file entries
    file=$(_gcp_scan_skip_paths_file)
    entries=$(_gcp_scan_load_skip_paths)
    _gcp_scan_show_skip_generic "Path-excluded skip list" "$file" "$entries" \
        "(no skip-paths file — nothing registered)" \
        "(file present but no paths registered)"
}

_gcp_scan_deferred_file() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    # Resolve the deferred cache file path (issue #1795). Honors the
    # GCP_SCAN_DEFERRED_FILE override (absolute or cwd-relative); otherwise
    # defaults to <repo-git-dir>/gcp-scan-deferred so it is a local-only cache
    # not tracked in git. Prints the path (it may not exist yet).
    if [ -n "${GCP_SCAN_DEFERRED_FILE-}" ]; then
        printf '%s\n' "$GCP_SCAN_DEFERRED_FILE"
        return 0
    fi
    local git_dir
    git_dir=$(git rev-parse --git-dir 2>/dev/null) || git_dir=".git"
    printf '%s/gcp-scan-deferred\n' "$git_dir"
}

_gcp_scan_load_deferred_cache() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    # Parse the deferred cache file (issue #1795) against the current base HEAD
    # SHA $1. File format per line: `<cand_sha> <base_head_sha> <timestamp> [# reason]`.
    # Emits `<cand_sha><TAB><timestamp>` for entries matching $1 (valid cache).
    local base_head="$1" file line cand_sha head_sha ts rest
    [ -z "$base_head" ] && return 0
    file=$(_gcp_scan_deferred_file)
    [ -f "$file" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        # Strip inline comment and whitespace
        line=$(_gcp_scan_clean_token "$line")
        [ -z "$line" ] && continue
        # Extract fields
        cand_sha="" head_sha="" ts=""
        read -r cand_sha head_sha ts rest <<EOF
$line
EOF
        [ -z "$cand_sha" ] || [ -z "$head_sha" ] && continue
        # Hex and prefix validation
        case "$cand_sha" in
            *[!0-9a-fA-F]*) continue ;;
        esac
        case "$cand_sha" in
            ????*) ;;
            *) continue ;;
        esac
        # Invalidation check: only match if head_sha matches base_head
        case "$base_head" in
            "$head_sha"*) ;;
            *) continue ;;
        esac
        printf '%s\t%s\n' "$cand_sha" "${ts:-(unknown)}"
    done <"$file"
}

_gcp_scan_record_deferred() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    # Record a deferred commit into the deferred cache file (issue #1795).
    # $1=cand_sha $2=base_head_sha $3=conflict_files
    local cand_sha="$1" base_head_sha="$2" conflict_files="$3"
    local file now dir
    [ -z "$cand_sha" ] || [ -z "$base_head_sha" ] && return 0
    file=$(_gcp_scan_deferred_file)
    dir=$(dirname "$file")
    [ -d "$dir" ] || mkdir -p "$dir" 2>/dev/null || return 0
    now=$(date -u +'%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date +'%Y-%m-%d')
    printf '%s %s %s  # unpredicted conflict: %s\n' \
        "$cand_sha" "$base_head_sha" "$now" "${conflict_files:-unknown}" >>"$file" 2>/dev/null || true
}

_gcp_scan_show_deferred() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    # Render the current deferred cache for `gcp scan --show-deferred` (issue #1795).
    local file entries="" line cand_sha head_sha ts rest
    file=$(_gcp_scan_deferred_file)
    if [ -f "$file" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            line=$(_gcp_scan_clean_token "$line")
            [ -z "$line" ] && continue
            read -r cand_sha head_sha ts rest <<EOF
$line
EOF
            [ -z "$cand_sha" ] && continue
            if [ -n "$entries" ]; then
                entries="${entries}
${cand_sha} (base HEAD: ${head_sha}, at: ${ts})"
            else
                entries="${cand_sha} (base HEAD: ${head_sha}, at: ${ts})"
            fi
        done <"$file"
    fi
    _gcp_scan_show_skip_generic "Deferred commit cache" "$file" "$entries" \
        "(no deferred cache file — nothing recorded)" \
        "(file present but no deferred commits recorded)"
}
