#!/bin/bash
set -euo pipefail

# Initialize common tools environment
# This assumes the script is run from the dotfiles repo, or ux_lib is in a known path.

# Load initialization (which includes UX library)
source "$(dirname "$0")/init.sh" || exit 1

# Snapshot LOC skips these extensions (data / generated / lockfiles), plus
# binaries (git sees them as -text) and extensionless files.
SNAPSHOT_IGNORE_EXTS="json snap lock"
SNAPSHOT_TOP=15
AUTHOR_TOP=10

# Churn/author exclusion set: awk regex on the numstat path (--no-renames keeps
# it a plain path) and the human list printed under the Churn section.
# [.] not \. : awk -v would eat the backslash.
CHURN_EXCLUDE_RE='[.](md|json|snap|lock)$|(^|/)generated/|(^|/)pnpm-lock[.]yaml$'
CHURN_EXCLUDE_DESC="*.md, *.json (openapi.json), *.snap, *.lock, pnpm-lock.yaml, generated/"

format_number() {
    local num=$1
    local sign=""
    if [[ $num == -* ]]; then
        sign="-"
        num=${num#-}
    fi
    local formatted=""
    while [[ ${#num} -gt 3 ]]; do
        local chunk=${num: -3}
        formatted=",${chunk}${formatted}"
        num=${num:0:-3}
    done
    formatted="${num}${formatted}"
    printf '%s%s' "$sign" "$formatted"
}

repo_stats_help() {
    ux_usage "devx stat" "[dir] [options]" "Show git commit, churn, author, test and LOC statistics for a repository"
    ux_bullet "dir defaults to the current directory"
    ux_bullet "--since <date>        limit commit/churn/author stats (git log --since)"
    ux_bullet "--until <date>        limit commit/churn/author stats (git log --until)"
    ux_bullet "--include-untracked   add untracked (non-ignored) files to snapshot LOC"
    ux_bullet "--by-author           list every author instead of the top ${AUTHOR_TOP}"
    ux_bullet ".mailmap (repo root, or ~/.config/git/mailmap) merges author identities"
}

# Tracked (optionally untracked) text files with an extension, one per line,
# as "<ext>\t<path>". shortcut: paths with newlines/tabs are git-quoted and
# skipped; switch to a NUL-safe parser if such repos show up.
list_snapshot_files() {
    local -a others=()
    [[ $include_untracked == 1 ]] && others=(--others --exclude-standard)
    git -C "$TARGET_DIR" -c core.quotepath=off ls-files --eol --cached "${others[@]}" |
        awk -v ignore="$SNAPSHOT_IGNORE_EXTS" '
            BEGIN { n = split(ignore, a, " "); for (i = 1; i <= n; i++) skip[a[i]] = 1 }
            {
                tab = index($0, "\t"); if (!tab) next
                meta = substr($0, 1, tab - 1); path = substr($0, tab + 1)
                # "w/ " (blank worktree eol) = deleted file, symlink or submodule: awk cannot read it.
                if (meta ~ /[iw]\/-text/ || meta ~ /w\/ / || path ~ /^"/ || path ~ /(^|\/)\.venv\//) next
                base = path; sub(/.*\//, "", base)
                if (base !~ /.\./) next
                ext = base; sub(/.*\./, "", ext)
                if (ext in skip) next
                print ext "\t" path
            }'
}

main() {
    local TARGET_DIR="" include_untracked=0 by_author=0
    local -a range=()
    while (($#)); do
        case "$1" in
            -h | --help) repo_stats_help; return 0 ;;
            --since | --until)
                if [[ $# -lt 2 ]]; then
                    ux_error "$1 requires a date" >&2
                    exit 1
                fi
                range+=("$1=$2"); shift ;;
            --since=* | --until=*) range+=("$1") ;;
            --include-untracked) include_untracked=1 ;;
            --by-author) by_author=1 ;;
            -*) ux_error "Unknown option: $1" >&2; exit 1 ;;
            *) TARGET_DIR=$1 ;;
        esac
        shift
    done
    TARGET_DIR=${TARGET_DIR:-.}

    if [[ ! -d $TARGET_DIR ]]; then
        ux_error "'${TARGET_DIR}' is not a directory" >&2
        exit 1
    fi

    TARGET_DIR=$(realpath "$TARGET_DIR")

    if ! git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        ux_error "'${TARGET_DIR}' is not a git repository" >&2
        exit 1
    fi

    # git reads only the repo .mailmap by default; honour the XDG one too.
    local -a gitcfg=()
    local xdg_mailmap="${XDG_CONFIG_HOME:-$HOME/.config}/git/mailmap"
    if [[ -f $xdg_mailmap ]] && ! git -C "$TARGET_DIR" config mailmap.file >/dev/null 2>&1; then
        gitcfg=(-c "mailmap.file=$xdg_mailmap")
    fi

    if ! git -C "$TARGET_DIR" rev-parse --verify -q HEAD >/dev/null; then
        ux_error "'${TARGET_DIR}' has no commits yet" >&2
        exit 1
    fi

    # --- Commits (range-aware) ---
    local commit_dates git_commits start_date="-" end_date="-" duration_days=0 avg_commits_per_day="0.00"
    # Sorted: committer dates are not monotonic in log order after rebases/clock skew.
    commit_dates=$(git -C "$TARGET_DIR" log --format=%cs "${range[@]}" HEAD | sort)
    git_commits=$(printf '%s' "$commit_dates" | grep -c . || true)
    if ((git_commits > 0)); then
        # Expansions, not head/tail: head would SIGPIPE printf under pipefail.
        start_date=${commit_dates%%$'\n'*}
        end_date=${commit_dates##*$'\n'}
        local start_epoch end_epoch days_for_avg
        start_epoch=$(date -d "$start_date" +%s)
        end_epoch=$(date -d "$end_date" +%s)
        duration_days=$(((end_epoch - start_epoch) / 86400))
        days_for_avg=$((duration_days < 1 ? 1 : duration_days))
        avg_commits_per_day=$(awk -v commits="$git_commits" -v days="$days_for_avg" 'BEGIN { printf "%.2f", commits / days }')
    fi

    # --- Churn + authors: one numstat pass, merges carry no numstat ---
    # Output: "T <adds> <dels>" then "A <adds> <commits> <name>" per author.
    local churn
    churn=$(git -C "$TARGET_DIR" "${gitcfg[@]}" log --no-renames --numstat --format='@%aN' "${range[@]}" HEAD |
        awk -F'\t' -v ex="$CHURN_EXCLUDE_RE" '
            /^@/ { who = substr($0, 2); commits[who]++; next }
            NF == 3 && $1 != "-" && tolower($3) !~ ex { add += $1; del += $2; a[who] += $1 }
            END {
                printf "T\t%d\t%d\n", add, del
                for (w in commits) printf "A\t%d\t%d\t%s\n", a[w], commits[w], w
            }')
    local churn_add churn_del
    # The "T" totals row is always the first line.
    IFS=$'\t' read -r _ churn_add churn_del <<<"$churn"

    # --- Snapshot LOC by discovered extension ---
    local files snapshot
    files=$(list_snapshot_files)
    snapshot=""
    if [[ -n $files ]]; then
        # Per-file line counts summed per extension ("<ext>\t<files>\t<loc>").
        # "./" prefix: awk would read a "a=b.js" argument as a variable assignment.
        snapshot=$(cut -f2- <<<"$files" | sed 's|^|./|' | tr '\n' '\0' |
            (cd "$TARGET_DIR" || exit; xargs -0 -r awk '{ n[substr(FILENAME, 3)]++ } END { for (f in n) print f "\t" n[f] }' 2>/dev/null || true) |
            awk -F'\t' 'NR == FNR { ext[$2] = $1; files[$1]++; next }
                { loc[ext[$1]] += $2 }
                END { for (e in files) printf "%s\t%d\t%d\n", e, files[e], loc[e] }' <(printf '%s\n' "$files") - |
            sort -t$'\t' -k3,3nr -k1,1)
    fi
    local total_files total_loc
    read -r total_files total_loc < <(awk -F'\t' '{ f += $2; l += $3 } END { print f + 0, l + 0 }' <<<"$snapshot")

    # Test Statistics (Heuristic: count 'def test_' in python test files)
    local test_count=0
    test_count=$(awk -F'\t' '$1 == "py" && $2 ~ /(^|\/)(test_[^\/]*|[^\/]*_test)\.py$/ { print $2 }' <<<"$files" |
        tr '\n' '\0' | (cd "$TARGET_DIR" || exit; xargs -0 -r grep -h "def test_" 2>/dev/null || true) | wc -l | tr -d ' ')

    # --- Display ---
    if [[ -t 1 ]]; then clear || true; fi
    ux_header "Repository Statistics: $(basename "$TARGET_DIR")"
    if ((${#range[@]})); then
        ux_info "Range: ${range[*]}"
    fi

    ux_section "Git Commit Statistics"
    ux_table_row "Total Commits" "$(format_number "$git_commits")"
    ux_table_row "Project Period" "${start_date} ~ ${end_date} (${duration_days} days)"
    ux_table_row "Commit Rate" "${avg_commits_per_day} commits/day"

    ux_section "Git Churn Statistics"
    ux_table_row "Additions" "+$(format_number "$churn_add")"
    ux_table_row "Deletions" "-$(format_number "$churn_del")"
    ux_table_row "Net" "$(format_number $((churn_add - churn_del)))"
    ux_bullet "Excluded: ${CHURN_EXCLUDE_DESC}, binary files, merge commits"

    ux_section "Author Contributions"
    ux_table_header "Author" "Commits" "Additions (share)"
    awk -F'\t' '$1 == "A"' <<<"$churn" | cut -f2- | sort -t$'\t' -k1,1nr -k2,2nr -k3,3 |
        awk -F'\t' -v top="$AUTHOR_TOP" -v all="$by_author" -v total="$churn_add" '
            function pct(x) { return total > 0 ? sprintf("%.2f%%", 100 * x / total) : "0.00%" }
            all == 1 || NR <= top { printf "%s\t%d\t%d\t%s\n", $3, $2, $1, pct($1); next }
            { oa += $1; oc += $2; on++ }
            END { if (on) printf "(%d others)\t%d\t%d\t%s\n", on, oc, oa, pct(oa) }' |
        while IFS=$'\t' read -r name commits adds share; do
            ux_table_row "$name" "$(format_number "$commits")" "+$(format_number "$adds") (${share})"
        done

    if ((test_count > 0)); then
        ux_section "Test Statistics"
        ux_table_row "Estimated Tests" "$(format_number "$test_count")"
    fi

    ux_section "File & Code Statistics"
    ux_table_row "${UX_BOLD}Total Files${UX_RESET}" "$(format_number "$total_files")"
    ux_table_row "${UX_BOLD}Total LOC${UX_RESET}" "$(format_number "$total_loc")"
    echo ""
    ux_table_header "Extension" "Files" "Lines of Code"
    awk -F'\t' -v top="$SNAPSHOT_TOP" '
        NF < 3 { next }
        NR <= top { print "." $1 "\t" $2 "\t" $3; next }
        { of += $2; ol += $3; on++ }
        END { if (on) printf "(%d others)\t%d\t%d\n", on, of, ol }' <<<"$snapshot" |
        while IFS=$'\t' read -r ext count loc; do
            ux_table_row "$ext" "$(format_number "$count")" "$(format_number "$loc")"
        done
    echo ""
    ux_bullet "Total LOC = current tracked code (snapshot, untracked $( ((include_untracked)) && echo included || echo excluded); ignores .${SNAPSHOT_IGNORE_EXTS// /, .}, binaries)"
    ux_bullet "Churn additions = lines added by commits in the range (cumulative history)"
}

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "${BASH_SOURCE[0]}" ]; then
    main "$@"
fi
